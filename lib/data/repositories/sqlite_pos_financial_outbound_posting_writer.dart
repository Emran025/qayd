import 'dart:convert';

import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/mappers/pos_invoice_payment_collection_sync_snapshot_codec.dart';
import 'package:qayd/data/mappers/pos_purchase_sync_snapshot_codec.dart';
import 'package:qayd/data/mappers/pos_sale_sync_snapshot_codec.dart';
import 'package:qayd/data/mappers/pos_sales_return_sync_snapshot_codec.dart';
import 'package:qayd/data/repositories/device_sync_outbox_dao.dart';
import 'package:qayd/data/repositories/pos_financial_event_store.dart';
import 'package:qayd/data/repositories/sqlite_pos_invoice_payment_collection_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_purchase_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_sale_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_sales_return_posting_repository.dart';
import 'package:qayd/domain/entities/pos_financial_outbound_bundle.dart';
import 'package:qayd/domain/entities/pos_financial_sync_event.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
import 'package:qayd/domain/entities/pos_purchase_posting.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';
import 'package:qayd/domain/entities/sync_node.dart';
import 'package:qayd/domain/repositories/pos_financial_outbound_posting_writer.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Commits the local business posting, encrypted financial outbox, and one
/// device-routed outbox row per paired recipient under the same SQLite commit.
final class SqlitePosFinancialOutboundPostingWriter
    implements PosFinancialOutboundPostingWriter {
  const SqlitePosFinancialOutboundPostingWriter({
    required DatabaseTransactionRunner transactionRunner,
    required PosFinancialEventStore eventStore,
    required DeviceSyncOutboxDao deviceSyncOutboxDao,
    required SqlitePosSalePostingRepository saleRepository,
    required SqlitePosPurchasePostingRepository purchaseRepository,
    required SqlitePosSalesReturnPostingRepository salesReturnRepository,
    required SqlitePosInvoicePaymentCollectionRepository collectionRepository,
  }) : _transactionRunner = transactionRunner,
       _eventStore = eventStore,
       _deviceSyncOutboxDao = deviceSyncOutboxDao,
       _saleRepository = saleRepository,
       _purchaseRepository = purchaseRepository,
       _salesReturnRepository = salesReturnRepository,
       _collectionRepository = collectionRepository;

  final DatabaseTransactionRunner _transactionRunner;
  final PosFinancialEventStore _eventStore;
  final DeviceSyncOutboxDao _deviceSyncOutboxDao;
  final SqlitePosSalePostingRepository _saleRepository;
  final SqlitePosPurchasePostingRepository _purchaseRepository;
  final SqlitePosSalesReturnPostingRepository _salesReturnRepository;
  final SqlitePosInvoicePaymentCollectionRepository _collectionRepository;

  @override
  Future<Result<void>> saveSaleWithOutboundAtomically(
    PosSalePosting posting,
    PosFinancialOutboundBundle bundle,
  ) => _writeInvoice(
    kind: PosFinancialEventKind.sale,
    invoice: posting.invoice,
    snapshot: PosSaleSyncSnapshotCodec.encode(posting),
    bundle: bundle,
    save: (txn) => _saleRepository.saveInTransaction(txn, posting),
  );

  @override
  Future<Result<void>> savePurchaseWithOutboundAtomically(
    PosPurchasePosting posting,
    PosFinancialOutboundBundle bundle,
  ) => _writeInvoice(
    kind: PosFinancialEventKind.purchase,
    invoice: posting.invoice,
    snapshot: PosPurchaseSyncSnapshotCodec.encode(posting),
    bundle: bundle,
    save: (txn) => _purchaseRepository.saveInTransaction(txn, posting),
  );

  @override
  Future<Result<void>> saveSalesReturnWithOutboundAtomically(
    PosSalesReturnPosting posting,
    PosFinancialOutboundBundle bundle,
  ) => _writeInvoice(
    kind: PosFinancialEventKind.salesReturn,
    invoice: posting.invoice,
    snapshot: PosSalesReturnSyncSnapshotCodec.encode(posting),
    bundle: bundle,
    save: (txn) => _salesReturnRepository.saveInTransaction(txn, posting),
  );

  @override
  Future<Result<void>> saveCollectionWithOutboundAtomically(
    PosInvoicePaymentCollectionPosting posting,
    PosFinancialOutboundBundle bundle,
  ) {
    final payment = posting.payment;
    final expectedSnapshot =
        PosInvoicePaymentCollectionSyncSnapshotCodec.encode(posting);
    final event = bundle.event;
    if (event.kind != PosFinancialEventKind.collection ||
        event.eventId != payment.id ||
        event.aggregateId != payment.invoiceId ||
        event.idempotencyKey != payment.idempotencyKey ||
        event.currencyCode != payment.currency.code ||
        event.totalMinor != payment.amount.minorUnits ||
        event.occurredAt.toUtc() != payment.occurredAt.toUtc() ||
        event.lines.isNotEmpty ||
        !_sameJson(event.snapshot, expectedSnapshot)) {
      return Future.value(_invalidBundle());
    }
    return _write(
      event: event,
      bundle: bundle,
      expectedKind: PosFinancialEventKind.collection,
      save: (txn) => _collectionRepository.saveInTransaction(txn, posting),
    );
  }

  Future<Result<void>> _writeInvoice({
    required PosFinancialEventKind kind,
    required PosInvoice invoice,
    required Map<String, Object?> snapshot,
    required PosFinancialOutboundBundle bundle,
    required Future<void> Function(Transaction txn) save,
  }) {
    final event = bundle.event;
    if (event.kind != kind ||
        event.eventId != invoice.id ||
        event.aggregateId != invoice.id ||
        event.idempotencyKey != invoice.idempotencyKey ||
        event.currencyCode != invoice.currency.code ||
        event.totalMinor != invoice.total.minorUnits ||
        event.occurredAt.toUtc() != invoice.invoiceDate.toUtc() ||
        event.lines.length != invoice.lines.length ||
        !_sameJson(event.snapshot, snapshot)) {
      return Future.value(_invalidBundle());
    }
    for (var i = 0; i < invoice.lines.length; i++) {
      final line = invoice.lines[i];
      final summary = event.lines[i];
      if (summary.productId != line.productId ||
          summary.quantityScaled != line.quantity.scaledUnits ||
          summary.quantityScale != line.quantity.scale ||
          summary.unitPriceMinor != line.unitPrice.minorUnits ||
          summary.totalMinor != line.lineTotal.minorUnits) {
        return Future.value(_invalidBundle());
      }
    }
    return _write(event: event, bundle: bundle, expectedKind: kind, save: save);
  }

  Future<Result<void>> _write({
    required PosFinancialSyncEvent event,
    required PosFinancialOutboundBundle bundle,
    required PosFinancialEventKind expectedKind,
    required Future<void> Function(Transaction txn) save,
  }) async {
    if (!_validBundle(event, bundle, expectedKind)) return _invalidBundle();
    try {
      await _transactionRunner.run<void>((txn) async {
        final stored = await _eventStore.enqueueOutboundInTransaction(
          txn,
          event: event,
          encryptedPayload: bundle.localEncryptedPayload,
        );
        if (!stored) {
          throw StateError('Conflicting immutable POS outbound event.');
        }
        await save(txn);
        for (final delivery in bundle.deliveries) {
          await _deviceSyncOutboxDao.enqueueInTransaction(
            txn,
            DeviceSyncOutboxEntry(
              id: delivery.nodeId,
              auditEntryId: event.eventId,
              targetDeviceId: delivery.targetDeviceId,
              encryptedPayload: delivery.encryptedPayload,
              signature: delivery.signature,
              state: 'pending',
              retryCount: 0,
              createdAt: delivery.createdAt,
              eventType: delivery.eventType,
            ),
          );
        }
      });
      return const Success(null);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posAccountingTransactionFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posAccountingTransactionFailed),
      );
    }
  }

  bool _validBundle(
    PosFinancialSyncEvent event,
    PosFinancialOutboundBundle bundle,
    PosFinancialEventKind expectedKind,
  ) {
    final source = event.sourceDeviceId;
    if (event.version != 2 ||
        event.kind != expectedKind ||
        event.ownerUserId == null ||
        event.ownerUserId! <= 0 ||
        source == null ||
        source.isEmpty ||
        event.targetDeviceId != source ||
        bundle.localEncryptedPayload.trim().isEmpty ||
        bundle.deliveries.isEmpty) {
      return false;
    }
    try {
      final parsed = PosFinancialSyncEvent.fromJson(event.toJson());
      if (parsed.payloadFingerprint != event.payloadFingerprint) return false;
    } catch (_) {
      return false;
    }

    final expectedType = _syncType(expectedKind).name;
    final nodeIds = <String>{};
    final targetIds = <String>{};
    for (final delivery in bundle.deliveries) {
      if (delivery.nodeId.trim().isEmpty ||
          delivery.targetDeviceId.trim().isEmpty ||
          delivery.targetDeviceId == source ||
          delivery.eventType != expectedType ||
          delivery.encryptedPayload.trim().isEmpty ||
          delivery.signature !=
              base64Encode(
                utf8.encode(
                  '${delivery.targetDeviceId}|${delivery.encryptedPayload}',
                ),
              ) ||
          !nodeIds.add(delivery.nodeId) ||
          !targetIds.add(delivery.targetDeviceId)) {
        return false;
      }
    }
    return true;
  }

  Result<void> _invalidBundle() => FailureResult(
    ValidationFailure(
      messageAr: AppStrings.posInvoiceInvalid,
      code: 'pos_financial_outbound_bundle_invalid',
    ),
  );

  bool _sameJson(Object? left, Object? right) =>
      _canonicalJson(left) == _canonicalJson(right);

  String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }

  SyncEventType _syncType(PosFinancialEventKind kind) => switch (kind) {
    PosFinancialEventKind.sale => SyncEventType.posSale,
    PosFinancialEventKind.purchase => SyncEventType.posPurchase,
    PosFinancialEventKind.salesReturn => SyncEventType.posSalesReturn,
    PosFinancialEventKind.purchaseReturn => SyncEventType.posPurchaseReturn,
    PosFinancialEventKind.collection => SyncEventType.posCollection,
  };
}
