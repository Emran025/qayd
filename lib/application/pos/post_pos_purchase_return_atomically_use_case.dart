import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/sync/pos_financial_outbound_event_preparer.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_purchase_return_posting.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/pos_financial_outbound_posting_writer.dart';
import 'package:qayd/domain/repositories/pos_purchase_return_posting_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Governed application boundary for atomic purchase-return posting.
final class PostPosPurchaseReturnAtomicallyUseCase {
  const PostPosPurchaseReturnAtomicallyUseCase({
    required GovernanceWriteGuard writeGuard,
    required FiscalPeriodRepository fiscalPeriodRepository,
    required PosPurchaseReturnPostingRepository postingRepository,
    this.outboundEventPreparer,
    this.outboundPostingWriter,
  }) : _writeGuard = writeGuard,
       _fiscalPeriodRepository = fiscalPeriodRepository,
       _postingRepository = postingRepository;

  final GovernanceWriteGuard _writeGuard;
  final FiscalPeriodRepository _fiscalPeriodRepository;
  final PosPurchaseReturnPostingRepository _postingRepository;
  final PosFinancialOutboundEventPreparer? outboundEventPreparer;
  final PosFinancialOutboundPostingWriter? outboundPostingWriter;

  Future<Result<void>> call(PosPurchaseReturnPosting posting) async {
    try {
      final governance = await _writeGuard.assertWritesPermitted();
      if (governance.isFailure) return FailureResult(governance.failureOrNull!);
      if (posting.invoice.type != PosInvoiceType.purchaseReturn ||
          !posting.invoice.status.isPosted ||
          posting.invoice.paid.minorUnits != 0 ||
          posting.invoice.due.minorUnits != posting.invoice.total.minorUnits) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posInvoiceNotPosted,
            code: 'pos_purchase_return_not_posted',
          ),
        );
      }
      final periods = await _fiscalPeriodRepository.listAllOrdered();
      if (periods.isFailure) return FailureResult(periods.failureOrNull!);
      if (FiscalPeriodPolicy.voucherDateInClosedPeriod(
        periods.valueOrNull!,
        posting.invoice.invoiceDate,
      )) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posInvoiceFiscalPeriodClosed,
            code: 'pos_purchase_return_closed_fiscal_period',
          ),
        );
      }
      final bundle = await outboundEventPreparer?.preparePurchaseReturn(
        posting,
      );
      if (bundle != null) {
        final writer = outboundPostingWriter;
        if (writer == null) {
          return FailureResult(
            ValidationFailure(
              messageAr: AppStrings.posInvoiceInvalid,
              code: 'pos_financial_outbound_writer_unavailable',
            ),
          );
        }
        return await writer.savePurchaseReturnWithOutboundAtomically(
          posting,
          bundle,
        );
      }
      return await _postingRepository.saveAtomically(posting);
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }
}
