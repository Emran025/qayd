import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/database/migrations/migration_049_sync_inbound_event_journal.dart';
import 'package:qayd/data/repositories/sqlite_sync_inbound_event_journal_repository.dart';
import 'package:qayd/domain/repositories/sync_inbound_event_journal_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _testKey(String character) => List.filled(64, character).join();

void main() {
  sqfliteFfiInit();

  late Database db;
  late SqliteSyncInboundEventJournalRepository journal;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await Migration049SyncInboundEventJournal().up(db);
    journal = SqliteSyncInboundEventJournalRepository(db);
  });

  tearDown(() async => db.close());

  test(
    'migration is idempotent and creates the encrypted-event journal',
    () async {
      await Migration049SyncInboundEventJournal().up(db);
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        ['sync_inbound_event_journal'],
      );
      expect(tables, hasLength(1));
    },
  );

  test(
    'claims an event once and treats an exact applied replay idempotently',
    () async {
      final firstClaim = await journal.beginProcessing(
        nodeId: 'event-1',
        senderPublicKey: _testKey('a'),
        eventType: 'posSale',
        payloadFingerprint: 'fingerprint-a',
      );
      expect(firstClaim, SyncInboundEventClaim.claimed);

      final concurrentClaim = await journal.beginProcessing(
        nodeId: 'event-1',
        senderPublicKey: _testKey('a'),
        eventType: 'posSale',
        payloadFingerprint: 'fingerprint-a',
      );
      expect(concurrentClaim, SyncInboundEventClaim.inProgress);

      await journal.markApplied('event-1');
      final replayClaim = await journal.beginProcessing(
        nodeId: 'event-1',
        senderPublicKey: _testKey('a'),
        eventType: 'posSale',
        payloadFingerprint: 'fingerprint-a',
      );
      expect(replayClaim, SyncInboundEventClaim.alreadyApplied);
    },
  );

  test(
    'rejects a changed payload under the same event ID without applying it',
    () async {
      final firstClaim = await journal.beginProcessing(
        nodeId: 'event-collision',
        senderPublicKey: _testKey('b'),
        eventType: 'posSale',
        payloadFingerprint: 'original-fingerprint',
      );
      expect(firstClaim, SyncInboundEventClaim.claimed);

      final collision = await journal.beginProcessing(
        nodeId: 'event-collision',
        senderPublicKey: _testKey('b'),
        eventType: 'posSale',
        payloadFingerprint: 'changed-fingerprint',
      );
      expect(collision, SyncInboundEventClaim.conflictingPayload);

      await journal.markApplied('event-collision');
      final originalReplay = await journal.beginProcessing(
        nodeId: 'event-collision',
        senderPublicKey: _testKey('b'),
        eventType: 'posSale',
        payloadFingerprint: 'original-fingerprint',
      );
      expect(originalReplay, SyncInboundEventClaim.alreadyApplied);
    },
  );

  test(
    'retains unsupported encrypted payload for review without plaintext',
    () async {
      const ciphertext = '{"version":99,"ciphertext":"opaque-ciphertext"}';
      final claim = await journal.beginProcessing(
        nodeId: 'unknown-event',
        senderPublicKey: _testKey('c'),
        eventType: 'unsupportedFutureEvent',
        payloadFingerprint: 'opaque-fingerprint',
      );
      expect(claim, SyncInboundEventClaim.claimed);

      await journal.quarantine(
        nodeId: 'unknown-event',
        reason: SyncInboundQuarantineReason.unsupportedEventType,
        encryptedPayload: ciphertext,
      );

      final quarantined = await journal.listQuarantined();
      expect(quarantined, hasLength(1));
      expect(quarantined.single.nodeId, 'unknown-event');
      expect(
        quarantined.single.reason,
        SyncInboundQuarantineReason.unsupportedEventType,
      );
      expect(quarantined.single.encryptedPayload, ciphertext);
      expect(
        quarantined.single.encryptedPayload,
        isNot(contains('invoice amount')),
      );

      final replay = await journal.beginProcessing(
        nodeId: 'unknown-event',
        senderPublicKey: _testKey('c'),
        eventType: 'unsupportedFutureEvent',
        payloadFingerprint: 'opaque-fingerprint',
      );
      expect(replay, SyncInboundEventClaim.quarantined);
    },
  );

  test(
    'returns a failed event to pending so a later attempt can retry',
    () async {
      final firstClaim = await journal.beginProcessing(
        nodeId: 'retryable-event',
        senderPublicKey: _testKey('d'),
        eventType: 'journalEntry',
        payloadFingerprint: 'retry-fingerprint',
      );
      expect(firstClaim, SyncInboundEventClaim.claimed);

      await journal.returnToPending('retryable-event');
      final retryClaim = await journal.beginProcessing(
        nodeId: 'retryable-event',
        senderPublicKey: _testKey('d'),
        eventType: 'journalEntry',
        payloadFingerprint: 'retry-fingerprint',
      );
      expect(retryClaim, SyncInboundEventClaim.claimed);
    },
  );
}
