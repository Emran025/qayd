import 'package:qayd/data/mappers/pos_invoice_payment_collection_sync_snapshot_codec.dart';
import 'package:qayd/data/mappers/pos_purchase_sync_snapshot_codec.dart';
import 'package:qayd/data/mappers/pos_sale_sync_snapshot_codec.dart';
import 'package:qayd/data/mappers/pos_sales_return_sync_snapshot_codec.dart';
import 'package:qayd/data/mappers/pos_purchase_return_sync_snapshot_codec.dart';
import 'package:qayd/domain/entities/device_session.dart';
import 'package:qayd/domain/entities/pos_financial_apply_result.dart';
import 'package:qayd/domain/entities/pos_financial_sync_event.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/sync_node.dart';
import 'package:qayd/domain/repositories/device_session_repository.dart';
import 'package:qayd/domain/repositories/pos_financial_inbound_application_repository.dart';

/// Authenticates and applies a POS financial event sent by another device
/// paired to the same Qayd account. This is not a counterparty auto-post path.
final class ApplyInboundPosFinancialEventUseCase {
  const ApplyInboundPosFinancialEventUseCase({
    required DeviceSessionRepository deviceSessionRepository,
    required PosFinancialInboundApplicationRepository applicationRepository,
    required int currentUserId,
    required String currentDeviceId,
  }) : _deviceSessionRepository = deviceSessionRepository,
       _applicationRepository = applicationRepository,
       _currentUserId = currentUserId,
       _currentDeviceId = currentDeviceId;

  final DeviceSessionRepository _deviceSessionRepository;
  final PosFinancialInboundApplicationRepository _applicationRepository;
  final int _currentUserId;
  final String _currentDeviceId;

