import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';

/// Persistence port for an atomic POS stock-and-accounting posting.
abstract interface class PosAccountingPostingRepository {
  Future<Result<void>> saveOpeningBalance({
    required PosStockMovement movement,
    required PosAccountingPosting posting,
  });

  Future<Result<void>> saveStockAdjustmentAtomically({
    required PosStockMovement movement,
    required PosAccountingPosting posting,
  });
}
