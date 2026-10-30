import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';

final class ReactivatePosProductUseCase {
  ReactivatePosProductUseCase(this._repository, this._guard);
  final PosProductRepository _repository;
  final GovernanceWriteGuard _guard;
  Future<Result<void>> call(String id) async {
    final gate = await _guard.assertWritesPermitted();
    if (gate.isFailure) return FailureResult(gate.failureOrNull!);
    final current = await _repository.getById(id);
    if (current.isFailure) return FailureResult(current.failureOrNull!);
    return _repository.save(current.valueOrNull!.activate());
  }
}
