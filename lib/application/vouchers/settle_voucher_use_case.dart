import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/domain/entities/audit_entry.dart';


/// Settles a confirmed voucher — marking it as fully resolved.
///
/// Protocol §4: Upon settlement acceptance, the original voucher state is
/// updated to `settled`, and the settlement voucher acts as the closing
/// record linked via `originVoucherId`.
class SettleVoucherUseCase {
  const SettleVoucherUseCase(
    this._voucherRepository,
    this._writeGuard, {
    this.auditLogService,
  }
  );

  final VoucherRepository _voucherRepository;
  final GovernanceWriteGuard _writeGuard;
  final AuditLogService? auditLogService;

  Future<Result<void>> call({required String voucherId}) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }

      final loaded = await _voucherRepository.getById(VoucherId(voucherId));
      if (loaded.isFailure) return FailureResult(loaded.failureOrNull!);
      final v = loaded.valueOrNull!;
      final oldState = {'id': v.id.value, 'state': v.state.name};

      if (!v.state.isConfirmed) {
        return  FailureResult(
          ValidationFailure(
            messageAr: AppStrings.theBondCanBe,
            code: 'voucher_settle_not_confirmed',
          ),
        );
      }

      final settled = v.settle(DateTime.now());
      final result = await _voucherRepository.save(settled);
      if (result.isSuccess) {
        await auditLogService?.log(
          entityType: 'voucher',
          entityId: settled.id.value,
          action: AuditAction.update,
          severity: AuditSeverity.info,
          oldData: oldState,
          newData: {'id': settled.id.value, 'state': settled.state.name},
        );
      }
      return result;
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
