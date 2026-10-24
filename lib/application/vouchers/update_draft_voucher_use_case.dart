import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/vouchers/dtos/update_draft_voucher_input.dart';
import 'package:qayd/application/vouchers/dtos/update_draft_voucher_output.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/domain/entities/audit_entry.dart';

class UpdateDraftVoucherUseCase {
  UpdateDraftVoucherUseCase(
    this._voucherRepository,
    this._currencyRepository,
    this._writeGuard,
    this._fiscalPeriodRepository, {
    AuditLogService? auditLogService,
  }) : _auditLogService = auditLogService;

  final VoucherRepository _voucherRepository;
  final CurrencyRepository _currencyRepository;
  final GovernanceWriteGuard _writeGuard;
  final FiscalPeriodRepository _fiscalPeriodRepository;
  final AuditLogService? _auditLogService;

  Future<Result<UpdateDraftVoucherOutput>> call(
      UpdateDraftVoucherInput input) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }
      final loaded =
          await _voucherRepository.getById(VoucherId(input.voucherId));
      if (loaded.isFailure) {
        return FailureResult(loaded.failureOrNull!);
      }
      final current = loaded.valueOrNull!;
      final oldState = {
        'id': current.id.value,
        'amount_minor': current.amount.minorUnits,
        'description': current.description,
      };

      CurrencyCode? currency;
      if (input.currencyCode != null) {
        final currencyRes =
            await _currencyRepository.getByCode(input.currencyCode!);
        if (currencyRes.isFailure || currencyRes.valueOrNull == null) {
          return FailureResult(ValidationFailure(
            messageAr: AppStrings.theSelectedCurrencyIs,
            code: 'invalid_currency',
          ));
        }
        currency = currencyRes.valueOrNull!;
      }

      Money? amount;
      if (input.amountMinorUnits != null) {
        // Use either the new currency or the current voucher's currency
        final activeCurrency = currency ?? current.currency;
        amount = Money.positiveAmount(input.amountMinorUnits!, activeCurrency);
      }

      final nextDate = input.date ?? current.date;
      final periodsR = await _fiscalPeriodRepository.listAllOrdered();
      if (periodsR.isSuccess &&
          FiscalPeriodPolicy.voucherDateInClosedPeriod(
            periodsR.valueOrNull!,
            nextDate,
          )) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.voucherDateInClosedPeriod,
            code: 'voucher_closed_period',
          ),
        );
      }

      final updated = current.updateDraft(
        type: input.type,
        date: input.date,
        amount: amount,
        currency: currency,
        counterpartyId: input.counterpartyAccountId != null
            ? AccountId(input.counterpartyAccountId!)
            : null,
        affectedAccountId: input.affectedAccountId != null
            ? AccountId(input.affectedAccountId!)
            : null,
        referenceNumber: input.referenceNumber,
        description: input.description,
        notes: input.notes,
      );
      final saved = await _voucherRepository.save(updated);
      if (saved.isSuccess) {
        await _auditLogService?.log(
          entityType: 'voucher',
          entityId: updated.id.value,
          action: AuditAction.update,
          severity: AuditSeverity.info,
          oldData: oldState,
          newData: {
            'id': updated.id.value,
            'amount_minor': updated.amount.minorUnits,
            'description': updated.description,
          },
        );
      }
      return await saved.fold(
        (f) => FailureResult(f),
        (_) => Success(
          UpdateDraftVoucherOutput(
            voucherId: updated.id.value,
            stateCode: updated.state.name,
          ),
        ),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
