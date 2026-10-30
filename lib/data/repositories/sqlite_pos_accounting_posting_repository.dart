import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/mappers/ledger_entry_mapper.dart';
import 'package:qayd/data/mappers/voucher_mapper.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/pos_accounting_posting_repository.dart';
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
    required PosAccountingPosting posting,
  }) async {
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
        final stockResult =
            await _stockRepository.getByIdempotencyKeyInTransaction(
          txn,
          movement.idempotencyKey,
        );
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
        final stockResult =
            await _stockRepository.getByIdempotencyKeyInTransaction(
          txn,
          movement.idempotencyKey,
        );
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
        final voucherResult = await _voucherRepository
            .saveWithLedgerEntriesInTransaction(
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
        existing.occurredAt.toUtc() == expected.occurredAt.toUtc() &&
        existing.idempotencyKey == expected.idempotencyKey;
  }

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
