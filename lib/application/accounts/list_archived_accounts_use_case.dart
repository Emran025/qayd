import 'package:qayd/application/accounts/dtos/account_summary_dto.dart';
import 'package:qayd/application/accounts/dtos/list_accounts_output.dart';
import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';

class ListArchivedAccountsUseCase {
  ListArchivedAccountsUseCase(this._accountRepository);

  final AccountRepository _accountRepository;

  Future<Result<ListAccountsOutput>> call() async {
    try {
      final accountsResult = await _accountRepository.getArchivedAccounts();
      if (accountsResult.isFailure) {
        return FailureResult(accountsResult.failureOrNull!);
      }
      
      final archivedAccounts = accountsResult.valueOrNull!;
      final summaries = archivedAccounts.map((a) => AccountSummaryDto(
        id: a.id.value,
        name: a.name,
        natureCode: a.nature == AccountNature.debit ? 'debit' : 'credit',
        isActive: a.isActive,
        isRoot: a.isRoot,
        parentId: a.parentId?.value,
        standardClassificationKind: a.classification.standardKind?.name,
        customClassificationName: a.classification.customName,
        // Balances are implicitly zero for archived accounts per domain invariant,
        // but we emit empty for strict adherence.
        balancesMinorUnits: const {},
        metadata: a.metadata,
      )).toList(growable: false);

      return Success(ListAccountsOutput(accounts: summaries));
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
