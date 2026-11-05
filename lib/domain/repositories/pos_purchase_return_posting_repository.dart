import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_purchase_return_posting.dart';

/// Atomic persistence boundary for a supplier purchase-return credit note.
abstract interface class PosPurchaseReturnPostingRepository {
  Future<Result<void>> saveAtomically(PosPurchaseReturnPosting posting);
}
