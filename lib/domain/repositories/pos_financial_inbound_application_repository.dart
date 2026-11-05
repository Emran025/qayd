import 'package:qayd/domain/entities/pos_financial_apply_result.dart';
import 'package:qayd/domain/entities/pos_financial_sync_event.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
import 'package:qayd/domain/entities/pos_purchase_posting.dart';
import 'package:qayd/domain/entities/pos_purchase_return_posting.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';

/// Atomic persistence boundary for same-company POS device replication.
///
/// Implementations must commit the posting, financial inbox dedupe row, and
/// inbound journal `applied` state in one SQLite transaction. A conflict is
/// retained but must never be reported as acknowledged/applied.
abstract interface class PosFinancialInboundApplicationRepository {
  Future<PosFinancialApplyResult> applySaleAtomically({
    required PosFinancialSyncEvent event,
    required PosSalePosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  });

  Future<PosFinancialApplyResult> applyPurchaseAtomically({
    required PosFinancialSyncEvent event,
    required PosPurchasePosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  });

  Future<PosFinancialApplyResult> applySalesReturnAtomically({
    required PosFinancialSyncEvent event,
    required PosSalesReturnPosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  });

  Future<PosFinancialApplyResult> applyPurchaseReturnAtomically({
    required PosFinancialSyncEvent event,
    required PosPurchaseReturnPosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  });

  Future<PosFinancialApplyResult> applyCollectionAtomically({
    required PosFinancialSyncEvent event,
    required PosInvoicePaymentCollectionPosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  });
}
