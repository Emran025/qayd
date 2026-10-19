import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/exceptions/invalid_pos_stock_exception.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// SQLite adapter for immutable POS stock movements and deterministic balance replay.
final class SqlitePosStockMovementRepository
    implements PosStockMovementRepository {
  SqlitePosStockMovementRepository(this._db, this._currencyRepository);

  final Database _db;
  final CurrencyRepository _currencyRepository;

  @override
  Future<Result<PosStockBalance>> getBalance({
    required String productId,
    required String warehouseId,
  }) async {
    try {
      final context = await _loadProductContext(_db, productId);
      if (context == null) return _productNotFound();
      return Success(
        await _readBalance(
          _db,
          productId: productId,
          warehouseId: warehouseId,
          currency: context.currency,
          scale: context.scale,
        ),
      );
    } on DatabaseException {
      return _readFailure();
    } on InvalidPosStockException catch (error) {
      return FailureResult(ValidationFailure(messageAr: error.messageAr));
    } catch (_) {
      return _readFailure();
    }
  }

  @override
  Future<Result<PosStockMovement?>> getByIdempotencyKey(String key) async {
    return getByIdempotencyKeyInTransaction(_db, key);
  }

  /// Reads an idempotent movement using an existing transaction executor.
  ///
  /// This is a Data-layer hook used by the atomic POS posting coordinator.
  Future<Result<PosStockMovement?>> getByIdempotencyKeyInTransaction(
    DatabaseExecutor executor,
    String key,
  ) async {
    final normalized = key.trim();
    if (normalized.isEmpty) return const Success(null);
    try {
      final rows = await executor.query(
        'pos_stock_movements',
        where: 'idempotency_key = ?',
        whereArgs: [normalized],
        limit: 1,
      );
      if (rows.isEmpty) return const Success(null);
      final mapped = await _mapRow(rows.first);
      if (mapped.isFailure) {
        return FailureResult<PosStockMovement?>(mapped.failureOrNull!);
      }
      return Success<PosStockMovement?>(mapped.valueOrNull);
    } on DatabaseException {
      return _readNullableFailure();
    } on InvalidPosStockException catch (error) {
      return FailureResult(ValidationFailure(messageAr: error.messageAr));
    } catch (_) {
      return _readNullableFailure();
    }
  }

  @override
  Future<Result<void>> append(PosStockMovement movement) async {
    try {
      await _db.transaction((txn) async {
        final duplicate = await txn.query(
          'pos_stock_movements',
          where: 'idempotency_key = ?',
          whereArgs: [movement.idempotencyKey],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          if (_rowMatchesMovement(duplicate.first, movement)) {
            throw const _StockMovementIdempotentReplayException();
          }
          throw const _StockMovementIdempotencyConflictException();
        }

        final context = await _loadProductContext(txn, movement.productId);
        if (context == null) throw const _StockProductNotFoundException();
        final balance = await _readBalance(
          txn,
          productId: movement.productId,
          warehouseId: movement.warehouseId,
          currency: context.currency,
          scale: context.scale,
        );
        try {
          balance.apply(movement);
        } on InvalidPosStockException catch (error) {
          throw _StockMovementPolicyException(error.messageAr);
        }
        await txn.insert(
          'pos_stock_movements',
          _toRow(movement),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      });
      return const Success(null);
    } on _StockMovementIdempotentReplayException {
      return const Success(null);
    } on _StockMovementIdempotencyConflictException {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockIdempotencyExists),
      );
    } on _StockProductNotFoundException {
      return _productNotFoundVoid();
    } on _StockMovementPolicyException catch (error) {
      return FailureResult(ValidationFailure(messageAr: error.messageAr));
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posStockAppendFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posStockAppendFailed),
      );
    }
  }

  /// Appends a movement using an existing transaction executor.
  ///
  /// It never opens a nested transaction and is intentionally a Data-layer
  /// hook for the atomic POS posting coordinator.
  Future<Result<void>> appendInTransaction(
    DatabaseExecutor executor,
    PosStockMovement movement,
  ) async {
    try {
      final duplicate = await executor.query(
        'pos_stock_movements',
        where: 'idempotency_key = ?',
        whereArgs: [movement.idempotencyKey],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        if (_rowMatchesMovement(duplicate.first, movement)) {
          return const Success(null);
        }
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockIdempotencyExists),
        );
      }

      final context = await _loadProductContext(executor, movement.productId);
      if (context == null) return _productNotFoundVoid();
      final balance = await _readBalance(
        executor,
        productId: movement.productId,
        warehouseId: movement.warehouseId,
        currency: context.currency,
        scale: context.scale,
      );
      // Sale postings are built from an average cost snapshot. If another
      // movement changed that snapshot before this transaction acquired the
      // write lock, accepting the stale unit cost would make COGS diverge
      // from the inventory valuation. Reject and let the caller rebuild.
      if (movement.direction == PosStockMovementDirection.outbound &&
          movement.unitCost != balance.averageUnitCost) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockAppendFailed),
        );
      }
      try {
        balance.apply(movement);
      } on InvalidPosStockException catch (error) {
        return FailureResult(ValidationFailure(messageAr: error.messageAr));
      }
      await executor.insert(
        'pos_stock_movements',
        _toRow(movement),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return const Success(null);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posStockAppendFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posStockAppendFailed),
      );
    }
  }

  Future<PosStockBalance> _readBalance(
    DatabaseExecutor executor, {
    required String productId,
    required String warehouseId,
    required CurrencyCode currency,
    required int scale,
  }) async {
    var balance =
        emptyPosStockBalance(currency: currency, quantityScale: scale);
    final rows = await executor.query(
      'pos_stock_movements',
      where: 'product_id = ? AND warehouse_id = ?',
      whereArgs: [productId, warehouseId],
      orderBy: 'occurred_at ASC, created_at ASC, id ASC',
    );
    for (final row in rows) {
      final movementResult = await _mapRow(row);
      if (movementResult.isFailure) {
        throw InvalidPosStockException(
          messageAr: movementResult.failureOrNull!.messageAr,
          code: 'pos_stock_invalid_persisted_movement',
        );
      }
      balance = balance.apply(movementResult.valueOrNull!);
    }
    return balance;
  }

  Future<_ProductStockContext?> _loadProductContext(
    DatabaseExecutor executor,
    String productId,
  ) async {
    final rows = await executor.query(
      'pos_products',
      columns: ['currency_code', 'quantity_scale'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final currencyResult = await _currency(rows.first['currency_code']);
    if (currencyResult.isFailure) {
      throw InvalidPosStockException(
        messageAr: currencyResult.failureOrNull!.messageAr,
        code: 'pos_stock_currency_lookup_failed',
      );
    }
    return _ProductStockContext(
      currency: currencyResult.valueOrNull!,
      scale: _asInt(rows.first['quantity_scale']),
    );
  }

  Future<Result<PosStockMovement>> _mapRow(Map<String, Object?> row) async {
    final currency = await _currency(row['currency_code']);
    if (currency.isFailure) return FailureResult(currency.failureOrNull!);
    final signed = _asInt(row['quantity_scaled']);
    if (signed == 0) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockInvalidMovement),
      );
    }
    final type = _typeFromDb(row['movement_type'] as String?);
    if (type == null) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockInvalidMovement),
      );
    }
    try {
      return Success(
        PosStockMovement.create(
          id: row['id']! as String,
          productId: row['product_id']! as String,
          warehouseId: row['warehouse_id']! as String,
          type: type,
          direction: signed > 0
              ? PosStockMovementDirection.inbound
              : PosStockMovementDirection.outbound,
          quantity: PosQuantity.fromScaled(
            signed.abs(),
            scale: _asInt(row['quantity_scale']),
          ),
          unitCost: Money.fromMinorUnits(
            _asInt(row['unit_cost_minor']),
            currency.valueOrNull!,
          ),
          sourceType: row['source_type'] as String?,
          sourceId: row['source_id'] as String?,
          sourceLineId: row['source_line_id'] as String?,
          lotId: row['lot_id'] as String?,
          occurredAt: DateTime.parse(row['occurred_at']! as String),
          idempotencyKey: row['idempotency_key']! as String,
          createdAt: DateTime.parse(row['created_at']! as String),
        ),
      );
    } on InvalidPosStockException catch (error) {
      return FailureResult(ValidationFailure(messageAr: error.messageAr));
    }
  }

  Future<Result<CurrencyCode>> _currency(Object? code) async {
    final currencyResult = await _currencyRepository.getByCode(code as String);
    if (currencyResult.isFailure) {
      return FailureResult(currencyResult.failureOrNull!);
    }
    final currency = currencyResult.valueOrNull;
    if (currency == null) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockCurrencyMismatch),
      );
    }
    return Success(currency);
  }

  static bool _rowMatchesMovement(
    Map<String, Object?> row,
    PosStockMovement movement,
  ) {
    final expected = _toRow(movement);
    for (final entry in expected.entries) {
      if (entry.key == 'created_at') continue;
      if (row[entry.key] != entry.value) return false;
    }
    return true;
  }

  static Map<String, Object?> _toRow(PosStockMovement movement) => {
        'id': movement.id,
        'product_id': movement.productId,
        'warehouse_id': movement.warehouseId,
        'movement_type': _typeToDb(movement.type),
        'quantity_scaled': movement.signedQuantityScaled,
        'quantity_scale': movement.quantity.scale,
        'unit_cost_minor': movement.unitCost.minorUnits,
        'currency_code': movement.unitCost.currency.code,
        'source_type': movement.sourceType,
        'source_id': movement.sourceId,
        'source_line_id': movement.sourceLineId,
        'lot_id': movement.lotId,
        'occurred_at': movement.occurredAt.toUtc().toIso8601String(),
        'idempotency_key': movement.idempotencyKey,
        'created_at': movement.createdAt.toUtc().toIso8601String(),
      };

  static String _typeToDb(PosStockMovementType type) {
    switch (type) {
      case PosStockMovementType.opening:
        return 'opening';
      case PosStockMovementType.purchase:
        return 'purchase';
      case PosStockMovementType.sale:
        return 'sale';
      case PosStockMovementType.salesReturn:
        return 'sales_return';
      case PosStockMovementType.purchaseReturn:
        return 'purchase_return';
      case PosStockMovementType.adjustment:
        return 'adjustment';
      case PosStockMovementType.damage:
        return 'damage';
      case PosStockMovementType.expiry:
        return 'expiry';
    }
  }

  static PosStockMovementType? _typeFromDb(String? value) {
    switch (value) {
      case 'opening':
        return PosStockMovementType.opening;
      case 'purchase':
        return PosStockMovementType.purchase;
      case 'sale':
        return PosStockMovementType.sale;
      case 'sales_return':
        return PosStockMovementType.salesReturn;
      case 'purchase_return':
        return PosStockMovementType.purchaseReturn;
      case 'adjustment':
        return PosStockMovementType.adjustment;
      case 'damage':
        return PosStockMovementType.damage;
      case 'expiry':
        return PosStockMovementType.expiry;
      default:
        return null;
    }
  }

  static int _asInt(Object? value) => (value as num).toInt();

  FailureResult<PosStockBalance> _productNotFound() => FailureResult(
        ValidationFailure(messageAr: AppStrings.posProductNotFound),
      );

  FailureResult<void> _productNotFoundVoid() => FailureResult(
        ValidationFailure(messageAr: AppStrings.posProductNotFound),
      );

  FailureResult<PosStockBalance> _readFailure() => FailureResult(
        DatabaseFailure(messageAr: AppStrings.posStockReadFailed),
      );

  FailureResult<PosStockMovement?> _readNullableFailure() => FailureResult(
        DatabaseFailure(messageAr: AppStrings.posStockReadFailed),
      );
}

final class _ProductStockContext {
  const _ProductStockContext({required this.currency, required this.scale});

  final CurrencyCode currency;
  final int scale;
}

final class _StockMovementIdempotentReplayException implements Exception {
  const _StockMovementIdempotentReplayException();
}

final class _StockMovementIdempotencyConflictException implements Exception {
  const _StockMovementIdempotencyConflictException();
}

final class _StockProductNotFoundException implements Exception {
  const _StockProductNotFoundException();
}

final class _StockMovementPolicyException implements Exception {
  const _StockMovementPolicyException(this.messageAr);

  final String messageAr;
}
