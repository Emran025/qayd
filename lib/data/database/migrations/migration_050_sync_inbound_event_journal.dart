import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Schema v50: retain encrypted inbound events and their processing state.
///
/// The journal deliberately stores no decrypted/business payload. Its payload
/// column is the original E2EE envelope, protected by SQLCipher, so unsupported
/// events remain available for review without being acknowledged as applied.
final class Migration050SyncInboundEventJournal implements SchemaMigration {
  @override
  int get version => 50;

  @override
  Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_inbound_event_journal (
        node_id TEXT NOT NULL PRIMARY KEY,
        sender_public_key TEXT,
        event_type TEXT NOT NULL,
        payload_fingerprint TEXT NOT NULL,
        encrypted_payload TEXT,
        state TEXT NOT NULL CHECK (
          state IN ('processing', 'pending', 'applied', 'quarantined')
        ),
        reason_code TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_inbound_journal_state_created
      ON sync_inbound_event_journal (state, created_at)
    ''');
  }
}
