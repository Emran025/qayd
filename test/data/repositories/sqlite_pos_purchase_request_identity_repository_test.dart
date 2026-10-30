import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/repositories/sqlite_pos_purchase_request_identity_repository.dart';
import 'package:qayd/domain/entities/pos_purchase_request_identity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('SqlitePosPurchaseRequestIdentityRepository', () {
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

    test('reuses the same UUID identity after repository recreation', () async {
      final fingerprint = List.filled(64, 'a').join();
      final firstRepository =
          SqlitePosPurchaseRequestIdentityRepository(db);
      final first = await firstRepository.getOrCreate(
        fingerprintHash: fingerprint,
        candidate: PosPurchaseRequestIdentity(
          invoiceId: 'invoice-first',
          idempotencyKey: 'key-first',
          createdAt: DateTime.utc(2026, 10, 30),
        ),
      );

      final restartedRepository =
          SqlitePosPurchaseRequestIdentityRepository(db);
      final replay = await restartedRepository.getOrCreate(
        fingerprintHash: fingerprint,
        candidate: PosPurchaseRequestIdentity(
          invoiceId: 'invoice-new',
          idempotencyKey: 'key-new',
          createdAt: DateTime.utc(2026, 10, 31),
        ),
      );

      expect(first.isSuccess, isTrue);
      expect(replay.isSuccess, isTrue);
      expect(replay.valueOrNull!.invoiceId, 'invoice-first');
      expect(replay.valueOrNull!.idempotencyKey, 'key-first');
      expect(replay.valueOrNull!.createdAt, DateTime.utc(2026, 10, 30));
      expect(await db.query('app_settings'), hasLength(1));
    });

    test('uses a different identity for a different request fingerprint',
        () async {
      final repository = SqlitePosPurchaseRequestIdentityRepository(db);
      final one = await repository.getOrCreate(
        fingerprintHash: List.filled(64, 'b').join(),
        candidate: PosPurchaseRequestIdentity(
          invoiceId: 'invoice-one',
          idempotencyKey: 'key-one',
          createdAt: DateTime.utc(2026, 10, 30),
        ),
      );
      final two = await repository.getOrCreate(
        fingerprintHash: List.filled(64, 'c').join(),
        candidate: PosPurchaseRequestIdentity(
          invoiceId: 'invoice-two',
          idempotencyKey: 'key-two',
          createdAt: DateTime.utc(2026, 10, 30),
        ),
      );

      expect(one.valueOrNull!.invoiceId, 'invoice-one');
      expect(two.valueOrNull!.invoiceId, 'invoice-two');
      expect(await db.query('app_settings'), hasLength(2));
    });
  });
}
