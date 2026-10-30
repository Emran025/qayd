import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/mappers/ledger_entry_mapper.dart';
import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/data/mappers/voucher_mapper.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/pos_sales_return_posting_repository.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// ACID coordinator for sales returns and full invoice reversals.
final class SqlitePosSalesReturnPostingRepository
    implements PosSalesReturnPostingRepository {
  SqlitePosSalesReturnPostingRepository(
    this._runner,
    this._stock,
    this._vouchers,
  );

  final DatabaseTransactionRunner _runner;
  final SqlitePosStockMovementRepository _stock;
  final SqliteVoucherRepository _vouchers;

  @override
  Future<Result<void>> saveAtomically(PosSalesReturnPosting posting) async {
    try {
      await _runner.run<void>((txn) async {
        final state = await _inspect(txn, posting);
        if (state == _ReturnState.exact) return;
        if (state != _ReturnState.absent) {
          throw _ReturnWriteFailure(
            ValidationFailure(
              messageAr: AppStrings.posAccountingPartialState,
              code: 'pos_sales_return_partial_or_conflicting_state',
            ),
          );
        }

        final sourceLines = await _validateSourceAndQuantities(txn, posting);
        for (final movement in posting.movements) {
          final result = await _stock.appendInTransaction(txn, movement);
          if (result.isFailure) {
            throw _ReturnWriteFailure(result.failureOrNull!);
          }
        }

        await txn.insert('pos_invoices', PosInvoiceMapper.toRow(posting.invoice));
        for (final line in posting.invoice.lines) {
          await txn.insert('pos_invoice_lines', PosInvoiceMapper.lineToRow(line));
        }
        for (final payment in posting.refundPayments) {
          await txn.insert(
            'pos_payments',
            PosInvoiceMapper.paymentToRow(payment, posting.invoice.createdAt),
          );
        }
        await txn.insert('pos_returns', _returnRelationRow(posting));
        for (final accounting in posting.postings) {
          final result = await _vouchers.saveWithLedgerEntriesInTransaction(
            txn,
            voucher: accounting.voucher,
            ledgerEntries: accounting.entries,
          );
          if (result.isFailure) {
            throw _ReturnWriteFailure(result.failureOrNull!);
          }
        }

        final totals = await _returnedQuantities(txn, posting.sourceInvoiceId);
        _assertNoOverReturn(sourceLines, totals);
        final fullyReturned = sourceLines.every(
          (line) => (totals[line['id'] as String] ?? 0) ==
              _asInt(line['quantity_scaled']),
        );
        final nextStatus = posting.voidSource
            ? 'voided'
            : fullyReturned
                ? 'fullyReturned'
                : 'partiallyReturned';
        final affected = await txn.update(
          'pos_invoices',
          {
            'status': nextStatus,
            'updated_at': posting.invoice.createdAt.toUtc().toIso8601String(),
          },
          where: 'id = ? AND status IN (?, ?)',
          whereArgs: [posting.sourceInvoiceId, 'paid', 'partiallyReturned'],
        );
        if (affected != 1) {
          throw _ReturnWriteFailure(
            ValidationFailure(
              messageAr: 'pos_sales_return_source_changed',
              code: 'pos_sales_return_source_changed',
            ),
          );
        }
      });
      return const Success(null);
    } on _ReturnWriteFailure catch (error) {
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

  Future<_ReturnState> _inspect(
    DatabaseExecutor executor,
    PosSalesReturnPosting posting,
  ) async {
    final invoiceByKey = await executor.query(
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
    final invoiceExists = invoiceByKey.isNotEmpty || invoiceById.isNotEmpty;
    final invoiceMatches = invoiceByKey.length == 1 &&
        invoiceById.length == 1 &&
        invoiceByKey.first['id'] == posting.invoice.id &&
        _mapMatches(
          invoiceByKey.first,
          PosInvoiceMapper.toRow(posting.invoice),
          ignored: const {'created_at', 'updated_at'},
        );
    if (invoiceExists && !invoiceMatches) return _ReturnState.conflict;

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
    final expectedPayments = posting.refundPayments
        .map((payment) => PosInvoiceMapper.paymentToRow(
              payment,
              posting.invoice.createdAt,
            ))
        .toList()
      ..sort(_compareIdMaps);
    final paymentsMatch = payments.length == expectedPayments.length &&
        _rowsMatch(payments, expectedPayments, ignored: const {'created_at'});

    final relationById = await executor.query(
      'pos_returns',
      where: 'id = ?',
      whereArgs: ['${posting.invoice.id}:relation'],
      limit: 1,
    );
    final relationByReturn = await executor.query(
      'pos_returns',
      where: 'return_invoice_id = ?',
      whereArgs: [posting.invoice.id],
      limit: 1,
    );
    final expectedRelation = _returnRelationRow(posting);
    final relationExists = relationById.isNotEmpty || relationByReturn.isNotEmpty;
    final relationMatches = relationById.length == 1 &&
        relationByReturn.length == 1 &&
        _mapMatches(
          relationById.first,
          expectedRelation,
          ignored: const {'created_at'},
        );
    if (relationExists && !relationMatches) return _ReturnState.conflict;

    var movementState = _ReturnState.exact;
    final movementRows = await executor.query(
      'pos_stock_movements',
      columns: ['id'],
      where: 'source_type = ? AND source_id = ?',
      whereArgs: ['pos_invoice', posting.invoice.id],
    );
    final expectedMovementIds = posting.movements.map((item) => item.id).toSet();
    final actualMovementIds = movementRows
        .map((row) => row['id'] as String)
        .toSet();
    if (movementRows.isNotEmpty &&
        (actualMovementIds.length != expectedMovementIds.length ||
            !actualMovementIds.containsAll(expectedMovementIds))) {
      return _ReturnState.conflict;
    }
    for (final movement in posting.movements) {
      final result = await _stock.getByIdempotencyKeyInTransaction(
        executor,
        movement.idempotencyKey,
      );
      if (result.isFailure) {
        throw _ReturnWriteFailure(result.failureOrNull!);
      }
      final existing = result.valueOrNull;
      if (existing == null) {
        movementState = _ReturnState.absent;
      } else if (!_sameMovement(existing, movement)) {
        return _ReturnState.conflict;
      }
    }

    final voucherRows = await executor.query(
      'vouchers',
      columns: ['id'],
      where: 'reference_number = ?',
      whereArgs: [posting.invoice.id],
    );
    final expectedVoucherIds = posting.postings
        .map((item) => item.voucher.id.value)
        .toSet();
    final actualVoucherIds = voucherRows
        .map((row) => row['id'] as String)
        .toSet();
    if (voucherRows.isNotEmpty &&
        (actualVoucherIds.length != expectedVoucherIds.length ||
            !actualVoucherIds.containsAll(expectedVoucherIds))) {
      return _ReturnState.conflict;
    }

    var postingState = _ReturnState.exact;
    for (final accounting in posting.postings) {
      final storedVoucher = await executor.query(
        'vouchers',
        where: 'id = ?',
        whereArgs: [accounting.voucher.id.value],
        limit: 1,
      );
      final ledgerRows = await executor.query(
        'ledger_entries',
        where: 'voucher_id = ?',
        whereArgs: [accounting.voucher.id.value],
        orderBy: 'id ASC',
      );
      final postingExists = storedVoucher.isNotEmpty || ledgerRows.isNotEmpty;
      if (!postingExists) {
        postingState = _ReturnState.absent;
        continue;
      }
      final expectedEntries = accounting.entries
          .map(LedgerEntryMapper.toModel)
          .map((entry) => entry.toMap())
          .toList()
        ..sort(_compareIdMaps);
      final sortedLedger = [...ledgerRows]..sort(_compareIdMaps);
      if (storedVoucher.length != 1 ||
          sortedLedger.length != expectedEntries.length ||
          !_mapMatches(
            storedVoucher.first,
            VoucherMapper.toModel(accounting.voucher).toMap(),
            ignored: const {'created_at'},
          ) ||
          !_rowsMatch(
            sortedLedger,
            expectedEntries,
            ignored: const {'created_at'},
          )) {
        return _ReturnState.conflict;
      }
    }

    final allExact = invoiceMatches &&
        linesMatch &&
        paymentsMatch &&
        relationMatches &&
        movementState == _ReturnState.exact &&
        postingState == _ReturnState.exact;
    if (allExact) {
      final source = await executor.query(
        'pos_invoices',
        where: 'id = ?',
        whereArgs: [posting.sourceInvoiceId],
        limit: 1,
      );
      if (source.length != 1) {
        return _ReturnState.partial;
      }
      final sourceLines = await executor.query(
        'pos_invoice_lines',
        where: 'invoice_id = ?',
        whereArgs: [posting.sourceInvoiceId],
      );
      final quantities = await _returnedQuantities(
        executor,
        posting.sourceInvoiceId,
      );
      try {
        _assertNoOverReturn(sourceLines, quantities);
        final sourceLineIds = sourceLines.map((line) => line['id']).toSet();
        if (quantities.keys.any((lineId) => !sourceLineIds.contains(lineId))) {
          return _ReturnState.conflict;
        }
        final allReturned = sourceLines.isNotEmpty && sourceLines.every((line) {
          final lineId = line['id'] as String;
          return (quantities[lineId] ?? 0) ==
              _asInt(line['quantity_scaled']);
        });
        final storedStatus = source.first['status'];
        if (posting.voidSource) {
          if (!allReturned || storedStatus != 'voided') {
            return _ReturnState.conflict;
          }
        } else {
          if (storedStatus == 'voided') return _ReturnState.conflict;
          final expectedStatus =
              allReturned ? 'fullyReturned' : 'partiallyReturned';
          if (storedStatus != expectedStatus) return _ReturnState.conflict;
        }
      } on _ReturnWriteFailure {
        return _ReturnState.conflict;
      }
      return _ReturnState.exact;
    }

    if (!invoiceExists &&
        lines.isEmpty &&
        payments.isEmpty &&
        !relationExists &&
        movementState == _ReturnState.absent &&
        postingState == _ReturnState.absent) {
      return _ReturnState.absent;
    }
    return _ReturnState.partial;
  }

  Future<List<Map<String, Object?>>> _validateSourceAndQuantities(
    DatabaseExecutor executor,
    PosSalesReturnPosting posting,
  ) async {
    final sources = await executor.query(
      'pos_invoices',
      where: 'id = ?',
      whereArgs: [posting.sourceInvoiceId],
      limit: 1,
    );
    if (sources.length != 1 ||
        sources.first['document_type'] != 'sale' ||
        sources.first['currency_code'] != posting.invoice.currency.code ||
        sources.first['warehouse_id'] != posting.invoice.warehouseId ||
        sources.first['counterparty_account_id'] !=
            posting.invoice.counterpartyAccountId?.value ||
        _asInt(sources.first['paid_minor']) !=
            _asInt(sources.first['total_minor']) ||
        _asInt(sources.first['due_minor']) != 0 ||
        !const {'paid', 'partiallyReturned'}
            .contains(sources.first['status']) ||
        (posting.voidSource && sources.first['status'] != 'paid')) {
      throw _ReturnWriteFailure(
        ValidationFailure(
          messageAr: 'pos_sales_return_source_changed',
          code: 'pos_sales_return_source_changed',
        ),
      );
    }
    final sourceLines = await executor.query(
      'pos_invoice_lines',
      where: 'invoice_id = ?',
      whereArgs: [posting.sourceInvoiceId],
      orderBy: 'id ASC',
    );
    if (sourceLines.isEmpty) {
      throw _ReturnWriteFailure(
        ValidationFailure(
          messageAr: 'pos_sales_return_source_lines_missing',
          code: 'pos_sales_return_source_lines_missing',
        ),
      );
    }
    _validateSourceInvoiceTotals(sources.single, sourceLines, posting);
    final priorRelations = await executor.query(
      'pos_returns',
      where: 'source_invoice_id = ?',
      whereArgs: [posting.sourceInvoiceId],
    );
    if (posting.voidSource && priorRelations.isNotEmpty) {
      throw _ReturnWriteFailure(
        ValidationFailure(
          messageAr: 'pos_sales_return_void_after_return_forbidden',
          code: 'pos_sales_return_void_after_return_forbidden',
        ),
      );
    }
    final previous = await _returnedQuantities(executor, posting.sourceInvoiceId);
    if (posting.voidSource && previous.values.any((quantity) => quantity > 0)) {
      throw _ReturnWriteFailure(
        ValidationFailure(
          messageAr: 'pos_sales_return_void_after_return_forbidden',
          code: 'pos_sales_return_void_after_return_forbidden',
        ),
      );
    }

    final sourceById = {
      for (final line in sourceLines) line['id'] as String: line,
    };
    if (previous.keys.any((sourceLineId) => !sourceById.containsKey(sourceLineId))) {
      throw _ReturnWriteFailure(
        ValidationFailure(
          messageAr: 'pos_sales_return_line_invalid',
          code: 'pos_sales_return_line_invalid',
        ),
      );
    }
    final discountRows = await executor.rawQuery(
      'SELECT l.source_line_id, SUM(l.discount_minor) AS amount '
      'FROM pos_invoice_lines l '
      'JOIN pos_invoices i ON i.id = l.invoice_id '
      'WHERE i.source_invoice_id = ? '
      "AND i.document_type = 'sales_return' "
      'AND l.source_line_id IS NOT NULL '
      'GROUP BY l.source_line_id',
      [posting.sourceInvoiceId],
    );
    final taxRows = await executor.rawQuery(
      'SELECT l.source_line_id, SUM(l.tax_minor) AS amount '
      'FROM pos_invoice_lines l '
      'JOIN pos_invoices i ON i.id = l.invoice_id '
      'WHERE i.source_invoice_id = ? '
      "AND i.document_type = 'sales_return' "
      'AND l.source_line_id IS NOT NULL '
      'GROUP BY l.source_line_id',
      [posting.sourceInvoiceId],
    );
    final priorDiscounts = {
      for (final row in discountRows)
        row['source_line_id'] as String: _asInt(row['amount']),
    };
    final priorTaxes = {
      for (final row in taxRows)
        row['source_line_id'] as String: _asInt(row['amount']),
    };
    final priorInvoices = await executor.query(
      'pos_invoices',
      where: 'source_invoice_id = ? AND document_type = ?',
      whereArgs: [posting.sourceInvoiceId, 'sales_return'],
    );
    var priorGross = 0;
    var priorDocumentDiscount = 0;
    var priorDocumentTax = 0;
    var priorLineDiscountTotal = 0;
    var priorLineTaxTotal = 0;
    for (final priorInvoice in priorInvoices) {
      priorDocumentDiscount += _asInt(priorInvoice['discount_minor']);
      priorDocumentTax += _asInt(priorInvoice['tax_minor']);
      final priorLines = await executor.query(
        'pos_invoice_lines',
        where: 'invoice_id = ?',
        whereArgs: [priorInvoice['id']],
      );
      for (final priorLine in priorLines) {
        priorLineDiscountTotal += _asInt(priorLine['discount_minor']);
        priorLineTaxTotal += _asInt(priorLine['tax_minor']);
        priorGross += PosMoneyMath.multiply(
          PosQuantity.fromScaled(
            _asInt(priorLine['quantity_scaled']),
            scale: _asInt(priorLine['quantity_scale']),
          ),
          Money.fromMinorUnits(
            _asInt(priorLine['unit_price_minor']),
            posting.invoice.currency,
          ),
        ).minorUnits;
      }
    }
    final priorGlobalDiscount = priorDocumentDiscount - priorLineDiscountTotal;
    final priorGlobalTax = priorDocumentTax - priorLineTaxTotal;
    final seenSourceLines = <String>{};
    var expectedSubtotal = 0;
    var expectedLineDiscountTotal = 0;
    var expectedLineTaxTotal = 0;
    for (final line in posting.invoice.lines) {
      final sourceLineId = line.sourceLineId;
      if (sourceLineId == null || !seenSourceLines.add(sourceLineId)) {
        throw _ReturnWriteFailure(
          ValidationFailure(
            messageAr: 'pos_sales_return_line_invalid',
            code: 'pos_sales_return_line_invalid',
          ),
        );
      }
      final sourceLine = sourceById[sourceLineId];
      if (sourceLine == null ||
          line.productId != sourceLine['product_id'] ||
          line.productNameSnapshot != sourceLine['product_name_snapshot'] ||
          line.barcodeSnapshot != sourceLine['barcode_snapshot'] ||
          line.quantity.scale != _asInt(sourceLine['quantity_scale']) ||
          line.unitPrice.currency != posting.invoice.currency ||
          line.unitCost.currency.code !=
              ((sourceLine['unit_cost_currency_code'] as String?) ??
                  (sources.single['currency_code'] as String)) ||
          line.unitPrice.minorUnits != _asInt(sourceLine['unit_price_minor']) ||
          line.unitCost.minorUnits != _asInt(sourceLine['unit_cost_minor'])) {
        throw _ReturnWriteFailure(
          ValidationFailure(
            messageAr: 'pos_sales_return_line_invalid',
            code: 'pos_sales_return_line_invalid',
          ),
        );
      }
      final total = (previous[sourceLineId] ?? 0) + line.quantity.scaledUnits;
      if (total > _asInt(sourceLine['quantity_scaled'])) {
        throw _ReturnWriteFailure(
          ValidationFailure(
            messageAr: 'pos_sales_return_quantity_exceeds_source',
            code: 'pos_sales_return_quantity_exceeds_source',
          ),
        );
      }
      final expectedLineDiscount = _cumulativeAllocation(
            _asInt(sourceLine['discount_minor']),
            total,
            _asInt(sourceLine['quantity_scaled']),
          ) -
          (priorDiscounts[sourceLineId] ?? 0);
      final expectedLineTax = _cumulativeAllocation(
            _asInt(sourceLine['tax_minor']),
            total,
            _asInt(sourceLine['quantity_scaled']),
          ) -
          (priorTaxes[sourceLineId] ?? 0);
      final lineGross = PosMoneyMath.multiply(line.quantity, line.unitPrice);
      if (line.discount.minorUnits != expectedLineDiscount ||
          line.tax.minorUnits != expectedLineTax ||
          line.lineTotal.minorUnits !=
              lineGross.minorUnits - expectedLineDiscount + expectedLineTax) {
        throw _ReturnWriteFailure(
          ValidationFailure(
            messageAr: 'pos_sales_return_line_amount_invalid',
            code: 'pos_sales_return_line_amount_invalid',
          ),
        );
      }
      expectedSubtotal += lineGross.minorUnits;
      expectedLineDiscountTotal += line.discount.minorUnits;
      expectedLineTaxTotal += line.tax.minorUnits;
      if (posting.voidSource &&
          line.quantity.scaledUnits != _asInt(sourceLine['quantity_scaled'])) {
        throw _ReturnWriteFailure(
          ValidationFailure(
            messageAr: 'pos_sales_return_void_must_cover_all_lines',
            code: 'pos_sales_return_void_must_cover_all_lines',
          ),
        );
      }
    }
    if (posting.voidSource &&
        (posting.invoice.lines.length != sourceLines.length ||
            seenSourceLines.length != sourceLines.length)) {
      throw _ReturnWriteFailure(
        ValidationFailure(
          messageAr: 'pos_sales_return_void_must_cover_all_lines',
          code: 'pos_sales_return_void_must_cover_all_lines',
        ),
      );
    }
    final sourceLineDiscountTotal = sourceLines.fold<int>(
      0,
      (sum, line) => sum + _asInt(line['discount_minor']),
    );
    final sourceLineTaxTotal = sourceLines.fold<int>(
      0,
      (sum, line) => sum + _asInt(line['tax_minor']),
    );
    final sourceSubtotal = _asInt(sources.single['subtotal_minor']);
    final sourceGlobalDiscount =
        _asInt(sources.single['discount_minor']) - sourceLineDiscountTotal;
    final sourceGlobalTax =
        _asInt(sources.single['tax_minor']) - sourceLineTaxTotal;
    if (sourceGlobalDiscount < 0 ||
        sourceGlobalTax < 0 ||
        priorGlobalDiscount < 0 ||
        priorGlobalTax < 0 ||
        priorGlobalDiscount > sourceGlobalDiscount ||
        priorGlobalTax > sourceGlobalTax ||
        sourceSubtotal <= 0 ||
        priorGross + expectedSubtotal > sourceSubtotal) {
      throw _ReturnWriteFailure(
        ValidationFailure(
          messageAr: 'pos_sales_return_history_invalid',
          code: 'pos_sales_return_history_invalid',
        ),
      );
    }
    final expectedGlobalDiscount = _cumulativeAllocation(
          sourceGlobalDiscount,
          priorGross + expectedSubtotal,
          sourceSubtotal,
        ) -
        priorGlobalDiscount;
    final expectedGlobalTax = _cumulativeAllocation(
          sourceGlobalTax,
          priorGross + expectedSubtotal,
          sourceSubtotal,
        ) -
        priorGlobalTax;
    if (expectedGlobalDiscount < 0 || expectedGlobalTax < 0 ||
        posting.invoice.subtotal.minorUnits != expectedSubtotal ||
        posting.invoice.discount.minorUnits !=
            expectedLineDiscountTotal + expectedGlobalDiscount ||
        posting.invoice.tax.minorUnits != expectedLineTaxTotal + expectedGlobalTax ||
        posting.invoice.total.minorUnits !=
            expectedSubtotal - expectedLineDiscountTotal - expectedGlobalDiscount +
                expectedLineTaxTotal + expectedGlobalTax) {
      throw _ReturnWriteFailure(
        ValidationFailure(
          messageAr: 'pos_sales_return_invoice_total_invalid',
          code: 'pos_sales_return_invoice_total_invalid',
        ),
      );
    }
    await _validateRefundPayments(executor, posting, sources.single);
    return sourceLines;
  }

  void _validateSourceInvoiceTotals(
    Map<String, Object?> sourceInvoice,
    List<Map<String, Object?>> sourceLines,
    PosSalesReturnPosting posting,
  ) {
    var subtotal = 0;
    var lineDiscount = 0;
    var lineTax = 0;
    for (final line in sourceLines) {
      final quantity = PosQuantity.fromScaled(
        _asInt(line['quantity_scaled']),
        scale: _asInt(line['quantity_scale']),
        allowZero: false,
      );
      final unitPrice = Money.fromMinorUnits(
        _asInt(line['unit_price_minor']),
        posting.invoice.currency,
      );
      final gross = PosMoneyMath.multiply(quantity, unitPrice).minorUnits;
      final discount = _asInt(line['discount_minor']);
      final tax = _asInt(line['tax_minor']);
      if (discount < 0 || tax < 0 || discount > gross ||
          _asInt(line['line_total_minor']) != gross - discount + tax) {
        throw _ReturnWriteFailure(
          ValidationFailure(
            messageAr: 'pos_sales_return_source_totals_invalid',
            code: 'pos_sales_return_source_totals_invalid',
          ),
        );
      }
      subtotal += gross;
      lineDiscount += discount;
      lineTax += tax;
    }
    final discount = _asInt(sourceInvoice['discount_minor']);
    final tax = _asInt(sourceInvoice['tax_minor']);
    if (subtotal != _asInt(sourceInvoice['subtotal_minor']) ||
        discount < lineDiscount ||
        tax < lineTax ||
        _asInt(sourceInvoice['total_minor']) !=
            subtotal - discount + tax) {
      throw _ReturnWriteFailure(
        ValidationFailure(
          messageAr: 'pos_sales_return_source_totals_invalid',
          code: 'pos_sales_return_source_totals_invalid',
        ),
      );
    }
  }

  Future<void> _validateRefundPayments(
    DatabaseExecutor executor,
    PosSalesReturnPosting posting,
    Map<String, Object?> sourceInvoice,
  ) async {
    final sourcePayments = await executor.query(
      'pos_payments',
      where: 'invoice_id = ?',
      whereArgs: [posting.sourceInvoiceId],
      orderBy: 'occurred_at ASC, id ASC',
    );
    final sourceTotal = _asInt(sourceInvoice['total_minor']);
    if (sourcePayments.isEmpty ||
        sourcePayments.any((row) =>
            row['payment_method'] == 'credit' ||
            row['currency_code'] != posting.invoice.currency.code) ||
        sourcePayments.fold<int>(
              0,
              (sum, row) => sum + _asInt(row['amount_minor']),
            ) !=
            sourceTotal) {
      throw _ReturnWriteFailure(
        ValidationFailure(
          messageAr: 'pos_sales_return_source_must_be_fully_paid',
          code: 'pos_sales_return_source_must_be_fully_paid',
        ),
      );
    }

    var allocated = 0;
    final denominator = sourcePayments.fold<int>(
      0,
      (sum, row) => sum + _asInt(row['amount_minor']),
    );
    final expected = <({Map<String, Object?> source, int index, int amount})>[];
    for (var index = 0; index < sourcePayments.length; index++) {
      final sourcePayment = sourcePayments[index];
      final amount = index == sourcePayments.length - 1
          ? posting.invoice.total.minorUnits - allocated
          : (_asInt(sourcePayment['amount_minor']) *
                      posting.invoice.total.minorUnits +
                  denominator ~/ 2) ~/
              denominator;
      if (amount <= 0) continue;
      allocated += amount;
      expected.add((source: sourcePayment, index: index, amount: amount));
    }
    if (expected.length != posting.refundPayments.length) {
      throw _ReturnWriteFailure(
        ValidationFailure(
          messageAr: 'pos_sales_return_refund_allocation_invalid',
          code: 'pos_sales_return_refund_allocation_invalid',
        ),
      );
    }
    for (var index = 0; index < expected.length; index++) {
      final allocation = expected[index];
      final refund = posting.refundPayments[index];
      final sourcePayment = allocation.source;
      if (refund.id != '${posting.invoice.id}:refund:${allocation.index}' ||
          refund.invoiceId != posting.invoice.id ||
          refund.idempotencyKey !=
              '${posting.invoice.idempotencyKey}:refund:${allocation.index}' ||
          refund.accountId.value != sourcePayment['account_id'] ||
          refund.method.name != sourcePayment['payment_method'] ||
          refund.amount.minorUnits != allocation.amount ||
          refund.currency.code != sourcePayment['currency_code'] ||
          refund.occurredAt.toUtc() != posting.invoice.createdAt.toUtc()) {
        throw _ReturnWriteFailure(
          ValidationFailure(
            messageAr: 'pos_sales_return_refund_allocation_invalid',
            code: 'pos_sales_return_refund_allocation_invalid',
          ),
        );
      }
    }
  }

  Future<Map<String, int>> _returnedQuantities(
    DatabaseExecutor executor,
    String sourceInvoiceId,
  ) async {
    final rows = await executor.rawQuery(
      'SELECT l.source_line_id, SUM(l.quantity_scaled) AS qty '
      'FROM pos_invoice_lines l '
      'JOIN pos_invoices i ON i.id = l.invoice_id '
      'WHERE i.source_invoice_id = ? '
      "AND i.document_type = 'sales_return' "
      'AND l.source_line_id IS NOT NULL '
      'GROUP BY l.source_line_id',
      [sourceInvoiceId],
    );
    return {
      for (final row in rows)
        row['source_line_id'] as String: _asInt(row['qty']),
    };
  }

  static void _assertNoOverReturn(
    List<Map<String, Object?>> sourceLines,
    Map<String, int> quantities,
  ) {
    for (final line in sourceLines) {
      final returned = quantities[line['id'] as String] ?? 0;
      if (returned > _asInt(line['quantity_scaled'])) {
        throw _ReturnWriteFailure(
          ValidationFailure(
            messageAr: 'pos_sales_return_quantity_exceeds_source',
            code: 'pos_sales_return_quantity_exceeds_source',
          ),
        );
      }
    }
  }

  static Map<String, Object?> _returnRelationRow(
    PosSalesReturnPosting posting,
  ) => {
        'id': '${posting.invoice.id}:relation',
        'source_invoice_id': posting.sourceInvoiceId,
        'return_invoice_id': posting.invoice.id,
        'reason': posting.reason,
        'created_at': posting.invoice.createdAt.toUtc().toIso8601String(),
      };

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
  ) => (left['id'] as String).compareTo(right['id'] as String);

  static int _asInt(Object? value) => value is int
      ? value
      : value is num
          ? value.toInt()
          : int.parse(value.toString());

  static int _cumulativeAllocation(int total, int part, int whole) =>
      (total * part + whole ~/ 2) ~/ whole;

  static bool _sameMovement(
    PosStockMovement existing,
    PosStockMovement expected,
  ) =>
      existing.id == expected.id &&
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

enum _ReturnState { absent, exact, partial, conflict }

final class _ReturnWriteFailure implements Exception {
  const _ReturnWriteFailure(this.failure);

  final Failure failure;
}
