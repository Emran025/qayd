import 'package:qayd/application/pos/build_pos_purchase_return_posting_use_case.dart';
import 'package:qayd/application/pos/post_pos_purchase_return_atomically_use_case.dart';
import 'package:qayd/application/pos/sign_pos_invoice_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_purchase_return_posting.dart';

/// Application entry point for building and committing a purchase return.
final class CompletePosPurchaseReturnUseCase {
  const CompletePosPurchaseReturnUseCase({
    required BuildPosPurchaseReturnPostingUseCase buildPosting,
    required PostPosPurchaseReturnAtomicallyUseCase postAtomically,
    required SignPosInvoiceUseCase signInvoice,
  }) : _buildPosting = buildPosting,
       _postAtomically = postAtomically,
       _signInvoice = signInvoice;

  final BuildPosPurchaseReturnPostingUseCase _buildPosting;
  final PostPosPurchaseReturnAtomicallyUseCase _postAtomically;
  final SignPosInvoiceUseCase _signInvoice;

  Future<Result<PosInvoice>> call(
    BuildPosPurchaseReturnPostingInput input,
  ) async {
    final build = await _buildPosting(input);
    if (build.isFailure) return FailureResult(build.failureOrNull!);
    final posting = build.valueOrNull!;
    final signed = await _signInvoice(
      invoice: posting.invoice,
      payments: const [],
      signedAt: input.createdAt,
    );
    if (signed.isFailure) return FailureResult(signed.failureOrNull!);
    final signedPosting = PosPurchaseReturnPosting(
      invoice: signed.valueOrNull!,
      sourceInvoiceId: posting.sourceInvoiceId,
      supplierPayablesAccountId: posting.supplierPayablesAccountId,
      inventoryAccountId: posting.inventoryAccountId,
      purchaseReturnsAccountId: posting.purchaseReturnsAccountId,
      movements: posting.movements,
      postings: posting.postings,
      reason: posting.reason,
    );
    final save = await _postAtomically(signedPosting);
    if (save.isFailure) return FailureResult(save.failureOrNull!);
    return Success(signedPosting.invoice);
  }
}
