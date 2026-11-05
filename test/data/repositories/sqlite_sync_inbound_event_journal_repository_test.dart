import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/database/migrations/migration_049_sync_inbound_event_journal.dart';
import 'package:qayd/data/database/migrations/migration_050_sync_inbound_event_journal_safety.dart';
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
    await Migration050SyncInboundEventJournalSafety().up(db);
    journal = SqliteSyncInboundEventJournalRepository(db);
  });

  tearDown(() async => db.close());

  test(
    'migration is idempotent and creates the encrypted-event journal',
    () async {
      await Migration049SyncInboundEventJournal().up(db);
      await Migration050SyncInboundEventJournalSafety().up(db);
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        ['sync_inbound_event_journal'],
      );
      expect(tables, hasLength(1));
      final columns = await db.rawQuery(
        'PRAGMA table_info(sync_inbound_event_journal)',
      );
      expect(
        columns.map((row) => row['name']),
        containsAll(<String>[
          'encrypted_payload',
          'conflicting_payload_fingerprint',
          'conflicting_encrypted_payload',
          'conflict_count',
        ]),
      );
    },
  );

  test(
    'claims an event once and treats an exact applied replay idempotently',
    () async {
      const ciphertext = '{"ciphertext":"opaque-event-1"}';
      final firstClaim = await journal.beginProcessing(
        nodeId: 'event-1',
        senderPublicKey: _testKey('a'),
        eventType: 'posSale',
        payloadFingerprint: 'fingerprint-a',
        encryptedPayload: ciphertext,
      );
      expect(firstClaim, SyncInboundEventClaim.claimed);

      final concurrentClaim = await journal.beginProcessing(
        nodeId: 'event-1',
        senderPublicKey: _testKey('a'),
        eventType: 'posSale',
        payloadFingerprint: 'fingerprint-a',
        encryptedPayload: ciphertext,
      );
      expect(concurrentClaim, SyncInboundEventClaim.inProgress);

      await journal.markApplied('event-1');
      final replayClaim = await journal.beginProcessing(
        nodeId: 'event-1',
        senderPublicKey: _testKey('a'),
        eventType: 'posSale',
        payloadFingerprint: 'fingerprint-a',
        encryptedPayload: ciphertext,
      );
      expect(replayClaim, SyncInboundEventClaim.alreadyApplied);
    },
  );

  test(
    'quarantines and retains both envelopes when an event ID conflicts',
    () async {
      const originalCiphertext = '{"ciphertext":"original"}';
      const conflictingCiphertext = '{"ciphertext":"changed"}';
      final firstClaim = await journal.beginProcessing(
        nodeId: 'event-collision',
        senderPublicKey: _testKey('b'),
        eventType: 'posSale',
        payloadFingerprint: 'original-fingerprint',
        encryptedPayload: originalCiphertext,
      );
      expect(firstClaim, SyncInboundEventClaim.claimed);

      final collision = await journal.beginProcessing(
        nodeId: 'event-collision',
        senderPublicKey: _testKey('b'),
        eventType: 'posSale',
        payloadFingerprint: 'changed-fingerprint',
        encryptedPayload: conflictingCiphertext,
      );
      expect(collision, SyncInboundEventClaim.conflictingPayload);

      final quarantined = await journal.listQuarantined();
      expect(quarantined, hasLength(1));
      expect(
        quarantined.single.reason,
        SyncInboundQuarantineReason.conflictingPayload,
      );
      expect(quarantined.single.encryptedPayload, originalCiphertext);
      expect(
        quarantined.single.conflictingPayloadFingerprint,
        'changed-fingerprint',
      );
      expect(
        quarantined.single.conflictingEncryptedPayload,
        conflictingCiphertext,
      );
      expect(quarantined.single.conflictCount, 1);

      final originalReplay = await journal.beginProcessing(
        nodeId: 'event-collision',
        senderPublicKey: _testKey('b'),
        eventType: 'posSale',
        payloadFingerprint: 'original-fingerprint',
        encryptedPayload: originalCiphertext,
      );
      expect(originalReplay, SyncInboundEventClaim.quarantined);
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
        encryptedPayload: ciphertext,
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
        encryptedPayload: ciphertext,
      );
      expect(replay, SyncInboundEventClaim.quarantined);
    },
  );

  test(
    'quarantines an expired in-flight event instead of replaying its handler',
    () async {
      const ciphertext = '{"ciphertext":"may-have-been-applied"}';
      final firstClaim = await journal.beginProcessing(
        nodeId: 'interrupted-event',
        senderPublicKey: _testKey('d'),
        eventType: 'journalEntry',
        payloadFingerprint: 'interrupted-fingerprint',
        encryptedPayload: ciphertext,
      );
      expect(firstClaim, SyncInboundEventClaim.claimed);

      await db.update(
        'sync_inbound_event_journal',
        {
          'updated_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
        },
        where: 'node_id = ?',
        whereArgs: ['interrupted-event'],
      );

      final retryClaim = await journal.beginProcessing(
        nodeId: 'interrupted-event',
        senderPublicKey: _testKey('d'),
        eventType: 'journalEntry',
        payloadFingerprint: 'interrupted-fingerprint',
        encryptedPayload: ciphertext,
      );
      expect(retryClaim, SyncInboundEventClaim.quarantined);

      final quarantined = await journal.listQuarantined();
      expect(quarantined, hasLength(1));
      expect(
        quarantined.single.reason,
        SyncInboundQuarantineReason.processingInterrupted,
      );
      expect(quarantined.single.encryptedPayload, ciphertext);
    },
  );

  test(
    'returns a failure known to precede domain handling to pending',
    () async {
      const ciphertext = '{"ciphertext":"retryable"}';
      final firstClaim = await journal.beginProcessing(
        nodeId: 'retryable-event',
        senderPublicKey: _testKey('e'),
        eventType: 'journalEntry',
        payloadFingerprint: 'retry-fingerprint',
        encryptedPayload: ciphertext,
      );
      expect(firstClaim, SyncInboundEventClaim.claimed);

      await journal.returnToPending('retryable-event');
      final retryClaim = await journal.beginProcessing(
        nodeId: 'retryable-event',
        senderPublicKey: _testKey('e'),
        eventType: 'journalEntry',
        payloadFingerprint: 'retry-fingerprint',
        encryptedPayload: ciphertext,
      );
      expect(retryClaim, SyncInboundEventClaim.claimed);
    },
  );
}
