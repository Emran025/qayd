import 'dart:collection';

import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/exceptions/invalid_pos_invoice_exception.dart';

/// Complete immutable payload required to atomically post one POS sale.
final class PosSalePosting {
  PosSalePosting({
    required this.invoice,
    required List<PosStockMovement> movements,
    required List<PosAccountingPosting> postings,
    required List<PosInvoicePayment> payments,
  })  : movements = UnmodifiableListView(movements),
        postings = UnmodifiableListView(postings),
        payments = UnmodifiableListView(payments) {
    if (invoice.type != PosInvoiceType.sale) {
      throw InvalidPosInvoiceException.invalidLine();
    }
    // A full cash/credit sale has two postings (commercial + COGS).
    // A split settlement may add a second commercial posting for the due leg.
    if (this.movements.isEmpty || this.postings.length < 2) {
      throw InvalidPosInvoiceException.invalidTotals();
    }
    if (this.movements.length != invoice.lines.length) {
      throw InvalidPosInvoiceException.invalidLine();
    }
    final lineIds = invoice.lines.map((line) => line.id).toSet();
    for (final movement in this.movements) {
      if (movement.sourceId != invoice.id ||
          movement.sourceType != 'pos_invoice' ||
          movement.direction != PosStockMovementDirection.outbound ||
          movement.sourceLineId == null ||
          !lineIds.contains(movement.sourceLineId)) {
        throw InvalidPosInvoiceException.invalidLine();
      }
    }
    for (final posting in this.postings) {
      if (posting.sourceId != invoice.id ||
          posting.voucher.referenceNumber != invoice.id ||
          posting.voucher.date.toUtc().year !=
              invoice.invoiceDate.toUtc().year ||
          posting.voucher.date.toUtc().month !=
              invoice.invoiceDate.toUtc().month ||
          posting.voucher.date.toUtc().day != invoice.invoiceDate.toUtc().day) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
      if (posting.entries.isEmpty ||
          posting.entries.any((entry) =>
              entry.currency != invoice.currency ||
              entry.voucherId != posting.voucher.id)) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
      final debit = posting.entries
          .where((entry) => entry.isDebit)
          .fold<int>(0, (sum, entry) => sum + entry.amount.minorUnits);
      final credit = posting.entries
          .where((entry) => !entry.isDebit)
          .fold<int>(0, (sum, entry) => sum + entry.amount.minorUnits);
      if (debit != credit || debit != posting.voucher.amount.minorUnits) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
    }
    for (final payment in this.payments) {
      if (payment.invoiceId != invoice.id ||
          payment.currency != invoice.currency) {
        throw InvalidPosInvoiceException.invalidPayment();
      }
    }
    final paid = this.payments.fold<int>(
      0,
      (sum, payment) => sum + payment.amount.minorUnits,
    );
    if (paid != invoice.paid.minorUnits) {
      throw InvalidPosInvoiceException.invalidPayment();
    }
  }

  final PosInvoice invoice;
  final UnmodifiableListView<PosStockMovement> movements;
  final UnmodifiableListView<PosAccountingPosting> postings;
  final UnmodifiableListView<PosInvoicePayment> payments;
}
