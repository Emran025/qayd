import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/mappers/ledger_entry_mapper.dart';
import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/data/mappers/voucher_mapper.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
import 'package:qayd/domain/repositories/pos_invoice_payment_collection_repository.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/entry_side.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';
import 'package:qayd/domain/value_objects/standard_account_classification_kind.dart';
import 'package:qayd/domain/value_objects/voucher_state.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Persists a later POS collection as one atomic payment + balance + voucher +
/// ledger operation. It never edits the original sale's revenue voucher.
final class SqlitePosInvoicePaymentCollectionRepository
    implements PosInvoicePaymentCollectionRepository {
  SqlitePosInvoicePaymentCollectionRepository(
    this._transactionRunner,
    this._voucherRepository,
  );

  final DatabaseTransactionRunner _transactionRunner;
  final SqliteVoucherRepository _voucherRepository;

  @override
  Future<Result<bool>> recoverCommitted(
    PosInvoicePaymentCollectionPosting posting,
  ) async {
    try {
      return await _transactionRunner.run((txn) async {
        final inspection = await _inspect(txn, posting);
        return Success(inspection == _Inspection.exactReplay);
      });
    } on _RepositoryFailure catch (error) {
      return FailureResult(error.failure);
    } on DatabaseException {
      return _databaseFailure<bool>();
    } catch (_) {
      return _databaseFailure<bool>();
    }
  }

  @override
  Future<Result<void>> saveAtomically(
    PosInvoicePaymentCollectionPosting posting,
  ) async {
    try {
      return await _transactionRunner.run((txn) async {
        await saveInTransaction(txn, posting);
        return const Success<void>(null);
      });
    } on _RepositoryFailure catch (error) {
      return FailureResult(error.failure);
    } on DatabaseException {
      return _databaseFailure<void>();
    } catch (_) {
      return _databaseFailure<void>();
    }
  }

  /// Saves a collection using the caller-owned transaction.
  ///
  /// All validation, idempotency inspection, balance update, payment, voucher,
  /// and ledger writes happen on [txn]. No nested transaction is opened here;
  /// database errors are intentionally allowed to escape to the transaction
  /// owner so it can roll back the whole unit of work.
  Future<void> saveInTransaction(
    Transaction txn,
    PosInvoicePaymentCollectionPosting posting,
  ) async {
    final inspection = await _inspect(txn, posting);
    if (inspection == _Inspection.exactReplay) {
      return;
    }

    final invoiceRows = await txn.query(
      'pos_invoices',
      where: 'id = ?',
      whereArgs: [posting.invoiceBefore.id],
      limit: 1,
    );
    if (invoiceRows.isEmpty) {
      _fail('pos_collection_invoice_missing');
    }
    final invoiceRow = invoiceRows.single;
    await _validateFreshPosting(txn, invoiceRow, posting);

    final updated = await txn.update(
      'pos_invoices',
      {
        'paid_minor': posting.invoiceAfter.paid.minorUnits,
        'due_minor': posting.invoiceAfter.due.minorUnits,
        'status': posting.invoiceAfter.status.name,
        'updated_at': posting.recordedAt.toUtc().toIso8601String(),
      },
      where: 'id = ? AND paid_minor = ? AND due_minor = ? AND status = ?',
      whereArgs: [
        posting.invoiceBefore.id,
        posting.invoiceBefore.paid.minorUnits,
        posting.invoiceBefore.due.minorUnits,
        posting.invoiceBefore.status.name,
      ],
    );
    if (updated != 1) _fail('pos_collection_invoice_changed');

    await txn.insert(
      'pos_payments',
      PosInvoiceMapper.paymentToRow(posting.payment, posting.recordedAt),
    );
    final voucherResult = await _voucherRepository
        .saveWithLedgerEntriesInTransaction(
          txn,
          voucher: posting.accountingPosting.voucher,
          ledgerEntries: posting.accountingPosting.entries,
        );
    if (voucherResult.isFailure) {
      throw _RepositoryFailure(voucherResult.failureOrNull!);
    }
  }

  Future<_Inspection> _inspect(
    DatabaseExecutor executor,
    PosInvoicePaymentCollectionPosting posting,
  ) async {
    final payment = posting.payment;
    final keyRows = await executor.query(
      'pos_payments',
      where: 'idempotency_key = ?',
      whereArgs: [payment.idempotencyKey],
    );
    final idRows = await executor.query(
      'pos_payments',
      where: 'id = ?',
      whereArgs: [payment.id],
    );
    final voucher = posting.accountingPosting.voucher;
    final voucherIdRows = await executor.query(
      'vouchers',
      where: 'id = ?',
      whereArgs: [voucher.id.value],
    );
    final voucherReferenceRows = await executor.query(
      'vouchers',
      where: 'reference_number = ?',
      whereArgs: [payment.id],
    );

    final hasPayment = keyRows.isNotEmpty || idRows.isNotEmpty;
    final hasAccounting =
        voucherIdRows.isNotEmpty ||
        voucherReferenceRows.isNotEmpty ||
        await _hasLedgerEntries(executor, posting);
    if (!hasPayment && !hasAccounting) return _Inspection.absent;
    if (keyRows.length != 1 ||
        idRows.length != 1 ||
        voucherIdRows.length != 1 ||
        voucherReferenceRows.length != 1 ||
        !_sameRow(
          keyRows.single,
          PosInvoiceMapper.paymentToRow(payment, posting.recordedAt),
        ) ||
        !_sameRow(
          idRows.single,
          PosInvoiceMapper.paymentToRow(payment, posting.recordedAt),
        ) ||
        !_sameRow(
          voucherIdRows.single,
          VoucherMapper.toModel(voucher).toMap(),
        ) ||
        !_sameRow(
          voucherReferenceRows.single,
          VoucherMapper.toModel(voucher).toMap(),
        ) ||
        !await _ledgerMatches(executor, posting)) {
      _fail('pos_collection_idempotency_conflict');
    }

    final invoiceRows = await executor.query(
      'pos_invoices',
      where: 'id = ?',
      whereArgs: [payment.invoiceId],
      limit: 1,
    );
    if (invoiceRows.length != 1 ||
        !await _invoicePaymentProjectionMatches(
          executor,
          invoiceRows.single,
          payment.invoiceId,
        )) {
      _fail('pos_collection_invoice_projection_mismatch');
    }
    return _Inspection.exactReplay;
  }

  Future<void> _validateFreshPosting(
    DatabaseExecutor executor,
    Map<String, Object?> row,
    PosInvoicePaymentCollectionPosting posting,
  ) async {
    final before = posting.invoiceBefore;
    final after = posting.invoiceAfter;
    final payment = posting.payment;
    final voucher = posting.accountingPosting.voucher;
    if (before.type != PosInvoiceType.sale ||
        after.id != before.id ||
        after.type != PosInvoiceType.sale ||
        before.postedAt == null ||
        (before.status != PosDocumentStatus.posted &&
            before.status != PosDocumentStatus.partiallyPaid) ||
        before.counterpartyAccountId == null ||
        PosDate.fromDateTime(
          payment.occurredAt.toLocal(),
        ).isBefore(PosDate.fromDateTime(before.invoiceDate.toLocal())) ||
        before.currency != payment.currency ||
        before.currency.code != (row['currency_code'] as String?) ||
        before.id != payment.invoiceId ||
        before.total.minorUnits != (row['total_minor'] as int?) ||
        before.paid.minorUnits != (row['paid_minor'] as int?) ||
        before.due.minorUnits != (row['due_minor'] as int?) ||
        before.status.name != (row['status'] as String?) ||
        before.counterpartyAccountId!.value !=
            (row['counterparty_account_id'] as String?) ||
        before.total.minorUnits != after.total.minorUnits ||
        before.currency != after.currency ||
        payment.amount.minorUnits <= 0 ||
        payment.amount.minorUnits > before.due.minorUnits ||
        payment.idempotencyKey.trim().isEmpty ||
        payment.method == PosPaymentMethod.credit ||
        payment.method == PosPaymentMethod.other ||
        posting.isReplay ||
        posting.accountingPosting.sourceId != payment.id ||
        voucher.type != VoucherType.receipt ||
        voucher.state != VoucherState.confirmed ||
        voucher.referenceNumber != payment.id ||
        voucher.amount != payment.amount ||
        voucher.currency != payment.currency ||
        voucher.date.toUtc() != payment.occurredAt.toUtc() ||
        voucher.counterpartyId != before.counterpartyAccountId ||
        voucher.affectedAccountId != payment.accountId ||
        before.id != (row['id'] as String?)) {
      _fail('pos_collection_posting_invalid');
    }

    final currentProjection = await _invoicePaymentProjectionMatches(
      executor,
      row,
      before.id,
    );
    if (!currentProjection) _fail('pos_collection_payment_history_mismatch');

    final customerActive = await _accountIsActive(
      executor,
      before.counterpartyAccountId!.value,
    );
    final paymentAccountEligible = await _isLiquidAssetAccount(
      executor,
      payment.accountId.value,
    );
    if (!customerActive) _fail('pos_collection_customer_inactive');
    if (!paymentAccountEligible) {
      _fail('pos_collection_payment_account_invalid');
    }

    final expectedAfter = before.applyPayment(
      payment.amount,
      posting.recordedAt,
    );
    if (after.paid.minorUnits != expectedAfter.paid.minorUnits ||
        after.due.minorUnits != expectedAfter.due.minorUnits ||
        after.status != expectedAfter.status) {
      _fail('pos_collection_balance_transition_invalid');
    }

    final entries = posting.accountingPosting.entries;
    if (entries.length != 2 ||
        entries
                .where(
                  (entry) =>
                      entry.accountId == payment.accountId &&
                      entry.side == EntrySide.debit &&
                      entry.amount == payment.amount,
                )
                .length !=
            1 ||
        entries
                .where(
                  (entry) =>
                      entry.accountId == before.counterpartyAccountId &&
                      entry.side == EntrySide.credit &&
                      entry.amount == payment.amount,
                )
                .length !=
            1 ||
        entries.any(
          (entry) =>
              entry.currency != payment.currency ||
              entry.voucherId != voucher.id,
        )) {
      _fail('pos_collection_ledger_direction_invalid');
    }
  }

  Future<bool> _invoicePaymentProjectionMatches(
    DatabaseExecutor executor,
    Map<String, Object?> invoiceRow,
    String invoiceId,
  ) async {
    final paymentRows = await executor.query(
      'pos_payments',
      columns: ['amount_minor', 'currency_code'],
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
    );
    final currencyCode = invoiceRow['currency_code'] as String?;
    final paidMinor = invoiceRow['paid_minor'] as int?;
    final dueMinor = invoiceRow['due_minor'] as int?;
    final totalMinor = invoiceRow['total_minor'] as int?;
    if (currencyCode == null ||
        paidMinor == null ||
        dueMinor == null ||
        totalMinor == null ||
        paidMinor < 0 ||
        dueMinor < 0 ||
        paidMinor + dueMinor != totalMinor) {
      return false;
    }
    var paymentTotal = 0;
    for (final row in paymentRows) {
      if (row['currency_code'] != currencyCode) return false;
      final amount = row['amount_minor'];
      if (amount is! int || amount <= 0) return false;
      paymentTotal += amount;
    }
    return paymentTotal == paidMinor;
  }

  Future<bool> _accountIsActive(
    DatabaseExecutor executor,
    String accountId,
  ) async {
    final rows = await executor.query(
      'accounts',
      columns: ['is_active', 'is_archived'],
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    return rows.length == 1 &&
        rows.single['is_active'] == 1 &&
        rows.single['is_archived'] == 0;
  }

  Future<bool> _isLiquidAssetAccount(
    DatabaseExecutor executor,
    String accountId,
  ) async {
    final rows = await executor.query(
      'accounts',
      columns: [
        'is_active',
        'is_archived',
        'standard_classification',
        'nature',
      ],
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    return rows.length == 1 &&
        rows.single['is_active'] == 1 &&
        rows.single['is_archived'] == 0 &&
        rows.single['standard_classification'] ==
            StandardAccountClassificationKind.liquidAssets.name &&
        rows.single['nature'] == AccountNature.debit.name;
  }

  Future<bool> _hasLedgerEntries(
    DatabaseExecutor executor,
    PosInvoicePaymentCollectionPosting posting,
  ) async {
    final voucherId = posting.accountingPosting.voucher.id.value;
    final rows = await executor.query(
      'ledger_entries',
      where: 'voucher_id = ?',
      whereArgs: [voucherId],
      limit: 1,
    );
    if (rows.isNotEmpty) return true;
    final entryIds = posting.accountingPosting.entries
        .map((entry) => entry.id.value)
        .toList(growable: false);
    if (entryIds.isEmpty) return false;
    final placeholders = List.filled(entryIds.length, '?').join(',');
    final byId = await executor.query(
      'ledger_entries',
      where: 'id IN ($placeholders)',
      whereArgs: entryIds,
      limit: 1,
    );
    return byId.isNotEmpty;
  }

  Future<bool> _ledgerMatches(
    DatabaseExecutor executor,
    PosInvoicePaymentCollectionPosting posting,
  ) async {
    final expected =
        posting.accountingPosting.entries
            .map(LedgerEntryMapper.toModel)
            .map((entry) => entry.toMap())
            .toList(growable: false)
          ..sort(
            (left, right) =>
                (left['id']! as String).compareTo(right['id']! as String),
          );
    final rows =
        (await executor.query(
          'ledger_entries',
          where: 'voucher_id = ?',
          whereArgs: [posting.accountingPosting.voucher.id.value],
        )).toList()..sort(
          (left, right) =>
              (left['id']! as String).compareTo(right['id']! as String),
        );
    if (rows.length != expected.length) return false;
    for (var index = 0; index < rows.length; index++) {
      if (!_sameRow(rows[index], expected[index])) return false;
    }
    return true;
  }

  bool _sameRow(Map<String, Object?> actual, Map<String, Object?> expected) {
    for (final entry in expected.entries) {
      if (actual[entry.key] != entry.value) return false;
    }
    return true;
  }

  Never _fail(String code) => throw _RepositoryFailure(
    ValidationFailure(
      messageAr: AppStrings.posInvoicePaymentInvalid,
      code: code,
    ),
  );

  FailureResult<T> _databaseFailure<T>() => FailureResult(
    DatabaseFailure(messageAr: AppStrings.posInvoicePaymentInvalid),
  );
}

enum _Inspection { absent, exactReplay }

final class _RepositoryFailure implements Exception {
  const _RepositoryFailure(this.failure);

  final Failure failure;
}
