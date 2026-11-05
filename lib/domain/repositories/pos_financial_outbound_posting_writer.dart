import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_financial_outbound_bundle.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
import 'package:qayd/domain/entities/pos_purchase_posting.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';

/// Commits a local posting and its encrypted per-device outbox entries together.
abstract interface class PosFinancialOutboundPostingWriter {
  Future<Result<void>> saveSaleWithOutboundAtomically(
    PosSalePosting posting,
    PosFinancialOutboundBundle bundle,
  );

  Future<Result<void>> savePurchaseWithOutboundAtomically(
    PosPurchasePosting posting,
    PosFinancialOutboundBundle bundle,
  );

  Future<Result<void>> saveSalesReturnWithOutboundAtomically(
    PosSalesReturnPosting posting,
    PosFinancialOutboundBundle bundle,
  );

  Future<Result<void>> saveCollectionWithOutboundAtomically(
    PosInvoicePaymentCollectionPosting posting,
    PosFinancialOutboundBundle bundle,
  );
}
