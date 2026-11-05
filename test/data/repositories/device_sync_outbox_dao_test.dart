import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/database/migrations/migration_034_device_sync.dart';
import 'package:qayd/data/database/migrations/migration_052_device_sync_outbox_event_type.dart';
import 'package:qayd/data/repositories/device_sync_outbox_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE audit_logs (id TEXT PRIMARY KEY)');
    await Migration034DeviceSync().up(db);
  });

  tearDown(() async => db.close());

  test('v52 defaults legacy rows to auditBatch and is idempotent', () async {
    await db.insert('device_sessions', {
      'device_id': 'target',
      'public_key_hex': 'key',
      'paired_at': '2026-11-05T00:00:00.000Z',
    });
    await db.insert('device_sync_outbox', {
      'id': 'legacy',
      'audit_entry_id': 'audit',
      'target_device_id': 'target',
      'encrypted_payload': 'ciphertext',
      'signature': 'signature',
      'created_at': '2026-11-05T00:00:00.000Z',
    });

    final migration = Migration052DeviceSyncOutboxEventType();
    await migration.up(db);
    await migration.up(db);

    final row = (await db.query(
      'device_sync_outbox',
      where: 'id = ?',
      whereArgs: ['legacy'],
    )).single;
    expect(row['event_type'], DeviceSyncOutboxEntry.defaultEventType);
    expect(
      (await db.rawQuery(
        'PRAGMA table_info(device_sync_outbox)',
      )).where((column) => column['name'] == 'event_type'),
      hasLength(1),
    );
  });

  test(
    'DAO persists trusted POS event types and keeps old maps compatible',
    () async {
      await Migration052DeviceSyncOutboxEventType().up(db);
      final dao = DeviceSyncOutboxDao(db);
      final entry = DeviceSyncOutboxEntry(
        id: 'pos',
        auditEntryId: 'audit',
        targetDeviceId: 'target',
        encryptedPayload: 'ciphertext',
        signature: 'signature',
        state: 'pending',
        retryCount: 0,
        createdAt: DateTime.utc(2026, 11, 5),
        eventType: 'posSale',
      );

      await dao.enqueue(entry);
      expect((await dao.listPending()).single.eventType, 'posSale');

      final legacyMap = Map<String, Object?>.from(entry.toMap())
        ..remove('event_type');
      expect(
        DeviceSyncOutboxEntry.fromMap(legacyMap).eventType,
        DeviceSyncOutboxEntry.defaultEventType,
      );
      expect(
        () => DeviceSyncOutboxEntry.fromMap({
          ...legacyMap,
          'event_type': 'untrusted',
        }),
        throwsArgumentError,
      );
    },
  );
}
