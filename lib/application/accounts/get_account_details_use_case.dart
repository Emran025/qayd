import 'package:qayd/application/accounts/dtos/account_default_cost_center_dto.dart';
import 'package:qayd/application/accounts/dtos/get_account_details_input.dart';
import 'package:qayd/application/accounts/dtos/get_account_details_output.dart';
import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/ledger_repository.dart';
import 'package:qayd/domain/services/balance_calculator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';

class GetAccountDetailsUseCase {
  GetAccountDetailsUseCase(
    this._accountRepository,
    this._ledgerRepository,
    this._balanceCalculator,
  );

  final AccountRepository _accountRepository;
  final LedgerRepository _ledgerRepository;
  final BalanceCalculator _balanceCalculator;

  Future<Result<GetAccountDetailsOutput>> call(
      GetAccountDetailsInput input) async {
    try {
      final loaded =
          await _accountRepository.getById(AccountId(input.accountId));
      if (loaded.isFailure) {
        return FailureResult(loaded.failureOrNull!);
      }
      final account = loaded.valueOrNull!;
      final entriesR = await _ledgerRepository.getEntriesForAccount(account.id);
      if (entriesR.isFailure) {
        return FailureResult(entriesR.failureOrNull!);
      }
      final entries = entriesR.valueOrNull!;
      final perCurrency = _balanceCalculator.signedBalanceMinorUnitsPerCurrency(
        entries: entries,
        accountId: account.id,
        nature: account.nature,
      );
      final balancesMinorUnits = {
        for (final entry in perCurrency.entries) entry.key.code: entry.value
      };
      String? parentName;
      if (account.parentId != null) {
        final p = await _accountRepository.getById(account.parentId!);
        if (p.isSuccess) {
          parentName = p.valueOrNull!.name;
        }
      }

      final partyDetailsR =
          await _accountRepository.getPartyDetails(account.id);
      final partyDetails = partyDetailsR.valueOrNull;

      // Fetch default cost centers; soft-fail so account details still load.
      final defaultCCRes =
          await _accountRepository.getDefaultCostCenters(account.id);
      final defaultCCs = defaultCCRes.isSuccess
          ? defaultCCRes.valueOrNull!
          : const <AccountDefaultCostCenterDto>[];

      return Success(
        GetAccountDetailsOutput(
          accountId: account.id.value,
          name: account.name,
          natureCode:
              account.nature == AccountNature.debit ? 'debit' : 'credit',
          isActive: account.isActive,
          isRoot: account.isRoot,
          parentId: account.parentId?.value,
          parentName: parentName,
          balancesMinorUnits: balancesMinorUnits,
          createdAtIso: account.createdAt.toIso8601String(),
          standardClassificationKind: account.classification.standardKind?.name,
          customClassificationName: account.classification.customName,
          phoneNumber: partyDetails?.phoneNumber,
          whatsappNumber: partyDetails?.whatsappNumber,
          bankAccountInfo: partyDetails?.bankAccountInfo,
          partyType: partyDetails?.partyType,
          defaultCostCenters: defaultCCs,
        ),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
