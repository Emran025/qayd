import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qayd/data/database/database_encryption_key_provider.dart';
import 'package:qayd/data/database/migrations/migration_registry.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Opens the encrypted SQLite database and applies migrations.
abstract final class DatabaseProvider {
  static const int schemaVersion = 43;

  static const String databaseFileName = 'qayd_finance.db';

  /// Path to the encrypted SQLite file (same path used by [open]).
  static Future<String> databaseFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, databaseFileName);
  }

  static Future<Database> open({
    required DatabaseEncryptionKeyProvider keyProvider,
  }) async {
    final path = await databaseFilePath();
    final key = await keyProvider.obtainKey();
    return openDatabase(
      path,
      version: schemaVersion,
      password: key,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await MigrationRegistry.applyFromTo(
          db,
          fromVersion: 0,
          toVersion: version,
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await MigrationRegistry.applyFromTo(
          db,
          fromVersion: oldVersion,
          toVersion: newVersion,
        );
      },
      onOpen: (db) async {
        // Safety net: ensure critical tables exist regardless of migration history.
        // This handles edge cases where a schema version bump was skipped.
        await db.execute('''
CREATE TABLE IF NOT EXISTS collaterals (
  id TEXT NOT NULL PRIMARY KEY,
  voucher_id TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  estimated_value_minor INTEGER NOT NULL,
  currency_code TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  expiry_date TEXT,
  images_json TEXT,
  encrypted_metadata TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (voucher_id) REFERENCES vouchers (id) ON DELETE CASCADE
)
''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_collaterals_voucher ON collaterals (voucher_id)',
        );
        await db.execute('''
CREATE TABLE IF NOT EXISTS collateral_revaluations (
  id TEXT NOT NULL PRIMARY KEY,
  collateral_id TEXT NOT NULL,
  old_value_minor INTEGER NOT NULL,
  new_value_minor INTEGER NOT NULL,
  old_expiry_date TEXT,
  new_expiry_date TEXT,
  reason TEXT NOT NULL,
  evaluated_at TEXT NOT NULL,
  FOREIGN KEY (collateral_id) REFERENCES collaterals (id) ON DELETE CASCADE
)
''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_revaluations_collateral ON collateral_revaluations (collateral_id)',
        );

        // Safety net for attachments (migration 014)
        await db.execute('''
CREATE TABLE IF NOT EXISTS attachments (
  id TEXT NOT NULL PRIMARY KEY,
  voucher_id TEXT NOT NULL,
  file_name TEXT NOT NULL,
  storage_path TEXT NOT NULL,
  encrypted_blob_hash TEXT NOT NULL,
  mime_type TEXT NOT NULL DEFAULT 'image/jpeg',
  byte_size INTEGER NOT NULL DEFAULT 0,
  source_type TEXT NOT NULL DEFAULT 'gallery',
  thumbnail_path TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (voucher_id) REFERENCES vouchers (id) ON DELETE CASCADE
)
''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_attachments_voucher ON attachments (voucher_id)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_attachments_hash ON attachments (encrypted_blob_hash)',
        );
      },
    );
  }
}
