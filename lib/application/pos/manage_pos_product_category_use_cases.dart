import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_product_category.dart';
import 'package:qayd/domain/repositories/pos_product_category_repository.dart';

final class SavePosProductCategoryUseCase {
  SavePosProductCategoryUseCase(this._repository, this._guard);
  final PosProductCategoryRepository _repository;
  final GovernanceWriteGuard _guard;
  Future<Result<void>> call(PosProductCategory category) async {
    final gate = await _guard.assertWritesPermitted();
    if (gate.isFailure) return FailureResult(gate.failureOrNull!);
    return _repository.save(category);
  }
}

final class DeactivatePosProductCategoryUseCase {
  DeactivatePosProductCategoryUseCase(this._repository, this._guard);
  final PosProductCategoryRepository _repository;
  final GovernanceWriteGuard _guard;
  Future<Result<void>> call(String id) async {
    final gate = await _guard.assertWritesPermitted();
    if (gate.isFailure) return FailureResult(gate.failureOrNull!);
    return _repository.deactivate(id);
  }
}

final class ReactivatePosProductCategoryUseCase {
  ReactivatePosProductCategoryUseCase(this._repository, this._guard);
  final PosProductCategoryRepository _repository;
  final GovernanceWriteGuard _guard;
  Future<Result<void>> call(PosProductCategory category) async {
    final gate = await _guard.assertWritesPermitted();
    if (gate.isFailure) return FailureResult(gate.failureOrNull!);
    return _repository.save(category.activate());
  }
}
