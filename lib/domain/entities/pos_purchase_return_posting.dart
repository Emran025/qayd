import 'dart:collection';

import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/exceptions/invalid_pos_invoice_exception.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/entities/pos_invoice_line_conversion.dart';

/// Complete immutable purchase-return credit note.
///
/// This is a perpetual-inventory transaction: its supplier-credit total is
/// debited to the supplier-payables control account, while inventory is
/// credited at its weighted-average carrying amount. Any difference is posted
/// to the explicitly mapped purchase-returns variance account. `invoice.due`
/// is the unapplied supplier credit, not a cash refund or cash payment.
final class PosPurchaseReturnPosting {
  PosPurchaseReturnPosting({
    required this.invoice,
    required this.sourceInvoiceId,
    required this.supplierPayablesAccountId,
    required this.inventoryAccountId,
    required this.purchaseReturnsAccountId,
    required List<PosStockMovement> movements,
    required List<PosAccountingPosting> postings,
    String? reason,
  }) : movements = UnmodifiableListView(movements),
       postings = UnmodifiableListView(postings),
       reason = reason?.trim().isEmpty == true ? null : reason?.trim() {
    if (sourceInvoiceId.trim().isEmpty ||
        invoice.type != PosInvoiceType.purchaseReturn ||
        invoice.sourceInvoiceId != sourceInvoiceId ||
        invoice.status != PosDocumentStatus.posted ||
        invoice.paid.minorUnits != 0 ||
        invoice.due.minorUnits != invoice.total.minorUnits ||
        invoice.counterpartyAccountId == null ||
        invoice.lines.isEmpty ||
        supplierPayablesAccountId == inventoryAccountId ||
        supplierPayablesAccountId == purchaseReturnsAccountId ||
        inventoryAccountId == purchaseReturnsAccountId) {
      throw InvalidPosInvoiceException.invalidTotals();
    }

    final linesById = <String, PosInvoiceLine>{};
    final sourceLineIds = <String>{};
    for (final line in invoice.lines) {
      final sourceLineId = line.sourceLineId;
      if (sourceLineId == null ||
          sourceLineId.isEmpty ||
          !sourceLineIds.add(sourceLineId) ||
          linesById.containsKey(line.id)) {
        throw InvalidPosInvoiceException.invalidLine();
      }
      linesById[line.id] = line;
    }

    final movementIds = <String>{};
    final movementKeys = <String>{};
    final movementQuantityByLine = <String, int>{};
    final movementCostByLine = <String, int>{};
    final movementLineIds = <String>{};
    for (final movement in movements) {
      final lineId = movement.sourceLineId;
      final line = lineId == null ? null : linesById[lineId];
      if (line == null ||
          !movementIds.add(movement.id) ||
          !movementKeys.add(movement.idempotencyKey) ||
          movement.sourceId != invoice.id ||
          movement.sourceType != 'pos_invoice' ||
          movement.type != PosStockMovementType.purchaseReturn ||
          movement.direction != PosStockMovementDirection.outbound ||
          movement.warehouseId != invoice.warehouseId ||
          movement.productId != line.productId ||
          movement.quantity.scale != line.quantity.scale ||
          movement.unitCost.currency != line.unitCost.currency ||
          (line.expiryTrackingSnapshot == true
              ? movement.lotId == null
              : movement.lotId != null)) {
        throw InvalidPosInvoiceException.invalidLine();
      }
      movementLineIds.add(lineId!);
      movementQuantityByLine.update(
        line.id,
        (quantity) => quantity + movement.quantity.scaledUnits,
        ifAbsent: () => movement.quantity.scaledUnits,
      );
      final bookValue = _inventoryBookValueInInvoiceCurrency(
        line: line,
        movement: movement,
        invoiceCurrency: invoice.currency,
      );
      movementCostByLine.update(
        line.id,
        (value) => value + bookValue.minorUnits,
        ifAbsent: () => bookValue.minorUnits,
      );
    }
    if (movementLineIds.length != linesById.length ||
        linesById.values.any(
          (line) =>
              movementQuantityByLine[line.id] != line.quantity.scaledUnits,
        )) {
      throw InvalidPosInvoiceException.invalidLine();
    }

    var inventoryCarryingValueMinor = 0;
    for (final value in movementCostByLine.values) {
      inventoryCarryingValueMinor += value;
    }
    _validateBalancedReturn(
      inventoryCarryingValueMinor: inventoryCarryingValueMinor,
      movementCostByLine: movementCostByLine,
      linesById: linesById,
    );
  }

  final PosInvoice invoice;
  final String sourceInvoiceId;
  final AccountId supplierPayablesAccountId;
  final AccountId inventoryAccountId;
  final AccountId purchaseReturnsAccountId;
  final List<PosStockMovement> movements;
  final List<PosAccountingPosting> postings;
  final String? reason;

