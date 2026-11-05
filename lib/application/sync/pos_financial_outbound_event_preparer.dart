import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:qayd/data/mappers/pos_invoice_payment_collection_sync_snapshot_codec.dart';
import 'package:qayd/data/mappers/pos_purchase_sync_snapshot_codec.dart';
import 'package:qayd/data/mappers/pos_sale_sync_snapshot_codec.dart';
import 'package:qayd/data/mappers/pos_sales_return_sync_snapshot_codec.dart';
import 'package:qayd/data/mappers/pos_purchase_return_sync_snapshot_codec.dart';
import 'package:qayd/domain/entities/pos_financial_outbound_bundle.dart';
import 'package:qayd/domain/entities/pos_financial_sync_event.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_purchase_posting.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';
import 'package:qayd/domain/entities/pos_purchase_return_posting.dart';
import 'package:qayd/domain/repositories/device_session_repository.dart';
import 'package:qayd/domain/services/e2ee_encryption_service.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/entities/sync_node.dart';

/// Builds immutable same-account POS events and encrypts one envelope per
/// active paired device. It performs no database writes.
final class PosFinancialOutboundEventPreparer {
  const PosFinancialOutboundEventPreparer({
    required DeviceSessionRepository deviceSessionRepository,
    required E2EEEncryptionService encryptionService,
    required Future<CryptoKeyPair?> Function() getCurrentUserKeyPair,
    required int ownerUserId,
    required String currentDeviceId,
  }) : _deviceSessionRepository = deviceSessionRepository,
       _encryptionService = encryptionService,
       _getCurrentUserKeyPair = getCurrentUserKeyPair,
       _ownerUserId = ownerUserId,
       _currentDeviceId = currentDeviceId;

  final DeviceSessionRepository _deviceSessionRepository;
  final E2EEEncryptionService _encryptionService;
  final Future<CryptoKeyPair?> Function() _getCurrentUserKeyPair;
  final int _ownerUserId;
  final String _currentDeviceId;

  Future<PosFinancialOutboundBundle?> prepareSale(PosSalePosting posting) =>
      _prepareInvoice(
        kind: PosFinancialEventKind.sale,
        invoice: posting.invoice,
        snapshot: PosSaleSyncSnapshotCodec.encode(posting),
      );

  Future<PosFinancialOutboundBundle?> preparePurchase(
    PosPurchasePosting posting,
  ) => _prepareInvoice(
    kind: PosFinancialEventKind.purchase,
    invoice: posting.invoice,
    snapshot: PosPurchaseSyncSnapshotCodec.encode(posting),
  );

  Future<PosFinancialOutboundBundle?> prepareSalesReturn(
    PosSalesReturnPosting posting,
  ) => _prepareInvoice(
    kind: PosFinancialEventKind.salesReturn,
    invoice: posting.invoice,
    snapshot: PosSalesReturnSyncSnapshotCodec.encode(posting),
  );

  Future<PosFinancialOutboundBundle?> preparePurchaseReturn(
    PosPurchaseReturnPosting posting,
  ) => _prepareInvoice(
    kind: PosFinancialEventKind.purchaseReturn,
    invoice: posting.invoice,
    snapshot: PosPurchaseReturnSyncSnapshotCodec.encode(posting),
  );

  Future<PosFinancialOutboundBundle?> prepareCollection(
    PosInvoicePaymentCollectionPosting posting,
  ) {
    final payment = posting.payment;
    return _prepare(
      kind: PosFinancialEventKind.collection,
      eventId: payment.id,
      aggregateId: payment.invoiceId,
      idempotencyKey: payment.idempotencyKey,
      currencyCode: payment.currency.code,
      occurredAt: payment.occurredAt,
      totalMinor: payment.amount.minorUnits,
      lines: const [],
      snapshot: PosInvoicePaymentCollectionSyncSnapshotCodec.encode(posting),
    );
  }

  Future<PosFinancialOutboundBundle?> _prepareInvoice({
    required PosFinancialEventKind kind,
    required PosInvoice invoice,
    required Map<String, Object?> snapshot,
  }) => _prepare(
    kind: kind,
    eventId: invoice.id,
    aggregateId: invoice.id,
    idempotencyKey: invoice.idempotencyKey,
    currencyCode: invoice.currency.code,
    occurredAt: invoice.invoiceDate,
    totalMinor: invoice.total.minorUnits,
    lines: invoice.lines
        .map(
          (line) => PosFinancialSyncLine(
            productId: line.productId,
            quantityScaled: line.quantity.scaledUnits,
            quantityScale: line.quantity.scale,
            unitPriceMinor: line.unitPrice.minorUnits,
            totalMinor: line.lineTotal.minorUnits,
          ),
        )
        .toList(growable: false),
    snapshot: snapshot,
  );

