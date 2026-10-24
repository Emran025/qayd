import 'package:flutter/foundation.dart';
import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/reports/dtos/generate_trial_balance_input.dart';
import 'package:qayd/application/reports/dtos/trial_balance_line_dto.dart';
import 'package:qayd/application/reports/dtos/trial_balance_output.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/ledger_entry.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/ledger_repository.dart';
import 'package:qayd/domain/services/trial_balance_generator.dart';
import 'package:qayd/domain/value_objects/date_range.dart';
import 'package:qayd/domain/value_objects/trial_balance_report.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';


class GenerateTrialBalanceUseCase {
  GenerateTrialBalanceUseCase(
    this._accountRepository,
    this._ledgerRepository,
    this._trialBalanceGenerator,
  );

  final AccountRepository _accountRepository;
  final LedgerRepository _ledgerRepository;
  final TrialBalanceGenerator _trialBalanceGenerator;

  Future<Result<TrialBalanceOutput>> call(
      GenerateTrialBalanceInput input) async {
    try {
      final start = input.fromDate ?? DateTime(2000);
      final end = input.toDate ?? DateTime.now();

      final accountsR = await _accountRepository.getAll();
      if (accountsR.isFailure) return FailureResult(accountsR.failureOrNull!);

      final entriesR = await _ledgerRepository.getAllEntries();
      if (entriesR.isFailure) return FailureResult(entriesR.failureOrNull!);

      final accounts = accountsR.valueOrNull!;
      final entries = entriesR.valueOrNull!;

      // Offload heavy calculation to background isolate
      final report = await compute(
          _buildReport,
          _TrialBalanceParams(
            generator: _trialBalanceGenerator,
            title: input.title ?? AppStrings.trialBalance,
            companyName: input.companyName ?? AppStrings.accountingRecordingSystem,
            dateRange: DateRange(start: start, end: end),
            accounts: accounts,
            entries: entries,
          ));

      return Success(
        TrialBalanceOutput(
          title: report.title,
          companyName: report.companyName,
          fromDate: report.dateRange.start,
          toDate: report.dateRange.end,
          lines: report.lines
              .map(
                (l) => TrialBalanceLineDto(
                  accountId: l.accountId.value,
                  accountCode: l.accountCode,
                  accountName: l.accountName,
                  accountLevel: l.accountLevel,
                  isParent: l.isParent,
                  currencyCode: l.currency.code,
                  currencySymbol: l.currency.symbol,
                  currencyDigits: l.currency.fractionalDigits,
                  openingDebitMinorUnits: l.openingDebitMinorUnits,
                  openingCreditMinorUnits: l.openingCreditMinorUnits,
                  periodDebitMinorUnits: l.periodDebitMinorUnits,
                  periodCreditMinorUnits: l.periodCreditMinorUnits,
                  closingDebitMinorUnits: l.closingDebitMinorUnits,
                  closingCreditMinorUnits: l.closingCreditMinorUnits,
                ),
              )
              .toList(growable: false),
          currencySections: {
            for (final entry in report.currencySections.entries)
              entry.key.code: TrialBalanceCurrencySectionDto(
                currencyCode: entry.key.code,
                currencySymbol: entry.key.symbol,
                currencyDigits: entry.key.fractionalDigits,
                openingDebitMinorUnits: entry.value.openingDebitMinorUnits,
                openingCreditMinorUnits: entry.value.openingCreditMinorUnits,
                periodDebitMinorUnits: entry.value.periodDebitMinorUnits,
                periodCreditMinorUnits: entry.value.periodCreditMinorUnits,
                closingDebitMinorUnits: entry.value.closingDebitMinorUnits,
                closingCreditMinorUnits: entry.value.closingCreditMinorUnits,
                isBalanced: entry.value.isBalanced,
                imbalanceMinorUnits: entry.value.imbalanceMinorUnits,
              ),
          },
          isOverallBalanced: report.isBalanced,
        ),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}

/// Helper function for compute() - must be top-level or static.
TrialBalanceReport _buildReport(_TrialBalanceParams p) {
  return p.generator.build(
    title: p.title,
    companyName: p.companyName,
    dateRange: p.dateRange,
    accounts: p.accounts,
    allEntries: p.entries,
  );
}

class _TrialBalanceParams {
  final TrialBalanceGenerator generator;
  final String title;
  final String companyName;
  final DateRange dateRange;
  final List<Account> accounts;
  final List<LedgerEntry> entries;

  _TrialBalanceParams({
    required this.generator,
    required this.title,
    required this.companyName,
    required this.dateRange,
    required this.accounts,
    required this.entries,
  });
}
