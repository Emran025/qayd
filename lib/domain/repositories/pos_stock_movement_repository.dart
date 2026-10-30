import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';

abstract interface class PosStockMovementRepository {
  Future<Result<PosStockBalance>> getBalance({
    required String productId,
    required String warehouseId,
  });

  Future<Result<PosStockMovement?>> getByIdempotencyKey(String key);

  Future<Result<List<PosStockMovement>>> listMovements({
    required String warehouseId,
    String? productId,
    PosStockMovementType? type,
    DateTime? fromInclusive,
    DateTime? untilExclusive,
    int limit = 100,
    int offset = 0,
  });

  Future<Result<void>> append(PosStockMovement movement);
}