  Future<PosFinancialOutboundBundle?> _prepare({
    required PosFinancialEventKind kind,
    required String eventId,
    required String aggregateId,
    required String idempotencyKey,
    required String currencyCode,
    required DateTime occurredAt,
    required int totalMinor,
    required List<PosFinancialSyncLine> lines,
    required Map<String, Object?> snapshot,
  }) async {
    if (_ownerUserId <= 0 || _currentDeviceId.trim().isEmpty) return null;

    final active = await _deviceSessionRepository.listActive();
    final targets = active
        .where(
          (session) =>
              session.isActive &&
              !session.isCurrent &&
              session.deviceId != _currentDeviceId,
        )
        .toList(growable: false);
    if (targets.isEmpty) return null;

    final keyPair = await _getCurrentUserKeyPair();
    if (keyPair == null) {
      throw StateError('Paired POS sync requires the current device key pair.');
    }
    final senderPublicKey = keyPair.publicKeyHex.trim().toLowerCase();
    if (!_isPublicKey(senderPublicKey)) {
      throw StateError('Current device public key is invalid.');
    }
    final ownSession = await _deviceSessionRepository.getById(_currentDeviceId);
    if (ownSession == null ||
        !ownSession.isActive ||
        !ownSession.isCurrent ||
        ownSession.publicKeyHex.trim().toLowerCase() != senderPublicKey) {
      throw StateError(
        'Current device is not registered as the active paired device.',
      );
    }

    final targetIds = <String>{};
    for (final session in targets) {
      final id = session.deviceId.trim();
      if (id.isEmpty ||
          !targetIds.add(id) ||
          !_isPublicKey(session.publicKeyHex)) {
        throw StateError(
          'A paired device has invalid or duplicate key metadata.',
        );
      }
    }

    final eventType = _syncType(kind).name;
    final common = <String, Object?>{
      'version': 2,
      'kind': kind.name,
      'owner_user_id': _ownerUserId,
      'source_device_id': _currentDeviceId,
      'event_id': eventId,
      'aggregate_id': aggregateId,
      'idempotency_key': idempotencyKey,
      'currency_code': currencyCode,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'total_minor': totalMinor,
      'lines': lines.map((line) => line.toJson()).toList(growable: false),
      'snapshot': snapshot,
    };

    Map<String, Object?> eventMapFor(String targetDeviceId) => {
      ...common,
      'target_device_id': targetDeviceId,
    };

    final localEvent = PosFinancialSyncEvent.fromJson(
      eventMapFor(_currentDeviceId),
    );
    final localNodeId = _stableNodeId(
      event: localEvent,
      senderPublicKey: senderPublicKey,
      receiverPublicKey: senderPublicKey,
    );
    final localEncrypted = await _encryptionService.encryptPayload(
      rawPayload: Map<String, dynamic>.from(localEvent.toJson()),
      senderKeyPair: keyPair,
      receiverPublicKeyHex: senderPublicKey,
      nodeId: localNodeId,
      eventType: eventType,
    );

    final deliveries = <PosFinancialOutboundDelivery>[];
    for (final session in targets) {
      final targetId = session.deviceId.trim();
      final event = PosFinancialSyncEvent.fromJson(eventMapFor(targetId));
      final targetPublicKey = session.publicKeyHex.trim().toLowerCase();
      final nodeId = _stableNodeId(
        event: event,
        senderPublicKey: senderPublicKey,
        receiverPublicKey: targetPublicKey,
      );
      final encrypted = await _encryptionService.encryptPayload(
        rawPayload: Map<String, dynamic>.from(event.toJson()),
        senderKeyPair: keyPair,
        receiverPublicKeyHex: targetPublicKey,
        nodeId: nodeId,
        eventType: eventType,
      );
      deliveries.add(
        PosFinancialOutboundDelivery(
          nodeId: nodeId,
          eventType: eventType,
          targetDeviceId: targetId,
          encryptedPayload: encrypted,
          signature: base64Encode(utf8.encode('$targetId|$encrypted')),
          createdAt: DateTime.now().toUtc(),
        ),
      );
    }

    return PosFinancialOutboundBundle(
      event: localEvent,
      localEncryptedPayload: localEncrypted,
      deliveries: deliveries,
    );
  }

  bool _isPublicKey(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  String _stableNodeId({
    required PosFinancialSyncEvent event,
    required String senderPublicKey,
    required String receiverPublicKey,
  }) {
    final digest = sha256
        .convert(
          utf8.encode(
            'qayd-pos-financial-v2\u0000${event.payloadFingerprint}'
            '\u0000${event.sourceDeviceId}\u0000${event.targetDeviceId}'
            '\u0000$senderPublicKey\u0000$receiverPublicKey',
          ),
        )
        .bytes;
    final bytes = List<int>.from(digest.take(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  SyncEventType _syncType(PosFinancialEventKind kind) => switch (kind) {
    PosFinancialEventKind.sale => SyncEventType.posSale,
    PosFinancialEventKind.purchase => SyncEventType.posPurchase,
    PosFinancialEventKind.salesReturn => SyncEventType.posSalesReturn,
    PosFinancialEventKind.purchaseReturn => SyncEventType.posPurchaseReturn,
    PosFinancialEventKind.collection => SyncEventType.posCollection,
  };
}
