import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';
/// Atomic persistence boundary for a complete sales return or full void.
abstract interface class PosSalesReturnPostingRepository {
  Future<Result<void>> saveAtomically(PosSalesReturnPosting posting);
}
