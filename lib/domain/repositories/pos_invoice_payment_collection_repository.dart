import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';

/// Atomic persistence boundary for a later collection against one POS invoice.
abstract interface class PosInvoicePaymentCollectionRepository {
  /// Returns true only when this exact payment, voucher, and ledger posting were
  /// already committed. A partial or conflicting replay returns a failure.
  Future<Result<bool>> recoverCommitted(
    PosInvoicePaymentCollectionPosting posting,
  );

  /// Saves the payment event, derived invoice balance, voucher, and ledger rows
  /// in one transaction. Replaying the exact request is a no-op success.
  Future<Result<void>> saveAtomically(
    PosInvoicePaymentCollectionPosting posting,
  );
}