  void _validateBalancedReturn({
    required int inventoryCarryingValueMinor,
    required Map<String, int> movementCostByLine,
    required Map<String, PosInvoiceLine> linesById,
  }) {
    final amount = invoice.total.minorUnits;
    final bookValue = inventoryCarryingValueMinor;
    if (amount < 0 || bookValue < 0) {
      throw InvalidPosInvoiceException.invalidTotals();
    }
    final expectedPostingCount =
        (amount > 0 && bookValue > 0 ? 1 : 0) +
        (amount > bookValue || bookValue > amount ? 1 : 0) +
        (amount == 0 && bookValue == 0 ? 0 : 0);
    if (postings.length != expectedPostingCount) {
      throw InvalidPosInvoiceException.invalidTotals();
    }

    final postingIds = <String>{};
    final entryIds = <String>{};
    var payableDebits = 0;
    var inventoryCredits = 0;
    var varianceDebits = 0;
    var varianceCredits = 0;
    for (final posting in postings) {
      final voucher = posting.voucher;
      final debits = posting.entries.where((entry) => entry.isDebit).toList();
      final credits = posting.entries.where((entry) => entry.isCredit).toList();
      if (posting.sourceId != invoice.id ||
          voucher.referenceNumber != invoice.id ||
          voucher.type != VoucherType.payment ||
          voucher.currency != invoice.currency ||
          voucher.amount.currency != invoice.currency ||
          voucher.amount.isNegative ||
          voucher.amount.isZero ||
          !voucher.state.isConfirmed ||
          !postingIds.add(voucher.id.value) ||
          posting.entries.length != 2 ||
          debits.length != 1 ||
          credits.length != 1 ||
          posting.entries.any(
            (entry) =>
                entry.voucherId != voucher.id ||
                entry.currency != invoice.currency ||
                entry.amount.currency != invoice.currency ||
                entry.amount.minorUnits != voucher.amount.minorUnits ||
                !entryIds.add(entry.id.value),
          )) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
      final debitAccount = debits.single.accountId;
      final creditAccount = credits.single.accountId;
      if (debitAccount == supplierPayablesAccountId &&
          creditAccount == inventoryAccountId) {
        payableDebits += voucher.amount.minorUnits;
        inventoryCredits += voucher.amount.minorUnits;
      } else if (debitAccount == supplierPayablesAccountId &&
          creditAccount == purchaseReturnsAccountId) {
        payableDebits += voucher.amount.minorUnits;
        varianceCredits += voucher.amount.minorUnits;
      } else if (debitAccount == purchaseReturnsAccountId &&
          creditAccount == inventoryAccountId) {
        varianceDebits += voucher.amount.minorUnits;
        inventoryCredits += voucher.amount.minorUnits;
      } else {
        throw InvalidPosInvoiceException.invalidTotals();
      }
    }

    if (payableDebits != amount ||
        inventoryCredits != bookValue ||
        varianceCredits - varianceDebits != amount - bookValue ||
        (amount == 0 && bookValue == 0 && postings.isNotEmpty)) {
      throw InvalidPosInvoiceException.invalidTotals();
    }
    // The account split is independently derived from the immutable source
    // invoice amounts and current weighted-average stock movement snapshots.
    if (movementCostByLine.keys
        .toSet()
        .difference(linesById.keys.toSet())
        .isNotEmpty) {
      throw InvalidPosInvoiceException.invalidLine();
    }
  }

  static Money _inventoryBookValueInInvoiceCurrency({
    required PosInvoiceLine line,
    required PosStockMovement movement,
    required CurrencyCode invoiceCurrency,
  }) {
    final movementValue = PosMoneyMath.multiply(
      movement.quantity,
      movement.unitCost,
    );
    if (movementValue.currency == invoiceCurrency) return movementValue;
    final conversion = line.currencyConversion;
    final originalQuote = conversion?.rateSnapshot;
    if (conversion == null ||
        conversion.purpose != PosInvoiceLineConversionPurpose.purchaseCost ||
        conversion.sourceAmount.currency != invoiceCurrency ||
        conversion.targetAmount.currency != movementValue.currency ||
        originalQuote == null) {
      throw InvalidPosInvoiceException.invalidTotals();
    }
    final reverseQuote = PosCurrencyRateQuote(
      rateId: originalQuote.rateId,
      storedFromCurrency: originalQuote.storedFromCurrency,
      storedToCurrency: originalQuote.storedToCurrency,
      storedRateScaled: originalQuote.storedRateScaled,
      requestedFromCurrency: originalQuote.requestedToCurrency,
      requestedToCurrency: originalQuote.requestedFromCurrency,
      effectiveAt: originalQuote.effectiveAt,
      recordedAt: originalQuote.recordedAt,
      createdAt: originalQuote.createdAt,
      isInverted: !originalQuote.isInverted,
      note: originalQuote.note,
    );
    return reverseQuote.convert(movementValue);
  }
}
