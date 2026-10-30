import 'dart:collection';

import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/exceptions/invalid_pos_invoice_exception.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';

/// Complete immutable payload required to atomically receive one POS purchase.
///
/// A purchase is accepted only when its invoice, inbound stock movements,
/// payments and balanced accounting vouchers describe the same transaction.
final class PosPurchasePosting {
  PosPurchasePosting({
    required this.invoice,
    required List<PosStockMovement> movements,
    required List<PosAccountingPosting> postings,
    required List<PosInvoicePayment> payments,
  })  : movements = UnmodifiableListView(movements),
        postings = UnmodifiableListView(postings),
        payments = UnmodifiableListView(payments) {
    final isCommittedStatus =
        invoice.status == PosDocumentStatus.posted ||
            invoice.status == PosDocumentStatus.partiallyPaid ||
            invoice.status == PosDocumentStatus.paid;
    if (invoice.type != PosInvoiceType.purchase ||
        !isCommittedStatus ||
        invoice.total.minorUnits <= 0 ||
        this.movements.isEmpty ||
        this.postings.isEmpty ||
        this.movements.length != invoice.lines.length) {
      throw InvalidPosInvoiceException.invalidTotals();
    }

    final linesById = <String, PosInvoiceLine>{
      for (final line in invoice.lines) line.id: line,
    };
    final movementIds = <String>{};
    final movementIdempotencyKeys = <String>{};
    final matchedLineIds = <String>{};
    for (final movement in this.movements) {
      final lineId = movement.sourceLineId;
      final line = lineId == null ? null : linesById[lineId];
      if (line == null ||
          !matchedLineIds.add(lineId!) ||
          !movementIds.add(movement.id) ||
          !movementIdempotencyKeys.add(movement.idempotencyKey) ||
          movement.sourceType != 'pos_invoice' ||
          movement.sourceId != invoice.id ||
          movement.direction != PosStockMovementDirection.inbound ||
          movement.type != PosStockMovementType.purchase ||
          movement.lotId != null ||
          movement.productId != line.productId ||
          movement.warehouseId != invoice.warehouseId ||
          movement.quantity != line.quantity ||
          movement.unitCost != line.unitCost ||
          movement.occurredAt.toUtc() != invoice.invoiceDate.toUtc()) {
        throw InvalidPosInvoiceException.invalidLine();
      }
    }
    if (matchedLineIds.length != invoice.lines.length) {
      throw InvalidPosInvoiceException.invalidLine();
    }

    final voucherIds = <String>{};
    var postingTotal = 0;
    AccountId? inventoryAccountId;
    for (final posting in this.postings) {
      final voucher = posting.voucher;
      if (posting.sourceId != invoice.id ||
          voucher.referenceNumber != invoice.id ||
          voucher.type != VoucherType.receipt ||
          voucher.amount.minorUnits <= 0 ||
          voucher.currency != invoice.currency ||
          voucher.counterpartyId == voucher.affectedAccountId ||
          !_sameUtcDay(voucher.date, invoice.invoiceDate) ||
          !voucherIds.add(voucher.id.value) ||
          posting.entries.length != 2 ||
          posting.entries.any((entry) =>
              entry.currency != invoice.currency ||
              entry.voucherId != voucher.id)) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
      inventoryAccountId ??= voucher.affectedAccountId;
      if (voucher.affectedAccountId != inventoryAccountId) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
      final debit = posting.entries
          .where((entry) => entry.isDebit)
          .fold<int>(0, (sum, entry) => sum + entry.amount.minorUnits);
      final credit = posting.entries
          .where((entry) => !entry.isDebit)
          .fold<int>(0, (sum, entry) => sum + entry.amount.minorUnits);
      if (debit != credit || debit != voucher.amount.minorUnits) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
      postingTotal += voucher.amount.minorUnits;
    }
    if (postingTotal != invoice.total.minorUnits) {
      throw InvalidPosInvoiceException.invalidTotals();
    }

    final paymentIds = <String>{};
    final paymentIdempotencyKeys = <String>{};
    final paidByAccount = <AccountId, int>{};
    var paid = 0;
    for (final payment in this.payments) {
      if (payment.invoiceId != invoice.id ||
          payment.currency != invoice.currency ||
          payment.method == PosPaymentMethod.credit ||
          payment.amount.minorUnits <= 0 ||
          payment.idempotencyKey.trim().isEmpty ||
          !paymentIds.add(payment.id) ||
          !paymentIdempotencyKeys.add(payment.idempotencyKey)) {
        throw InvalidPosInvoiceException.invalidPayment();
      }
      paid += payment.amount.minorUnits;
      paidByAccount.update(
        payment.accountId,
        (amount) => amount + payment.amount.minorUnits,
        ifAbsent: () => payment.amount.minorUnits,
      );
    }
    for (final entry in paidByAccount.entries) {
      final voucherAmount = this.postings
          .where((posting) => posting.voucher.counterpartyId == entry.key)
          .fold<int>(
            0,
            (sum, posting) => sum + posting.voucher.amount.minorUnits,
          );
      if (voucherAmount != entry.value) {
        throw InvalidPosInvoiceException.invalidPayment();
      }
    }
    if (paid != invoice.paid.minorUnits ||
        invoice.paid.minorUnits + invoice.due.minorUnits !=
            invoice.total.minorUnits ||
        (invoice.paid.isZero && invoice.status != PosDocumentStatus.posted) ||
        (invoice.paid.minorUnits > 0 &&
            invoice.due.isZero &&
            invoice.status != PosDocumentStatus.paid) ||
        (invoice.paid.minorUnits > 0 &&
            invoice.due.minorUnits > 0 &&
            invoice.status != PosDocumentStatus.partiallyPaid)) {
      throw InvalidPosInvoiceException.invalidPayment();
    }
  }

  final PosInvoice invoice;
  final UnmodifiableListView<PosStockMovement> movements;
  final UnmodifiableListView<PosAccountingPosting> postings;
  final UnmodifiableListView<PosInvoicePayment> payments;

  static bool _sameUtcDay(DateTime left, DateTime right) {
    final a = left.toUtc();
    final b = right.toUtc();
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
