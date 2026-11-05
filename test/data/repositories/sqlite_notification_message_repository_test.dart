import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/repositories/sqlite_notification_message_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqliteNotificationMessageRepository repository;

  const id = 'credit-invoice-1';
  const pendingPayload = '{"acknowledgment_status":"pending"}';

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE notification_messages (
        id TEXT PRIMARY KEY,
        body_text TEXT NOT NULL,
        raw_payload_json TEXT
      )
    ''');
    await db.insert('notification_messages', {
      'id': id,
      'body_text': 'pending',
      'raw_payload_json': pendingPayload,
    });
    repository = SqliteNotificationMessageRepository(db);
  });

  tearDown(() async => db.close());

  test(
    'only one concurrent credit-invoice decision wins compare-and-set',
    () async {
      final results = await Future.wait([
        repository.updateBodyAndPayloadIfUnchanged(
          id: id,
          expectedRawPayloadJson: pendingPayload,
          bodyText: 'accepted',
          rawPayloadJson: '{"acknowledgment_status":"accepted"}',
        ),
        repository.updateBodyAndPayloadIfUnchanged(
          id: id,
          expectedRawPayloadJson: pendingPayload,
          bodyText: 'rejected',
          rawPayloadJson: '{"acknowledgment_status":"rejected"}',
        ),
      ]);

      expect(results.every((result) => result.isSuccess), isTrue);
      expect(
        results.where((result) => result.valueOrNull == true),
        hasLength(1),
      );

      final row = (await db.query(
        'notification_messages',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      )).single;
      final savedPayload =
          jsonDecode(row['raw_payload_json']! as String)
              as Map<String, dynamic>;
      expect(
        savedPayload['acknowledgment_status'],
        anyOf('accepted', 'rejected'),
      );
      expect(row['body_text'], savedPayload['acknowledgment_status']);
    },
  );

  test(
    'stale sender delivery update cannot overwrite a received acknowledgment',
    () async {
      final received = await repository.updateBodyAndPayloadIfUnchanged(
        id: id,
        expectedRawPayloadJson: pendingPayload,
        bodyText: 'accepted',
        rawPayloadJson:
            '{"acknowledgment_status":"accepted","acknowledgment_node_id":"ack-1"}',
      );
      final staleDelivery = await repository.updateBodyAndPayloadIfUnchanged(
        id: id,
        expectedRawPayloadJson: pendingPayload,
        bodyText: 'awaiting',
        rawPayloadJson:
            '{"acknowledgment_status":"pending","delivery_status":"queued"}',
      );

      expect(received.valueOrNull, isTrue);
      expect(staleDelivery.valueOrNull, isFalse);

      final row = (await db.query(
        'notification_messages',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      )).single;
      final savedPayload =
          jsonDecode(row['raw_payload_json']! as String)
              as Map<String, dynamic>;
      expect(savedPayload['acknowledgment_status'], 'accepted');
      expect(savedPayload['acknowledgment_node_id'], 'ack-1');
    },
  );
}
