import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/domain/entities/audit_entry.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';

/// Deletes a draft voucher — only when it is still in the Draft state.
///
/// For non-draft vouchers, use [WithdrawVoucherUseCase] instead
/// (non-destructive retraction preserving audit trail).
class DeleteDraftVoucherUseCase {
  const DeleteDraftVoucherUseCase(
    this._voucherRepository,
    this._writeGuard, {
    AuditLogService? auditLogService,
  }) : _auditLogService = auditLogService;

  final VoucherRepository _voucherRepository;
  final GovernanceWriteGuard _writeGuard;
  final AuditLogService? _auditLogService;

  Future<Result<void>> call({required String voucherId}) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }

      final loaded = await _voucherRepository.getById(VoucherId(voucherId));
      final old = loaded.valueOrNull;
      final result = await _voucherRepository.deleteDraft(VoucherId(voucherId));
      if (result.isSuccess && old != null) {
        await _auditLogService?.log(
          entityType: 'voucher',
          entityId: old.id.value,
          action: AuditAction.delete,
          severity: AuditSeverity.warning,
          oldData: {
            'id': old.id.value,
            'state': old.state.name,
            'type': old.type.name,
          },
        );
      }
      return result;
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
