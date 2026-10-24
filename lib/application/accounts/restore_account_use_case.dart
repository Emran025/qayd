import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/audit_entry.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/application/governance/audit_log_service.dart';

class RestoreAccountUseCase {
  RestoreAccountUseCase(
    this._accountRepository,
    this._writeGuard, {
    AuditLogService? auditLogService,
  }) : _auditLogService = auditLogService;

  final AccountRepository _accountRepository;
  final GovernanceWriteGuard _writeGuard;
  final AuditLogService? _auditLogService;

  Future<Result<String>> call(String accountIdRaw) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) return FailureResult(gate.failureOrNull!);

      final loaded = await _accountRepository.getById(AccountId(accountIdRaw));
      if (loaded.isFailure) return FailureResult(loaded.failureOrNull!);

      final account = loaded.valueOrNull!;
      final restored = account.unarchive();
      final saved = await _accountRepository.save(restored);

      if (saved.isSuccess) {
        await _auditLogService?.log(
          entityType: 'account',
          entityId: restored.id.value,
          action: AuditAction.update,
          oldData: {'is_archived': true},
          newData: {'is_archived': false},
        );
      }

      return await saved.fold(
        (f) => FailureResult(f),
        (_) => Success(restored.id.value),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
