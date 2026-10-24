import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_product_category.dart';
import 'package:qayd/domain/repositories/pos_product_category_repository.dart';

final class ListPosProductCategoriesUseCase {
  const ListPosProductCategoriesUseCase(this._repository);
  final PosProductCategoryRepository _repository;

  Future<Result<List<PosProductCategory>>> call({bool activeOnly = true}) {
    return _repository.list(activeOnly: activeOnly);
  }
}
