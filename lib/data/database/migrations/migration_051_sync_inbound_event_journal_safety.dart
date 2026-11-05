import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Schema v51: retain conflicting envelopes and fail closed on old in-flight
/// inbound events whose domain-commit outcome cannot be inferred.
final class Migration051SyncInboundEventJournalSafety
    implements SchemaMigration {
  @override
  int get version => 51;

  @override
  Future<void> up(Database db) async {
    await db.addColumnIfNotExists(
      'sync_inbound_event_journal',
      'conflicting_payload_fingerprint',
      'TEXT',
    );
    await db.addColumnIfNotExists(
      'sync_inbound_event_journal',
      'conflicting_encrypted_payload',
      'TEXT',
    );
    await db.addColumnIfNotExists(
      'sync_inbound_event_journal',
      'conflict_count',
      'INTEGER NOT NULL',
      defaultValue: '0',
    );

    // v50 could return events to pending after handler-side writes or crash
    // while processing, so these legacy rows have an ambiguous outcome. Keep
    // them unacknowledged and quarantined rather than risk replaying writes.
    await db.update(
      'sync_inbound_event_journal',
      {
        'state': 'quarantined',
        'reason_code': 'processingInterrupted',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'state IN (?, ?)',
      whereArgs: ['processing', 'pending'],
    );

    // Financial POS events have their own durable idempotency boundary.  The
    // generic encrypted journal remains the quarantine/audit record; these
    // tables are the local transaction boundary used by a financial handler.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pos_financial_event_outbox (
        event_id TEXT NOT NULL PRIMARY KEY,
        event_kind TEXT NOT NULL CHECK (event_kind IN
          ('sale', 'purchase', 'salesReturn', 'purchaseReturn', 'collection')),
        aggregate_id TEXT NOT NULL,
        idempotency_key TEXT NOT NULL UNIQUE,
        payload_fingerprint TEXT NOT NULL,
        encrypted_payload TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'pending' CHECK
          (state IN ('pending', 'delivered', 'failed')),
        created_at TEXT NOT NULL,
        delivered_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pos_financial_event_inbox (
        event_id TEXT NOT NULL PRIMARY KEY,
        idempotency_key TEXT NOT NULL UNIQUE,
        event_kind TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        payload_fingerprint TEXT NOT NULL,
        state TEXT NOT NULL CHECK (state IN ('applied', 'conflict')),
        applied_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pos_inventory_conflicts (
        id TEXT NOT NULL PRIMARY KEY,
        event_id TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        requested_quantity INTEGER NOT NULL,
        available_quantity INTEGER NOT NULL,
        state TEXT NOT NULL DEFAULT 'unresolved' CHECK
          (state IN ('unresolved', 'reconciled', 'rejected')),
        created_at TEXT NOT NULL,
        resolved_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pos_financial_outbox_state '
      'ON pos_financial_event_outbox (state, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pos_inventory_conflicts_state '
      'ON pos_inventory_conflicts (state, created_at)',
    );
  }
}
