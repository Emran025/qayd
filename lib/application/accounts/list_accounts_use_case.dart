import 'package:qayd/application/accounts/dtos/account_summary_dto.dart';
import 'package:qayd/application/accounts/dtos/list_accounts_input.dart';
import 'package:qayd/application/accounts/dtos/list_accounts_output.dart';
import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/fiscal/brought_forward_balance_loader.dart';
import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/fiscal_period.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/ledger_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/services/balance_calculator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/domain/value_objects/entry_side.dart';

class ListAccountsUseCase {
  ListAccountsUseCase(
    this._accountRepository,
    this._ledgerRepository,
    this._balanceCalculator,
    this._voucherRepository,
    this._fiscalPeriodRepository,
  );

  final AccountRepository _accountRepository;
  final LedgerRepository _ledgerRepository;
  final BalanceCalculator _balanceCalculator;
  final VoucherRepository _voucherRepository;
  final FiscalPeriodRepository _fiscalPeriodRepository;

  Future<Result<ListAccountsOutput>> call(ListAccountsInput input) async {
    try {
      // 1. Fetch all accounts (we need the tree structure for aggregation)
      final accountsResult = await _accountRepository.getAll(
        activeOnly: input.activeOnly,
        excludeArchived: input.excludeArchived,
      );
      if (accountsResult.isFailure) {
        return FailureResult(accountsResult.failureOrNull!);
      }
      final allAccounts = accountsResult.valueOrNull!;

      // 2. Confirmed ledger: latest closed snapshot + delta (V3), or full history.
      final bfResult = await BroughtForwardBalanceLoader.load(
        fiscal: _fiscalPeriodRepository,
        ledger: _ledgerRepository,
      );
      if (bfResult.isFailure) {
        return FailureResult(bfResult.failureOrNull!);
      }
      final bf = bfResult.valueOrNull!;
      final snapshotBase = bf.snapshotMinorByAccountAndCurrency;
      final deltaEntries = bf.deltaEntries;

      final periodsR = await _fiscalPeriodRepository.listAllOrdered();
      final closedPeriods =
          periodsR.isSuccess ? periodsR.valueOrNull! : <FiscalPeriod>[];

      // 3. Fetch all pending/unconfirmed vouchers to include user's claims
      // Non-confirmed vouchers are not yet in the ledger.
      final allVouchersResult = await _voucherRepository.getAll();
      if (allVouchersResult.isFailure) {
        return FailureResult(allVouchersResult.failureOrNull!);
      }
      final unconfirmedVouchers = allVouchersResult.valueOrNull!
          .where((v) => !v.state.isConfirmed && !v.state.isSettled)
          .where(
            (v) =>
                v.receiverStatus != AgreementStatus.rejected &&
                !v.state.isWithdrawn,
          )
          .toList();

      // 4. Pre-compute base balances for every account (Ledger + Pending Vouchers)
      final directBalances = <String, Map<String, int>>{};
      for (final a in allAccounts) {
        final fromSnap = snapshotBase[a.id.value] ?? const <String, int>{};
        final baseMap = Map<String, int>.from(fromSnap);

        final perCurrencyDelta =
            _balanceCalculator.signedBalanceMinorUnitsPerCurrency(
          entries: deltaEntries,
          accountId: a.id,
          nature: a.nature,
        );
        for (final e in perCurrencyDelta.entries) {
          baseMap[e.key.code] = (baseMap[e.key.code] ?? 0) + e.value;
        }

        // Add impact of pending claims (Perspective: "My Accounts")
        for (final v in unconfirmedVouchers) {
          if (FiscalPeriodPolicy.voucherDateInClosedPeriod(
            closedPeriods,
            v.date,
          )) {
            continue;
          }
          final impact = _calculateVoucherImpact(v, a.id, a.nature);
          if (impact != 0) {
            final code = v.currency.code;
            baseMap[code] = (baseMap[code] ?? 0) + impact;
          }
        }

        directBalances[a.id.value] = baseMap;
      }

      // 5. Build recursive aggregation logic with memoization
      final memo = <String, Map<String, int>>{};
      Map<String, int> aggregate(String accountId) {
        if (memo.containsKey(accountId)) return memo[accountId]!;

        final total = Map<String, int>.from(directBalances[accountId] ?? {});
        final children = allAccounts.where(
          (a) => a.parentId?.value == accountId,
        );
        for (final child in children) {
          final childTotal = aggregate(child.id.value);
          childTotal.forEach((code, amount) {
            total[code] = (total[code] ?? 0) + amount;
          });
        }
        memo[accountId] = total;
        return total;
      }

      // 6. Build summaries for the requested accounts
      var accountsToShow = allAccounts;
      if (input.parentAccountId != null) {
        final pid = input.parentAccountId!;
        accountsToShow =
            allAccounts.where((a) => a.parentId?.value == pid).toList();
      }

      final summaries = <AccountSummaryDto>[];
      for (final a in accountsToShow) {
        final balancesMinorUnits = aggregate(a.id.value);
        summaries.add(
          AccountSummaryDto(
            id: a.id.value,
            name: a.name,
            natureCode: a.nature == AccountNature.debit ? 'debit' : 'credit',
            isActive: a.isActive,
            isRoot: a.isRoot,
            parentId: a.parentId?.value,
            standardClassificationKind: a.classification.standardKind?.name,
            customClassificationName: a.classification.customName,
            balancesMinorUnits: balancesMinorUnits,
            metadata: a.metadata,
          ),
        );
      }

      return Success(ListAccountsOutput(accounts: summaries));
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }

  /// Universal impact calculation for a Voucher on an account balance in Qayd.
  /// Consistently applies Debit/Credit sides based on AccountNature.
  int _calculateVoucherImpact(Voucher v, AccountId a, AccountNature nature) {
    EntrySide? side;

    if (v.type == VoucherType.receipt) {
      if (v.affectedAccountId == a) side = EntrySide.debit;
      if (v.counterpartyId == a) side = EntrySide.credit;
    } else {
      // Payment
      if (v.affectedAccountId == a) side = EntrySide.credit;
      if (v.counterpartyId == a) side = EntrySide.debit;
    }

    if (side == null) return 0;

    // §6: Signature-Gated Impact
    // A document only affects an account's balance if the owner of that account has signed it.
    // However, if this is an inbound claim that we (the receiver) haven't accepted yet,
    // it shouldn't affect ANY local account balances (neither ours nor the counterparty's) 
    // until we formally approve it.
    if (v.isInbound && v.receiverStatus != AgreementStatus.accepted) {
      return 0;
    }

    // Use the `isInbound` flag to accurately determine creator (sender) vs receiver roles.
    final bool isAccountOwnerTheSender =
        v.isInbound ? v.counterpartyId == a : v.affectedAccountId == a;
    final bool isAccountOwnerTheReceiver =
        v.isInbound ? v.affectedAccountId == a : v.counterpartyId == a;

    if (isAccountOwnerTheSender && v.senderStatus != AgreementStatus.accepted) {
      return 0;
    }
    if (isAccountOwnerTheReceiver &&
        v.receiverStatus != AgreementStatus.accepted) {
      return 0;
    }

    final isDebitAccount = nature == AccountNature.debit;
    if (isDebitAccount) {
      // Debit increases balance for Debit-natured accounts (Asset, Expense)
      return side == EntrySide.debit
          ? v.amount.minorUnits
          : -v.amount.minorUnits;
    } else {
      // Credit increases balance for Credit-natured accounts (Liability, Equity, Revenue)
      return side == EntrySide.credit
          ? v.amount.minorUnits
          : -v.amount.minorUnits;
    }
  }
}
