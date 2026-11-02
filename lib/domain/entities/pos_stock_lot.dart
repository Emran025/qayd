import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

/// Immutable description of a physical stock lot.
///
/// [remainingQuantity] is a persisted projection of append-only stock
/// movements; it is never authoritative and must reconcile with their replay.
final class PosStockLot {
  const PosStockLot._({
    required this.id,
    required this.productId,
    required this.warehouseId,
    required this.supplierLotNumber,
    required this.expiryDate,
    required this.receivedQuantity,
    required this.remainingQuantity,
    required this.unitCost,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PosStockLot.create({
    required String id,
    required String productId,
    required String warehouseId,
    required PosDate expiryDate,
    String? supplierLotNumber,
    required PosQuantity receivedQuantity,
    required Money unitCost,
    DateTime? createdAt,
  }) {
    final normalizedId = id.trim();
    final normalizedProductId = productId.trim();
    final normalizedWarehouseId = warehouseId.trim();
    if (normalizedId.isEmpty ||
        normalizedProductId.isEmpty ||
        normalizedWarehouseId.isEmpty ||
        !receivedQuantity.isPositive ||
        unitCost.isNegative) {
      throw ArgumentError('Invalid POS stock lot');
    }
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    final supplierNumber = supplierLotNumber?.trim();
    return PosStockLot._(
      id: normalizedId,
      productId: normalizedProductId,
      warehouseId: normalizedWarehouseId,
      supplierLotNumber: supplierNumber == null || supplierNumber.isEmpty
          ? null
          : supplierNumber,
      expiryDate: expiryDate,
      receivedQuantity: receivedQuantity,
      remainingQuantity: PosQuantity.fromScaled(
        0,
        scale: receivedQuantity.scale,
      ),
      unitCost: unitCost,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  /// Rehydrates historical rows. Missing expiry dates remain unknown; they are
  /// never inferred or backfilled.
  factory PosStockLot.restore({
    required String id,
    required String productId,
    required String warehouseId,
    required String? supplierLotNumber,
    required PosDate? expiryDate,
    required PosQuantity receivedQuantity,
    required PosQuantity remainingQuantity,
    required Money unitCost,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    if (id.trim().isEmpty ||
        productId.trim().isEmpty ||
        warehouseId.trim().isEmpty ||
        receivedQuantity.scale != remainingQuantity.scale ||
        receivedQuantity.scaledUnits <= 0 ||
        remainingQuantity.scaledUnits < 0 ||
        remainingQuantity.scaledUnits > receivedQuantity.scaledUnits ||
        unitCost.isNegative) {
      throw ArgumentError('Invalid persisted POS stock lot');
    }
    final supplierNumber = supplierLotNumber?.trim();
    return PosStockLot._(
      id: id.trim(),
      productId: productId.trim(),
      warehouseId: warehouseId.trim(),
      supplierLotNumber: supplierNumber == null || supplierNumber.isEmpty
          ? null
          : supplierNumber,
      expiryDate: expiryDate,
      receivedQuantity: receivedQuantity,
      remainingQuantity: remainingQuantity,
      unitCost: unitCost,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
  }

  final String id;
  final String productId;
  final String warehouseId;
  final String? supplierLotNumber;
  final PosDate? expiryDate;
  final PosQuantity receivedQuantity;
  final PosQuantity remainingQuantity;
  final Money unitCost;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool hasSameImmutableData(PosStockLot other) =>
      id == other.id &&
      productId == other.productId &&
      warehouseId == other.warehouseId &&
      supplierLotNumber == other.supplierLotNumber &&
      expiryDate == other.expiryDate &&
      receivedQuantity == other.receivedQuantity &&
      unitCost == other.unitCost;
}