  /// Returns the paired device key only when server routing and the local
  /// paired-device registry both prove this is a same-account device event.
  Future<String?> trustedSenderPublicKey(SyncNode node) async {
    if (!_isFinancialNode(node.eventType) ||
        _currentUserId <= 0 ||
        node.senderId != _currentUserId ||
        node.receiverId != _currentUserId ||
        node.targetDeviceId != _currentDeviceId) {
      return null;
    }
    final senderDeviceId = node.senderDeviceId?.trim();
    if (senderDeviceId == null ||
        senderDeviceId.isEmpty ||
        senderDeviceId == _currentDeviceId) {
      return null;
    }

    final DeviceSession? session = await _deviceSessionRepository.getById(
      senderDeviceId,
    );
    if (session == null ||
        session.deviceId != senderDeviceId ||
        !session.isActive ||
        session.isCurrent) {
      return null;
    }
    final key = session.publicKeyHex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) return null;
    final envelopeKey = node.senderPublicKey?.trim().toLowerCase();
    if (envelopeKey != null && envelopeKey != key) return null;
    return key;
  }

  Future<PosFinancialApplyResult> call({
    required SyncNode node,
    required Map<String, dynamic> decryptedPayload,
  }) async {
    if (await trustedSenderPublicKey(node) == null) {
      throw const FormatException(
        'POS sender device is not an active paired device',
      );
    }
    final raw = <String, Object?>{};
    for (final entry in decryptedPayload.entries) {
      raw[entry.key] = entry.value;
    }
    final event = PosFinancialSyncEvent.fromJson(raw);
    if (event.version != 2 ||
        event.ownerUserId != _currentUserId ||
        event.sourceDeviceId != node.senderDeviceId ||
        event.targetDeviceId != _currentDeviceId ||
        node.targetDeviceId != _currentDeviceId ||
        node.senderId != _currentUserId ||
        node.receiverId != _currentUserId) {
      throw const FormatException(
        'POS event is not routed to this paired account/device',
      );
    }
    if (node.eventType != _syncTypeFor(event.kind)) {
      throw const FormatException(
        'POS event kind does not match its sync envelope',
      );
    }

    switch (event.kind) {
      case PosFinancialEventKind.sale:
        final posting = PosSaleSyncSnapshotCodec.decode(event.snapshot);
        _validateInvoiceEvent(event, posting.invoice);
        return _applicationRepository.applySaleAtomically(
          event: event,
          posting: posting,
          transportNodeId: node.id,
          encryptedPayload: node.encryptedPayload,
        );
      case PosFinancialEventKind.purchase:
        final posting = PosPurchaseSyncSnapshotCodec.decode(event.snapshot);
        _validateInvoiceEvent(event, posting.invoice);
        return _applicationRepository.applyPurchaseAtomically(
          event: event,
          posting: posting,
          transportNodeId: node.id,
          encryptedPayload: node.encryptedPayload,
        );
      case PosFinancialEventKind.salesReturn:
        final posting = PosSalesReturnSyncSnapshotCodec.decode(event.snapshot);
        _validateInvoiceEvent(event, posting.invoice);
        return _applicationRepository.applySalesReturnAtomically(
          event: event,
          posting: posting,
          transportNodeId: node.id,
          encryptedPayload: node.encryptedPayload,
        );
      case PosFinancialEventKind.collection:
        final posting = PosInvoicePaymentCollectionSyncSnapshotCodec.decode(
          event.snapshot,
        );
        final payment = posting.payment;
        if (event.eventId != payment.id ||
            event.aggregateId != payment.invoiceId ||
            event.idempotencyKey != payment.idempotencyKey ||
            event.currencyCode != payment.currency.code ||
            event.totalMinor != payment.amount.minorUnits ||
            event.occurredAt.toUtc() != payment.occurredAt.toUtc() ||
            event.lines.isNotEmpty ||
            posting.invoiceBefore.id != payment.invoiceId ||
            posting.invoiceAfter.id != payment.invoiceId) {
          throw const FormatException(
            'Collection event summary does not match its snapshot',
          );
        }
        return _applicationRepository.applyCollectionAtomically(
          event: event,
          posting: posting,
          transportNodeId: node.id,
          encryptedPayload: node.encryptedPayload,
        );
      case PosFinancialEventKind.purchaseReturn:
        final posting = PosPurchaseReturnSyncSnapshotCodec.decode(
          event.snapshot,
        );
        _validateInvoiceEvent(event, posting.invoice);
        return _applicationRepository.applyPurchaseReturnAtomically(
          event: event,
          posting: posting,
          transportNodeId: node.id,
          encryptedPayload: node.encryptedPayload,
        );
    }
  }

  void _validateInvoiceEvent(PosFinancialSyncEvent event, PosInvoice invoice) {
    if (event.eventId != invoice.id ||
        event.aggregateId != invoice.id ||
        event.idempotencyKey != invoice.idempotencyKey ||
        event.currencyCode != invoice.currency.code ||
        event.totalMinor != invoice.total.minorUnits ||
        event.occurredAt.toUtc() != invoice.invoiceDate.toUtc() ||
        event.lines.length != invoice.lines.length) {
      throw const FormatException(
        'POS document summary does not match its snapshot',
      );
    }
    for (var i = 0; i < invoice.lines.length; i++) {
      final line = invoice.lines[i];
      final summary = event.lines[i];
      if (summary.productId != line.productId ||
          summary.quantityScaled != line.quantity.scaledUnits ||
          summary.quantityScale != line.quantity.scale ||
          summary.unitPriceMinor != line.unitPrice.minorUnits ||
          summary.totalMinor != line.lineTotal.minorUnits) {
        throw const FormatException(
          'POS line summary does not match its snapshot',
        );
      }
    }
  }

  SyncEventType _syncTypeFor(PosFinancialEventKind kind) => switch (kind) {
    PosFinancialEventKind.sale => SyncEventType.posSale,
    PosFinancialEventKind.purchase => SyncEventType.posPurchase,
    PosFinancialEventKind.salesReturn => SyncEventType.posSalesReturn,
    PosFinancialEventKind.purchaseReturn => SyncEventType.posPurchaseReturn,
    PosFinancialEventKind.collection => SyncEventType.posCollection,
  };

  bool _isFinancialNode(SyncEventType type) => switch (type) {
    SyncEventType.posSale ||
    SyncEventType.posPurchase ||
    SyncEventType.posSalesReturn ||
    SyncEventType.posPurchaseReturn ||
    SyncEventType.posCollection => true,
    _ => false,
  };
}
