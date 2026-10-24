import 'package:flutter/foundation.dart';
import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/reports/dtos/balance_sheet_output.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/ledger_entry.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/ledger_repository.dart';
import 'package:qayd/domain/services/balance_sheet_generator.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/standard_account_classification_kind.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';


class GenerateBalanceSheetUseCase {
  GenerateBalanceSheetUseCase(
    this._accountRepository,
    this._ledgerRepository,
    this._balanceSheetGenerator,
  );

  final AccountRepository _accountRepository;
  final LedgerRepository _ledgerRepository;
  final BalanceSheetGenerator _balanceSheetGenerator;

  Future<Result<BalanceSheetOutput>> call(DateTime atDate) async {
    try {
      final accountsR = await _accountRepository.getAll();
      if (accountsR.isFailure) return FailureResult(accountsR.failureOrNull!);

      final entriesR = await _ledgerRepository.getAllEntries();
      if (entriesR.isFailure) return FailureResult(entriesR.failureOrNull!);

      final accounts = accountsR.valueOrNull!;
      final entries = entriesR.valueOrNull!;

      // Offload to background isolate
      final lines = await compute(
          _buildBalanceSheet,
          _BalanceSheetParams(
            generator: _balanceSheetGenerator,
            atDate: atDate,
            accounts: accounts,
            entries: entries,
          ));

      final dtoLines = lines
          .map((l) => BalanceSheetLineDto(
                accountId: l.accountId,
                parentId: l.parentId,
                accountCode: l.accountCode,
                accountName: l.accountName,
                level: l.level,
                isParent: l.isParent,
                currencyCode: l.currency.code,
                currencySymbol: l.currency.symbol,
                currencyDigits: l.currency.fractionalDigits,
                balanceMinorUnits: l.balanceMinorUnits,
                classification: l.classification,
              ))
          .toList();

      // ── Build per-currency section totals ──────────────────────────────
      final currencySections = _buildCurrencySections(dtoLines);

      return Success(
        BalanceSheetOutput(
          atDate: atDate,
          title: AppStrings.balanceSheet,
          companyName: AppStrings.accountingRecordingSystem,
          lines: dtoLines,
          currencySections: currencySections,
        ),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }

  Map<String, BalanceSheetCurrencySectionDto> _buildCurrencySections(
    List<BalanceSheetLineDto> lines,
  ) {
    // Only aggregate root-level (level == 0) lines to avoid double-counting
    // hierarchy children. Root accounts carry rolled-up balances.
    // Aggregating only root-level (accounts with no parent) lines to avoid double-counting
    // hierarchy children. Root accounts carry rolled-up balances.
    final rootLines = lines.where((l) => l.parentId == null);

    final perCurrency = <String, _CurrencyAccumulator>{};
    for (final l in rootLines) {
      final acc = perCurrency.putIfAbsent(
        l.currencyCode,
        () => _CurrencyAccumulator(
          currencyCode: l.currencyCode,
          currencySymbol: l.currencySymbol,
          currencyDigits: l.currencyDigits,
        ),
      );

      if (_isAsset(l.classification)) {
        acc.assets += l.balanceMinorUnits;
      } else if (_isLiability(l.classification)) {
        acc.liabilities += l.balanceMinorUnits;
      } else {
        acc.equity += l.balanceMinorUnits;
      }
    }

    return {
      for (final entry in perCurrency.entries)
        entry.key: BalanceSheetCurrencySectionDto(
          currencyCode: entry.value.currencyCode,
          currencySymbol: entry.value.currencySymbol,
          currencyDigits: entry.value.currencyDigits,
          totalAssetsMinorUnits: entry.value.assets,
          totalLiabilitiesMinorUnits: entry.value.liabilities,
          totalEquityMinorUnits: entry.value.equity,
          // Equation: Assets + Liabilities + Equity = 0 (signed Dr-Cr)
          isBalanced: (entry.value.assets +
                      entry.value.liabilities +
                      entry.value.equity)
                  .abs() <
              10, // Tolerance for rounding if any (usually 0 in integer math)
        ),
    };
  }

  static bool _isAsset(AccountClassification c) {
    if (c.standardKind != null) {
      return c.standardKind == StandardAccountClassificationKind.liquidAssets ||
          c.standardKind == StandardAccountClassificationKind.receivables ||
          c.standardKind ==
              StandardAccountClassificationKind.fixedProfitableAssets ||
          c.standardKind ==
              StandardAccountClassificationKind.fixedDepreciableAssets;
    }
    // Fallback for custom classifications
    return c.defaultNature == AccountNature.debit;
  }

  static bool _isLiability(AccountClassification c) {
    if (c.standardKind != null) {
      return c.standardKind == StandardAccountClassificationKind.payables ||
          c.standardKind == StandardAccountClassificationKind.settlements ||
          c.standardKind ==
              StandardAccountClassificationKind.clearingRemittances;
    }
    // Fallback for custom classifications
    return c.defaultNature == AccountNature.credit;
  }
}

/// Helper function for compute()
List<BalanceSheetLine> _buildBalanceSheet(_BalanceSheetParams p) {
  return p.generator.build(
    atDate: p.atDate,
    accounts: p.accounts,
    allEntries: p.entries,
  );
}

class _BalanceSheetParams {
  final BalanceSheetGenerator generator;
  final DateTime atDate;
  final List<Account> accounts;
  final List<LedgerEntry> entries;

  _BalanceSheetParams({
    required this.generator,
    required this.atDate,
    required this.accounts,
    required this.entries,
  });
}

class _CurrencyAccumulator {
  _CurrencyAccumulator({
    required this.currencyCode,
    required this.currencySymbol,
    required this.currencyDigits,
  });

  final String currencyCode;
  final String currencySymbol;
  final int currencyDigits;
  int assets = 0;
  int liabilities = 0;
  int equity = 0;
}
