import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_stock_lot.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';

final class ListPosStockDisposalLotsUseCase {
  const ListPosStockDisposalLotsUseCase(this._repository);

  final PosStockMovementRepository _repository;

  Future<Result<List<PosStockLot>>> call({
    required String productId,
    required String warehouseId,
  }) {
    return _repository.getDisposalLots(
      productId: productId,
      warehouseId: warehouseId,
    );
  }
}
