import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/repositories/sqlite_pos_payment_collection_request_identity_repository.dart';
import 'package:qayd/domain/entities/pos_payment_collection_request_identity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqlitePosPaymentCollectionRequestIdentityRepository repository;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    repository = SqlitePosPaymentCollectionRequestIdentityRepository(db);
  });

  tearDown(() async => db.close());

  test('reuses the same durable key until the successful result is acknowledged',
      () async {
    const hash =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final now = DateTime.utc(2026, 2, 1, 10);
    final original = PosPaymentCollectionRequestIdentity(
      paymentId: 'payment-original',
      idempotencyKey: 'key-original',
      createdAt: now,
      occurredAt: now.add(const Duration(days: 1)),
    );
    final first = await repository.getOrCreate(
      fingerprintHash: hash,
      candidate: original,
    );
    final retry = await repository.getOrCreate(
      fingerprintHash: hash,
      candidate: PosPaymentCollectionRequestIdentity(
        paymentId: 'payment-new',
        idempotencyKey: 'key-new',
        createdAt: now.add(const Duration(minutes: 1)),
        occurredAt: now.add(const Duration(days: 2)),
      ),
    );

    expect(first.valueOrNull!.paymentId, 'payment-original');
    expect(retry.valueOrNull!.paymentId, 'payment-original');
    expect(retry.valueOrNull!.idempotencyKey, 'key-original');
    expect(retry.valueOrNull!.occurredAt, now.add(const Duration(days: 1)));

    final acknowledged = await repository.acknowledgeCommitted(
      fingerprintHash: hash,
      identity: retry.valueOrNull!,
    );
    final next = await repository.getOrCreate(
      fingerprintHash: hash,
      candidate: PosPaymentCollectionRequestIdentity(
        paymentId: 'payment-next',
        idempotencyKey: 'key-next',
        createdAt: now.add(const Duration(minutes: 2)),
        occurredAt: now.add(const Duration(days: 3)),
      ),
    );

    expect(acknowledged.isSuccess, isTrue);
    expect(next.valueOrNull!.paymentId, 'payment-next');
    expect(next.valueOrNull!.idempotencyKey, 'key-next');
  });

  test('discards only a known uncommitted matching identity', () async {
    const hash =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final now = DateTime.utc(2026, 2, 1, 10);
    final original = PosPaymentCollectionRequestIdentity(
      paymentId: 'payment-invalid-date',
      idempotencyKey: 'key-invalid-date',
      createdAt: now,
      occurredAt: now,
    );
    final stored = await repository.getOrCreate(
      fingerprintHash: hash,
      candidate: original,
    );
    final mismatched = await repository.discardUncommitted(
      fingerprintHash: hash,
      identity: PosPaymentCollectionRequestIdentity(
        paymentId: 'other-payment',
        idempotencyKey: 'other-key',
        createdAt: now,
        occurredAt: now,
      ),
    );
    final discarded = await repository.discardUncommitted(
      fingerprintHash: hash,
      identity: stored.valueOrNull!,
    );
    final next = await repository.getOrCreate(
      fingerprintHash: hash,
      candidate: PosPaymentCollectionRequestIdentity(
        paymentId: 'payment-corrected-date',
        idempotencyKey: 'key-corrected-date',
        createdAt: now.add(const Duration(minutes: 1)),
        occurredAt: now.add(const Duration(days: 1)),
      ),
    );

    expect(mismatched.isFailure, isTrue);
    expect(discarded.isSuccess, isTrue);
    expect(next.valueOrNull!.paymentId, 'payment-corrected-date');
  });
}
