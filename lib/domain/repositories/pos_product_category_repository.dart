import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_product_category.dart';

abstract interface class PosProductCategoryRepository {
  Future<Result<List<PosProductCategory>>> list({bool activeOnly = true});
  Future<Result<void>> save(PosProductCategory category);
  Future<Result<void>> deactivate(String id);
}
