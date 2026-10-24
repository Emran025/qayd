import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/mappers/ledger_entry_mapper.dart';
import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/data/mappers/voucher_mapper.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/pos_sale_posting_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Data-only atomic coordinator for a complete posted POS sale.
final class SqlitePosSalePostingRepository implements PosSalePostingRepository {
  SqlitePosSalePostingRepository(
    this._transactionRunner,
    this._stockRepository,
    this._voucherRepository,
  );

  final DatabaseTransactionRunner _transactionRunner;
  final SqlitePosStockMovementRepository _stockRepository;
  final SqliteVoucherRepository _voucherRepository;

  @override
  Future<Result<void>> saveAtomically(PosSalePosting posting) async {
    try {
      await _transactionRunner.run<void>((txn) async {
        final state = await _inspect(txn, posting);
        if (state == _SaleState.exact) return;
        if (state != _SaleState.absent) {
          throw _AtomicSaleFailure(
            ValidationFailure(messageAr: AppStrings.posAccountingPartialState),
          );
        }

        for (final movement in posting.movements) {
          final result = await _stockRepository.appendInTransaction(
            txn,
            movement,
          );
          if (result.isFailure) {
            throw _AtomicSaleFailure(result.failureOrNull!);
          }
        }

        await txn.insert(
            'pos_invoices', PosInvoiceMapper.toRow(posting.invoice));
        for (final line in posting.invoice.lines) {
          await txn.insert(
              'pos_invoice_lines', PosInvoiceMapper.lineToRow(line));
        }
        for (final payment in posting.payments) {
          await txn.insert(
            'pos_payments',
            PosInvoiceMapper.paymentToRow(
              payment,
              posting.invoice.createdAt,
            ),
          );
        }
        for (final accountingPosting in posting.postings) {
          final result =
              await _voucherRepository.saveWithLedgerEntriesInTransaction(
            txn,
            voucher: accountingPosting.voucher,
            ledgerEntries: accountingPosting.entries,
          );
          if (result.isFailure) {
            throw _AtomicSaleFailure(result.failureOrNull!);
          }
        }
      });
      return const Success(null);
    } on _AtomicSaleFailure catch (error) {
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

  Future<_SaleState> _inspect(
    DatabaseExecutor executor,
    PosSalePosting posting,
  ) async {
    final invoiceRows = await executor.query(
      'pos_invoices',
      where: 'idempotency_key = ?',
      whereArgs: [posting.invoice.idempotencyKey],
      limit: 1,
    );
    final invoiceById = await executor.query(
      'pos_invoices',
      where: 'id = ?',
      whereArgs: [posting.invoice.id],
      limit: 1,
    );
    final invoiceExists = invoiceRows.isNotEmpty || invoiceById.isNotEmpty;
    final invoiceMatches = invoiceRows.length == 1 &&
        invoiceById.length == 1 &&
        invoiceRows.first['id'] == posting.invoice.id &&
        _mapMatches(
          invoiceRows.first,
          PosInvoiceMapper.toRow(posting.invoice),
          ignored: const {'created_at', 'updated_at'},
        );
    if (invoiceExists && !invoiceMatches) return _SaleState.conflict;

    final lines = await executor.query(
      'pos_invoice_lines',
      where: 'invoice_id = ?',
      whereArgs: [posting.invoice.id],
      orderBy: 'id ASC',
    );
    final expectedLines = posting.invoice.lines
        .map(PosInvoiceMapper.lineToRow)
        .toList()
      ..sort(_compareIdMaps);
    final linesMatch = lines.length == expectedLines.length &&
        _rowsMatch(lines, expectedLines, ignored: const {'created_at'});

    final payments = await executor.query(
      'pos_payments',
      where: 'invoice_id = ?',
      whereArgs: [posting.invoice.id],
      orderBy: 'id ASC',
    );
    final expectedPayments = posting.payments
        .map((payment) => PosInvoiceMapper.paymentToRow(
              payment,
              posting.invoice.createdAt,
            ))
        .toList()
      ..sort(_compareIdMaps);
    final paymentsMatch = payments.length == expectedPayments.length &&
        _rowsMatch(payments, expectedPayments, ignored: const {'created_at'});

    var movementState = _SaleState.exact;
    for (final movement in posting.movements) {
      final result = await _stockRepository.getByIdempotencyKeyInTransaction(
        executor,
        movement.idempotencyKey,
      );
      if (result.isFailure) throw _AtomicSaleFailure(result.failureOrNull!);
      final existing = result.valueOrNull;
      if (existing == null) {
        movementState = _SaleState.absent;
      } else if (!_sameMovement(existing, movement)) {
        return _SaleState.conflict;
      }
    }

    final sourceVoucherRows = await executor.query(
      'vouchers',
      columns: ['id'],
      where: 'reference_number = ?',
      whereArgs: [posting.invoice.id],
    );
    final expectedVoucherIds = posting.postings
        .map((accountingPosting) => accountingPosting.voucher.id.value)
        .toSet();
    final actualVoucherIds = sourceVoucherRows
        .map((row) => row['id'] as String)
        .toSet();
    if (sourceVoucherRows.isNotEmpty &&
        (actualVoucherIds.length != expectedVoucherIds.length ||
            !actualVoucherIds.containsAll(expectedVoucherIds))) {
      return _SaleState.conflict;
    }

    var postingState = _SaleState.exact;
    for (final accountingPosting in posting.postings) {
      final voucherRows = await executor.query(
        'vouchers',
        where: 'id = ?',
        whereArgs: [accountingPosting.voucher.id.value],
        limit: 1,
      );
      final ledgerRows = await executor.query(
        'ledger_entries',
        where: 'voucher_id = ?',
        whereArgs: [accountingPosting.voucher.id.value],
        orderBy: 'id ASC',
      );
      final voucherExists = voucherRows.isNotEmpty || ledgerRows.isNotEmpty;
      if (!voucherExists) {
        postingState = _SaleState.absent;
        continue;
      }
      final expectedEntries = accountingPosting.entries
          .map(LedgerEntryMapper.toModel)
          .map((model) => model.toMap())
          .toList()
        ..sort(_compareIdMaps);
      final actualEntries = [...ledgerRows]..sort(_compareIdMaps);
      if (voucherRows.length != 1 ||
          actualEntries.length != expectedEntries.length ||
          !_mapMatches(
            voucherRows.first,
            VoucherMapper.toModel(accountingPosting.voucher).toMap(),
            ignored: const {'created_at'},
          ) ||
          !_rowsMatch(
            actualEntries,
            expectedEntries,
            ignored: const {'created_at'},
          )) {
        return _SaleState.conflict;
      }
    }

    final allExact = invoiceMatches &&
        linesMatch &&
        paymentsMatch &&
        movementState == _SaleState.exact &&
        postingState == _SaleState.exact;
    if (allExact) return _SaleState.exact;
    if (!invoiceExists &&
        lines.isEmpty &&
        payments.isEmpty &&
        movementState == _SaleState.absent &&
        postingState == _SaleState.absent) {
      return _SaleState.absent;
    }
    return _SaleState.partial;
  }

  static bool _rowsMatch(
    List<Map<String, Object?>> actual,
    List<Map<String, Object?>> expected, {
    required Set<String> ignored,
  }) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (!_mapMatches(actual[index], expected[index], ignored: ignored)) {
        return false;
      }
    }
    return true;
  }

  static bool _mapMatches(
    Map<String, Object?> actual,
    Map<String, Object?> expected, {
    required Set<String> ignored,
  }) {
    for (final entry in expected.entries) {
      if (ignored.contains(entry.key)) continue;
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
}

enum _SaleState { absent, exact, partial, conflict }

final class _AtomicSaleFailure implements Exception {
  const _AtomicSaleFailure(this.failure);

  final Failure failure;
}
