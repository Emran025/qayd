import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_profit_margin.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_barcode.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// SQLite adapter for the POS product aggregate.
final class SqlitePosProductRepository implements PosProductRepository {
  SqlitePosProductRepository(this._db, this._currencyRepository);

  final Database _db;
  final CurrencyRepository _currencyRepository;

  @override
  Future<Result<PosProduct>> getById(String id) async {
    try {
      final rows = await _db.query(
        'pos_products',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return _notFound();
      return await _mapRow(rows.first);
    } on DatabaseException {
      return _readFailure();
    } catch (_) {
      return _readFailure();
    }
  }

  @override
  Future<Result<PosProduct?>> getByBarcode(PosBarcode barcode) async {
    try {
      final rows = await _db.rawQuery(
        '''
        SELECT p.*
        FROM pos_products p
        INNER JOIN pos_product_barcodes b ON b.product_id = p.id
        WHERE b.barcode = ? AND p.is_active = 1
        LIMIT 1
        ''',
        [barcode.value],
      );
      if (rows.isEmpty) return const Success(null);
      final mapped = await _mapRow(rows.first);
      return mapped.fold<Result<PosProduct?>>(
        (failure) => FailureResult<PosProduct?>(failure),
        (product) => Success<PosProduct?>(product),
      );
    } on DatabaseException {
      return _readNullableFailure();
    } catch (_) {
      return _readNullableFailure();
    }
  }

  @override
  Future<Result<List<PosProduct>>> list({
    bool activeOnly = true,
    String? search,
  }) async {
    try {
      final clauses = <String>[];
      final args = <Object?>[];
      if (activeOnly) clauses.add('p.is_active = 1');
      final normalizedSearch = search?.trim();
      if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
        clauses.add('(p.name LIKE ? OR p.sku LIKE ? OR b.barcode LIKE ?)');
        final pattern = '%$normalizedSearch%';
        args
          ..add(pattern)
          ..add(pattern)
          ..add(pattern);
      }
      final whereSql = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
      final rows = await _db.rawQuery(
        '''
        SELECT DISTINCT p.*
        FROM pos_products p
        LEFT JOIN pos_product_barcodes b ON b.product_id = p.id
        $whereSql
        ORDER BY p.name COLLATE NOCASE ASC
        ''',
        args,
      );

      final products = <PosProduct>[];
      for (final row in rows) {
        final mapped = await _mapRow(row);
        if (mapped.isFailure) return FailureResult(mapped.failureOrNull!);
        products.add(mapped.valueOrNull!);
      }
      return Success(products);
    } on DatabaseException {
      return _readListFailure();
    } catch (_) {
      return _readListFailure();
    }
  }

