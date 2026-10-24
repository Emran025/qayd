import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_product_category.dart';
import 'package:qayd/domain/repositories/pos_product_category_repository.dart';

final class CreatePosProductCategoryInput {
  const CreatePosProductCategoryInput({
    required this.name,
    required this.code,
    this.parentId,
  });

  final String name;
  final String code;
  final String? parentId;
}

final class CreatePosProductCategoryUseCase {
  const CreatePosProductCategoryUseCase(
    this._repository,
    this._writeGuard,
    this._idGenerator,
  );

  final PosProductCategoryRepository _repository;
  final GovernanceWriteGuard _writeGuard;
  final IdGenerator _idGenerator;

  Future<Result<PosProductCategory>> call(
    CreatePosProductCategoryInput input,
  ) async {
    final gate = await _writeGuard.assertWritesPermitted();
    if (gate.isFailure) return FailureResult(gate.failureOrNull!);
    try {
      final category = PosProductCategory.create(
        id: _idGenerator.next(),
        name: input.name,
        code: input.code,
        parentId: input.parentId,
      );
      final saved = await _repository.save(category);
      if (saved.isFailure) return FailureResult(saved.failureOrNull!);
      return Success(category);
    } catch (error) {
      return FailureResult(
        // The repository/application boundary already localizes persistence
        // failures; malformed category input is returned as a validation error.
        const ValidationFailure(messageAr: 'بيانات التصنيف غير صالحة.'),
      );
    }
  }
}
