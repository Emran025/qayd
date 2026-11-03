import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/mappers/ledger_entry_mapper.dart';
import 'package:qayd/data/mappers/voucher_mapper.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_stock_lot.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/pos_accounting_posting_repository.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/entry_side.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Atomic SQLite adapter for POS stock and official voucher/ledger effects.
final class SqlitePosAccountingPostingRepository
    implements PosAccountingPostingRepository {
  SqlitePosAccountingPostingRepository(
    this._transactionRunner,
    this._stockRepository,
    this._voucherRepository,
  );

  final DatabaseTransactionRunner _transactionRunner;
  final SqlitePosStockMovementRepository _stockRepository;
  final SqliteVoucherRepository _voucherRepository;

  @override
  Future<Result<void>> saveOpeningBalance({
    required PosStockMovement movement,
    List<PosStockMovement> additionalMovements = const [],
    List<PosStockLot> lots = const [],
    required PosAccountingPosting posting,
  }) async {
    final movements = [movement, ...additionalMovements];
    if (movements.any(
      (item) => !_sameUtcCalendarDate(posting.voucher.date, item.occurredAt),
    )) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posAccountingDateMismatch),
      );
    }
    if (movements.any(
          (item) =>
              item.sourceId?.trim() != posting.sourceId.trim() ||
              item.type != PosStockMovementType.opening ||
              item.sourceType != 'opening_balance' ||
              item.direction != PosStockMovementDirection.inbound,
        ) ||
        posting.voucher.referenceNumber?.trim() != posting.sourceId.trim()) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posAccountingSourceMismatch),
      );
    }
    try {
      await _transactionRunner.run<void>((txn) async {
        var existingMovementCount = 0;
        for (final item in movements) {
          final stockResult = await _stockRepository
              .getByIdempotencyKeyInTransaction(txn, item.idempotencyKey);
          if (stockResult.isFailure) {
            throw _AtomicPostingFailure(stockResult.failureOrNull!);
          }
          final existing = stockResult.valueOrNull;
          if (existing == null) continue;
          if (!_sameMovement(existing, item)) {
            throw _AtomicPostingFailure(
              ValidationFailure(
                messageAr: AppStrings.posAccountingPartialState,
              ),
            );
          }
          existingMovementCount++;
        }
        final referencedLotIds =
            movements.map((item) => item.lotId).whereType<String>().toSet();
        final expectedLotIds = lots.map((lot) => lot.id).toSet();
        if (referencedLotIds.length !=
                movements.where((item) => item.lotId != null).length ||
            referencedLotIds.length != expectedLotIds.length ||
            !referencedLotIds.containsAll(expectedLotIds)) {
          throw _AtomicPostingFailure(
            ValidationFailure(
              messageAr: AppStrings.posAccountingSourceMismatch,
            ),
          );
        }
        var existingLotCount = 0;
        for (final lot in lots) {
          final rows = await txn.query(
            'pos_stock_lots',
            where: 'id = ?',
            whereArgs: [lot.id],
            limit: 1,
          );
          if (rows.isEmpty) continue;
          existingLotCount++;
          final row = rows.first;
          if (row['product_id'] != lot.productId ||
              row['warehouse_id'] != lot.warehouseId ||
              row['lot_number'] != lot.supplierLotNumber ||
              row['expiry_date'] != lot.expiryDate?.isoDate ||
              (row['received_quantity_scaled'] as num).toInt() !=
                  lot.receivedQuantity.scaledUnits ||
              (row['quantity_scale'] as num).toInt() !=
                  lot.receivedQuantity.scale ||
              (row['unit_cost_minor'] as num).toInt() !=
                  lot.unitCost.minorUnits ||
              row['currency_code'] != lot.unitCost.currency.code) {
            throw _AtomicPostingFailure(
              ValidationFailure(
                messageAr: AppStrings.posAccountingPartialState,
              ),
            );
          }
        }
        final postingState = await _inspectPosting(txn, posting);
        if (existingMovementCount == movements.length &&
            existingLotCount == lots.length &&
            postingState == _PostingState.exact) {
          return;
        }
        if (existingMovementCount > 0 ||
            existingLotCount > 0 ||
            postingState != _PostingState.absent) {
          throw _AtomicPostingFailure(
            ValidationFailure(messageAr: _failureMessage(postingState)),
          );
        }

        final duplicateSource = await txn.query(
          'vouchers',
          columns: ['id'],
          where: 'reference_number = ?',
          whereArgs: [posting.sourceId],
          limit: 1,
        );
        if (duplicateSource.isNotEmpty) {
          throw _AtomicPostingFailure(
            ValidationFailure(
              messageAr: AppStrings.posAccountingDuplicateSource,
            ),
          );
        }
        for (final lot in lots) {
          final lotResult = await _stockRepository.createLotInTransaction(
            txn,
            lot,
          );
          if (lotResult.isFailure) {
            throw _AtomicPostingFailure(lotResult.failureOrNull!);
          }
        }
        for (final item in movements) {
          final appendResult = await _stockRepository.appendInTransaction(
            txn,
            item,
          );
          if (appendResult.isFailure) {
            throw _AtomicPostingFailure(appendResult.failureOrNull!);
          }
        }
        final voucherResult =
            await _voucherRepository.saveWithLedgerEntriesInTransaction(
          txn,
          voucher: posting.voucher,
          ledgerEntries: posting.entries,
        );
        if (voucherResult.isFailure) {
          throw _AtomicPostingFailure(voucherResult.failureOrNull!);
        }
      });
      return const Success(null);
    } on _AtomicPostingFailure catch (error) {
      return FailureResult(error.failure);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posAccountingTransactionFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posAccountingTransactionFailed),
      );
    }
  }

  @override
  Future<Result<void>> saveStockAdjustmentAtomically({
    required PosStockMovement movement,
    required PosAccountingPosting posting,
  }) async {
    if (movement.type != PosStockMovementType.adjustment ||
        movement.sourceType != 'manual_adjustment') {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posAccountingSourceMismatch),
      );
    }
    if (!_sameUtcCalendarDate(posting.voucher.date, movement.occurredAt)) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posAccountingDateMismatch),
      );
    }
    if (movement.sourceId?.trim() != posting.sourceId.trim() ||
        posting.voucher.referenceNumber?.trim() != posting.sourceId.trim()) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posAccountingSourceMismatch),
      );
    }
    try {
      await _transactionRunner.run<void>((txn) async {
        final stockResult = await _stockRepository
            .getByIdempotencyKeyInTransaction(txn, movement.idempotencyKey);
        if (stockResult.isFailure) {
          throw _AtomicPostingFailure(stockResult.failureOrNull!);
        }
        final existingMovement = stockResult.valueOrNull;
        final postingState = await _inspectPosting(txn, posting);

        if (existingMovement != null &&
            postingState == _PostingState.exact &&
            _sameMovement(existingMovement, movement)) {
          return;
        }
        if (existingMovement != null || postingState != _PostingState.absent) {
          throw _AtomicPostingFailure(
            ValidationFailure(messageAr: _failureMessage(postingState)),
          );
        }

        final duplicateSource = await txn.query(
          'vouchers',
          columns: ['id'],
          where: 'reference_number = ?',
          whereArgs: [posting.sourceId],
          limit: 1,
        );
        if (duplicateSource.isNotEmpty) {
          throw _AtomicPostingFailure(
            ValidationFailure(
              messageAr: AppStrings.posAccountingDuplicateSource,
            ),
          );
        }

        final appendResult = await _stockRepository.appendInTransaction(
          txn,
          movement,
        );
        if (appendResult.isFailure) {
          throw _AtomicPostingFailure(appendResult.failureOrNull!);
        }
        final voucherResult =
            await _voucherRepository.saveWithLedgerEntriesInTransaction(
          txn,
          voucher: posting.voucher,
          ledgerEntries: posting.entries,
        );
        if (voucherResult.isFailure) {
          throw _AtomicPostingFailure(voucherResult.failureOrNull!);
        }
      });
      return const Success(null);
    } on _AtomicPostingFailure catch (error) {
      return FailureResult(error.failure);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posAccountingTransactionFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posAccountingTransactionFailed),
      );
    }
  }

  @override
  Future<Result<void>> saveStockDisposalAtomically({
    required PosStockMovement movement,
    required PosAccountingPosting posting,
  }) async {
    final isReversal = movement.reversesSourceId != null;
    final expectedSourceType =
        isReversal ? 'stock_disposal_reversal' : 'stock_disposal';
    if (movement.sourceType != expectedSourceType ||
        movement.voucherId != posting.voucher.id.value ||
        !_sameUtcCalendarDate(posting.voucher.date, movement.occurredAt) ||
        movement.sourceId?.trim() != posting.sourceId.trim() ||
        posting.voucher.referenceNumber?.trim() != posting.sourceId.trim() ||
        !_hasExpectedDisposalPosting(movement, posting)) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posAccountingSourceMismatch),
      );
    }
    try {
      await _transactionRunner.run<void>((txn) async {
        final stockResult = await _stockRepository
            .getByIdempotencyKeyInTransaction(txn, movement.idempotencyKey);
        if (stockResult.isFailure) {
          throw _AtomicPostingFailure(stockResult.failureOrNull!);
        }
        final existingMovement = stockResult.valueOrNull;
        final postingState = await _inspectPosting(txn, posting);
        if (existingMovement != null &&
            postingState == _PostingState.exact &&
            _sameMovement(existingMovement, movement)) {
          return;
        }
        if (existingMovement != null || postingState != _PostingState.absent) {
          throw _AtomicPostingFailure(
            ValidationFailure(messageAr: _failureMessage(postingState)),
          );
        }

        final duplicateSource = await txn.query(
          'vouchers',
          columns: ['id'],
          where: 'reference_number = ?',
          whereArgs: [posting.sourceId],
          limit: 1,
        );
        if (duplicateSource.isNotEmpty) {
          throw _AtomicPostingFailure(
            ValidationFailure(
              messageAr: AppStrings.posAccountingDuplicateSource,
            ),
          );
        }

        if (isReversal) {
          await _validateDisposalReversal(txn, movement, posting);
        } else {
          final validation = await _stockRepository
              .validateStockDisposalInTransaction(txn, movement);
          if (validation.isFailure) {
            throw _AtomicPostingFailure(validation.failureOrNull!);
          }
          final amount = PosMoneyMath.multiply(
            movement.quantity,
            validation.valueOrNull!.averageUnitCost,
          );
          if (amount.minorUnits <= 0 || amount != posting.voucher.amount) {
            throw _AtomicPostingFailure(
              ValidationFailure(messageAr: AppStrings.posStockDisposalCostChanged),
            );
          }
        }

        final appendResult = await _stockRepository.appendInTransaction(
          txn,
          movement,
          allowStockDisposal: true,
        );
        if (appendResult.isFailure) {
          throw _AtomicPostingFailure(appendResult.failureOrNull!);
        }
        final voucherResult =
            await _voucherRepository.saveWithLedgerEntriesInTransaction(
          txn,
          voucher: posting.voucher,
          ledgerEntries: posting.entries,
        );
        if (voucherResult.isFailure) {
          throw _AtomicPostingFailure(voucherResult.failureOrNull!);
        }
        final lotId = movement.lotId;
        if (lotId != null) {
          final projection = await _stockRepository
              .verifyLotProjectionInTransaction(txn, lotId);
          if (projection.isFailure) {
            throw _AtomicPostingFailure(projection.failureOrNull!);
          }
        }
      });
      return const Success(null);
    } on _AtomicPostingFailure catch (error) {
      return FailureResult(error.failure);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posAccountingTransactionFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posAccountingTransactionFailed),
      );
    }
  }

  Future<_PostingState> _inspectPosting(
    DatabaseExecutor executor,
    PosAccountingPosting posting,
  ) async {
    final voucherRows = await executor.query(
      'vouchers',
      where: 'id = ?',
      whereArgs: [posting.voucher.id.value],
      limit: 1,
    );
    final ledgerRows = await executor.query(
      'ledger_entries',
      where: 'voucher_id = ?',
      whereArgs: [posting.voucher.id.value],
      orderBy: 'id ASC',
    );
    if (voucherRows.isEmpty && ledgerRows.isEmpty) {
      return _PostingState.absent;
    }
    if (voucherRows.length != 1 ||
        ledgerRows.length != posting.entries.length ||
        !_mapMatches(
          voucherRows.firstOrNull,
          VoucherMapper.toModel(posting.voucher).toMap(),
        )) {
      return _PostingState.conflict;
    }

    final expectedEntries = posting.entries
        .map((entry) => LedgerEntryMapper.toModel(entry).toMap())
        .toList()
      ..sort(_compareIdMaps);
    final actualEntries = [...ledgerRows]..sort(_compareIdMaps);
    for (var index = 0; index < expectedEntries.length; index++) {
      if (!_mapMatches(actualEntries[index], expectedEntries[index])) {
        return _PostingState.conflict;
      }
    }
    return _PostingState.exact;
  }

  static bool _mapMatches(
    Map<String, Object?>? actual,
    Map<String, Object?> expected,
  ) {
    if (actual == null) return false;
    for (final entry in expected.entries) {
      // created_at is audit metadata generated at first persistence. It is not
      // part of the business idempotency fingerprint, just like stock rows.
      if (entry.key == 'created_at') continue;
      if (actual[entry.key] != entry.value) return false;
    }
    return true;
  }

  static int _compareIdMaps(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    return (left['id'] as String).compareTo(right['id'] as String);
  }

  static bool _sameMovement(
    PosStockMovement existing,
    PosStockMovement expected,
  ) {
    return existing.id == expected.id &&
        existing.productId == expected.productId &&
        existing.warehouseId == expected.warehouseId &&
        existing.type == expected.type &&
        existing.direction == expected.direction &&
        existing.quantity == expected.quantity &&
        existing.unitCost == expected.unitCost &&
        existing.sourceType == expected.sourceType &&
        existing.sourceId == expected.sourceId &&
        existing.sourceLineId == expected.sourceLineId &&
        existing.lotId == expected.lotId &&
        existing.disposalReason == expected.disposalReason &&
        existing.reasonDetail == expected.reasonDetail &&
        existing.voucherId == expected.voucherId &&
        existing.reversesSourceId == expected.reversesSourceId &&
        existing.occurredAt.toUtc() == expected.occurredAt.toUtc() &&
        existing.idempotencyKey == expected.idempotencyKey;
  }

  static bool _hasExpectedDisposalPosting(
    PosStockMovement movement,
    PosAccountingPosting posting,
  ) {
    if (posting.entries.length != 2) return false;
    final debitEntries = posting.entries
        .where((entry) => entry.side == EntrySide.debit)
        .toList(growable: false);
    final creditEntries = posting.entries
        .where((entry) => entry.side == EntrySide.credit)
        .toList(growable: false);
    if (debitEntries.length != 1 || creditEntries.length != 1) return false;
    final debit = debitEntries.single;
    final credit = creditEntries.single;
    final voucher = posting.voucher;
    if (debit.amount != voucher.amount ||
        credit.amount != voucher.amount ||
        debit.currency != voucher.currency ||
        credit.currency != voucher.currency) {
      return false;
    }
    if (movement.reversesSourceId != null) {
      return movement.disposalReason == null &&
          movement.direction == PosStockMovementDirection.inbound &&
          movement.type == PosStockMovementType.adjustment &&
          movement.sourceType == 'stock_disposal_reversal' &&
          voucher.type == VoucherType.receipt &&
          debit.accountId == voucher.affectedAccountId &&
          credit.accountId == voucher.counterpartyId;
    }
    return movement.disposalReason != null &&
        movement.direction == PosStockMovementDirection.outbound &&
        movement.sourceType == 'stock_disposal' &&
        voucher.type == VoucherType.payment &&
        debit.accountId == voucher.counterpartyId &&
        credit.accountId == voucher.affectedAccountId;
  }

  Future<void> _validateDisposalReversal(
    DatabaseExecutor txn,
    PosStockMovement movement,
    PosAccountingPosting posting,
  ) async {
    final sourceId = movement.reversesSourceId?.trim();
    if (sourceId == null || sourceId.isEmpty) {
      throw _disposalReversalFailure();
    }
    final originals = await txn.query(
      'pos_stock_movements',
      where: "source_type = 'stock_disposal' AND source_id = ?",
      whereArgs: [sourceId],
      limit: 2,
    );
    if (originals.length != 1) throw _disposalReversalFailure();
    final original = originals.single;
    final originalQuantity = (original['quantity_scaled'] as num).toInt();
    if (originalQuantity >= 0 ||
        original['disposal_reason_code'] == null ||
        movement.sourceId == sourceId ||
        movement.sourceType != 'stock_disposal_reversal' ||
        movement.direction != PosStockMovementDirection.inbound ||
        movement.type != PosStockMovementType.adjustment ||
        movement.productId != original['product_id'] ||
        movement.warehouseId != original['warehouse_id'] ||
        movement.lotId != original['lot_id'] ||
        movement.quantity.scaledUnits != -originalQuantity ||
        movement.quantity.scale != (original['quantity_scale'] as num).toInt() ||
        movement.unitCost.minorUnits !=
            (original['unit_cost_minor'] as num).toInt() ||
        movement.unitCost.currency.code != original['currency_code']) {
      throw _disposalReversalFailure();
    }
    final existingReversals = await txn.query(
      'pos_stock_movements',
      columns: ['id'],
      where: 'reverses_source_id = ?',
      whereArgs: [sourceId],
      limit: 1,
    );
    if (existingReversals.isNotEmpty) throw _disposalReversalFailure();

    final originalVoucherId = original['voucher_id'] as String?;
    if (originalVoucherId == null || originalVoucherId.isEmpty) {
      throw _disposalReversalFailure();
    }
    final voucherRows = await txn.query(
      'vouchers',
      columns: [
        'amount_minor',
        'counterparty_id',
        'affected_account_id',
        'type',
      ],
      where: 'id = ?',
      whereArgs: [originalVoucherId],
      limit: 1,
    );
    if (voucherRows.isEmpty) throw _disposalReversalFailure();
    final originalVoucher = voucherRows.single;
    final amount = PosMoneyMath.multiply(movement.quantity, movement.unitCost);
    if (amount.minorUnits !=
            (originalVoucher['amount_minor'] as num).toInt() ||
        posting.voucher.amount != amount ||
        posting.voucher.counterpartyId.value !=
            originalVoucher['counterparty_id'] ||
        posting.voucher.affectedAccountId.value !=
            originalVoucher['affected_account_id'] ||
        originalVoucher['type'] != 'payment') {
      throw _disposalReversalFailure();
    }
  }

  _AtomicPostingFailure _disposalReversalFailure() => _AtomicPostingFailure(
        ValidationFailure(messageAr: AppStrings.posStockDisposalInvalid),
      );

  static bool _sameUtcCalendarDate(DateTime left, DateTime right) {
    final a = left.toUtc();
    final b = right.toUtc();
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _failureMessage(_PostingState state) {
    if (state == _PostingState.conflict) {
      return AppStrings.posAccountingDuplicateSource;
    }
    return AppStrings.posAccountingPartialState;
  }
}

enum _PostingState { absent, exact, conflict }

final class _AtomicPostingFailure implements Exception {
  const _AtomicPostingFailure(this.failure);

  final Failure failure;
}
