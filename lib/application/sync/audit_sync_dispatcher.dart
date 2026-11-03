import 'package:qayd/application/sync/audit_sync_compression_service.dart';

import 'dart:convert';

import 'package:qayd/data/repositories/device_sync_outbox_dao.dart';
import 'package:qayd/domain/entities/audit_entry.dart';
import 'package:qayd/domain/services/e2ee_encryption_service.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:uuid/uuid.dart';

class AuditSyncDispatcher {
  AuditSyncDispatcher({
    required this.outboxDao,
    required this.e2eeService,
    required this.getCurrentKeyPair,
    this.compressionService = const AuditSyncCompressionService(),
  });

  final DeviceSyncOutboxDao outboxDao;
  final E2EEEncryptionService e2eeService;
  final Future<CryptoKeyPair?> Function() getCurrentKeyPair;
  final AuditSyncCompressionService compressionService;

  Future<void> dispatchEntryToDevice({
    required AuditEntry entry,
    required String targetDeviceId,
    required String receiverPublicKeyHex,
    SyncPacketReason? reason,
  }) async {
    await dispatchBatchToDevice(
      entries: [entry],
      targetDeviceId: targetDeviceId,
      receiverPublicKeyHex: receiverPublicKeyHex,
      reason: reason,
    );
  }

  Future<void> dispatchBatchToDevice({
    required List<AuditEntry> entries,
    required String targetDeviceId,
    required String receiverPublicKeyHex,
    bool isLastBatch = false,
    int? batchIndex,
    int? totalBatches,
    SyncPacketReason? reason,
  }) async {
    if (entries.isEmpty) return;
    final keyPair = await getCurrentKeyPair();
    if (keyPair == null) return;

    final compressed = compressionService.compressBatch(
      entries,
      reason: reason ?? SyncPacketReason.liveEvent,
    );
    final payload = {
      'kind': 'audit_batch',
      'encoding': 'gzip+base64',
      'entries_gzip': base64Encode(compressed),
      'entry_count': entries.length,
      'is_last_batch': isLastBatch,
      if (batchIndex != null) 'batch_index': batchIndex,
      if (totalBatches != null) 'total_batches': totalBatches,
    };
    final nodeId = const Uuid().v4();
    final encrypted = await e2eeService.encryptPayload(
      rawPayload: payload,
      senderKeyPair: keyPair,
      receiverPublicKeyHex: receiverPublicKeyHex,
      nodeId: nodeId,
      eventType: 'auditBatch',
    );

    final envelope = '$targetDeviceId|$encrypted';
    final signature = base64Encode(utf8.encode(envelope));
    await outboxDao.enqueue(
      DeviceSyncOutboxEntry(
        id: nodeId,
        auditEntryId: entries.first.id,
        targetDeviceId: targetDeviceId,
        encryptedPayload: encrypted,
        signature: signature,
        state: 'pending',
        retryCount: 0,
        createdAt: DateTime.now(),
      ),
    );
  }
}
