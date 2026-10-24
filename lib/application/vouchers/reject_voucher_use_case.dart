import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/domain/entities/audit_entry.dart';


/// \"Reject\" is represented by setting the voucher agreement status to `rejected`
/// and dispatching an E2EE rejection event to the counterparty.
///
/// Sync flow:
///   1. Validate voucher is in draft state.
///   2. Mark as rejected locally.
///   3. Fire-and-forget rejection E2EE event via [SyncEventDispatcher] (outbox-routed
///      so it survives network outages and retries automatically).
class RejectVoucherUseCase {
  const RejectVoucherUseCase(
    this._voucherRepository,
    this._writeGuard, {
    this.syncEventDispatcher,
    this.auditLogService,
  });

  final VoucherRepository _voucherRepository;
  final GovernanceWriteGuard _writeGuard;

  /// Optional — when provided the rejection is propagated via E2EE sync.
  /// Omitted in contexts that have no network dependency (e.g. unit tests).
  final SyncEventDispatcher? syncEventDispatcher;
  final AuditLogService? auditLogService;

  Future<Result<void>> call({
    required String voucherId,
    String? reason,
  }) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }
      final loaded = await _voucherRepository.getById(
        VoucherId(voucherId),
      );
      if (loaded.isFailure) return FailureResult(loaded.failureOrNull!);
      final v = loaded.valueOrNull!;
      final oldState = {
        'id': v.id.value,
        'receiver_status': v.receiverStatus.name,
      };
      if (!v.state.isDraft) {
        // Only drafts can be rejected in Phase-A.
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.aConfirmedOrSettled,
            code: 'voucher_reject_not_draft',
          ),
        );
      }

      final rejected = v.attachRejection(
        reason: reason ?? '',
        status: AgreementStatus.rejected,
      );

      final saved = await _voucherRepository.save(rejected);
      if (saved.isFailure) return saved;

      await auditLogService?.log(
        entityType: 'voucher',
        entityId: rejected.id.value,
        action: AuditAction.update,
        severity: AuditSeverity.warning,
        oldData: oldState,
        newData: {
          'id': rejected.id.value,
          'receiver_status': rejected.receiverStatus.name,
          'receiver_rejection_reason': rejected.rejectionReason,
        },
      );

      // §5.A — Dispatch rejection E2EE event via outbox (fire-and-forget).
      // The outbox guarantees delivery even if the network is temporarily down.
      syncEventDispatcher?.dispatchVoucherRejection(rejected).ignore();

      return saved;
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