  @override
  Future<Result<void>> save(PosProduct product) async {
    final currencyResult = await _currencyRepository.getByCode(
      product.currency.code,
    );
    if (currencyResult.isFailure) {
      return FailureResult(currencyResult.failureOrNull!);
    }
    if (currencyResult.valueOrNull == null) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posProductCurrencyMismatch),
      );
    }

    try {
      await _db.transaction((txn) async {
        for (final barcode in product.barcodes) {
          final rows = await txn.query(
            'pos_product_barcodes',
            columns: ['product_id'],
            where: 'barcode = ?',
            whereArgs: [barcode.value],
            limit: 1,
          );
          if (rows.isNotEmpty && rows.first['product_id'] != product.id) {
            throw const _PosProductBarcodeConflictException();
          }
        }

        final productMap = <String, Object?>{
          'id': product.id,
          'sku': product.sku,
          'name': product.name,
          'category_id': product.categoryId,
          'description': product.description,
          'unit_name': product.unitName,
          'currency_code': product.currency.code,
          'sale_price_minor': product.salePrice.minorUnits,
          'purchase_price_minor': product.purchasePrice.minorUnits,
          'profit_margin_type':
              product.profitMargin.isPercentage ? 'percentage' : 'fixed_amount',
          'profit_margin_value': product.profitMargin.isPercentage
              ? product.profitMargin.percentageBasisPoints!
              : product.profitMargin.fixedAmount!.minorUnits,
          'quantity_scale': product.quantityScale,
          'reorder_level_scaled': product.reorderLevel.scaledUnits,
          'expiry_tracking': product.expiryTracking ? 1 : 0,
          'is_active': product.isActive ? 1 : 0,
          'created_at': product.createdAt.toUtc().toIso8601String(),
          'updated_at': product.updatedAt.toUtc().toIso8601String(),
        };
        final updated = await txn.update(
          'pos_products',
          productMap,
          where: 'id = ?',
          whereArgs: [product.id],
        );
        if (updated == 0) {
          await txn.insert(
            'pos_products',
            productMap,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }

        await txn.delete(
          'pos_product_barcodes',
          where: 'product_id = ?',
          whereArgs: [product.id],
        );
        for (var index = 0; index < product.barcodes.length; index++) {
          final barcode = product.barcodes[index];
          await txn.insert('pos_product_barcodes', <String, Object?>{
            'id': '${product.id}:barcode:$index',
            'product_id': product.id,
            'barcode': barcode.value,
            'symbology': null,
            'is_primary': index == 0 ? 1 : 0,
            'created_at': product.updatedAt.toUtc().toIso8601String(),
          });
        }
      });
      return const Success(null);
    } on _PosProductBarcodeConflictException {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posProductBarcodeExists),
      );
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posProductSaveFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posProductSaveFailed),
      );
    }
  }

  @override
  Future<Result<void>> deactivate(String id) async {
    try {
      final updated = await _db.update(
        'pos_products',
        <String, Object?>{
          'is_active': 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated == 0) return _notFoundVoid();
      return const Success(null);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posProductSaveFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posProductSaveFailed),
      );
    }
  }

  Future<Result<PosProduct>> _mapRow(Map<String, Object?> row) async {
    final currencyResult = await _currencyRepository.getByCode(
      row['currency_code'] as String,
    );
    if (currencyResult.isFailure) {
      return FailureResult(currencyResult.failureOrNull!);
    }
    final currency = currencyResult.valueOrNull;
    if (currency == null) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posProductCurrencyMismatch),
      );
    }

    final barcodeRows = await _db.query(
      'pos_product_barcodes',
      columns: ['barcode'],
      where: 'product_id = ?',
      whereArgs: [row['id']],
      orderBy: 'is_primary DESC, created_at ASC',
    );
    return Success(
      PosProduct.restore(
        id: row['id']! as String,
        sku: row['sku']! as String,
        name: row['name']! as String,
        categoryId: row['category_id'] as String?,
        description: row['description'] as String?,
        unitName: row['unit_name']! as String,
        currency: currency,
        salePrice: Money.fromMinorUnits(
          _asInt(row['sale_price_minor']),
          currency,
        ),
        purchasePrice: Money.fromMinorUnits(
          _asInt(row['purchase_price_minor']),
          currency,
        ),
        profitMargin: _profitMarginFromRow(row, currency),
        quantityScale: _asInt(row['quantity_scale']),
        reorderLevel: PosQuantity.fromScaled(
          _asInt(row['reorder_level_scaled']),
          scale: _asInt(row['quantity_scale']),
        ),
        expiryTracking: _asInt(row['expiry_tracking']) == 1,
        isActive: _asInt(row['is_active']) == 1,
        barcodes: barcodeRows
            .map((barcode) => PosBarcode(barcode['barcode']! as String))
            .toList(growable: false),
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      ),
    );
  }

  static int _asInt(Object? value) => (value as num).toInt();

  static PosProfitMargin _profitMarginFromRow(
    Map<String, Object?> row,
    CurrencyCode currency,
  ) {
    final type = row['profit_margin_type'] as String? ?? 'percentage';
    final value = row['profit_margin_value'] == null
        ? 0
        : _asInt(row['profit_margin_value']);
    return switch (type) {
      'percentage' => PosProfitMargin.percentage(value),
      'fixed_amount' => PosProfitMargin.fixedAmount(
          Money.fromMinorUnits(value, currency),
        ),
      _ => throw FormatException('Unknown POS product margin type $type'),
    };
  }

  FailureResult<PosProduct> _notFound() => FailureResult(
        ValidationFailure(messageAr: AppStrings.posProductNotFound),
      );

  FailureResult<PosProduct?> _readNullableFailure() => FailureResult(
        DatabaseFailure(messageAr: AppStrings.posProductReadFailed),
      );

  FailureResult<List<PosProduct>> _readListFailure() => FailureResult(
        DatabaseFailure(messageAr: AppStrings.posProductReadFailed),
      );

  FailureResult<PosProduct> _readFailure() => FailureResult(
        DatabaseFailure(messageAr: AppStrings.posProductReadFailed),
      );

  FailureResult<void> _notFoundVoid() => FailureResult(
        ValidationFailure(messageAr: AppStrings.posProductNotFound),
      );
}

final class _PosProductBarcodeConflictException implements Exception {
  const _PosProductBarcodeConflictException();
}
