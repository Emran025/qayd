import 'package:qayd/application/pos/build_pos_purchase_posting_use_case.dart';
import 'package:qayd/application/pos/post_pos_purchase_atomically_use_case.dart';
import 'package:qayd/application/pos/sign_pos_invoice_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_purchase_posting.dart';

/// Complete application boundary for POS purchase receiving.
///
/// The purchase is fully built and signed before the governed atomic writer is
/// called; no stock-only write is exposed by this flow.
final class CompletePosPurchaseUseCase {
  const CompletePosPurchaseUseCase({
    required BuildPosPurchasePostingUseCase buildPosting,
    required PostPosPurchaseAtomicallyUseCase postAtomically,
    required SignPosInvoiceUseCase signInvoice,
  })  : _buildPosting = buildPosting,
        _postAtomically = postAtomically,
        _signInvoice = signInvoice;

  final BuildPosPurchasePostingUseCase _buildPosting;
  final PostPosPurchaseAtomicallyUseCase _postAtomically;
  final SignPosInvoiceUseCase _signInvoice;

  Future<Result<PosInvoice>> call(BuildPosPurchasePostingInput input) async {
    final buildResult = await _buildPosting(input);
    if (buildResult.isFailure) {
      return FailureResult(buildResult.failureOrNull!);
    }
    final posting = buildResult.valueOrNull!;
    final signedResult = await _signInvoice(
      invoice: posting.invoice,
      payments: posting.payments,
      signedAt: input.createdAt,
    );
    if (signedResult.isFailure) {
      return FailureResult(signedResult.failureOrNull!);
    }
    final signedPosting = PosPurchasePosting(
      invoice: signedResult.valueOrNull!,
      movements: posting.movements,
      postings: posting.postings,
      payments: posting.payments,
    );
    final commitResult = await _postAtomically(signedPosting);
    if (commitResult.isFailure) {
      return FailureResult(commitResult.failureOrNull!);
    }
    return Success(signedPosting.invoice);
  }
}
