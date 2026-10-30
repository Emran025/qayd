import 'package:qayd/application/pos/build_pos_sales_return_posting_use_case.dart';
import 'package:qayd/application/pos/post_pos_sales_return_atomically_use_case.dart';
import 'package:qayd/application/pos/sign_pos_invoice_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';

/// Complete application boundary for an atomic POS sales return/full void.
final class CompletePosSalesReturnUseCase {
  const CompletePosSalesReturnUseCase({
    required BuildPosSalesReturnPostingUseCase buildPosting,
    required PostPosSalesReturnAtomicallyUseCase postAtomically,
    required SignPosInvoiceUseCase signInvoice,
  })  : _buildPosting = buildPosting,
        _postAtomically = postAtomically,
        _signInvoice = signInvoice;

  final BuildPosSalesReturnPostingUseCase _buildPosting;
  final PostPosSalesReturnAtomicallyUseCase _postAtomically;
  final SignPosInvoiceUseCase _signInvoice;

  Future<Result<PosInvoice>> call(
    BuildPosSalesReturnPostingInput input,
  ) async {
    final buildResult = await _buildPosting(input);
    if (buildResult.isFailure) {
      return FailureResult(buildResult.failureOrNull!);
    }
    final posting = buildResult.valueOrNull!;
    final signedResult = await _signInvoice(
      invoice: posting.invoice,
      payments: posting.refundPayments,
      signedAt: input.createdAt,
    );
    if (signedResult.isFailure) {
      return FailureResult(signedResult.failureOrNull!);
    }
    final signedPosting = PosSalesReturnPosting(
      invoice: signedResult.valueOrNull!,
      sourceInvoiceId: posting.sourceInvoiceId,
      salesReturnsAccountId: posting.salesReturnsAccountId,
      inventoryAccountId: posting.inventoryAccountId,
      costOfGoodsSoldAccountId: posting.costOfGoodsSoldAccountId,
      movements: posting.movements,
      postings: posting.postings,
      refundPayments: posting.refundPayments,
      voidSource: posting.voidSource,
      reason: posting.reason,
    );
    final commitResult = await _postAtomically(signedPosting);
    if (commitResult.isFailure) {
      return FailureResult(commitResult.failureOrNull!);
    }
    return Success(signedPosting.invoice);
  }
}
