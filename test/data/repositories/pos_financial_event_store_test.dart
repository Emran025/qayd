import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/database/migrations/migration_050_sync_inbound_event_journal.dart';
import 'package:qayd/data/database/migrations/migration_051_sync_inbound_event_journal_safety.dart';
import 'package:qayd/data/repositories/pos_financial_event_store.dart';
import 'package:qayd/domain/entities/pos_financial_sync_event.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PosFinancialSyncEvent event({String id = 'event-1', int total = 100}) {
  final json = jsonEncode({
    'version': 1,
    'kind': 'sale',
    'event_id': id,
    'aggregate_id': 'invoice-1',
    'idempotency_key': 'key-$id',
    'currency_code': 'USD',
    'occurred_at': '2026-11-05T00:00:00Z',
    'total_minor': total,
    'lines': [
      {
        'product_id': 'p1',
        'quantity': 1,
        'unit_price_minor': total,
        'total_minor': total,
      },
    ],
  });
  return PosFinancialSyncEvent.decode(json);
}

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await Migration050SyncInboundEventJournal().up(db);
    await Migration051SyncInboundEventJournalSafety().up(db);
  });

  tearDown(() => db.close());

  test(
    'applies business mutation and inbox marker in one transaction',
    () async {
      final store = PosFinancialEventStore(db);
      var writes = 0;
      final first = await store.applyInbound(
        event(),
        applyBusinessMutation: (txn) async {
          writes++;
          await txn.insert('pos_financial_event_inbox', {
            // Deliberately no insert here: this callback represents invoice,
            // stock and ledger writes owned by the application coordinator.
            'event_id': 'callback-row',
            'idempotency_key': 'callback-key',
            'event_kind': 'sale',
            'aggregate_id': 'invoice-callback',
            'payload_fingerprint': 'callback-fingerprint',
            'state': 'applied',
            'applied_at': DateTime.now().toUtc().toIso8601String(),
          });
        },
      );
      expect(first, PosFinancialApplyResult.applied);
      expect(writes, 1);

      final replay = await store.applyInbound(
        event(),
        applyBusinessMutation: (_) async => writes++,
      );
      expect(replay, PosFinancialApplyResult.exactReplay);
      expect(writes, 1);
    },
  );

  test(
    'same event id with different fingerprint is retained as conflict',
    () async {
      final store = PosFinancialEventStore(db);
      await store.applyInbound(event(), applyBusinessMutation: (_) async {});
      final result = await store.applyInbound(
        event(total: 101),
        applyBusinessMutation: (_) async {},
      );
      expect(result, PosFinancialApplyResult.conflictingReplay);
      final conflicts = await db.query('pos_financial_event_conflicts');
      expect(conflicts, hasLength(1));
      expect(conflicts.single['state'], 'unresolved');
      expect(conflicts.single['conflict_code'], 'eventIdReused');
      expect(conflicts.single.containsKey('requested_quantity'), isFalse);
    },
  );

  test(
    'applies through the caller transaction without opening a nested transaction',
    () async {
      final store = PosFinancialEventStore(db);
      var callbackTransaction;

      final result = await db.transaction((txn) async {
        return store.applyInboundInTransaction(
          txn,
          event(id: 'transaction-event'),
          applyBusinessMutation: (businessTxn) async {
            callbackTransaction = businessTxn;
            await businessTxn.insert('pos_financial_event_inbox', {
              'event_id': 'callback-row',
              'idempotency_key': 'callback-key',
              'event_kind': 'sale',
              'aggregate_id': 'invoice-callback',
              'payload_fingerprint': 'callback-fingerprint',
              'state': 'applied',
              'applied_at': DateTime.now().toUtc().toIso8601String(),
            });
          },
        );
      });

      expect(result, PosFinancialApplyResult.applied);
      expect(callbackTransaction, isNotNull);
      expect(await db.query('pos_financial_event_inbox'), hasLength(2));
    },
  );

  test('rolls back business and inbox writes when callback throws', () async {
    final store = PosFinancialEventStore(db);

    await expectLater(
      db.transaction((txn) async {
        await store.applyInboundInTransaction(
          txn,
          event(id: 'rollback-event'),
          applyBusinessMutation: (businessTxn) async {
            await businessTxn.insert('pos_financial_event_inbox', {
              'event_id': 'rollback-callback-row',
              'idempotency_key': 'rollback-callback-key',
              'event_kind': 'sale',
              'aggregate_id': 'invoice-rollback',
              'payload_fingerprint': 'rollback-callback-fingerprint',
              'state': 'applied',
              'applied_at': DateTime.now().toUtc().toIso8601String(),
            });
            throw StateError('business mutation failed');
          },
        );
      }),
      throwsA(isA<StateError>()),
    );

    expect(await db.query('pos_financial_event_inbox'), isEmpty);
  });
}
