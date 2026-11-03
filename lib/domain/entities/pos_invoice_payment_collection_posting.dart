import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';

/// Prepared, immutable payload for one later collection on a POS sale invoice.
///
/// For a new operation [invoiceBefore] and [invoiceAfter] describe the balance
/// transition. For a verified replay both refer to the currently persisted
/// invoice; persistence still verifies the immutable payment and accounting
/// event without rewriting later balance changes.
final class PosInvoicePaymentCollectionPosting {
  const PosInvoicePaymentCollectionPosting({
    required this.invoiceBefore,
    required this.invoiceAfter,
    required this.payment,
    required this.accountingPosting,
    required this.recordedAt,
    this.isReplay = false,
  });

  final PosInvoice invoiceBefore;
  final PosInvoice invoiceAfter;
  final PosInvoicePayment payment;
  final PosAccountingPosting accountingPosting;
  final DateTime recordedAt;
  final bool isReplay;
}
