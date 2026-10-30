import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_purchase_posting.dart';

abstract interface class PosPurchasePostingRepository {
  Future<Result<void>> saveAtomically(PosPurchasePosting posting);
}
