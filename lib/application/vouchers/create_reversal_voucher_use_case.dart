import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/domain/entities/audit_entry.dart';


/// Creates a reversal (مرتجع) voucher linked to the original via [originVoucherId].
///
/// Protocol §3: The reversal is a new voucher with the inverse type of the
/// original, carrying the same amount and counterparty, but linked via
/// originVoucherId for the "Reply" mechanism.
///
/// Protocol §4: Settlement vouchers also use this flow — a settlement is
/// technically a follow-up to a previous pledge, linked via originVoucherId.
final class CreateReversalVoucherUseCase {
  const CreateReversalVoucherUseCase(
    this._voucherRepository,
    this._currencyRepository,
    this._idGenerator,
    this._writeGuard, {
    AuditLogService? auditLogService,
  }) : _auditLogService = auditLogService;

  final VoucherRepository _voucherRepository;
  final CurrencyRepository _currencyRepository;
  final IdGenerator _idGenerator;
  final GovernanceWriteGuard _writeGuard;
  final AuditLogService? _auditLogService;

  /// Creates a reversal of the given [originVoucherId].
  ///
  /// If [asSettlement] is true, the voucher is created as a settlement
  /// (same type as original) and the original is marked as settled.
  Future<Result<String>> call({
    required String originVoucherId,
    bool asSettlement = false,
    String? description,
  }) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }

      // Load the original voucher
      final originResult = await _voucherRepository.getById(
        VoucherId(originVoucherId),
      );
      if (originResult.isFailure) {
        return FailureResult(originResult.failureOrNull!);
      }
      final original = originResult.valueOrNull!;

      // Validate: only confirmed vouchers can be reversed/settled
      if (!original.state.isConfirmed && !asSettlement) {
        // Reversals also work on draft in some correction scenarios
        if (!original.state.isDraft) {
          return  FailureResult(
            ValidationFailure(
              messageAr: AppStrings.aReturnCannotBe,
              code: 'reversal_source_not_confirmed',
            ),
          );
        }
      }

      // Resolve currency
      final currencyResult = await _currencyRepository.getByCode(
        original.currency.code,
      );
      if (currencyResult.isFailure) {
        return FailureResult(currencyResult.failureOrNull!);
      }
      final currency = currencyResult.valueOrNull!;

      // Create the reversal/settlement voucher
      final newId = VoucherId(_idGenerator.next());

      // Reversal: inverse type. Settlement: same type as follow-up.
      final reversalType = asSettlement
          ? original.type
          : (original.type == VoucherType.receipt
              ? VoucherType.payment
              : VoucherType.receipt);

      final reversal = Voucher.draft(
        id: newId,
        type: reversalType,
        date: DateTime.now(),
        amount: Money.positiveAmount(
          original.amount.minorUnits,
          currency,
        ),
        currency: currency,
        counterpartyId: original.counterpartyId,
        affectedAccountId: original.affectedAccountId,
        createdAt: DateTime.now(),
        description: description ??
            (asSettlement
                ? 'تسوية — ردّ على سند #${original.id.value.substring(0, 8)}'
                : 'مرتجع — ردّ على سند #${original.id.value.substring(0, 8)}'),
        originVoucherId: original.id,
      );

      final saved = await _voucherRepository.save(reversal);
      if (saved.isFailure) return FailureResult(saved.failureOrNull!);
      await _auditLogService?.log(
        entityType: 'voucher',
        entityId: reversal.id.value,
        action: AuditAction.create,
        severity: AuditSeverity.info,
        newData: {
          'id': reversal.id.value,
          'origin_voucher_id': original.id.value,
          'type': reversal.type.name,
          'state': reversal.state.name,
        },
      );

      // If settlement, update the original voucher's state to settled
      if (asSettlement && original.state.isConfirmed) {
        final settled = original.settle(DateTime.now());
        await _voucherRepository.save(settled);
        await _auditLogService?.log(
          entityType: 'voucher',
          entityId: settled.id.value,
          action: AuditAction.update,
          severity: AuditSeverity.info,
          oldData: {'id': original.id.value, 'state': original.state.name},
          newData: {'id': settled.id.value, 'state': settled.state.name},
        );
      }

      return Success(newId.value);
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
