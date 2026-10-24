import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_041_pos_invoice_metadata.dart';
import 'package:qayd/data/database/migrations/migration_042_pos_product_categories.dart';
import 'package:qayd/data/repositories/sqlite_pos_product_repository.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_barcode.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _CurrencyRepository implements CurrencyRepository {
  _CurrencyRepository(this.currency);

  final CurrencyCode currency;

  @override
  Future<Result<CurrencyCode?>> getByCode(String code) async {
    return Success(code == currency.code ? currency : null);
  }

  @override
  Future<Result<List<CurrencyCode>>> getAll({bool onlyActive = false}) async {
    return Success([currency]);
  }

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

  group('SqlitePosProductRepository', () {
    late Database db;
    late SqlitePosProductRepository repository;

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
      repository = SqlitePosProductRepository(
        db,
        _CurrencyRepository(currency),
      );
    });

    tearDown(() => db.close());

    PosProduct product({
      required String id,
      required String sku,
      required String name,
      List<PosBarcode> barcodes = const <PosBarcode>[],
    }) {
      return PosProduct.create(
        id: id,
        sku: sku,
        name: name,
        currency: currency,
        salePrice: Money.fromMinorUnits(1500, currency),
        purchasePrice: Money.fromMinorUnits(900, currency),
        quantityScale: 0,
        reorderLevel: PosQuantity.whole(2),
        barcodes: barcodes,
        now: DateTime.utc(2026, 1, 1),
      );
    }

    test('saves and restores a product with its primary barcode', () async {
      final saved = await repository.save(
        product(
          id: 'product-1',
          sku: 'SKU-1',
          name: 'Coffee',
          barcodes: [PosBarcode('12345')],
        ),
      );
      final restored = await repository.getById('product-1');
      final byBarcode = await repository.getByBarcode(PosBarcode('12345'));

      expect(saved.isSuccess, isTrue);
      expect(restored.isSuccess, isTrue);
      expect(restored.valueOrNull!.salePrice.minorUnits, 1500);
      expect(restored.valueOrNull!.reorderLevel.scaledUnits, 2);
      expect(restored.valueOrNull!.primaryBarcode!.value, '12345');
      expect(byBarcode.valueOrNull!.id, 'product-1');
    });

    test('searches by barcode and excludes inactive barcode matches', () async {
      await repository.save(
        product(
          id: 'product-1',
          sku: 'SKU-1',
          name: 'Coffee',
          barcodes: [PosBarcode('62900001')],
        ),
      );

      final bySearch = await repository.list(search: '62900001');
      expect(bySearch.valueOrNull, hasLength(1));
      expect(bySearch.valueOrNull!.single.id, 'product-1');

      await repository.deactivate('product-1');
      expect(
        (await repository.getByBarcode(PosBarcode('62900001'))).valueOrNull,
        isNull,
      );
      expect((await repository.list(search: '62900001')).valueOrNull, isEmpty);
    });

    test('lists by active status and search, then deactivates immutably',
        () async {
      await repository.save(
        product(id: 'product-1', sku: 'SKU-1', name: 'Coffee'),
      );
      await repository.save(
        product(id: 'product-2', sku: 'SKU-2', name: 'Tea'),
      );

      final before = await repository.list(search: 'Tea');
      final disabled = await repository.deactivate('product-2');
      final after = await repository.list();
      final all = await repository.list(activeOnly: false);

      expect(before.valueOrNull, hasLength(1));
      expect(before.valueOrNull!.single.name, 'Tea');
      expect(disabled.isSuccess, isTrue);
      expect(after.valueOrNull!.map((item) => item.id), contains('product-1'));
      expect(after.valueOrNull!.map((item) => item.id),
          isNot(contains('product-2')));
      expect(all.valueOrNull, hasLength(2));
      expect(
          all.valueOrNull!
              .singleWhere((item) => item.id == 'product-2')
              .isActive,
          isFalse);
    });

    test('rejects a barcode already owned by another product', () async {
      await repository.save(
        product(
          id: 'product-1',
          sku: 'SKU-1',
          name: 'Coffee',
          barcodes: [PosBarcode('12345')],
        ),
      );
      final result = await repository.save(
        product(
          id: 'product-2',
          sku: 'SKU-2',
          name: 'Tea',
          barcodes: [PosBarcode('12345')],
        ),
      );

      expect(result.isFailure, isTrue);
      expect(
          (await repository.getByBarcode(PosBarcode('12345'))).valueOrNull!.id,
          'product-1');
      expect(
          (await repository.list(activeOnly: false)).valueOrNull, hasLength(1));
    });

    test('rejects a product whose currency is not registered', () async {
      final otherCurrency = CurrencyCode(
        code: 'USD',
        nameAr: 'دولار',
        symbol: r'$',
      );
      final result = await repository.save(
        PosProduct.create(
          id: 'product-usd',
          sku: 'USD-1',
          name: 'USD product',
          currency: otherCurrency,
          salePrice: Money.fromMinorUnits(100, otherCurrency),
          purchasePrice: Money.fromMinorUnits(50, otherCurrency),
        ),
      );

      expect(result.isFailure, isTrue);
      expect((await repository.list(activeOnly: false)).valueOrNull, isEmpty);
    });
  });
}
