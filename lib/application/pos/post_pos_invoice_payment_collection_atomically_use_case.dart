import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/sync/pos_financial_outbound_event_preparer.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/pos_invoice_payment_collection_repository.dart';
import 'package:qayd/domain/repositories/pos_financial_outbound_posting_writer.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Governed application boundary for one later POS payment collection.
final class PostPosInvoicePaymentCollectionAtomicallyUseCase {
  const PostPosInvoicePaymentCollectionAtomicallyUseCase({
    required GovernanceWriteGuard writeGuard,
    required FiscalPeriodRepository fiscalPeriodRepository,
    required PosInvoicePaymentCollectionRepository postingRepository,
    this.outboundEventPreparer,
    this.outboundPostingWriter,
  }) : _writeGuard = writeGuard,
       _fiscalPeriodRepository = fiscalPeriodRepository,
       _postingRepository = postingRepository;

  final GovernanceWriteGuard _writeGuard;
  final FiscalPeriodRepository _fiscalPeriodRepository;
  final PosInvoicePaymentCollectionRepository _postingRepository;
  final PosFinancialOutboundEventPreparer? outboundEventPreparer;
  final PosFinancialOutboundPostingWriter? outboundPostingWriter;

  Future<Result<void>> call(PosInvoicePaymentCollectionPosting posting) async {
    try {
      // A previously committed exact request is a read-only recovery, not a new
      // write. Recover it before governance/period gates so retries stay safe.
      final recovered = await _postingRepository.recoverCommitted(posting);
      if (recovered.isFailure) return FailureResult(recovered.failureOrNull!);
      if (recovered.valueOrNull == true) {
        final bundle = await outboundEventPreparer?.prepareCollection(posting);
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
          return await writer.saveCollectionWithOutboundAtomically(
            posting,
            bundle,
          );
        }
        return const Success(null);
      }

      final governance = await _writeGuard.assertWritesPermitted();
      if (governance.isFailure) {
        return FailureResult(governance.failureOrNull!);
      }
      final periods = await _fiscalPeriodRepository.listAllOrdered();
      if (periods.isFailure) return FailureResult(periods.failureOrNull!);
      if (FiscalPeriodPolicy.voucherDateInClosedPeriod(
        periods.valueOrNull!,
        posting.payment.occurredAt,
      )) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posInvoiceFiscalPeriodClosed,
            code: 'pos_collection_closed_fiscal_period',
          ),
        );
      }
      final bundle = await outboundEventPreparer?.prepareCollection(posting);
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
        return await writer.saveCollectionWithOutboundAtomically(
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
