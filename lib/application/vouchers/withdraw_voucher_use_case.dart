import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/entities/audit_entry.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';


/// Withdraws (سحب) a voucher — non-destructive retraction.
///
/// Protocol §2.A: A voucher can be withdrawn if it is still in Draft,
/// UnderRequest, or Rejected states. The record remains in the database
/// for audit integrity but is flagged as withdrawn. It disappears from
/// the recipient's "Inbox" and is moved to a local "Archive" for the creator.
final class WithdrawVoucherUseCase {
  const WithdrawVoucherUseCase(
    this._voucherRepository,
    this._writeGuard, {
    SyncEventDispatcher? syncEventDispatcher,
    AuditLogService? auditLogService,
  })  : _syncEventDispatcher = syncEventDispatcher,
        _auditLogService = auditLogService;

  final VoucherRepository _voucherRepository;
  final GovernanceWriteGuard _writeGuard;
  final SyncEventDispatcher? _syncEventDispatcher;
  final AuditLogService? _auditLogService;

  Future<Result<void>> call({required String voucherId}) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }

      final loaded = await _voucherRepository.getById(VoucherId(voucherId));
      if (loaded.isFailure) return FailureResult(loaded.failureOrNull!);
      final v = loaded.valueOrNull!;

      if (!v.canWithdraw) {
        return  FailureResult(
          ValidationFailure(
            messageAr: AppStrings.aBondThatHas,
            code: 'voucher_withdraw_not_allowed',
          ),
        );
      }

      final now = DateTime.now();
      final withdrawn = v.withdraw(now);
      final saved = await _voucherRepository.save(withdrawn);
      if (saved.isSuccess && _syncEventDispatcher != null) {
        _syncEventDispatcher!.dispatchVoucherWithdrawal(withdrawn).ignore();
      }

      if (saved.isSuccess) {
        await _auditLogService?.log(
          entityType: 'voucher',
          entityId: withdrawn.id.value,
          action: AuditAction.delete, // Withdrawal is semantically a soft-delete
          oldData: {'state': v.state.name},
          newData: {'state': withdrawn.state.name},
        );
      }

      // ── Cascade Withdrawal to Automated Internal Vouchers ──────────────
      if (saved.isSuccess) {
        final childrenRes = await _voucherRepository.getByOriginVoucherId(v.id);
        if (childrenRes.isSuccess) {
          for (final child in childrenRes.valueOrNull!) {
            // If it's an automated internal posting, withdraw it too
            if (child.state.isConfirmed && child.originVoucherId == v.id) {
              // Internal vouchers can be withdrawn even if confirmed
              // because they have no counterparty agreement constraints.
              final withdrawnChild = child.withdraw(now);
              await _voucherRepository.save(withdrawnChild);
            }
          }
        }
      }

      return saved;
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
