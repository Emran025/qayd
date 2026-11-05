import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_stock_lot.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/exceptions/invalid_pos_stock_exception.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/pos_stock_disposal_reason.dart';
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

  @override
  Future<Result<List<PosStockLot>>> getSellableLots({
    required String productId,
    required String warehouseId,
    required PosDate businessDate,
  }) async {
    try {
      final context = await _loadProductContext(_db, productId);
      if (context == null || !context.expiryTracking) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockInvalidMovement),
        );
      }
      final lotlessRows = await _db.rawQuery(
        '''
        SELECT COALESCE(SUM(quantity_scaled), 0) AS quantity_scaled
        FROM pos_stock_movements
        WHERE product_id = ? AND warehouse_id = ? AND lot_id IS NULL
        ''',
        [productId, warehouseId],
      );
      if (_asInt(lotlessRows.first['quantity_scaled']) > 0) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockLotlessBalance),
        );
      }

      final rows = await _db.query(
        'pos_stock_lots',
        where: 'product_id = ? AND warehouse_id = ?',
        whereArgs: [productId, warehouseId],
        orderBy: 'expiry_date ASC, created_at ASC, id ASC',
      );
      final eligible = <PosStockLot>[];
      for (final row in rows) {
        final lot = await _mapLotRow(row);
        if (lot == null ||
            lot.receivedQuantity.scale != context.scale ||
            lot.unitCost.currency != context.currency) {
          return FailureResult(
            ValidationFailure(
              messageAr: AppStrings.posStockLotProjectionMismatch,
            ),
          );
        }
        final invalidMovement = await _db.query(
          'pos_stock_movements',
          columns: ['id'],
          where: '''
            lot_id = ? AND (
              product_id <> ? OR warehouse_id <> ? OR
              quantity_scale <> ? OR currency_code <> ?
            )
          ''',
          whereArgs: [
            lot.id,
            productId,
            warehouseId,
            context.scale,
            context.currency.code,
          ],
          limit: 1,
        );
        final quantityRows = await _db.rawQuery(
          '''
          SELECT COALESCE(SUM(quantity_scaled), 0) AS quantity_scaled
          FROM pos_stock_movements WHERE lot_id = ?
          ''',
          [lot.id],
        );
        final replayedQuantity = _asInt(quantityRows.first['quantity_scaled']);
        if (invalidMovement.isNotEmpty ||
            replayedQuantity != lot.remainingQuantity.scaledUnits) {
          return FailureResult(
            ValidationFailure(
              messageAr: AppStrings.posStockLotProjectionMismatch,
            ),
          );
        }
        final expiry = lot.expiryDate;
        if (lot.remainingQuantity.isZero ||
            expiry == null ||
            expiry.isBefore(businessDate)) {
          continue;
        }
        eligible.add(lot);
      }
      return Success(eligible);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posStockReadFailed),
      );
    } on Object {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockLotProjectionMismatch),
      );
    }
  }

  @override
  Future<Result<List<PosStockLot>>> getDisposalLots({
    required String productId,
    required String warehouseId,
  }) async {
    try {
      final context = await _loadProductContext(_db, productId);
      if (context == null) return _productNotFoundLots();
      final lotlessRows = await _db.rawQuery(
        '''
        SELECT COALESCE(SUM(quantity_scaled), 0) AS quantity_scaled
        FROM pos_stock_movements
        WHERE product_id = ? AND warehouse_id = ? AND lot_id IS NULL
        ''',
        [productId, warehouseId],
      );
      if (context.expiryTracking &&
          _asInt(lotlessRows.first['quantity_scaled']) > 0) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockLotlessBalance),
        );
      }

      final rows = await _db.query(
        'pos_stock_lots',
        where: 'product_id = ? AND warehouse_id = ?',
        whereArgs: [productId, warehouseId],
        orderBy: 'expiry_date ASC, created_at ASC, id ASC',
      );
      final openLots = <PosStockLot>[];
      for (final row in rows) {
        final lot = await _mapLotRow(row);
        if (lot == null ||
            lot.receivedQuantity.scale != context.scale ||
            lot.unitCost.currency != context.currency) {
          return FailureResult(
            ValidationFailure(messageAr: AppStrings.posStockLotProjectionMismatch),
          );
        }
        final invalidMovement = await _db.query(
          'pos_stock_movements',
          columns: ['id'],
          where: '''
            lot_id = ? AND (
              product_id <> ? OR warehouse_id <> ? OR
              quantity_scale <> ? OR currency_code <> ?
            )
          ''',
          whereArgs: [
            lot.id,
            productId,
            warehouseId,
            context.scale,
            context.currency.code,
          ],
          limit: 1,
        );
        final quantityRows = await _db.rawQuery(
          '''
          SELECT COALESCE(SUM(quantity_scaled), 0) AS quantity_scaled
          FROM pos_stock_movements WHERE lot_id = ?
          ''',
          [lot.id],
        );
        if (invalidMovement.isNotEmpty ||
            _asInt(quantityRows.first['quantity_scaled']) !=
                lot.remainingQuantity.scaledUnits) {
          return FailureResult(
            ValidationFailure(messageAr: AppStrings.posStockLotProjectionMismatch),
          );
        }
        if (!lot.remainingQuantity.isZero) openLots.add(lot);
      }
      return Success(openLots);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posStockReadFailed),
      );
    } on Object {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockLotProjectionMismatch),
      );
    }
  }

  @override
  Future<Result<List<PosStockMovement>>> listMovementsForSource({
    required String sourceType,
    required String sourceId,
    PosStockMovementType? type,
  }) async {
    final normalizedType = sourceType.trim();
    final normalizedId = sourceId.trim();
    if (normalizedType.isEmpty || normalizedId.isEmpty) {
      return _invalidMovementListFailure();
    }
    try {
      final clauses = <String>['source_type = ?', 'source_id = ?'];
      final args = <Object?>[normalizedType, normalizedId];
      if (type != null) {
        clauses.add('movement_type = ?');
        args.add(_typeToDb(type));
      }
      final rows = await _db.query(
        'pos_stock_movements',
        where: clauses.join(' AND '),
        whereArgs: args,
        orderBy: 'created_at ASC, id ASC',
      );
      final movements = <PosStockMovement>[];
      for (final row in rows) {
        final mapped = await _mapRow(row);
        if (mapped.isFailure) return FailureResult(mapped.failureOrNull!);
        movements.add(mapped.valueOrNull!);
      }
      return Success(movements);
    } on DatabaseException {
      return _readMovementListFailure();
    } catch (_) {
      return _readMovementListFailure();
    }
  }

  /// Creates an immutable lot row inside the posting transaction. The database
  /// trigger derives its remaining projection only after the inbound movement.
  Future<Result<void>> createLotInTransaction(
    DatabaseExecutor executor,
    PosStockLot lot,
  ) async {
    if (lot.expiryDate == null || lot.remainingQuantity.scaledUnits != 0) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockInvalidMovement),
      );
    }
    try {
      final existing = await executor.query(
        'pos_stock_lots',
        where: 'id = ?',
        whereArgs: [lot.id],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final mapped = await _mapLotRow(existing.first);
        if (mapped != null && mapped.hasSameImmutableData(lot)) {
          return const Success(null);
        }
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockIdempotencyExists),
        );
      }
      await executor.insert(
        'pos_stock_lots',
        _lotToRow(lot),
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
  Future<Result<List<PosStockMovement>>> listMovements({
    required String warehouseId,
    String? productId,
    PosStockMovementType? type,
    DateTime? fromInclusive,
    DateTime? untilExclusive,
    int limit = 100,
    int offset = 0,
  }) async {
    final normalizedWarehouseId = warehouseId.trim();
    final normalizedProductId = productId?.trim();
    if (normalizedWarehouseId.isEmpty ||
        (normalizedProductId != null && normalizedProductId.isEmpty)) {
      return _invalidMovementListFailure();
    }
    if (fromInclusive != null &&
        untilExclusive != null &&
        !fromInclusive.isBefore(untilExclusive)) {
      return _invalidMovementListFailure();
    }

    final clauses = <String>['warehouse_id = ?'];
    final args = <Object?>[normalizedWarehouseId];
    if (normalizedProductId != null) {
      clauses.add('product_id = ?');
      args.add(normalizedProductId);
    }
    if (type != null) {
      clauses.add('movement_type = ?');
      args.add(_typeToDb(type));
    }
    if (fromInclusive != null) {
      clauses.add('occurred_at >= ?');
      args.add(fromInclusive.toUtc().toIso8601String());
    }
    if (untilExclusive != null) {
      clauses.add('occurred_at < ?');
      args.add(untilExclusive.toUtc().toIso8601String());
    }

    try {
      final rows = await _db.query(
        'pos_stock_movements',
        where: clauses.join(' AND '),
        whereArgs: args,
        orderBy: 'occurred_at DESC, created_at DESC, id DESC',
        limit: limit.clamp(1, 500).toInt(),
        offset: offset.clamp(0, 0x7fffffff).toInt(),
      );
      final movements = <PosStockMovement>[];
      for (final row in rows) {
        try {
          final mapped = await _mapRow(row);
          if (mapped.isFailure) return FailureResult(mapped.failureOrNull!);
          movements.add(mapped.valueOrNull!);
        } catch (_) {
          return _invalidMovementListFailure();
        }
      }
      return Success(movements);
    } on DatabaseException {
      return _readMovementListFailure();
    } on InvalidPosStockException catch (error) {
      return FailureResult(ValidationFailure(messageAr: error.messageAr));
    } catch (_) {
      return _readMovementListFailure();
    }
  }

  @override
  Future<Result<void>> append(PosStockMovement movement) async {
    if (_requiresAtomicDisposalPosting(movement)) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockDisposalAtomicRequired),
      );
    }
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
        final lotFailure = await _validateMovementLot(txn, movement, context);
        if (lotFailure != null) throw _StockMovementPolicyException(lotFailure);
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
    PosStockMovement movement, {
    bool allowStockDisposal = false,
  }
  ) async {
    if (!allowStockDisposal && _requiresAtomicDisposalPosting(movement)) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockDisposalAtomicRequired),
      );
    }
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
      final lotFailure = await _validateMovementLot(
        executor,
        movement,
        context,
      );
      if (lotFailure != null) {
        return FailureResult(ValidationFailure(messageAr: lotFailure));
      }
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

  /// Revalidates disposal policy and its weighted-average valuation against the
  /// transaction snapshot. No writes happen until this method succeeds.
  Future<Result<PosStockBalance>> validateStockDisposalInTransaction(
    DatabaseExecutor executor,
    PosStockMovement movement,
  ) async {
    try {
      final reason = movement.disposalReason;
      if (reason == null ||
          movement.direction != PosStockMovementDirection.outbound ||
          movement.sourceType != 'stock_disposal' ||
          movement.sourceId == null ||
          movement.voucherId == null ||
          movement.quantity.isZero) {
        return _invalidDisposalBalance();
      }
      final expectedType = switch (reason) {
        PosStockDisposalReason.damage => PosStockMovementType.damage,
        PosStockDisposalReason.expiry => PosStockMovementType.expiry,
        PosStockDisposalReason.authorizedLoss => PosStockMovementType.adjustment,
        PosStockDisposalReason.other => PosStockMovementType.adjustment,
      };
      if (movement.type != expectedType ||
          (reason == PosStockDisposalReason.other &&
              (movement.reasonDetail == null ||
                  movement.reasonDetail!.trim().isEmpty))) {
        return _invalidDisposalBalance();
      }
      final warehouseRows = await executor.query(
        'pos_warehouses',
        columns: ['id'],
        where: 'id = ? AND is_active = 1',
        whereArgs: [movement.warehouseId],
        limit: 1,
      );
      if (warehouseRows.isEmpty) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockWarehouseIdRequired),
        );
      }
      final context = await _loadProductContext(executor, movement.productId);
      if (context == null) return _productNotFoundBalance();
      final lotFailure = await _validateMovementLot(executor, movement, context);
      if (lotFailure != null) {
        return FailureResult(ValidationFailure(messageAr: lotFailure));
      }
      if (reason == PosStockDisposalReason.expiry &&
          (!context.expiryTracking || movement.lotId == null)) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockDisposalExpiryLotRequired),
        );
      }
      if (movement.lotId != null) {
        final lotRows = await executor.query(
          'pos_stock_lots',
          columns: ['expiry_date'],
          where: 'id = ? AND product_id = ? AND warehouse_id = ?',
          whereArgs: [
            movement.lotId,
            movement.productId,
            movement.warehouseId,
          ],
          limit: 1,
        );
        if (lotRows.isEmpty) {
          return FailureResult(
            ValidationFailure(messageAr: AppStrings.posStockLotProjectionMismatch),
          );
        }
        final expiryRaw = lotRows.first['expiry_date'] as String?;
        final expiry = expiryRaw == null ? null : PosDate.parse(expiryRaw);
        final businessDate = PosDate.fromDateTime(movement.occurredAt.toLocal());
        if (reason == PosStockDisposalReason.expiry &&
            (expiry == null || !expiry.isBefore(businessDate))) {
          return FailureResult(
            ValidationFailure(messageAr: AppStrings.posStockDisposalNotExpired),
          );
        }
        if (reason == PosStockDisposalReason.damage &&
            expiry != null &&
            expiry.isBefore(businessDate)) {
          return FailureResult(
            ValidationFailure(messageAr: AppStrings.posStockDisposalBatchExpired),
          );
        }
      }
      final balance = await _readBalance(
        executor,
        productId: movement.productId,
        warehouseId: movement.warehouseId,
        currency: context.currency,
        scale: context.scale,
      );
      if (movement.unitCost != balance.averageUnitCost) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockDisposalCostChanged),
        );
      }
      try {
        balance.apply(movement);
      } on InvalidPosStockException catch (error) {
        return FailureResult(ValidationFailure(messageAr: error.messageAr));
      }
      return Success(balance);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posStockReadFailed),
      );
    } on InvalidPosStockException catch (error) {
      return FailureResult(ValidationFailure(messageAr: error.messageAr));
    } on Object {
      return _invalidDisposalBalance();
    }
  }

  static bool _requiresAtomicDisposalPosting(PosStockMovement movement) {
    return movement.type == PosStockMovementType.damage ||
        movement.type == PosStockMovementType.expiry ||
        movement.sourceType == 'stock_disposal' ||
        movement.sourceType == 'stock_disposal_reversal' ||
        movement.disposalReason != null ||
        movement.reversesSourceId != null;
  }

  /// Appends a purchase-return movement only after proving that it reverses
  /// stock received on the linked original purchase line and does not exceed
  /// that line/lot's unreturned quantity. The ordinary append path continues
  /// to reject reversal movements.
  Future<Result<void>> appendPurchaseReturnInTransaction(
    DatabaseExecutor executor,
    PosStockMovement movement,
  ) async {
    if (movement.type != PosStockMovementType.purchaseReturn ||
        movement.direction != PosStockMovementDirection.outbound ||
        movement.sourceType != 'pos_invoice' ||
        movement.sourceId == null ||
        movement.sourceLineId == null ||
        movement.reversesSourceId == null ||
        movement.quantity.isZero) {
      return _invalidPurchaseReturnStock();
    }
    try {
      final returnRows = await executor.rawQuery(
        'SELECT i.document_type, i.source_invoice_id, i.warehouse_id, '
        'l.source_line_id, l.product_id, l.quantity_scale '
        'FROM pos_invoices i JOIN pos_invoice_lines l ON l.invoice_id = i.id '
        'WHERE i.id = ? AND l.id = ?',
        [movement.sourceId, movement.sourceLineId],
      );
      if (returnRows.length != 1 ||
          returnRows.single['document_type'] != 'purchase_return' ||
          returnRows.single['source_invoice_id'] != movement.reversesSourceId ||
          returnRows.single['warehouse_id'] != movement.warehouseId ||
          returnRows.single['source_line_id'] == null ||
          returnRows.single['product_id'] != movement.productId ||
          _asInt(returnRows.single['quantity_scale']) != movement.quantity.scale) {
        return _invalidPurchaseReturnStock();
      }
      final originalLineId = returnRows.single['source_line_id'] as String;
      final sourceRows = await executor.query(
        'pos_invoices',
        columns: ['id', 'warehouse_id'],
        where: 'id = ? AND document_type = ? AND status IN (?, ?, ?, ?)',
        whereArgs: [
          movement.reversesSourceId,
          'purchase',
          'posted',
          'partiallyPaid',
          'paid',
          'partiallyReturned',
        ],
        limit: 1,
      );
      final originalLines = await executor.query(
        'pos_invoice_lines',
        where:
            'id = ? AND invoice_id = ? AND product_id = ? AND quantity_scale = ?',
        whereArgs: [
          originalLineId,
          movement.reversesSourceId,
          movement.productId,
          movement.quantity.scale,
        ],
        limit: 1,
      );
      if (sourceRows.length != 1 ||
          sourceRows.single['warehouse_id'] != movement.warehouseId ||
          originalLines.length != 1) {
        return _invalidPurchaseReturnStock();
      }
      final sourceMovements = await executor.rawQuery(
        'SELECT COALESCE(SUM(quantity_scaled), 0) AS quantity_scaled '
        'FROM pos_stock_movements '
        "WHERE source_type = 'pos_invoice' AND source_id = ? "
        "AND source_line_id = ? AND product_id = ? AND warehouse_id = ? "
        "AND movement_type = 'purchase' AND quantity_scale = ? "
        'AND quantity_scaled > 0',
        [
          movement.reversesSourceId,
          originalLineId,
          movement.productId,
          movement.warehouseId,
          movement.quantity.scale,
        ],
      );
      final sourceLotMovements = await executor.rawQuery(
        'SELECT COALESCE(SUM(quantity_scaled), 0) AS quantity_scaled '
        'FROM pos_stock_movements '
        "WHERE source_type = 'pos_invoice' AND source_id = ? "
        "AND source_line_id = ? AND product_id = ? AND warehouse_id = ? "
        "AND movement_type = 'purchase' AND quantity_scale = ? "
        'AND quantity_scaled > 0 AND lot_id IS ?',
        [
          movement.reversesSourceId,
          originalLineId,
          movement.productId,
          movement.warehouseId,
          movement.quantity.scale,
          movement.lotId,
        ],
      );
      final priorReturns = await executor.rawQuery(
        'SELECT COALESCE(SUM(ABS(m.quantity_scaled)), 0) AS quantity_scaled '
        'FROM pos_stock_movements m '
        'JOIN pos_invoice_lines rl ON rl.id = m.source_line_id '
        'JOIN pos_invoices ri ON ri.id = rl.invoice_id '
        "WHERE ri.document_type = 'purchase_return' "
        'AND ri.source_invoice_id = ? AND rl.source_line_id = ? '
        "AND m.movement_type = 'purchase_return' "
        'AND m.quantity_scaled < 0 AND m.lot_id IS ?',
        [movement.reversesSourceId, originalLineId, movement.lotId],
      );
      final purchased = _asInt(sourceMovements.single['quantity_scaled']);
      final purchasedFromLot =
          _asInt(sourceLotMovements.single['quantity_scaled']);
      final alreadyReturned = _asInt(priorReturns.single['quantity_scaled']);
      final sourceQuantity = _asInt(originalLines.single['quantity_scaled']);
      if (purchased != sourceQuantity ||
          purchasedFromLot == 0 ||
          alreadyReturned + movement.quantity.scaledUnits > purchasedFromLot) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posStockInvalidMovement,
            code: 'pos_purchase_return_stock_exceeds_source',
          ),
        );
      }
      // The caller already inserted the immutable return invoice and line in
      // this transaction. Only this branch may admit a reversal movement.
      return await appendInTransaction(
        executor,
        movement,
        allowStockDisposal: true,
      );
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posStockAppendFailed),
      );
    } catch (_) {
      return _invalidPurchaseReturnStock();
    }
  }

  FailureResult<void> _invalidPurchaseReturnStock() => FailureResult(
        ValidationFailure(
          messageAr: AppStrings.posStockInvalidMovement,
          code: 'pos_purchase_return_stock_link_invalid',
        ),
      );

  /// Verifies the database's lot projection after all other atomic writes.
  Future<Result<void>> verifyLotProjectionInTransaction(
    DatabaseExecutor executor,
    String lotId,
  ) async {
    try {
      final lotRows = await executor.query(
        'pos_stock_lots',
        columns: ['remaining_quantity_scaled'],
        where: 'id = ?',
        whereArgs: [lotId],
        limit: 1,
      );
      if (lotRows.isEmpty) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockLotProjectionMismatch),
        );
      }
      final movementRows = await executor.rawQuery(
        '''
        SELECT COALESCE(SUM(quantity_scaled), 0) AS quantity_scaled
        FROM pos_stock_movements WHERE lot_id = ?
        ''',
        [lotId],
      );
      if (_asInt(lotRows.first['remaining_quantity_scaled']) !=
          _asInt(movementRows.first['quantity_scaled'])) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockLotProjectionMismatch),
        );
      }
      return const Success(null);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posStockReadFailed),
      );
    } catch (_) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockLotProjectionMismatch),
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
    var balance = emptyPosStockBalance(
      currency: currency,
      quantityScale: scale,
    );
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
      columns: ['currency_code', 'quantity_scale', 'expiry_tracking'],
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
      expiryTracking: _asInt(rows.first['expiry_tracking']) == 1,
    );
  }

  Future<String?> _validateMovementLot(
    DatabaseExecutor executor,
    PosStockMovement movement,
    _ProductStockContext context,
  ) async {
    final lotId = movement.lotId;
    if (lotId == null || lotId.isEmpty) {
      return context.expiryTracking ? AppStrings.posStockLotRequired : null;
    }
    final rows = await executor.query(
      'pos_stock_lots',
      where: 'id = ?',
      whereArgs: [lotId],
      limit: 1,
    );
    if (rows.isEmpty) return AppStrings.posStockLotProjectionMismatch;
    final lot = await _mapLotRow(rows.first);
    if (lot == null ||
        lot.productId != movement.productId ||
        lot.warehouseId != movement.warehouseId ||
        lot.receivedQuantity.scale != movement.quantity.scale ||
        lot.unitCost.currency != movement.unitCost.currency ||
        (context.expiryTracking && lot.expiryDate == null)) {
      return AppStrings.posStockLotProjectionMismatch;
    }
    final quantityRows = await executor.rawQuery(
      '''
      SELECT COALESCE(SUM(quantity_scaled), 0) AS quantity_scaled
      FROM pos_stock_movements WHERE lot_id = ?
      ''',
      [lotId],
    );
    if (_asInt(quantityRows.first['quantity_scaled']) !=
        lot.remainingQuantity.scaledUnits) {
      return AppStrings.posStockLotProjectionMismatch;
    }
    final nextRemaining =
        lot.remainingQuantity.scaledUnits + movement.signedQuantityScaled;
    if (nextRemaining < 0 || nextRemaining > lot.receivedQuantity.scaledUnits) {
      return AppStrings.posStockLotsInsufficient;
    }
    if (movement.type == PosStockMovementType.sale) {
      final expiry = lot.expiryDate;
      final today = PosDate.todayLocal();
      final movementDate = PosDate.fromDateTime(movement.occurredAt.toLocal());
      final eligibilityDate =
          today.isBefore(movementDate) ? movementDate : today;
      // Recheck both the current local date and the invoice date inside the
      // posting transaction so a stale FEFO read or future-dated payload cannot
      // consume a lot that is expired when the movement takes effect.
      if (expiry == null || expiry.isBefore(eligibilityDate)) {
        return AppStrings.posStockLotsInsufficient;
      }
    }
    return null;
  }

  Future<PosStockLot?> _mapLotRow(Map<String, Object?> row) async {
    final currency = await _currency(row['currency_code']);
    if (currency.isFailure) return null;
    final expiryRaw = row['expiry_date'] as String?;
    final expiry = expiryRaw == null ? null : PosDate.parse(expiryRaw);
    final scale = _asInt(row['quantity_scale']);
    return PosStockLot.restore(
      id: row['id']! as String,
      productId: row['product_id']! as String,
      warehouseId: row['warehouse_id']! as String,
      supplierLotNumber: row['lot_number'] as String?,
      expiryDate: expiry,
      receivedQuantity: PosQuantity.fromScaled(
        _asInt(row['received_quantity_scaled']),
        scale: scale,
      ),
      remainingQuantity: PosQuantity.fromScaled(
        _asInt(row['remaining_quantity_scaled']),
        scale: scale,
      ),
      unitCost: Money.fromMinorUnits(
        _asInt(row['unit_cost_minor']),
        currency.valueOrNull!,
      ),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }

  static Map<String, Object?> _lotToRow(PosStockLot lot) => {
        'id': lot.id,
        'product_id': lot.productId,
        'warehouse_id': lot.warehouseId,
        'lot_number': lot.supplierLotNumber,
        'expiry_date': lot.expiryDate?.isoDate,
        'received_quantity_scaled': lot.receivedQuantity.scaledUnits,
        'remaining_quantity_scaled': 0,
        'quantity_scale': lot.receivedQuantity.scale,
        'unit_cost_minor': lot.unitCost.minorUnits,
        'currency_code': lot.unitCost.currency.code,
        'created_at': lot.createdAt.toUtc().toIso8601String(),
        'updated_at': lot.updatedAt.toUtc().toIso8601String(),
      };

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
          disposalReason: parsePosStockDisposalReason(
            row['disposal_reason_code'] as String?,
          ),
          reasonDetail: row['reason_detail'] as String?,
          voucherId: row['voucher_id'] as String?,
          reversesSourceId: row['reverses_source_id'] as String?,
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
        'disposal_reason_code': movement.disposalReason?.code,
        'reason_detail': movement.reasonDetail,
        'voucher_id': movement.voucherId,
        'reverses_source_id': movement.reversesSourceId,
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

  FailureResult<PosStockBalance> _productNotFoundBalance() =>
      _productNotFound();

  FailureResult<List<PosStockLot>> _productNotFoundLots() => FailureResult(
        ValidationFailure(messageAr: AppStrings.posProductNotFound),
      );

  FailureResult<PosStockBalance> _invalidDisposalBalance() => FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockDisposalInvalid),
      );

  FailureResult<void> _productNotFoundVoid() => FailureResult(
        ValidationFailure(messageAr: AppStrings.posProductNotFound),
      );

  FailureResult<PosStockBalance> _readFailure() =>
      FailureResult(DatabaseFailure(messageAr: AppStrings.posStockReadFailed));

  FailureResult<PosStockMovement?> _readNullableFailure() =>
      FailureResult(DatabaseFailure(messageAr: AppStrings.posStockReadFailed));

  FailureResult<List<PosStockMovement>> _invalidMovementListFailure() =>
      FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockInvalidMovement),
      );

  FailureResult<List<PosStockMovement>> _readMovementListFailure() =>
      FailureResult(DatabaseFailure(messageAr: AppStrings.posStockReadFailed));
}

final class _ProductStockContext {
  const _ProductStockContext({
    required this.currency,
    required this.scale,
    required this.expiryTracking,
  });

  final CurrencyCode currency;
  final int scale;
  final bool expiryTracking;
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
