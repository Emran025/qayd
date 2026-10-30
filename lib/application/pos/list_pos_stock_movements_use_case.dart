import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';

final class ListPosStockMovementsInput {
  const ListPosStockMovementsInput({
    required this.warehouseId,
    this.productId,
    this.type,
    this.fromInclusive,
    this.untilExclusive,
    this.limit = 100,
    this.offset = 0,
  });

  final String warehouseId;
  final String? productId;
  final PosStockMovementType? type;
  final DateTime? fromInclusive;
  final DateTime? untilExclusive;
  final int limit;
  final int offset;
}

final class ListPosStockMovementsUseCase {
  ListPosStockMovementsUseCase(this._repository);

  final PosStockMovementRepository _repository;

  Future<Result<List<PosStockMovement>>> call(
    ListPosStockMovementsInput input,
  ) {
    return _repository.listMovements(
      warehouseId: input.warehouseId,
      productId: input.productId,
      type: input.type,
      fromInclusive: input.fromInclusive,
      untilExclusive: input.untilExclusive,
      limit: input.limit,
      offset: input.offset,
    );
  }
}
