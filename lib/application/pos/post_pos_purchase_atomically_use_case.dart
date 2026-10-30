import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_purchase_posting.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/pos_purchase_posting_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Governed application boundary for posting a complete POS purchase.
final class PostPosPurchaseAtomicallyUseCase {
  const PostPosPurchaseAtomicallyUseCase({
    required GovernanceWriteGuard writeGuard,
    required FiscalPeriodRepository fiscalPeriodRepository,
    required PosPurchasePostingRepository postingRepository,
  })  : _writeGuard = writeGuard,
        _fiscalPeriodRepository = fiscalPeriodRepository,
        _postingRepository = postingRepository;

  final GovernanceWriteGuard _writeGuard;
  final FiscalPeriodRepository _fiscalPeriodRepository;
  final PosPurchasePostingRepository _postingRepository;

  Future<Result<void>> call(PosPurchasePosting posting) async {
    try {
      final governance = await _writeGuard.assertWritesPermitted();
      if (governance.isFailure) {
        return FailureResult(governance.failureOrNull!);
      }

      final status = posting.invoice.status;
      if (!status.isPosted && !status.isPaid && status.name != 'partiallyPaid') {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posInvoiceInvalid,
            code: 'pos_purchase_not_posted',
          ),
        );
      }
      final periods = await _fiscalPeriodRepository.listAllOrdered();
      if (periods.isFailure) {
        return FailureResult(periods.failureOrNull!);
      }
      if (FiscalPeriodPolicy.voucherDateInClosedPeriod(
        periods.valueOrNull!,
        posting.invoice.invoiceDate,
      )) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posInvoiceFiscalPeriodClosed,
            code: 'pos_purchase_closed_fiscal_period',
          ),
        );
      }
      return await _postingRepository.saveAtomically(posting);
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }
}
