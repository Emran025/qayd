import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_041_pos_invoice_metadata.dart';
import 'package:qayd/data/database/migrations/migration_042_pos_product_categories.dart';
import 'package:qayd/data/database/migrations/migration_046_pos_stock_lots_fefo.dart';
import 'package:qayd/data/database/migrations/migration_registry.dart';
import 'package:qayd/data/repositories/sqlite_pos_product_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_lot.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';
import 'package:qayd/domain/value_objects/pos_stock_disposal_reason.dart';
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
  Future<Result<void>> save(
    CurrencyCode currency, {
    bool isPredefined = false,
  }) async =>
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
      await MigrationRegistry.applyFromTo(
        db,
        fromVersion: 42,
        toVersion: MigrationRegistry.ordered.last.version,
      );
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

    test(
        'upgrade preserves legacy lot-less tracked balance without inventing a lot',
        () async {
      final legacyPath =
          '${Directory.systemTemp.path}/qayd-legacy-${DateTime.now().microsecondsSinceEpoch}.db';
      final legacyDb = await databaseFactoryFfi.openDatabase(legacyPath);
      try {
        await legacyDb.execute('''
          CREATE TABLE accounts (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, nature TEXT NOT NULL,
            parent_id TEXT, is_default INTEGER NOT NULL, is_active INTEGER NOT NULL,
            is_archived INTEGER NOT NULL, created_at TEXT NOT NULL,
            standard_classification TEXT, custom_classification_name TEXT,
            custom_classification_nature TEXT, metadata TEXT
          )
        ''');
        await Migration040PosFoundation().up(legacyDb);
        await Migration041PosInvoiceMetadata().up(legacyDb);
        await Migration042PosProductCategories().up(legacyDb);
        await MigrationRegistry.applyFromTo(
          legacyDb,
          fromVersion: 42,
          toVersion: 45,
        );
        await legacyDb.insert('pos_warehouses', <String, Object?>{
          'id': 'warehouse-1',
          'code': 'POS-MAIN',
          'name': 'POS Main',
          'is_default': 1,
          'is_active': 1,
          'created_at': '2026-01-01T00:00:00.000Z',
          'updated_at': '2026-01-01T00:00:00.000Z',
        });
        final currencies = _CurrencyRepository(currency);
        await SqlitePosProductRepository(legacyDb, currencies).save(
          PosProduct.create(
            id: 'product-1',
            sku: 'SKU-1',
            name: 'Legacy tracked item',
            currency: currency,
            salePrice: Money.fromMinorUnits(300, currency),
            purchasePrice: Money.fromMinorUnits(100, currency),
            quantityScale: 0,
            expiryTracking: true,
            now: DateTime.utc(2026, 1, 1),
          ),
        );
        await legacyDb.insert('pos_stock_movements', <String, Object?>{
          'id': 'legacy-opening',
          'product_id': 'product-1',
          'warehouse_id': 'warehouse-1',
          'movement_type': 'opening',
          'quantity_scaled': 3,
          'quantity_scale': 0,
          'unit_cost_minor': 100,
          'currency_code': currency.code,
          'source_type': 'legacy',
          'source_id': 'legacy-opening',
          'source_line_id': null,
          'lot_id': null,
          'occurred_at': '2026-01-01T00:00:00.000Z',
          'idempotency_key': 'legacy-opening-key',
          'created_at': '2026-01-01T00:00:00.000Z',
        });

        await Migration046PosStockLotsFefo().up(legacyDb);
        await Migration046PosStockLotsFefo().up(legacyDb);
        await MigrationRegistry.applyFromTo(
          legacyDb,
          fromVersion: 46,
          toVersion: MigrationRegistry.ordered.last.version,
        );

        expect(await legacyDb.query('pos_stock_lots'), isEmpty);
        final legacyMovement =
            (await legacyDb.query('pos_stock_movements')).single;
        expect(legacyMovement['lot_id'], isNull);
        expect(legacyMovement['quantity_scaled'], 3);
        final upgradedRepository = SqlitePosStockMovementRepository(
          legacyDb,
          currencies,
        );
        final balance = await upgradedRepository.getBalance(
          productId: 'product-1',
          warehouseId: 'warehouse-1',
        );
        final lots = await upgradedRepository.getSellableLots(
          productId: 'product-1',
          warehouseId: 'warehouse-1',
          businessDate: PosDate.fromParts(2026, 1, 1),
        );
        expect(balance.valueOrNull?.quantity.scaledUnits, 3);
        expect(lots.isFailure, isTrue);
      } finally {
        await legacyDb.close();
        await databaseFactoryFfi.deleteDatabase(legacyPath);
      }
    });

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

    test('returns unexpired lots in deterministic FEFO order', () async {
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
          expiryTracking: true,
          now: DateTime.utc(2026, 1, 1),
        ),
      );

      Future<void> receiveLot(String id, PosDate expiry) async {
        final lot = PosStockLot.create(
          id: id,
          productId: 'product-1',
          warehouseId: 'warehouse-1',
          supplierLotNumber: null,
          expiryDate: expiry,
          receivedQuantity: PosQuantity.whole(1),
          unitCost: Money.fromMinorUnits(100, currency),
          createdAt: DateTime.utc(2026, 1, 1),
        );
        expect(
          (await repository.createLotInTransaction(db, lot)).isSuccess,
          isTrue,
        );
        expect(
          (await repository.append(
            PosStockMovement.create(
              id: 'movement-$id',
              productId: 'product-1',
              warehouseId: 'warehouse-1',
              type: PosStockMovementType.purchase,
              direction: PosStockMovementDirection.inbound,
              quantity: PosQuantity.whole(1),
              unitCost: Money.fromMinorUnits(100, currency),
              sourceType: 'test',
              sourceId: id,
              lotId: id,
              occurredAt: DateTime.utc(2026, 1, 1),
              idempotencyKey: 'key-$id',
              createdAt: DateTime.utc(2026, 1, 1),
            ),
          ))
              .isSuccess,
          isTrue,
        );
      }

      await receiveLot('lot-expired', PosDate.fromParts(2026, 1, 9));
      await receiveLot('lot-today-b', PosDate.fromParts(2026, 1, 10));
      await receiveLot('lot-today-a', PosDate.fromParts(2026, 1, 10));

      final result = await repository.getSellableLots(
        productId: 'product-1',
        warehouseId: 'warehouse-1',
        businessDate: PosDate.fromParts(2026, 1, 10),
      );

      expect(result.isSuccess, isTrue, reason: result.failureOrNull?.messageAr);
      expect(result.valueOrNull!.map((lot) => lot.id), [
        'lot-today-a',
        'lot-today-b',
      ]);
    });

    test('includes expired lots for disposal and validates date, lot and amount',
        () async {
      await db.update(
        'pos_products',
        {'expiry_tracking': 1},
        where: 'id = ?',
        whereArgs: ['product-1'],
      );
      final now = DateTime.now();
      final today = PosDate.todayLocal();
      final yesterday = PosDate.fromDateTime(
        DateTime(today.year, today.month, today.day)
            .subtract(const Duration(days: 1)),
      );

      Future<void> receiveLot(String id, PosDate expiry) async {
        final lot = PosStockLot.create(
          id: id,
          productId: 'product-1',
          warehouseId: 'warehouse-1',
          supplierLotNumber: id,
          expiryDate: expiry,
          receivedQuantity: PosQuantity.whole(1),
          unitCost: Money.fromMinorUnits(100, currency),
          createdAt: now,
        );
        expect(
          (await repository.createLotInTransaction(db, lot)).isSuccess,
          isTrue,
        );
        final received = await repository.append(
          PosStockMovement.create(
            id: '$id-receipt',
            productId: 'product-1',
            warehouseId: 'warehouse-1',
            type: PosStockMovementType.purchase,
            direction: PosStockMovementDirection.inbound,
            quantity: PosQuantity.whole(1),
            unitCost: Money.fromMinorUnits(100, currency),
            sourceType: 'test',
            sourceId: '$id-receipt',
            lotId: id,
            occurredAt: now,
            idempotencyKey: '$id-receipt-key',
            createdAt: now,
          ),
        );
        expect(received.isSuccess, isTrue);
      }

      await receiveLot('lot-expired', yesterday);
      await receiveLot('lot-current', today);
      await db.insert('pos_warehouses', <String, Object?>{
        'id': 'warehouse-2',
        'code': 'POS-SECOND',
        'name': 'Second POS Warehouse',
        'is_default': 0,
        'is_active': 1,
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      });
      final lots = await repository.getDisposalLots(
        productId: 'product-1',
        warehouseId: 'warehouse-1',
      );
      expect(lots.isSuccess, isTrue);
      expect(lots.valueOrNull!.map((lot) => lot.id),
          containsAll(['lot-expired', 'lot-current']));

      PosStockMovement disposal({
        required String id,
        required PosStockDisposalReason reason,
        required String lotId,
        String warehouseId = 'warehouse-1',
        int quantity = 1,
      }) {
        final type = reason == PosStockDisposalReason.damage
            ? PosStockMovementType.damage
            : PosStockMovementType.expiry;
        return PosStockMovement.create(
          id: id,
          productId: 'product-1',
          warehouseId: warehouseId,
          type: type,
          direction: PosStockMovementDirection.outbound,
          quantity: PosQuantity.whole(quantity),
          unitCost: Money.fromMinorUnits(100, currency),
          sourceType: 'stock_disposal',
          sourceId: 'source-$id',
          lotId: lotId,
          disposalReason: reason,
          voucherId: 'voucher-$id',
          occurredAt: now,
          idempotencyKey: 'key-$id',
          createdAt: now,
        );
      }

      final validExpiry = await repository.validateStockDisposalInTransaction(
        db,
        disposal(
          id: 'valid-expiry',
          reason: PosStockDisposalReason.expiry,
          lotId: 'lot-expired',
        ),
      );
      final expiredAsDamage =
          await repository.validateStockDisposalInTransaction(
        db,
        disposal(
          id: 'expired-damage',
          reason: PosStockDisposalReason.damage,
          lotId: 'lot-expired',
        ),
      );
      final healthyAsExpiry =
          await repository.validateStockDisposalInTransaction(
        db,
        disposal(
          id: 'healthy-expiry',
          reason: PosStockDisposalReason.expiry,
          lotId: 'lot-current',
        ),
      );
      final overLotQuantity =
          await repository.validateStockDisposalInTransaction(
        db,
        disposal(
          id: 'over-lot',
          reason: PosStockDisposalReason.damage,
          lotId: 'lot-current',
          quantity: 2,
        ),
      );
      final validDamage = await repository.validateStockDisposalInTransaction(
        db,
        disposal(
          id: 'valid-damage',
          reason: PosStockDisposalReason.damage,
          lotId: 'lot-current',
        ),
      );
      final missingLot = await repository.validateStockDisposalInTransaction(
        db,
        disposal(
          id: 'missing-lot',
          reason: PosStockDisposalReason.damage,
          lotId: 'lot-does-not-exist',
        ),
      );
      final wrongWarehouseLot =
          await repository.validateStockDisposalInTransaction(
        db,
        disposal(
          id: 'wrong-warehouse-lot',
          reason: PosStockDisposalReason.damage,
          lotId: 'lot-current',
          warehouseId: 'warehouse-2',
        ),
      );

      expect(validExpiry.isSuccess, isTrue);
      expect(expiredAsDamage.isFailure, isTrue);
      expect(healthyAsExpiry.isFailure, isTrue);
      expect(overLotQuantity.isFailure, isTrue);
      expect(validDamage.isSuccess, isTrue);
      expect(missingLot.isFailure, isTrue);
      expect(wrongWarehouseLot.isFailure, isTrue);
    });

    test(
      'rechecks lot expiry against the later of today and the sale date',
      () async {
        await db.update(
          'pos_products',
          {'expiry_tracking': 1},
          where: 'id = ?',
          whereArgs: ['product-1'],
        );
        final now = DateTime.now();
        final today = PosDate.todayLocal();
        final yesterday = PosDate.fromDateTime(
          DateTime(today.year, today.month, today.day)
              .subtract(const Duration(days: 1)),
        );

        Future<void> receiveLot({
          required String id,
          required PosDate expiry,
          required int quantity,
        }) async {
          final lot = PosStockLot.create(
            id: id,
            productId: 'product-1',
            warehouseId: 'warehouse-1',
            supplierLotNumber: null,
            expiryDate: expiry,
            receivedQuantity: PosQuantity.whole(quantity),
            unitCost: Money.fromMinorUnits(100, currency),
            createdAt: now,
          );
          expect(
            (await repository.createLotInTransaction(db, lot)).isSuccess,
            isTrue,
          );
          final receipt = await repository.append(
            PosStockMovement.create(
              id: '$id:receipt',
              productId: 'product-1',
              warehouseId: 'warehouse-1',
              type: PosStockMovementType.purchase,
              direction: PosStockMovementDirection.inbound,
              quantity: PosQuantity.whole(quantity),
              unitCost: Money.fromMinorUnits(100, currency),
              sourceType: 'test',
              sourceId: '$id:receipt',
              lotId: id,
              occurredAt: now,
              idempotencyKey: '$id:receipt-key',
              createdAt: now,
            ),
          );
          expect(receipt.isSuccess, isTrue,
              reason: receipt.failureOrNull?.messageAr);
        }

        Future<Result<void>> sellLot({
          required String lotId,
          required String suffix,
          required DateTime occurredAt,
        }) =>
            repository.append(
              PosStockMovement.create(
                id: 'sale:$suffix',
                productId: 'product-1',
                warehouseId: 'warehouse-1',
                type: PosStockMovementType.sale,
                direction: PosStockMovementDirection.outbound,
                quantity: PosQuantity.whole(1),
                unitCost: Money.fromMinorUnits(100, currency),
                sourceType: 'pos_invoice',
                sourceId: 'sale:$suffix',
                sourceLineId: 'line:$suffix',
                lotId: lotId,
                occurredAt: occurredAt,
                idempotencyKey: 'sale:$suffix:key',
                createdAt: now,
              ),
            );

        await receiveLot(id: 'today-lot', expiry: today, quantity: 2);
        await receiveLot(id: 'expired-lot', expiry: yesterday, quantity: 1);

        final saleOnExpiryDate = await sellLot(
          lotId: 'today-lot',
          suffix: 'inclusive',
          occurredAt: now,
        );
        final futureSaleFromExpiredLot = await sellLot(
          lotId: 'today-lot',
          suffix: 'future',
          occurredAt: now.add(const Duration(days: 1)),
        );
        final backdatedSaleFromExpiredLot = await sellLot(
          lotId: 'expired-lot',
          suffix: 'backdated',
          occurredAt: now.subtract(const Duration(days: 1)),
        );

        expect(saleOnExpiryDate.isSuccess, isTrue);
        expect(futureSaleFromExpiredLot.isFailure, isTrue);
        expect(backdatedSaleFromExpiredLot.isFailure, isTrue);
        expect(await db.query('pos_stock_movements'), hasLength(3));
      },
    );

    test(
      'appends signed movements and replays weighted average balance',
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
        final rows = await db.query('pos_stock_movements', orderBy: 'id ASC');

        expect(balance.isSuccess, isTrue);
        expect(balance.valueOrNull!.quantity.scaledUnits, 15);
        expect(balance.valueOrNull!.valuation.minorUnits, 2250);
        expect(balance.valueOrNull!.averageUnitCost.minorUnits, 150);
        expect(rows.map((row) => row['quantity_scaled']), contains(-5));
      },
    );

    test(
      'accepts an exact idempotent replay without adding a second row',
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
      },
    );

    test(
      'rejects duplicate idempotency keys without adding a second row',
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
      },
    );

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

    test(
      'lists movements in deterministic descending order with pagination',
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
        expect(firstPage.valueOrNull!.map((item) => item.id), [
          'sale',
          'purchase',
        ]);
        expect(secondPage.valueOrNull!.map((item) => item.id), ['opening']);
      },
    );

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
