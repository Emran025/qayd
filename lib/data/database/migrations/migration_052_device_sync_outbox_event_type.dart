import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:qayd/data/database/migrations/migration_034_device_sync.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Schema v52: preserve the event discriminator for device outbox routing.
final class Migration052DeviceSyncOutboxEventType implements SchemaMigration {
  @override
  int get version => 52;

  @override
  Future<void> up(Database db) async {
    await ensureDeviceSyncTables(db);
    await db.addColumnIfNotExists(
      'device_sync_outbox',
      'event_type',
      'TEXT NOT NULL',
      defaultValue: "'auditBatch'",
    );
  }
}
