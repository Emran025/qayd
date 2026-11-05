import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/sync/pos_financial_outbound_event_preparer.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/pos_sale_posting_repository.dart';
import 'package:qayd/domain/repositories/pos_financial_outbound_posting_writer.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Governed application boundary for posting a complete POS sale.
///
/// The payload is built before this use case is called. This layer only applies
/// cross-cutting write policies and delegates the complete write to the atomic
/// repository. It never touches SQL or ledger tables.
final class PostPosSaleAtomicallyUseCase {
  const PostPosSaleAtomicallyUseCase({
    required GovernanceWriteGuard writeGuard,
    required FiscalPeriodRepository fiscalPeriodRepository,
    required PosSalePostingRepository postingRepository,
    this.outboundEventPreparer,
    this.outboundPostingWriter,
  }) : _writeGuard = writeGuard,
       _fiscalPeriodRepository = fiscalPeriodRepository,
       _postingRepository = postingRepository;

  final GovernanceWriteGuard _writeGuard;
  final FiscalPeriodRepository _fiscalPeriodRepository;
  final PosSalePostingRepository _postingRepository;
  final PosFinancialOutboundEventPreparer? outboundEventPreparer;
  final PosFinancialOutboundPostingWriter? outboundPostingWriter;

  Future<Result<void>> call(PosSalePosting posting) async {
    try {
      final governance = await _writeGuard.assertWritesPermitted();
      if (governance.isFailure) return FailureResult(governance.failureOrNull!);

      if (!posting.invoice.status.isPosted && !posting.invoice.status.isPaid) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posInvoiceNotPosted,
            code: 'pos_sale_not_posted',
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
            code: 'pos_sale_closed_fiscal_period',
          ),
        );
      }
      final bundle = await outboundEventPreparer?.prepareSale(posting);
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
        return await writer.saveSaleWithOutboundAtomically(posting, bundle);
      }
      return await _postingRepository.saveAtomically(posting);
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }
}
