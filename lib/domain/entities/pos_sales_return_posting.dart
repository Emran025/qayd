import 'dart:collection';

import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/exceptions/invalid_pos_invoice_exception.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/voucher_state.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';

/// Complete, immutable payload for one sales-return transaction.
/// It deliberately has no dependency on [PosSalePosting].
final class PosSalesReturnPosting {
  PosSalesReturnPosting({
    required this.invoice,
    required this.sourceInvoiceId,
    required this.salesReturnsAccountId,
    required this.inventoryAccountId,
    required this.costOfGoodsSoldAccountId,
    required List<PosStockMovement> movements,
    required List<PosAccountingPosting> postings,
    required List<PosInvoicePayment> refundPayments,
    required this.voidSource,
    String? reason,
  })  : movements = UnmodifiableListView(movements),
        postings = UnmodifiableListView(postings),
        refundPayments = UnmodifiableListView(refundPayments),
        reason = reason?.trim().isEmpty == true ? null : reason?.trim() {
    if (sourceInvoiceId.trim().isEmpty ||
        invoice.type != PosInvoiceType.salesReturn ||
        invoice.sourceInvoiceId != sourceInvoiceId ||
        invoice.status != PosDocumentStatus.paid ||
        invoice.paid.minorUnits != invoice.total.minorUnits ||
        invoice.due.minorUnits != 0 ||
        invoice.lines.isEmpty ||
        movements.length != invoice.lines.length ||
        (refundPayments.isEmpty && invoice.total.minorUnits > 0)) {
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

    final movementLineIds = <String>{};
    final movementIds = <String>{};
    final movementKeys = <String>{};
    for (final movement in movements) {
      final lineId = movement.sourceLineId;
      final line = lineId == null ? null : linesById[lineId];
      if (line == null ||
          !movementLineIds.add(lineId!) ||
          !movementIds.add(movement.id) ||
          !movementKeys.add(movement.idempotencyKey) ||
          movement.sourceId != invoice.id ||
          movement.sourceType != 'pos_invoice' ||
          movement.type != PosStockMovementType.salesReturn ||
          movement.direction != PosStockMovementDirection.inbound ||
          movement.warehouseId != invoice.warehouseId ||
          movement.productId != line.productId ||
          movement.quantity.scaledUnits != line.quantity.scaledUnits ||
          movement.quantity.scale != line.quantity.scale ||
          movement.unitCost.minorUnits != line.unitCost.minorUnits ||
          movement.unitCost.currency != invoice.currency) {
        throw InvalidPosInvoiceException.invalidLine();
      }
    }
    if (movementLineIds.length != linesById.length) {
      throw InvalidPosInvoiceException.invalidLine();
    }

    final paymentIds = <String>{};
    final paymentKeys = <String>{};
    for (final payment in refundPayments) {
      if (payment.invoiceId != invoice.id ||
          payment.currency != invoice.currency ||
          payment.amount.currency != invoice.currency ||
          payment.amount.isZero ||
          payment.amount.isNegative ||
          payment.method == PosPaymentMethod.credit ||
          !paymentIds.add(payment.id) ||
          !paymentKeys.add(payment.idempotencyKey)) {
        throw InvalidPosInvoiceException.invalidPayment();
      }
    }
    if (refundPayments.fold<int>(
          0,
          (sum, payment) => sum + payment.amount.minorUnits,
        ) !=
        invoice.total.minorUnits) {
      throw InvalidPosInvoiceException.invalidPayment();
    }

    final cogsAmount = movements.fold<int>(
      0,
      (sum, movement) =>
          sum + PosMoneyMath.multiply(movement.quantity, movement.unitCost).minorUnits,
    );
    final expectedPostingCount = refundPayments.length + (cogsAmount > 0 ? 1 : 0);
    if (postings.length != expectedPostingCount) {
      throw InvalidPosInvoiceException.invalidTotals();
    }

    final voucherIds = <String>{};
    final ledgerEntryIds = <String>{};
    var allVoucherAmounts = 0;
    for (final posting in postings) {
      final voucher = posting.voucher;
      if (posting.sourceId != invoice.id ||
          voucher.referenceNumber != invoice.id ||
          voucher.currency != invoice.currency ||
          voucher.amount.isZero ||
          voucher.amount.isNegative ||
          !voucher.state.isConfirmed ||
          !voucherIds.add(voucher.id.value) ||
          posting.entries.length != 2 ||
          posting.entries.any((entry) =>
              entry.voucherId != voucher.id ||
              entry.currency != invoice.currency ||
              entry.amount.currency != invoice.currency ||
              !ledgerEntryIds.add(entry.id.value))) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
      final debits = posting.entries.where((entry) => entry.isDebit).toList();
      final credits = posting.entries.where((entry) => entry.isCredit).toList();
      if (debits.length != 1 || credits.length != 1 ||
          debits.single.amount.minorUnits != voucher.amount.minorUnits ||
          credits.single.amount.minorUnits != voucher.amount.minorUnits) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
      allVoucherAmounts += voucher.amount.minorUnits;
    }

    for (var index = 0; index < refundPayments.length; index++) {
      final payment = refundPayments[index];
      final posting = postings[index];
      final voucher = posting.voucher;
      final debit = posting.entries.singleWhere((entry) => entry.isDebit);
      final credit = posting.entries.singleWhere((entry) => entry.isCredit);
      if (voucher.type != VoucherType.receipt ||
          voucher.amount.minorUnits != payment.amount.minorUnits ||
          voucher.affectedAccountId != salesReturnsAccountId ||
          voucher.counterpartyId != payment.accountId ||
          debit.accountId != salesReturnsAccountId ||
          credit.accountId != payment.accountId) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
    }

    if (cogsAmount > 0) {
      final posting = postings.last;
      final voucher = posting.voucher;
      final debit = posting.entries.singleWhere((entry) => entry.isDebit);
      final credit = posting.entries.singleWhere((entry) => entry.isCredit);
      if (voucher.type != VoucherType.receipt ||
          voucher.amount.minorUnits != cogsAmount ||
          voucher.affectedAccountId != inventoryAccountId ||
          voucher.counterpartyId != costOfGoodsSoldAccountId ||
          debit.accountId != inventoryAccountId ||
          credit.accountId != costOfGoodsSoldAccountId) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
    }
    if (allVoucherAmounts != invoice.total.minorUnits + cogsAmount) {
      throw InvalidPosInvoiceException.invalidTotals();
    }
  }

  final PosInvoice invoice;
  final String sourceInvoiceId;
  final AccountId salesReturnsAccountId;
  final AccountId inventoryAccountId;
  final AccountId costOfGoodsSoldAccountId;
  final List<PosStockMovement> movements;
  final List<PosAccountingPosting> postings;
  final List<PosInvoicePayment> refundPayments;
  final bool voidSource;
  final String? reason;
}
