import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/audit_entry.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/ledger_repository.dart';
import 'package:qayd/domain/services/balance_calculator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

class ArchiveAccountUseCase {
  ArchiveAccountUseCase(
    this._accountRepository,
    this._ledgerRepository,
    this._balanceCalculator,
    this._writeGuard, {
    AuditLogService? auditLogService,
  }) : _auditLogService = auditLogService;

  final AccountRepository _accountRepository;
  final LedgerRepository _ledgerRepository;
  final BalanceCalculator _balanceCalculator;
  final GovernanceWriteGuard _writeGuard;
  final AuditLogService? _auditLogService;

  Future<Result<String>> call(String accountIdRaw) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) return FailureResult(gate.failureOrNull!);

      final loaded = await _accountRepository.getById(AccountId(accountIdRaw));
      if (loaded.isFailure) return FailureResult(loaded.failureOrNull!);

      final account = loaded.valueOrNull!;
      final entriesR = await _ledgerRepository.getEntriesForAccount(account.id);
      if (entriesR.isFailure) return FailureResult(entriesR.failureOrNull!);

      final entries = entriesR.valueOrNull!;
      final perCurrency = _balanceCalculator.signedBalanceMinorUnitsPerCurrency(
        entries: entries,
        accountId: account.id,
        nature: account.nature,
      );

      final hasBalance = perCurrency.values.any((v) => v != 0);
      Money balanceCheck;
      if (hasBalance) {
        final entry = perCurrency.entries.firstWhere((e) => e.value != 0);
        balanceCheck = Money.nonNegative(entry.value.abs(), entry.key);
      } else {
        balanceCheck = Money.zero(
            CurrencyCode(code: 'SAR', nameAr: '﷼', symbol: AppStrings.rs));
      }

      final archived = account.archive(balance: balanceCheck);
      final saved = await _accountRepository.save(archived);

      if (saved.isSuccess) {
        await _auditLogService?.log(
          entityType: 'account',
          entityId: archived.id.value,
          action: AuditAction.update,
          oldData: {'is_archived': false},
          newData: {'is_archived': true},
        );
      }

      return await saved.fold(
        (f) => FailureResult(f),
        (_) => Success(archived.id.value),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
