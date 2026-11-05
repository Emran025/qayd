import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/database/migrations/migration_049_sync_inbound_event_journal.dart';
import 'package:qayd/data/database/migrations/migration_050_sync_inbound_event_journal_safety.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await Migration049SyncInboundEventJournal().up(db);
  });

  tearDown(() async => db.close());

  test('v50 adds conflict fields and quarantines ambiguous v49 rows', () async {
    const createdAt = '2026-11-05T00:00:00.000Z';
    for (final row in <Map<String, Object?>>[
      {
        'node_id': 'interrupted',
        'event_type': 'posSale',
        'payload_fingerprint': 'fp-interrupted',
        'encrypted_payload': null,
        'state': 'processing',
      },
      {
        'node_id': 'pending',
        'event_type': 'posSale',
        'payload_fingerprint': 'fp-pending',
        'encrypted_payload': null,
        'state': 'pending',
      },
      {
        'node_id': 'applied',
        'event_type': 'posSale',
        'payload_fingerprint': 'fp-applied',
        'encrypted_payload': null,
        'state': 'applied',
      },
      {
        'node_id': 'quarantined',
        'event_type': 'futureEvent',
        'payload_fingerprint': 'fp-quarantined',
        'encrypted_payload': 'ciphertext-only',
        'state': 'quarantined',
        'reason_code': 'unsupportedEventType',
      },
    ]) {
      await db.insert('sync_inbound_event_journal', {
        ...row,
        'created_at': createdAt,
        'updated_at': createdAt,
      });
    }

    final migration = Migration050SyncInboundEventJournalSafety();
    await migration.up(db);
    await migration.up(db);

    final rows = await db.query(
      'sync_inbound_event_journal',
      orderBy: 'node_id ASC',
    );
    final byId = {for (final row in rows) row['node_id']: row};
    expect(byId['interrupted']?['state'], 'quarantined');
    expect(byId['interrupted']?['reason_code'], 'processingInterrupted');
    expect(byId['interrupted']?['encrypted_payload'], isNull);
    expect(byId['pending']?['state'], 'quarantined');
    expect(byId['pending']?['reason_code'], 'processingInterrupted');
    expect(byId['applied']?['state'], 'applied');
    expect(byId['quarantined']?['encrypted_payload'], 'ciphertext-only');
    expect(byId['quarantined']?['reason_code'], 'unsupportedEventType');

    final columns = await db.rawQuery(
      'PRAGMA table_info(sync_inbound_event_journal)',
    );
    expect(
      columns.map((row) => row['name']),
      containsAll(<String>[
        'conflicting_payload_fingerprint',
        'conflicting_encrypted_payload',
        'conflict_count',
      ]),
    );
  });
}
