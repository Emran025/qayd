import 'package:qayd/domain/entities/pos_financial_sync_event.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Result of the durable financial inbox gate.
enum PosFinancialApplyResult { applied, exactReplay, conflictingReplay }

/// Transaction boundary for POS financial replication.
///
/// Callers must perform invoice/stock/ledger writes in [Database.transaction]
/// and invoke [applyInbound] in the same callback. A conflict is persisted and
/// never returned as applied; an exact replay does not write business rows.
final class PosFinancialEventStore {
  const PosFinancialEventStore(this._db);

  final Database _db;

  /// Persists an encrypted financial event before transport is attempted.
  /// ConflictAlgorithm.ignore makes an exact retry harmless; callers must
  /// compare the immutable fingerprint before treating an ignored insert as
  /// success.
  Future<bool> enqueueOutbound({
    required PosFinancialSyncEvent event,
    required String encryptedPayload,
  }) async {
    final inserted = await _db.insert('pos_financial_event_outbox', {
      'event_id': event.eventId,
      'event_kind': event.kind.name,
      'aggregate_id': event.aggregateId,
      'idempotency_key': event.idempotencyKey,
      'payload_fingerprint': event.payloadFingerprint,
      'encrypted_payload': encryptedPayload,
      'state': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (inserted != 0) return true;
    final existing = await _db.query(
      'pos_financial_event_outbox',
      columns: ['payload_fingerprint'],
      where: 'event_id = ?',
      whereArgs: [event.eventId],
      limit: 1,
    );
    return existing.isNotEmpty &&
        existing.single['payload_fingerprint'] == event.payloadFingerprint;
  }

  Future<PosFinancialApplyResult> applyInbound(
    PosFinancialSyncEvent event, {
    required Future<void> Function(Transaction txn) applyBusinessMutation,
  }) {
    return _db.transaction((txn) async {
      final existing = await txn.query(
        'pos_financial_event_inbox',
        where: 'event_id = ?',
        whereArgs: [event.eventId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        if (row['payload_fingerprint'] == event.payloadFingerprint &&
            row['idempotency_key'] == event.idempotencyKey &&
            row['state'] == 'applied') {
          return PosFinancialApplyResult.exactReplay;
        }
        await _recordConflict(txn, event);
        return PosFinancialApplyResult.conflictingReplay;
      }

      final sameKey = await txn.query(
        'pos_financial_event_inbox',
        where: 'idempotency_key = ?',
        whereArgs: [event.idempotencyKey],
        limit: 1,
      );
      if (sameKey.isNotEmpty) {
        await _recordConflict(txn, event);
        return PosFinancialApplyResult.conflictingReplay;
      }

      await applyBusinessMutation(txn);
      await txn.insert('pos_financial_event_inbox', {
        'event_id': event.eventId,
        'idempotency_key': event.idempotencyKey,
        'event_kind': event.kind.name,
        'aggregate_id': event.aggregateId,
        'payload_fingerprint': event.payloadFingerprint,
        'state': 'applied',
        'applied_at': DateTime.now().toUtc().toIso8601String(),
      });
      return PosFinancialApplyResult.applied;
    });
  }

  Future<void> _recordConflict(
    Transaction txn,
    PosFinancialSyncEvent event,
  ) async {
    await txn.insert('pos_inventory_conflicts', {
      'id': '${event.eventId}:${event.payloadFingerprint}',
      'event_id': event.eventId,
      'aggregate_id': event.aggregateId,
      'requested_quantity': event.lines.fold<int>(
        0,
        (sum, line) => sum + line.quantity,
      ),
      'available_quantity': 0,
      'state': 'unresolved',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
