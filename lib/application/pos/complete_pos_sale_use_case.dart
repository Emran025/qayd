import 'package:qayd/application/pos/build_pos_sale_posting_use_case.dart';
import 'package:qayd/application/pos/post_pos_sale_atomically_use_case.dart';
import 'package:qayd/application/pos/sign_pos_invoice_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/entities/pos_discount_rule.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';

/// Complete application boundary for a POS sale.
///
/// It deliberately builds the complete immutable payload before invoking the
/// governed atomic writer. A failure in either stage leaves no partial UI-side
/// promise that a sale was committed.
final class CompletePosSaleUseCase {
  const CompletePosSaleUseCase({
    required BuildPosSalePostingUseCase buildPosting,
    required PostPosSaleAtomicallyUseCase postAtomically,
    required SignPosInvoiceUseCase signInvoice,
  }) : _buildPosting = buildPosting,
       _postAtomically = postAtomically,
       _signInvoice = signInvoice;

  final BuildPosSalePostingUseCase _buildPosting;
  final PostPosSaleAtomicallyUseCase _postAtomically;
  final SignPosInvoiceUseCase _signInvoice;

  Future<Result<PosInvoice>> call({
    required String invoiceId,
    required String invoiceNumber,
    required String warehouseId,
    required CurrencyCode currency,
    required List<BuildPosSaleLineInput> lines,
    required String idempotencyKey,
    required DateTime invoiceDate,
    required DateTime createdAt,
    AccountId? customerAccountId,
    PosSaleSettlementInput? settlement,
    PosDiscountRule? cartDiscountRule,
    DateTime? creditDueDate,
    String? creditTerms,
    bool cashSale = true,
  }) async {
    final buildResult = await _buildPosting(
      BuildPosSalePostingInput(
        invoiceId: invoiceId,
        invoiceNumber: invoiceNumber,
        warehouseId: warehouseId,
        currency: currency,
        lines: lines,
        idempotencyKey: idempotencyKey,
        invoiceDate: invoiceDate,
        createdAt: createdAt,
        customerAccountId: customerAccountId,
        settlement: settlement,
        cartDiscountRule: cartDiscountRule,
        creditDueDate: creditDueDate,
        creditTerms: creditTerms,
        cashSale: cashSale,
      ),
    );
    if (buildResult.isFailure) {
      return FailureResult(buildResult.failureOrNull!);
    }
    final posting = buildResult.valueOrNull!;
    final signedResult = await _signInvoice(
      invoice: posting.invoice,
      payments: posting.payments,
      signedAt: createdAt,
    );
    if (signedResult.isFailure) {
      return FailureResult(signedResult.failureOrNull!);
    }
    final signedPosting = PosSalePosting(
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
