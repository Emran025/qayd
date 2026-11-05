import 'package:qayd/domain/repositories/sync_inbound_event_journal_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// SQLCipher-backed journal for fail-closed inbound sync processing.
final class SqliteSyncInboundEventJournalRepository
    implements SyncInboundEventJournalRepository {
  const SqliteSyncInboundEventJournalRepository(this._db);

  final Database _db;
  static const _table = 'sync_inbound_event_journal';
  static const _processingLease = Duration(minutes: 30);
  static const _financialEventTypes = {
    'posSale',
    'posPurchase',
    'posSalesReturn',
    'posPurchaseReturn',
    'posCollection',
  };

  @override
  Future<SyncInboundEventClaim> beginProcessing({
    required String nodeId,
    required String? senderPublicKey,
    required String eventType,
    required String payloadFingerprint,
    required String encryptedPayload,
  }) async {
    return _db.transaction(
      (txn) => beginProcessingInTransaction(
        txn,
        nodeId: nodeId,
        senderPublicKey: senderPublicKey,
        eventType: eventType,
        payloadFingerprint: payloadFingerprint,
        encryptedPayload: encryptedPayload,
      ),
    );
  }

  @override
  Future<SyncInboundEventClaim> beginProcessingInTransaction(
    Transaction txn, {
    required String nodeId,
    required String? senderPublicKey,
    required String eventType,
    required String payloadFingerprint,
    required String encryptedPayload,
  }) async {
    return _beginProcessing(
      txn,
      nodeId: nodeId,
      senderPublicKey: senderPublicKey,
      eventType: eventType,
      payloadFingerprint: payloadFingerprint,
      encryptedPayload: encryptedPayload,
    );
  }

  Future<SyncInboundEventClaim> _beginProcessing(
    DatabaseExecutor executor, {
    required String nodeId,
    required String? senderPublicKey,
    required String eventType,
    required String payloadFingerprint,
    required String encryptedPayload,
  }) async {
    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();
    final rows = await executor.query(
      _table,
      where: 'node_id = ?',
      whereArgs: [nodeId],
      limit: 1,
    );
    if (rows.isEmpty) {
      await executor.insert(_table, <String, Object?>{
        'node_id': nodeId,
        'sender_public_key': senderPublicKey,
        'event_type': eventType,
        'payload_fingerprint': payloadFingerprint,
        'encrypted_payload': encryptedPayload,
        'state': 'processing',
        'created_at': nowIso,
        'updated_at': nowIso,
      });
      return SyncInboundEventClaim.claimed;
    }

    final row = rows.single;
    if (row['payload_fingerprint'] != payloadFingerprint) {
      final conflictState = row['state'] == 'applied'
          ? 'applied'
          : 'quarantined';
      await executor.rawUpdate(
        '''
        UPDATE $_table
        SET state = ?, reason_code = ?,
            conflicting_payload_fingerprint =
              COALESCE(conflicting_payload_fingerprint, ?),
            conflicting_encrypted_payload =
              COALESCE(conflicting_encrypted_payload, ?),
            conflict_count = conflict_count + 1,
            updated_at = ?
        WHERE node_id = ?
        ''',
        [
          conflictState,
          SyncInboundQuarantineReason.conflictingPayload.name,
          payloadFingerprint,
          encryptedPayload,
          nowIso,
          nodeId,
        ],
      );
      return SyncInboundEventClaim.conflictingPayload;
    }

    switch (row['state']) {
      case 'applied':
        return SyncInboundEventClaim.alreadyApplied;
      case 'quarantined':
        return SyncInboundEventClaim.quarantined;
      case 'processing':
        final lastUpdated = DateTime.tryParse(
          row['updated_at'] as String? ?? '',
        );
        if (lastUpdated != null &&
            now.difference(lastUpdated) <= _processingLease) {
          return SyncInboundEventClaim.inProgress;
        }
        if (_financialEventTypes.contains(row['event_type'])) {
          // Financial posting, event inbox, and journal-applied state share a
          // single commit. If the transaction did not commit, replay is safe;
          // if it did, the financial inbox makes the replay a no-op.
          final claimed = await executor.update(
            _table,
            {'updated_at': nowIso},
            where: 'node_id = ? AND state = ? AND updated_at = ?',
            whereArgs: [nodeId, 'processing', row['updated_at']],
          );
          return claimed == 1
              ? SyncInboundEventClaim.claimed
              : SyncInboundEventClaim.inProgress;
        }
        // A stale processing row has an ambiguous outcome: the app could
        // have stopped after committing business writes but before marking
        // this event applied. Never re-run that handler automatically.
        await executor.update(
          _table,
          {
            'state': 'quarantined',
            'reason_code':
                SyncInboundQuarantineReason.processingInterrupted.name,
            'updated_at': nowIso,
          },
          where: 'node_id = ? AND state = ?',
          whereArgs: [nodeId, 'processing'],
        );
        return SyncInboundEventClaim.quarantined;
      case 'pending':
        await executor.update(
          _table,
          {'state': 'processing', 'reason_code': null, 'updated_at': nowIso},
          where: 'node_id = ? AND state = ?',
          whereArgs: [nodeId, 'pending'],
        );
        return SyncInboundEventClaim.claimed;
      default:
        throw StateError('Unknown inbound sync journal state.');
    }
  }

  @override
  Future<void> markApplied(String nodeId) async {
    await _db.transaction((txn) => markAppliedInTransaction(txn, nodeId));
  }

  @override
  Future<void> markAppliedInTransaction(Transaction txn, String nodeId) async {
    await _updateProcessing(txn, nodeId, <String, Object?>{
      'state': 'applied',
      'reason_code': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> returnToPending(String nodeId) async {
    await _db.transaction((txn) => returnToPendingInTransaction(txn, nodeId));
  }

  @override
  Future<void> returnToPendingInTransaction(
    Transaction txn,
    String nodeId,
  ) async {
    await _updateProcessing(txn, nodeId, <String, Object?>{
      'state': 'pending',
      'reason_code': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> quarantine({
    required String nodeId,
    required SyncInboundQuarantineReason reason,
    required String encryptedPayload,
  }) async {
    await _db.transaction(
      (txn) => quarantineInTransaction(
        txn,
        nodeId: nodeId,
        reason: reason,
        encryptedPayload: encryptedPayload,
      ),
    );
  }

  @override
  Future<void> quarantineInTransaction(
    Transaction txn, {
    required String nodeId,
    required SyncInboundQuarantineReason reason,
    required String encryptedPayload,
  }) async {
    final updated = await txn.update(
      _table,
      <String, Object?>{
        'state': 'quarantined',
        'reason_code': reason.name,
        'encrypted_payload': encryptedPayload,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: "node_id = ? AND state IN ('processing', 'quarantined')",
      whereArgs: [nodeId],
    );
    if (updated != 1) {
      throw StateError('Inbound sync journal cannot be quarantined.');
    }
  }

  @override
  Future<List<SyncInboundQuarantinedEvent>> listQuarantined({
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 1000) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 1000.');
    }
    final rows = await _db.query(
      _table,
      where: 'state = ? OR conflict_count > 0',
      whereArgs: ['quarantined'],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(_toQuarantinedEvent).toList(growable: false);
  }

  Future<void> _updateProcessing(
    DatabaseExecutor executor,
    String nodeId,
    Map<String, Object?> values,
  ) async {
    final updated = await executor.update(
      _table,
      values,
      where: 'node_id = ? AND state = ?',
      whereArgs: [nodeId, 'processing'],
    );
    if (updated != 1) {
      throw StateError('Inbound sync journal state changed unexpectedly.');
    }
  }

  SyncInboundQuarantinedEvent _toQuarantinedEvent(Map<String, Object?> row) {
    final reasonCode = row['reason_code'] as String?;
    final reason = SyncInboundQuarantineReason.values.firstWhere(
      (candidate) => candidate.name == reasonCode,
      orElse: () => SyncInboundQuarantineReason.invalidPayload,
    );
    final encryptedPayload = row['encrypted_payload'] as String?;
    return SyncInboundQuarantinedEvent(
      nodeId: row['node_id'] as String,
      eventType: row['event_type'] as String,
      payloadFingerprint: row['payload_fingerprint'] as String,
      encryptedPayload: encryptedPayload,
      reason: reason,
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      conflictingPayloadFingerprint:
          row['conflicting_payload_fingerprint'] as String?,
      conflictingEncryptedPayload:
          row['conflicting_encrypted_payload'] as String?,
      conflictCount: row['conflict_count'] as int? ?? 0,
    );
  }
}
