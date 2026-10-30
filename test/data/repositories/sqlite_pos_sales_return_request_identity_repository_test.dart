import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/repositories/sqlite_pos_sales_return_request_identity_repository.dart';
import 'package:qayd/domain/entities/pos_sales_return_request_identity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  });
  tearDown(() => db.close());

  final fingerprint = List.filled(64, 'd').join();
  PosSalesReturnRequestIdentity identity(String id) =>
      PosSalesReturnRequestIdentity(
        invoiceId: id,
        idempotencyKey: '$id-key',
        createdAt: DateTime.utc(2026, 10, 31),
      );

  test('absent request creates and persists opaque identity', () async {
    final repository = SqlitePosSalesReturnRequestIdentityRepository(db);
    final result = await repository.getOrCreate(
      fingerprintHash: fingerprint,
      candidate: identity('return-1'),
    );
    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull!.invoiceId, 'return-1');
    expect(await db.query('app_settings'), hasLength(1));
  });

  test('reopens and returns original identity, ignoring new candidate', () async {
    final first = SqlitePosSalesReturnRequestIdentityRepository(db);
    await first.getOrCreate(
      fingerprintHash: fingerprint,
      candidate: identity('return-1'),
    );
    final reopened = SqlitePosSalesReturnRequestIdentityRepository(db);
    final result = await reopened.getOrCreate(
      fingerprintHash: fingerprint,
      candidate: identity('return-new'),
    );
    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull!.invoiceId, 'return-1');
    expect(result.valueOrNull!.idempotencyKey, 'return-1-key');
  });

  test('acknowledges matching identity and leaves conflicting identity intact',
      () async {
    final repository = SqlitePosSalesReturnRequestIdentityRepository(db);
    final saved = identity('return-1');
    await repository.getOrCreate(fingerprintHash: fingerprint, candidate: saved);
    final conflict = await repository.acknowledgeCommitted(
      fingerprintHash: fingerprint,
      identity: identity('return-2'),
    );
    expect(conflict.isFailure, isTrue);
    expect(await db.query('app_settings'), hasLength(1));
    final acknowledged = await repository.acknowledgeCommitted(
      fingerprintHash: fingerprint,
      identity: saved,
    );
    expect(acknowledged.isSuccess, isTrue);
    expect(await db.query('app_settings'), isEmpty);
  });
}
