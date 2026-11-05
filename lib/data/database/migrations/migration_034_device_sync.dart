import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Creates the base device-pairing tables without changing audit-log columns.
/// Later migrations may call this idempotent helper to repair partial upgrade
/// fixtures while preserving the canonical schema.
Future<void> ensureDeviceSyncTables(Database db) async {
  await db.execute('''
CREATE TABLE IF NOT EXISTS device_sessions (
  device_id TEXT NOT NULL PRIMARY KEY,
  device_name TEXT,
  public_key_hex TEXT NOT NULL,
  paired_at TEXT NOT NULL,
  last_sync_seq INTEGER NOT NULL DEFAULT 0,
  last_seen_at TEXT,
  is_current INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  role TEXT
)
''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS device_sync_outbox (
  id TEXT NOT NULL PRIMARY KEY,
  audit_entry_id TEXT NOT NULL,
  target_device_id TEXT NOT NULL,
  encrypted_payload TEXT NOT NULL,
  signature TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending',
  retry_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  sent_at TEXT,
  FOREIGN KEY (target_device_id) REFERENCES device_sessions(device_id)
)
''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_dso_state ON device_sync_outbox(state)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_dso_target ON device_sync_outbox(target_device_id)',
  );
}

final class Migration034DeviceSync implements SchemaMigration {
  @override
  int get version => 34;

  @override
  Future<void> up(Database db) async {
    await ensureDeviceSyncTables(db);
    await db.addColumnIfNotExists('audit_logs', 'sync_seq', 'INTEGER');
    await db.addColumnIfNotExists('audit_logs', 'device_id', 'TEXT');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_sync_seq ON audit_logs(sync_seq)',
    );
  }
}
