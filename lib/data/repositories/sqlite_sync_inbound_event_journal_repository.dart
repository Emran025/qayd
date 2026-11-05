import 'package:qayd/domain/repositories/sync_inbound_event_journal_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// SQLCipher-backed journal for fail-closed inbound sync processing.
final class SqliteSyncInboundEventJournalRepository
    implements SyncInboundEventJournalRepository {
  const SqliteSyncInboundEventJournalRepository(this._db);

  final Database _db;
  static const _table = 'sync_inbound_event_journal';
  static const _processingLease = Duration(minutes: 30);

  @override
  Future<SyncInboundEventClaim> beginProcessing({
    required String nodeId,
    required String? senderPublicKey,
    required String eventType,
    required String payloadFingerprint,
    required String encryptedPayload,
  }) async {
    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();
    return _db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        where: 'node_id = ?',
        whereArgs: [nodeId],
        limit: 1,
      );
      if (rows.isEmpty) {
        await txn.insert(_table, <String, Object?>{
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
        await txn.rawUpdate(
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
            'quarantined',
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
          // A stale processing row has an ambiguous outcome: the app could
          // have stopped after committing business writes but before marking
          // this event applied. Never re-run that handler automatically.
          await txn.update(
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
          await txn.update(
            _table,
            {'state': 'processing', 'reason_code': null, 'updated_at': nowIso},
            where: 'node_id = ? AND state = ?',
            whereArgs: [nodeId, 'pending'],
          );
          return SyncInboundEventClaim.claimed;
        default:
          throw StateError('Unknown inbound sync journal state.');
      }
    });
  }

  @override
  Future<void> markApplied(String nodeId) async {
    await _updateProcessing(
      nodeId,
      <String, Object?>{
        'state': 'applied',
        'reason_code': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  @override
  Future<void> returnToPending(String nodeId) async {
    await _updateProcessing(
      nodeId,
      <String, Object?>{
        'state': 'pending',
        'reason_code': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  @override
  Future<void> quarantine({
    required String nodeId,
    required SyncInboundQuarantineReason reason,
    required String encryptedPayload,
  }) async {
    await _updateProcessing(
      nodeId,
      <String, Object?>{
        'state': 'quarantined',
        'reason_code': reason.name,
        'encrypted_payload': encryptedPayload,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
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
      where: 'state = ?',
      whereArgs: ['quarantined'],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(_toQuarantinedEvent).toList(growable: false);
  }

  Future<void> _updateProcessing(
    String nodeId,
    Map<String, Object?> values,
  ) async {
    final updated = await _db.update(
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
