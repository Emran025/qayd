import 'package:qayd/domain/exceptions/invalid_pos_stock_exception.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/pos_stock_disposal_reason.dart';

enum PosStockMovementType {
  opening,
  purchase,
  sale,
  salesReturn,
  purchaseReturn,
  adjustment,
  damage,
  expiry,
}

enum PosStockMovementDirection { inbound, outbound }

extension PosStockMovementTypeX on PosStockMovementType {
  PosStockMovementDirection get normalDirection {
    switch (this) {
      case PosStockMovementType.opening:
      case PosStockMovementType.purchase:
      case PosStockMovementType.salesReturn:
        return PosStockMovementDirection.inbound;
      case PosStockMovementType.sale:
      case PosStockMovementType.purchaseReturn:
      case PosStockMovementType.damage:
      case PosStockMovementType.expiry:
        return PosStockMovementDirection.outbound;
      case PosStockMovementType.adjustment:
        throw InvalidPosStockException.directionRequired();
    }
  }
}

/// Immutable append-only stock movement.
///
/// Quantity is always positive in the domain. Direction is explicit and the
/// SQLite adapter maps it to the signed `quantity_scaled` column.
final class PosStockMovement {
  PosStockMovement._({
    required this.id,
    required this.productId,
    required this.warehouseId,
    required this.type,
    required this.direction,
    required this.quantity,
    required this.unitCost,
    required this.sourceType,
    required this.sourceId,
    required this.sourceLineId,
    required this.lotId,
    required this.disposalReason,
    required this.reasonDetail,
    required this.voucherId,
    required this.reversesSourceId,
    required this.occurredAt,
    required this.idempotencyKey,
    required this.createdAt,
  });

  factory PosStockMovement.create({
    required String id,
    required String productId,
    required String warehouseId,
    required PosStockMovementType type,
    PosStockMovementDirection? direction,
    required PosQuantity quantity,
    required Money unitCost,
    String? sourceType,
    String? sourceId,
    String? sourceLineId,
    String? lotId,
    PosStockDisposalReason? disposalReason,
    String? reasonDetail,
    String? voucherId,
    String? reversesSourceId,
    required DateTime occurredAt,
    required String idempotencyKey,
    DateTime? createdAt,
  }) {
    final normalizedId = id.trim();
    final normalizedProductId = productId.trim();
    final normalizedWarehouseId = warehouseId.trim();
    final normalizedIdempotencyKey = idempotencyKey.trim();
    if (normalizedId.isEmpty) throw InvalidPosStockException.idRequired();
    if (normalizedProductId.isEmpty) {
      throw InvalidPosStockException.productIdRequired();
    }
    if (normalizedWarehouseId.isEmpty) {
      throw InvalidPosStockException.warehouseIdRequired();
    }
    if (normalizedIdempotencyKey.isEmpty) {
      throw InvalidPosStockException.idempotencyKeyRequired();
    }
    if (quantity.isZero) {
      throw InvalidPosStockException.outcomeNegative();
    }
    if (unitCost.isNegative) {
      throw InvalidPosStockException.outcomeNegative();
    }
    final resolvedDirection = direction ?? type.normalDirection;
    final created = (createdAt ?? DateTime.now()).toUtc();
    return PosStockMovement._(
      id: normalizedId,
      productId: normalizedProductId,
      warehouseId: normalizedWarehouseId,
      type: type,
      direction: resolvedDirection,
      quantity: quantity,
      unitCost: unitCost,
      sourceType: sourceType?.trim(),
      sourceId: sourceId?.trim(),
      sourceLineId: sourceLineId?.trim(),
      lotId: lotId?.trim(),
      disposalReason: disposalReason,
      reasonDetail: reasonDetail?.trim().isEmpty == true
          ? null
          : reasonDetail?.trim(),
      voucherId: voucherId?.trim().isEmpty == true ? null : voucherId?.trim(),
      reversesSourceId: reversesSourceId?.trim().isEmpty == true
          ? null
          : reversesSourceId?.trim(),
      occurredAt: occurredAt.toUtc(),
      idempotencyKey: normalizedIdempotencyKey,
      createdAt: created,
    );
  }

  final String id;
  final String productId;
  final String warehouseId;
  final PosStockMovementType type;
  final PosStockMovementDirection direction;
  final PosQuantity quantity;
  final Money unitCost;
  final String? sourceType;
  final String? sourceId;
  final String? sourceLineId;
  final String? lotId;
  final PosStockDisposalReason? disposalReason;
  final String? reasonDetail;
  final String? voucherId;
  final String? reversesSourceId;
  final DateTime occurredAt;
  final String idempotencyKey;
  final DateTime createdAt;

  int get signedQuantityScaled => direction == PosStockMovementDirection.inbound
      ? quantity.scaledUnits
      : -quantity.scaledUnits;
}

/// Exact on-hand quantity and valuation after replaying stock movements.
final class PosStockBalance {
  const PosStockBalance({
    required this.quantity,
    required this.valuation,
  });

  final PosQuantity quantity;
  final Money valuation;

  Money get averageUnitCost {
    if (quantity.isZero) return Money.zero(valuation.currency);
    final scaledValuation =
        valuation.minorUnits * PosMoneyMath.scaleFactor(quantity.scale);
    return Money.fromMinorUnits(
      _roundHalfUp(scaledValuation, quantity.scaledUnits),
      valuation.currency,
    );
  }

  PosStockBalance apply(PosStockMovement movement) {
    if (movement.quantity.scale != quantity.scale) {
      throw InvalidPosStockException.scaleMismatch();
    }
    if (movement.unitCost.currency != valuation.currency) {
      throw InvalidPosStockException.currencyMismatch();
    }

    if (movement.direction == PosStockMovementDirection.inbound) {
      final addedValue =
          movement.quantity.scaledUnits * movement.unitCost.minorUnits;
      final nextQuantity = PosQuantity.fromScaled(
        quantity.scaledUnits + movement.quantity.scaledUnits,
        scale: quantity.scale,
      );
      return PosStockBalance(
        quantity: nextQuantity,
        valuation: Money.fromMinorUnits(
          valuation.minorUnits + addedValue,
          valuation.currency,
        ),
      );
    }

    if (movement.quantity.scaledUnits > quantity.scaledUnits) {
      throw InvalidPosStockException.insufficientStock();
    }
    final outgoingValue =
        PosMoneyMath.multiply(movement.quantity, averageUnitCost).minorUnits;
    final nextQuantity = PosQuantity.fromScaled(
      quantity.scaledUnits - movement.quantity.scaledUnits,
      scale: quantity.scale,
    );
    return PosStockBalance(
      quantity: nextQuantity,
      valuation: Money.fromMinorUnits(
        valuation.minorUnits - outgoingValue,
        valuation.currency,
      ),
    );
  }

  static int _roundHalfUp(int numerator, int denominator) {
    return (numerator + denominator ~/ 2) ~/ denominator;
  }
}

PosStockBalance emptyPosStockBalance({
  required CurrencyCode currency,
  required int quantityScale,
}) {
  return PosStockBalance(
    quantity: PosQuantity.fromScaled(0, scale: quantityScale),
    valuation: Money.zero(currency),
  );
}
