import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class RecordPosStockMovementInput {
  const RecordPosStockMovementInput({
    required this.productId,
    required this.warehouseId,
    required this.type,
    required this.direction,
    required this.quantityScaled,
    required this.quantityScale,
    required this.unitCostMinor,
    required this.currencyCode,
    required this.idempotencyKey,
    this.sourceType,
    this.sourceId,
    this.sourceLineId,
    this.lotId,
    this.occurredAt,
  });

  final String productId;
  final String warehouseId;
  final PosStockMovementType type;
  final PosStockMovementDirection direction;
  final int quantityScaled;
  final int quantityScale;
  final int unitCostMinor;
  final String currencyCode;
  final String idempotencyKey;
  final String? sourceType;
  final String? sourceId;
  final String? sourceLineId;
  final String? lotId;
  final DateTime? occurredAt;
}

final class RecordPosStockMovementUseCase {
  RecordPosStockMovementUseCase(
    this._repository,
    this._productRepository,
    this._writeGuard,
    this._idGenerator,
  );

  final PosStockMovementRepository _repository;
  final PosProductRepository _productRepository;
  final GovernanceWriteGuard _writeGuard;
  final IdGenerator _idGenerator;

  Future<Result<void>> call(RecordPosStockMovementInput input) async {
    if (input.type == PosStockMovementType.damage ||
        input.type == PosStockMovementType.expiry) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockDisposalAtomicRequired),
      );
    }
    final gate = await _writeGuard.assertWritesPermitted();
    if (gate.isFailure) return FailureResult(gate.failureOrNull!);

    final productResult =
        await _productRepository.getById(input.productId.trim());
    if (productResult.isFailure) {
      return FailureResult(productResult.failureOrNull!);
    }
    final product = productResult.valueOrNull!;
    if (!product.isActive) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockProductInactive),
      );
    }
    if (input.currencyCode.trim() != product.currency.code) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockCurrencyMismatch),
      );
    }
    if (input.quantityScale != product.quantityScale) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posStockScaleMismatch),
      );
    }

    try {
      final movement = PosStockMovement.create(
        id: _idGenerator.next(),
        productId: product.id,
        warehouseId: input.warehouseId,
        type: input.type,
        direction: input.direction,
        quantity: PosQuantity.positive(
          input.quantityScaled,
          scale: input.quantityScale,
        ),
        unitCost: Money.nonNegative(input.unitCostMinor, product.currency),
        sourceType: input.sourceType,
        sourceId: input.sourceId,
        sourceLineId: input.sourceLineId,
        lotId: input.lotId,
        occurredAt: input.occurredAt ?? DateTime.now().toUtc(),
        idempotencyKey: input.idempotencyKey,
      );
      return await _repository.append(movement);
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }
}
