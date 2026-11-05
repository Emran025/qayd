import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/repositories/pos_financial_event_store.dart';
import 'package:qayd/data/repositories/sqlite_pos_invoice_payment_collection_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_purchase_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_purchase_return_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_sale_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_sales_return_posting_repository.dart';
import 'package:qayd/domain/entities/pos_financial_apply_result.dart';
import 'package:qayd/domain/entities/pos_financial_sync_event.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
import 'package:qayd/domain/entities/pos_purchase_posting.dart';
import 'package:qayd/domain/entities/pos_purchase_return_posting.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';
import 'package:qayd/domain/repositories/pos_financial_inbound_application_repository.dart';
import 'package:qayd/domain/repositories/sync_inbound_event_journal_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Owns the single transaction spanning POS business rows, financial inbox
/// deduplication, and the generic encrypted-node journal.
final class SqlitePosFinancialInboundApplicationRepository
    implements PosFinancialInboundApplicationRepository {
  const SqlitePosFinancialInboundApplicationRepository({
    required DatabaseTransactionRunner transactionRunner,
    required PosFinancialEventStore eventStore,
    required SyncInboundEventJournalRepository inboundJournal,
    required SqlitePosSalePostingRepository saleRepository,
    required SqlitePosPurchasePostingRepository purchaseRepository,
    required SqlitePosSalesReturnPostingRepository salesReturnRepository,
    required SqlitePosPurchaseReturnPostingRepository purchaseReturnRepository,
    required SqlitePosInvoicePaymentCollectionRepository collectionRepository,
  }) : _transactionRunner = transactionRunner,
       _eventStore = eventStore,
       _inboundJournal = inboundJournal,
       _saleRepository = saleRepository,
       _purchaseRepository = purchaseRepository,
       _salesReturnRepository = salesReturnRepository,
       _purchaseReturnRepository = purchaseReturnRepository,
       _collectionRepository = collectionRepository;

  final DatabaseTransactionRunner _transactionRunner;
  final PosFinancialEventStore _eventStore;
  final SyncInboundEventJournalRepository _inboundJournal;
  final SqlitePosSalePostingRepository _saleRepository;
  final SqlitePosPurchasePostingRepository _purchaseRepository;
  final SqlitePosSalesReturnPostingRepository _salesReturnRepository;
  final SqlitePosPurchaseReturnPostingRepository _purchaseReturnRepository;
  final SqlitePosInvoicePaymentCollectionRepository _collectionRepository;

  @override
  Future<PosFinancialApplyResult> applySaleAtomically({
    required PosFinancialSyncEvent event,
    required PosSalePosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  }) {
    _requireKind(event, PosFinancialEventKind.sale, transportNodeId);
    return _apply(
      event,
      transportNodeId,
      encryptedPayload,
      (txn) => _saleRepository.saveInTransaction(txn, posting),
    );
  }

  @override
  Future<PosFinancialApplyResult> applyPurchaseAtomically({
    required PosFinancialSyncEvent event,
    required PosPurchasePosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  }) {
    _requireKind(event, PosFinancialEventKind.purchase, transportNodeId);
    return _apply(
      event,
      transportNodeId,
      encryptedPayload,
      (txn) => _purchaseRepository.saveInTransaction(txn, posting),
    );
  }

  @override
  Future<PosFinancialApplyResult> applySalesReturnAtomically({
    required PosFinancialSyncEvent event,
    required PosSalesReturnPosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  }) {
    _requireKind(event, PosFinancialEventKind.salesReturn, transportNodeId);
    return _apply(
      event,
      transportNodeId,
      encryptedPayload,
      (txn) => _salesReturnRepository.saveInTransaction(txn, posting),
    );
  }

  @override
  Future<PosFinancialApplyResult> applyPurchaseReturnAtomically({
    required PosFinancialSyncEvent event,
    required PosPurchaseReturnPosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  }) {
    _requireKind(event, PosFinancialEventKind.purchaseReturn, transportNodeId);
    return _apply(
      event,
      transportNodeId,
      encryptedPayload,
      (txn) => _purchaseReturnRepository.saveInTransaction(txn, posting),
    );
  }

  @override
  Future<PosFinancialApplyResult> applyCollectionAtomically({
    required PosFinancialSyncEvent event,
    required PosInvoicePaymentCollectionPosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  }) {
    _requireKind(event, PosFinancialEventKind.collection, transportNodeId);
    return _apply(
      event,
      transportNodeId,
      encryptedPayload,
      (txn) => _collectionRepository.saveInTransaction(txn, posting),
    );
  }

  Future<PosFinancialApplyResult> _apply(
    PosFinancialSyncEvent event,
    String transportNodeId,
    String encryptedPayload,
    Future<void> Function(Transaction txn) saveBusinessPosting,
  ) {
    return _transactionRunner.run<PosFinancialApplyResult>((txn) async {
      final result = await _eventStore.applyInboundInTransaction(
        txn,
        event,
        applyBusinessMutation: saveBusinessPosting,
      );
      if (result == PosFinancialApplyResult.conflictingReplay) {
        await _inboundJournal.quarantineInTransaction(
          txn,
          nodeId: transportNodeId,
          reason: SyncInboundQuarantineReason.handlerRejected,
          encryptedPayload: encryptedPayload,
        );
      } else {
        await _inboundJournal.markAppliedInTransaction(txn, transportNodeId);
      }
      return result;
    });
  }

  void _requireKind(
    PosFinancialSyncEvent event,
    PosFinancialEventKind expected,
    String transportNodeId,
  ) {
    if (event.version != 2 ||
        event.kind != expected ||
        transportNodeId.trim().isEmpty) {
      throw const FormatException('Invalid POS financial transaction identity');
    }
  }
}
