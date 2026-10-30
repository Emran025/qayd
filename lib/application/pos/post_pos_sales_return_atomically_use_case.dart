import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/pos_sales_return_posting_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Governed application boundary for an atomic sales return/full void.
final class PostPosSalesReturnAtomicallyUseCase {
  const PostPosSalesReturnAtomicallyUseCase({
    required GovernanceWriteGuard writeGuard,
    required FiscalPeriodRepository fiscalPeriodRepository,
    required PosSalesReturnPostingRepository postingRepository,
  })  : _writeGuard = writeGuard,
        _fiscalPeriodRepository = fiscalPeriodRepository,
        _postingRepository = postingRepository;

  final GovernanceWriteGuard _writeGuard;
  final FiscalPeriodRepository _fiscalPeriodRepository;
  final PosSalesReturnPostingRepository _postingRepository;

  Future<Result<void>> call(PosSalesReturnPosting posting) async {
    final governance = await _writeGuard.assertWritesPermitted();
    if (governance.isFailure) return FailureResult(governance.failureOrNull!);

    if (posting.invoice.type != PosInvoiceType.salesReturn ||
        !posting.invoice.status.isPaid) {
      return FailureResult(
        ValidationFailure(
          messageAr: AppStrings.posInvoiceNotPosted,
          code: 'pos_sales_return_not_posted',
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
          code: 'pos_sales_return_closed_fiscal_period',
        ),
      );
    }
    return _postingRepository.saveAtomically(posting);
  }
}
