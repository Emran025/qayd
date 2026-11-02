import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_stock_lot.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';

abstract interface class PosStockMovementRepository {
  Future<Result<PosStockBalance>> getBalance({
    required String productId,
    required String warehouseId,
  });

  Future<Result<PosStockMovement?>> getByIdempotencyKey(String key);

  /// Returns reconciled, non-empty lots that are valid through [businessDate],
  /// ordered by FEFO with a deterministic tie-break.
  Future<Result<List<PosStockLot>>> getSellableLots({
    required String productId,
    required String warehouseId,
    required PosDate businessDate,
  });

  /// Reads the immutable allocation movements associated with a source
  /// document. This is used to route sales returns back to their original lots.
  Future<Result<List<PosStockMovement>>> listMovementsForSource({
    required String sourceType,
    required String sourceId,
    PosStockMovementType? type,
  });

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
