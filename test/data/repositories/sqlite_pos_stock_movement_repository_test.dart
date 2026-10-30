import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_041_pos_invoice_metadata.dart';
import 'package:qayd/data/database/migrations/migration_042_pos_product_categories.dart';
import 'package:qayd/data/repositories/sqlite_pos_product_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _CurrencyRepository implements CurrencyRepository {
  _CurrencyRepository(this.currency);

  final CurrencyCode currency;

  @override
  Future<Result<CurrencyCode?>> getByCode(String code) async =>
      Success(code == currency.code ? currency : null);

  @override
  Future<Result<List<CurrencyCode>>> getAll({bool onlyActive = false}) async =>
      Success([currency]);

  @override
  Future<Result<void>> save(CurrencyCode currency,
          {bool isPredefined = false}) async =>
      const Success(null);

  @override
  Future<Result<void>> toggleActiveStatus(String code, bool isActive) async =>
      const Success(null);

  @override
  Future<Result<String>> getBaseCurrencyCode() async => Success(currency.code);

  @override
  Future<Result<void>> setBaseCurrencyCode(String code) async =>
      const Success(null);
}

void main() {
  sqfliteFfiInit();
  final currency = CurrencyCode(
    code: 'SAR',
    nameAr: 'ريال سعودي',
    symbol: 'ر.س',
  );

  group('SqlitePosStockMovementRepository', () {
    late Database db;
    late SqlitePosStockMovementRepository repository;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE accounts (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          nature TEXT NOT NULL,
          parent_id TEXT,
          is_default INTEGER NOT NULL,
          is_active INTEGER NOT NULL,
          is_archived INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          standard_classification TEXT,
          custom_classification_name TEXT,
          custom_classification_nature TEXT,
          metadata TEXT
        )
      ''');
      await Migration040PosFoundation().up(db);
      await Migration041PosInvoiceMetadata().up(db);
      await Migration042PosProductCategories().up(db);
      await db.insert('pos_warehouses', <String, Object?>{
        'id': 'warehouse-1',
        'code': 'POS-MAIN',
        'name': 'POS Main',
        'is_default': 1,
        'is_active': 1,
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      final currencyRepository = _CurrencyRepository(currency);
      final productRepository = SqlitePosProductRepository(
        db,
        currencyRepository,
      );
      await productRepository.save(
        PosProduct.create(
          id: 'product-1',
          sku: 'SKU-1',
          name: 'Coffee',
          currency: currency,
          salePrice: Money.fromMinorUnits(300, currency),
          purchasePrice: Money.fromMinorUnits(100, currency),
          quantityScale: 0,
          reorderLevel: PosQuantity.whole(1),
          now: DateTime.utc(2026, 1, 1),
        ),
      );
      repository = SqlitePosStockMovementRepository(db, currencyRepository);
    });

    tearDown(() => db.close());

    PosStockMovement movement({
      required String id,
      required PosStockMovementType type,
      required PosStockMovementDirection direction,
      required int quantity,
      required int cost,
      String? idempotencyKey,
      DateTime? occurredAt,
    }) {
      return PosStockMovement.create(
        id: id,
        productId: 'product-1',
        warehouseId: 'warehouse-1',
        type: type,
        direction: direction,
        quantity: PosQuantity.whole(quantity),
        unitCost: Money.fromMinorUnits(cost, currency),
        occurredAt: occurredAt ?? DateTime.utc(2026, 1, 1),
        idempotencyKey: idempotencyKey ?? 'key-$id',
        createdAt: DateTime.utc(2026, 1, 1),
      );
    }

    test('appends signed movements and replays weighted average balance',
        () async {
      await repository.append(
        movement(
          id: 'opening',
          type: PosStockMovementType.opening,
          direction: PosStockMovementDirection.inbound,
          quantity: 10,
          cost: 100,
        ),
      );
      await repository.append(
        movement(
          id: 'purchase',
          type: PosStockMovementType.purchase,
          direction: PosStockMovementDirection.inbound,
          quantity: 10,
          cost: 200,
          occurredAt: DateTime.utc(2026, 1, 2),
        ),
      );
      await repository.append(
        movement(
          id: 'sale',
          type: PosStockMovementType.sale,
          direction: PosStockMovementDirection.outbound,
          quantity: 5,
          cost: 150,
          occurredAt: DateTime.utc(2026, 1, 3),
        ),
      );

      final balance = await repository.getBalance(
        productId: 'product-1',
        warehouseId: 'warehouse-1',
      );
      final rows = await db.query(
        'pos_stock_movements',
        orderBy: 'id ASC',
      );

      expect(balance.isSuccess, isTrue);
      expect(balance.valueOrNull!.quantity.scaledUnits, 15);
      expect(balance.valueOrNull!.valuation.minorUnits, 2250);
      expect(balance.valueOrNull!.averageUnitCost.minorUnits, 150);
      expect(rows.map((row) => row['quantity_scaled']), contains(-5));
    });

    test('accepts an exact idempotent replay without adding a second row',
        () async {
      final movementValue = movement(
        id: 'opening',
        type: PosStockMovementType.opening,
        direction: PosStockMovementDirection.inbound,
        quantity: 1,
        cost: 100,
        idempotencyKey: 'same-key',
      );
      final first = await repository.append(movementValue);
      final replay = await repository.append(movementValue);

      expect(first.isSuccess, isTrue);
      expect(replay.isSuccess, isTrue);
      expect(await db.query('pos_stock_movements'), hasLength(1));
    });

    test('rejects duplicate idempotency keys without adding a second row',
        () async {
      final first = await repository.append(
        movement(
          id: 'opening',
          type: PosStockMovementType.opening,
          direction: PosStockMovementDirection.inbound,
          quantity: 1,
          cost: 100,
          idempotencyKey: 'same-key',
        ),
      );
      final duplicate = await repository.append(
        movement(
          id: 'different-id',
          type: PosStockMovementType.opening,
          direction: PosStockMovementDirection.inbound,
          quantity: 9,
          cost: 900,
          idempotencyKey: 'same-key',
        ),
      );

      expect(first.isSuccess, isTrue);
      expect(duplicate.isFailure, isTrue);
      expect(
        (await repository.getByIdempotencyKey('same-key')).valueOrNull!.id,
        'opening',
      );
      expect(await db.query('pos_stock_movements'), hasLength(1));
    });

    test('rejects insufficient outbound stock atomically', () async {
      final result = await repository.append(
        movement(
          id: 'sale-too-large',
          type: PosStockMovementType.sale,
          direction: PosStockMovementDirection.outbound,
          quantity: 1,
          cost: 100,
        ),
      );

      expect(result.isFailure, isTrue);
      expect(await db.query('pos_stock_movements'), isEmpty);
    });

    test('lists movements in deterministic descending order with pagination',
        () async {
      await repository.append(
        movement(
          id: 'opening',
          type: PosStockMovementType.opening,
          direction: PosStockMovementDirection.inbound,
          quantity: 10,
          cost: 100,
          occurredAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repository.append(
        movement(
          id: 'purchase',
          type: PosStockMovementType.purchase,
          direction: PosStockMovementDirection.inbound,
          quantity: 5,
          cost: 200,
          occurredAt: DateTime.utc(2026, 1, 2),
        ),
      );
      await repository.append(
        movement(
          id: 'sale',
          type: PosStockMovementType.sale,
          direction: PosStockMovementDirection.outbound,
          quantity: 2,
          cost: 133,
          occurredAt: DateTime.utc(2026, 1, 3),
        ),
      );

      final firstPage = await repository.listMovements(
        warehouseId: 'warehouse-1',
        limit: 2,
      );
      final secondPage = await repository.listMovements(
        warehouseId: 'warehouse-1',
        limit: 2,
        offset: 2,
      );

      expect(firstPage.isSuccess, isTrue);
      expect(firstPage.valueOrNull!.map((item) => item.id),
          ['sale', 'purchase']);
      expect(secondPage.valueOrNull!.map((item) => item.id), ['opening']);
    });

    test('filters by type, product, and UTC date range', () async {
      await repository.append(
        movement(
          id: 'opening',
          type: PosStockMovementType.opening,
          direction: PosStockMovementDirection.inbound,
          quantity: 10,
          cost: 100,
          occurredAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repository.append(
        movement(
          id: 'purchase',
          type: PosStockMovementType.purchase,
          direction: PosStockMovementDirection.inbound,
          quantity: 5,
          cost: 200,
          occurredAt: DateTime.utc(2026, 1, 2),
        ),
      );

      final result = await repository.listMovements(
        warehouseId: 'warehouse-1',
        productId: 'product-1',
        type: PosStockMovementType.purchase,
        fromInclusive: DateTime.utc(2026, 1, 2),
        untilExclusive: DateTime.utc(2026, 1, 3),
      );

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.map((item) => item.id), ['purchase']);
      expect(result.valueOrNull!.single.productId, 'product-1');
      expect(result.valueOrNull!.single.type, PosStockMovementType.purchase);
    });

    test('rejects an inverted date range', () async {
      final result = await repository.listMovements(
        warehouseId: 'warehouse-1',
        fromInclusive: DateTime.utc(2026, 1, 3),
        untilExclusive: DateTime.utc(2026, 1, 2),
      );

      expect(result.isFailure, isTrue);
    });
  });
}
