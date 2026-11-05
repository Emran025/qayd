import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Schema v50: retain conflicting envelopes and fail closed on old in-flight
/// inbound events whose domain-commit outcome cannot be inferred.
final class Migration050SyncInboundEventJournalSafety implements SchemaMigration {
  @override
  int get version => 50;

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

    // v49 could return events to pending after handler-side writes or crash
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
  }
}
