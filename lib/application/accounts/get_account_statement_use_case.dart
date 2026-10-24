import 'package:qayd/application/accounts/dtos/account_statement_line_dto.dart';
import 'package:qayd/application/accounts/dtos/account_statement_output.dart';
import 'package:qayd/application/accounts/dtos/get_account_statement_input.dart';
import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/ledger_entry.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/ledger_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/entry_side.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';


class GetAccountStatementUseCase {
  GetAccountStatementUseCase(
    this._accountRepository,
    this._ledgerRepository,
    this._voucherRepository,
  );

  final AccountRepository _accountRepository;
  final LedgerRepository _ledgerRepository;
  final VoucherRepository _voucherRepository;

  Future<Result<AccountStatementOutput>> call(
    GetAccountStatementInput input,
  ) async {
    try {
      if (input.fromDate != null &&
          input.toDate != null &&
          input.fromDate!.isAfter(input.toDate!)) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.invalidDateRange,
            code: 'statement_date_range',
          ),
        );
      }

      final accountR =
          await _accountRepository.getById(AccountId(input.accountId));
      if (accountR.isFailure) {
        return FailureResult(accountR.failureOrNull!);
      }
      final account = accountR.valueOrNull!;

      final entriesR = await _ledgerRepository.getEntriesForAccount(account.id);
      if (entriesR.isFailure) {
        return FailureResult(entriesR.failureOrNull!);
      }
      var entries = List<LedgerEntry>.of(entriesR.valueOrNull!);
      entries = entries
          .where((e) => _inDateRange(e.date, input.fromDate, input.toDate))
          .toList(growable: false);
      entries.sort((a, b) {
        final c = a.date.compareTo(b.date);
        if (c != 0) return c;
        return a.createdAt.compareTo(b.createdAt);
      });

      final voucherText = <String, String>{};
      final uniqueVoucherIds = entries.map((e) => e.voucherId).toSet().toList();
      final voucherResults = await Future.wait(
        uniqueVoucherIds.map((id) => _voucherRepository.getById(id)),
      );

      for (var i = 0; i < uniqueVoucherIds.length; i++) {
        final vr = voucherResults[i];
        if (vr.isFailure) {
          return FailureResult(vr.failureOrNull!);
        }
        final v = vr.valueOrNull!;
        final text = v.description ?? v.notes ?? '';
        voucherText[v.id.value] = text;
      }

      var running = 0;
      final lines = <AccountStatementLineDto>[];
      for (final e in entries) {
        final delta = _signedDelta(e, account.nature);
        running += delta;
        final debitCol = e.side == EntrySide.debit ? e.amount.minorUnits : 0;
        final creditCol = e.side == EntrySide.credit ? e.amount.minorUnits : 0;
        lines.add(
          AccountStatementLineDto(
            dateIso: e.date.toIso8601String(),
            description: voucherText[e.voucherId.value] ?? '',
            debitMinorUnits: debitCol,
            creditMinorUnits: creditCol,
            balanceMinorUnits: running,
            voucherId: e.voucherId.value,
            currencyCode: e.currency.code,
            currencySymbol: e.currency.symbol,
            currencyDigits: e.currency.fractionalDigits,
          ),
        );
      }

      return Success(
        AccountStatementOutput(
          accountId: account.id.value,
          accountName: account.name,
          natureCode:
              account.nature == AccountNature.debit ? 'debit' : 'credit',
          lines: lines,
        ),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }

  bool _inDateRange(DateTime entry, DateTime? from, DateTime? to) {
    final day = DateTime(entry.year, entry.month, entry.day);
    if (from != null) {
      final f = DateTime(from.year, from.month, from.day);
      if (day.isBefore(f)) return false;
    }
    if (to != null) {
      final t = DateTime(to.year, to.month, to.day);
      if (day.isAfter(t)) return false;
    }
    return true;
  }

  int _signedDelta(LedgerEntry e, AccountNature nature) {
    if (nature == AccountNature.debit) {
      return e.side == EntrySide.debit
          ? e.amount.minorUnits
          : -e.amount.minorUnits;
    }
    return e.side == EntrySide.credit
        ? e.amount.minorUnits
        : -e.amount.minorUnits;
  }
}
