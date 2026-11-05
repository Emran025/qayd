import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/mappers/ledger_entry_mapper.dart';
import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/data/mappers/voucher_mapper.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_purchase_return_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/pos_purchase_return_posting_repository.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// ACID coordinator for purchase returns, supplier credits, inventory, ledger,
/// and source-document status.
final class SqlitePosPurchaseReturnPostingRepository
    implements PosPurchaseReturnPostingRepository {
  SqlitePosPurchaseReturnPostingRepository(
    this._runner,
    this._stock,
    this._vouchers,
  );

  final DatabaseTransactionRunner _runner;
  final SqlitePosStockMovementRepository _stock;
  final SqliteVoucherRepository _vouchers;
  static const _sourceSnapshotKeys = <String>[
    'unit_cost_currency_code',
    'conversion_purpose',
    'conversion_source_minor',
    'conversion_source_currency_code',
    'conversion_target_minor',
    'conversion_target_currency_code',
    'fx_rate_id',
    'fx_requested_from_code',
    'fx_requested_to_code',
    'fx_stored_from_code',
    'fx_stored_to_code',
    'fx_rate_scaled',
    'fx_effective_at',
    'fx_recorded_at',
    'fx_created_at',
    'fx_is_inverted',
    'fx_note',
    'expiry_tracking_snapshot',
  ];

  @override
  Future<Result<void>> saveAtomically(PosPurchaseReturnPosting posting) async {
    try {
      await _runner.run<void>((txn) => saveInTransaction(txn, posting));
      return const Success(null);
    } on _PurchaseReturnWriteFailure catch (error) {
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

  Future<void> saveInTransaction(
    Transaction txn,
    PosPurchaseReturnPosting posting,
  ) async {
    final state = await _inspect(txn, posting);
    if (state == _ReturnState.exact) return;
    if (state != _ReturnState.absent) {
      throw _PurchaseReturnWriteFailure(
        ValidationFailure(
          messageAr: AppStrings.posAccountingPartialState,
          code: 'pos_purchase_return_partial_or_conflicting_state',
        ),
      );
    }

    final sourceLines = await _validateSourceAndQuantities(txn, posting);
    await _validateAccounts(txn, posting);
    await txn.insert('pos_invoices', PosInvoiceMapper.toRow(posting.invoice));
    for (final line in posting.invoice.lines) {
      await txn.insert('pos_invoice_lines', PosInvoiceMapper.lineToRow(line));
    }
    await txn.insert('pos_returns', _relationRow(posting));
    for (final movement in posting.movements) {
      final result = await _stock.appendPurchaseReturnInTransaction(
        txn,
        movement,
      );
      if (result.isFailure) {
        throw _PurchaseReturnWriteFailure(result.failureOrNull!);
      }
    }
    for (final accounting in posting.postings) {
      final result = await _vouchers.saveWithLedgerEntriesInTransaction(
        txn,
        voucher: accounting.voucher,
        ledgerEntries: accounting.entries,
      );
      if (result.isFailure) {
        throw _PurchaseReturnWriteFailure(result.failureOrNull!);
      }
    }

    final totals = await _returnedQuantities(txn, posting.sourceInvoiceId);
    _assertNoOverReturn(sourceLines, totals);
    final fullyReturned = sourceLines.every(
      (line) =>
          (totals[line['id'] as String] ?? 0) ==
          _asInt(line['quantity_scaled']),
    );
    final affected = await txn.update(
      'pos_invoices',
      {
        'status': fullyReturned ? 'fullyReturned' : 'partiallyReturned',
        'updated_at': posting.invoice.createdAt.toUtc().toIso8601String(),
      },
      where: 'id = ? AND status IN (?, ?, ?, ?)',
      whereArgs: [
        posting.sourceInvoiceId,
        'posted',
        'partiallyPaid',
        'paid',
        'partiallyReturned',
      ],
    );
    if (affected != 1) {
      throw _PurchaseReturnWriteFailure(
        ValidationFailure(
          messageAr: AppStrings.posInvoiceInvalid,
          code: 'pos_purchase_return_source_changed',
        ),
      );
    }
  }

  Future<_ReturnState> _inspect(
    DatabaseExecutor executor,
    PosPurchaseReturnPosting posting,
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
    final invoiceMatches =
        invoiceByKey.length == 1 &&
        invoiceById.length == 1 &&
        invoiceByKey.first['id'] == posting.invoice.id &&
        _mapMatches(
          invoiceByKey.first,
          PosInvoiceMapper.toRow(posting.invoice),
          ignored: const {'created_at', 'updated_at'},
        );
    if (invoiceExists && !invoiceMatches) return _ReturnState.conflict;

    final actualLines = await executor.query(
      'pos_invoice_lines',
      where: 'invoice_id = ?',
      whereArgs: [posting.invoice.id],
      orderBy: 'id ASC',
    );
    final expectedLines =
        posting.invoice.lines.map(PosInvoiceMapper.lineToRow).toList()
          ..sort(_compareIdMaps);
    final linesMatch =
        actualLines.length == expectedLines.length &&
        _rowsMatch(actualLines, expectedLines, ignored: const {'created_at'});

    final relationId = '${posting.invoice.id}:relation';
    final relationById = await executor.query(
      'pos_returns',
      where: 'id = ?',
      whereArgs: [relationId],
      limit: 1,
    );
    final relationByReturn = await executor.query(
      'pos_returns',
      where: 'return_invoice_id = ?',
      whereArgs: [posting.invoice.id],
      limit: 1,
    );
    final relationExists =
        relationById.isNotEmpty || relationByReturn.isNotEmpty;
    final relationMatches =
        relationById.length == 1 &&
        relationByReturn.length == 1 &&
        _mapMatches(
          relationById.first,
          _relationRow(posting),
          ignored: const {'created_at'},
        );
    if (relationExists && !relationMatches) return _ReturnState.conflict;

    final movementRows = await executor.query(
      'pos_stock_movements',
      columns: ['id'],
      where: 'source_type = ? AND source_id = ?',
      whereArgs: ['pos_invoice', posting.invoice.id],
    );
    final expectedMovementIds = posting.movements.map((m) => m.id).toSet();
    final actualMovementIds = movementRows
        .map((r) => r['id'] as String)
        .toSet();
    if (movementRows.isNotEmpty &&
        (actualMovementIds.length != expectedMovementIds.length ||
            !actualMovementIds.containsAll(expectedMovementIds))) {
      return _ReturnState.conflict;
    }
    var movementState = _ReturnState.exact;
    for (final movement in posting.movements) {
      final existingResult = await _stock.getByIdempotencyKeyInTransaction(
        executor,
        movement.idempotencyKey,
      );
      if (existingResult.isFailure) {
        throw _PurchaseReturnWriteFailure(existingResult.failureOrNull!);
      }
      final existing = existingResult.valueOrNull;
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
        .map((p) => p.voucher.id.value)
        .toSet();
    final actualVoucherIds = voucherRows.map((r) => r['id'] as String).toSet();
    if (voucherRows.isNotEmpty &&
        (actualVoucherIds.length != expectedVoucherIds.length ||
            !actualVoucherIds.containsAll(expectedVoucherIds))) {
      return _ReturnState.conflict;
    }

    var postingState = _ReturnState.exact;
    for (final accounting in posting.postings) {
      final voucherRowsForPosting = await executor.query(
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
      if (voucherRowsForPosting.isEmpty && ledgerRows.isEmpty) {
        postingState = _ReturnState.absent;
        continue;
      }
      final expectedEntries =
          accounting.entries
              .map(LedgerEntryMapper.toModel)
              .map((entry) => entry.toMap())
              .toList()
            ..sort(_compareIdMaps);
      if (voucherRowsForPosting.length != 1 ||
          ledgerRows.length != expectedEntries.length ||
          !_mapMatches(
            voucherRowsForPosting.first,
            VoucherMapper.toModel(accounting.voucher).toMap(),
            ignored: const {'created_at'},
          ) ||
          !_rowsMatch(
            [...ledgerRows]..sort(_compareIdMaps),
            expectedEntries,
            ignored: const {'created_at'},
          )) {
        return _ReturnState.conflict;
      }
    }

    if (invoiceMatches &&
        linesMatch &&
        relationMatches &&
        movementState == _ReturnState.exact &&
        postingState == _ReturnState.exact) {
      final source = await executor.query(
        'pos_invoices',
        where: 'id = ?',
        whereArgs: [posting.sourceInvoiceId],
        limit: 1,
      );
      if (source.length != 1 ||
          source.first['document_type'] != 'purchase' ||
          !{
            'partiallyReturned',
            'fullyReturned',
          }.contains(source.first['status'])) {
        return _ReturnState.conflict;
      }
      final allSourceLines = await executor.query(
        'pos_invoice_lines',
        where: 'invoice_id = ?',
        whereArgs: [posting.sourceInvoiceId],
      );
      final returned = await _returnedQuantities(
        executor,
        posting.sourceInvoiceId,
      );
      try {
        _assertNoOverReturn(allSourceLines, returned);
      } on _PurchaseReturnWriteFailure {
        return _ReturnState.conflict;
      }
      final fullyReturned =
          allSourceLines.isNotEmpty &&
          allSourceLines.every(
            (line) =>
                (returned[line['id'] as String] ?? 0) ==
                _asInt(line['quantity_scaled']),
          );
      if ((fullyReturned && source.first['status'] != 'fullyReturned') ||
          (!fullyReturned && source.first['status'] != 'partiallyReturned')) {
        return _ReturnState.conflict;
      }
      return _ReturnState.exact;
    }

    if (!invoiceExists &&
        actualLines.isEmpty &&
        !relationExists &&
        movementState == _ReturnState.absent &&
        (postingState == _ReturnState.absent || posting.postings.isEmpty)) {
      return _ReturnState.absent;
    }
    return _ReturnState.partial;
  }

  Future<List<Map<String, Object?>>> _validateSourceAndQuantities(
    DatabaseExecutor executor,
    PosPurchaseReturnPosting posting,
  ) async {
    final sources = await executor.query(
      'pos_invoices',
      where: 'id = ?',
      whereArgs: [posting.sourceInvoiceId],
      limit: 1,
    );
    if (sources.length != 1 ||
        sources.single['document_type'] != 'purchase' ||
        sources.single['currency_code'] != posting.invoice.currency.code ||
        sources.single['warehouse_id'] != posting.invoice.warehouseId ||
        sources.single['counterparty_account_id'] !=
            posting.invoice.counterpartyAccountId?.value ||
        sources.single['status'] == 'voided' ||
        sources.single['status'] == 'fullyReturned' ||
        sources.single['status'] == 'draft') {
      throw _invalid('pos_purchase_return_source_changed');
    }
    if (_asInt(sources.single['tax_minor']) != 0) {
      throw _invalid('pos_purchase_return_tax_account_required');
    }
    final sourceLines = await executor.query(
      'pos_invoice_lines',
      where: 'invoice_id = ?',
      whereArgs: [posting.sourceInvoiceId],
      orderBy: 'id ASC',
    );
    if (sourceLines.isEmpty) {
      throw _invalid('pos_purchase_return_source_lines_missing');
    }

    final sourceById = {
      for (final line in sourceLines) line['id'] as String: line,
    };
    final priorInvoices = await executor.query(
      'pos_invoices',
      where: 'source_invoice_id = ? AND document_type = ?',
      whereArgs: [posting.sourceInvoiceId, 'purchase_return'],
    );
    final priorQuantity = <String, int>{};
    final priorDiscount = <String, int>{};
    final priorTax = <String, int>{};
    var priorGross = 0;
    var priorGlobalDiscount = 0;
    var priorGlobalTax = 0;
    var priorLineDiscount = 0;
    var priorLineTax = 0;
    for (final prior in priorInvoices) {
      if (prior['status'] != 'posted' ||
          _asInt(prior['paid_minor']) != 0 ||
          _asInt(prior['due_minor']) != _asInt(prior['total_minor']) ||
          prior['currency_code'] != posting.invoice.currency.code ||
          prior['warehouse_id'] != posting.invoice.warehouseId ||
          prior['counterparty_account_id'] !=
              posting.invoice.counterpartyAccountId?.value) {
        throw _invalid('pos_purchase_return_history_invalid');
      }
      final priorLines = await executor.query(
        'pos_invoice_lines',
        where: 'invoice_id = ?',
        whereArgs: [prior['id']],
      );
      priorGlobalDiscount += _asInt(prior['discount_minor']);
      priorGlobalTax += _asInt(prior['tax_minor']);
      for (final line in priorLines) {
        final sourceLineId = line['source_line_id'] as String?;
        final original = sourceLineId == null ? null : sourceById[sourceLineId];
        if (original == null ||
            line['product_id'] != original['product_id'] ||
            _asInt(line['quantity_scale']) !=
                _asInt(original['quantity_scale']) ||
            _asInt(line['unit_price_minor']) !=
                _asInt(original['unit_price_minor']) ||
            _asInt(line['unit_cost_minor']) !=
                _asInt(original['unit_cost_minor']) ||
            !_sourceSnapshotMatches(line, original)) {
          throw _invalid('pos_purchase_return_history_invalid');
        }
        priorQuantity.update(
          sourceLineId!,
          (value) => value + _asInt(line['quantity_scaled']),
          ifAbsent: () => _asInt(line['quantity_scaled']),
        );
        priorDiscount.update(
          sourceLineId,
          (value) => value + _asInt(line['discount_minor']),
          ifAbsent: () => _asInt(line['discount_minor']),
        );
        priorTax.update(
          sourceLineId,
          (value) => value + _asInt(line['tax_minor']),
          ifAbsent: () => _asInt(line['tax_minor']),
        );
        priorLineDiscount += _asInt(line['discount_minor']);
        priorLineTax += _asInt(line['tax_minor']);
        priorGross += PosMoneyMath.multiply(
          PosQuantity.fromScaled(
            _asInt(line['quantity_scaled']),
            scale: _asInt(line['quantity_scale']),
          ),
          Money.fromMinorUnits(
            _asInt(line['unit_price_minor']),
            posting.invoice.currency,
          ),
        ).minorUnits;
      }
    }
    priorGlobalDiscount -= priorLineDiscount;
    priorGlobalTax -= priorLineTax;

    var expectedSubtotal = 0;
    var expectedLineDiscount = 0;
    var expectedLineTax = 0;
    final seen = <String>{};
    for (final line in posting.invoice.lines) {
      final sourceLineId = line.sourceLineId;
      final original = sourceLineId == null ? null : sourceById[sourceLineId];
      if (sourceLineId == null ||
          !seen.add(sourceLineId) ||
          original == null ||
          line.productId != original['product_id'] ||
          line.productNameSnapshot != original['product_name_snapshot'] ||
          line.barcodeSnapshot != original['barcode_snapshot'] ||
          line.quantity.scale != _asInt(original['quantity_scale']) ||
          line.unitPrice.currency != posting.invoice.currency ||
          line.unitPrice.minorUnits != _asInt(original['unit_price_minor']) ||
          line.unitCost.minorUnits != _asInt(original['unit_cost_minor']) ||
          line.unitCost.currency.code !=
              ((original['unit_cost_currency_code'] as String?) ??
                  posting.invoice.currency.code) ||
          !_sourceSnapshotMatches(PosInvoiceMapper.lineToRow(line), original)) {
        throw _invalid('pos_purchase_return_line_invalid');
      }
      final cumulative =
          (priorQuantity[sourceLineId] ?? 0) + line.quantity.scaledUnits;
      if (cumulative > _asInt(original['quantity_scaled'])) {
        throw _invalid('pos_purchase_return_quantity_exceeds_source');
      }
      final expectedDiscount =
          _cumulativeAllocation(
            _asInt(original['discount_minor']),
            cumulative,
            _asInt(original['quantity_scaled']),
          ) -
          (priorDiscount[sourceLineId] ?? 0);
      final expectedTax =
          _cumulativeAllocation(
            _asInt(original['tax_minor']),
            cumulative,
            _asInt(original['quantity_scaled']),
          ) -
          (priorTax[sourceLineId] ?? 0);
      if (line.discount.minorUnits != expectedDiscount ||
          line.tax.minorUnits != expectedTax) {
        throw _invalid('pos_purchase_return_line_amount_invalid');
      }
      final gross = PosMoneyMath.multiply(
        line.quantity,
        line.unitPrice,
      ).minorUnits;
      if (line.lineTotal.minorUnits != gross - expectedDiscount + expectedTax) {
        throw _invalid('pos_purchase_return_line_amount_invalid');
      }
      expectedSubtotal += gross;
      expectedLineDiscount += line.discount.minorUnits;
      expectedLineTax += line.tax.minorUnits;
    }

    final sourceSubtotal = _asInt(sources.single['subtotal_minor']);
    final sourceLineDiscount = sourceLines.fold<int>(
      0,
      (sum, line) => sum + _asInt(line['discount_minor']),
    );
    final sourceLineTax = sourceLines.fold<int>(
      0,
      (sum, line) => sum + _asInt(line['tax_minor']),
    );
    final sourceGlobalDiscount =
        _asInt(sources.single['discount_minor']) - sourceLineDiscount;
    final sourceGlobalTax = _asInt(sources.single['tax_minor']) - sourceLineTax;
    if (sourceGlobalDiscount < 0 ||
        sourceGlobalTax < 0 ||
        priorGlobalDiscount < 0 ||
        priorGlobalTax < 0 ||
        priorGross + expectedSubtotal > sourceSubtotal) {
      throw _invalid('pos_purchase_return_history_invalid');
    }
    final globalDiscount = sourceSubtotal == 0
        ? 0
        : _cumulativeAllocation(
                sourceGlobalDiscount,
                priorGross + expectedSubtotal,
                sourceSubtotal,
              ) -
              priorGlobalDiscount;
    final globalTax = sourceSubtotal == 0
        ? 0
        : _cumulativeAllocation(
                sourceGlobalTax,
                priorGross + expectedSubtotal,
                sourceSubtotal,
              ) -
              priorGlobalTax;
    if (globalDiscount < 0 ||
        globalTax < 0 ||
        posting.invoice.subtotal.minorUnits != expectedSubtotal ||
        posting.invoice.discount.minorUnits !=
            expectedLineDiscount + globalDiscount ||
        posting.invoice.tax.minorUnits != expectedLineTax + globalTax ||
        posting.invoice.total.minorUnits !=
            expectedSubtotal -
                expectedLineDiscount -
                globalDiscount +
                expectedLineTax +
                globalTax) {
      throw _invalid('pos_purchase_return_invoice_total_invalid');
    }
    final totalReturnedValue =
        priorInvoices.fold<int>(
          0,
          (sum, invoice) => sum + _asInt(invoice['total_minor']),
        ) +
        posting.invoice.total.minorUnits;
    if (totalReturnedValue > _asInt(sources.single['total_minor'])) {
      throw _invalid('pos_purchase_return_value_exceeds_source');
    }
    return sourceLines;
  }

  Future<void> _validateAccounts(
    DatabaseExecutor executor,
    PosPurchaseReturnPosting posting,
  ) async {
    final ids = <String>{
      posting.supplierPayablesAccountId.value,
      posting.inventoryAccountId.value,
      posting.purchaseReturnsAccountId.value,
      posting.invoice.counterpartyAccountId!.value,
      for (final accounting in posting.postings)
        for (final entry in accounting.entries) entry.accountId.value,
    };
    final rows = await executor.query(
      'accounts',
      columns: ['id', 'is_active', 'is_archived'],
      where: 'id IN (${List<String>.filled(ids.length, '?').join(',')})',
      whereArgs: ids.toList(growable: false),
    );
    if (rows.length != ids.length ||
        rows.any(
          (row) =>
              _asInt(row['is_active']) != 1 || _asInt(row['is_archived']) != 0,
        )) {
      throw _invalid('pos_purchase_return_account_mapping_missing');
    }
  }

  Future<Map<String, int>> _returnedQuantities(
    DatabaseExecutor executor,
    String sourceInvoiceId,
  ) async {
    final rows = await executor.rawQuery(
      'SELECT l.source_line_id, SUM(l.quantity_scaled) AS quantity_scaled '
      'FROM pos_invoice_lines l JOIN pos_invoices i ON i.id = l.invoice_id '
      'WHERE i.source_invoice_id = ? AND i.document_type = ? '
      'AND l.source_line_id IS NOT NULL GROUP BY l.source_line_id',
      [sourceInvoiceId, 'purchase_return'],
    );
    return {
      for (final row in rows)
        row['source_line_id'] as String: _asInt(row['quantity_scaled']),
    };
  }

  void _assertNoOverReturn(
    List<Map<String, Object?>> sourceLines,
    Map<String, int> quantities,
  ) {
    final sourceIds = sourceLines.map((line) => line['id']).toSet();
    if (quantities.keys.any((id) => !sourceIds.contains(id)) ||
        sourceLines.any((line) {
          final id = line['id'] as String;
          return (quantities[id] ?? 0) > _asInt(line['quantity_scaled']);
        })) {
      throw _invalid('pos_purchase_return_quantity_exceeds_source');
    }
  }

  Map<String, Object?> _relationRow(PosPurchaseReturnPosting posting) => {
    'id': '${posting.invoice.id}:relation',
    'source_invoice_id': posting.sourceInvoiceId,
    'return_invoice_id': posting.invoice.id,
    'reason': posting.reason,
    'created_at': posting.invoice.createdAt.toUtc().toIso8601String(),
  };

  bool _sameMovement(PosStockMovement left, PosStockMovement right) =>
      left.id == right.id &&
      left.productId == right.productId &&
      left.warehouseId == right.warehouseId &&
      left.type == right.type &&
      left.direction == right.direction &&
      left.quantity == right.quantity &&
      left.unitCost == right.unitCost &&
      left.sourceType == right.sourceType &&
      left.sourceId == right.sourceId &&
      left.sourceLineId == right.sourceLineId &&
      left.lotId == right.lotId &&
      left.reversesSourceId == right.reversesSourceId &&
      left.occurredAt.toUtc() == right.occurredAt.toUtc() &&
      left.idempotencyKey == right.idempotencyKey;

  bool _mapMatches(
    Map<String, Object?> actual,
    Map<String, Object?> expected, {
    Set<String> ignored = const {},
  }) {
    final keys = expected.keys.where((key) => !ignored.contains(key));
    return keys.every((key) => actual[key] == expected[key]);
  }

  bool _sourceSnapshotMatches(
    Map<String, Object?> candidate,
    Map<String, Object?> source,
  ) => _sourceSnapshotKeys.every((key) => candidate[key] == source[key]);

  bool _rowsMatch(
    List<Map<String, Object?>> actual,
    List<Map<String, Object?>> expected, {
    Set<String> ignored = const {},
  }) =>
      actual.length == expected.length &&
      List.generate(
        actual.length,
        (i) => i,
      ).every((i) => _mapMatches(actual[i], expected[i], ignored: ignored));

  int _compareIdMaps(Map<String, Object?> a, Map<String, Object?> b) =>
      (a['id'] as String).compareTo(b['id'] as String);

  int _cumulativeAllocation(int total, int part, int whole) =>
      whole == 0 ? 0 : (total * part + whole ~/ 2) ~/ whole;

  int _asInt(Object? value) => value is int ? value : (value as num).toInt();

  _PurchaseReturnWriteFailure _invalid(String code) =>
      _PurchaseReturnWriteFailure(
        ValidationFailure(messageAr: code, code: code),
      );
}

final class _PurchaseReturnWriteFailure implements Exception {
  const _PurchaseReturnWriteFailure(this.failure);
  final Failure failure;
}

enum _ReturnState { absent, exact, partial, conflict }
