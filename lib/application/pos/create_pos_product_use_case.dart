import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_barcode.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class CreatePosProductInput {
  const CreatePosProductInput({
    required this.sku,
    required this.name,
    required this.currencyCode,
    required this.salePriceMinor,
    required this.purchasePriceMinor,
    this.quantityScale = 0,
    this.reorderLevelScaled = 0,
    this.expiryTracking = false,
    this.barcodes = const <String>[],
    this.description,
    this.categoryId,
    this.unitName = 'unit',
  });

  final String sku;
  final String name;
  final String currencyCode;
  final int salePriceMinor;
  final int purchasePriceMinor;
  final int quantityScale;
  final int reorderLevelScaled;
  final bool expiryTracking;
  final List<String> barcodes;
  final String? description;
  final String? categoryId;
  final String unitName;
}

final class CreatePosProductUseCase {
  CreatePosProductUseCase(
    this._repository,
    this._currencyRepository,
    this._writeGuard,
    this._idGenerator,
  );

  final PosProductRepository _repository;
  final CurrencyRepository _currencyRepository;
  final GovernanceWriteGuard _writeGuard;
  final IdGenerator _idGenerator;

  Future<Result<void>> call(CreatePosProductInput input) async {
    final gate = await _writeGuard.assertWritesPermitted();
    if (gate.isFailure) return FailureResult(gate.failureOrNull!);

    final currencyResult = await _currencyRepository.getByCode(
      input.currencyCode.trim(),
    );
    if (currencyResult.isFailure) {
      return FailureResult(currencyResult.failureOrNull!);
    }
    final currency = currencyResult.valueOrNull;
    if (currency == null) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posProductCurrencyNotFound),
      );
    }

    try {
      final product = PosProduct.create(
        id: _idGenerator.next(),
        sku: input.sku,
        name: input.name,
        currency: currency,
        salePrice: Money.nonNegative(input.salePriceMinor, currency),
        purchasePrice: Money.nonNegative(input.purchasePriceMinor, currency),
        quantityScale: input.quantityScale,
        reorderLevel: PosQuantity.fromScaled(
          input.reorderLevelScaled,
          scale: input.quantityScale,
        ),
        expiryTracking: input.expiryTracking,
        barcodes: input.barcodes
            .map(PosBarcode.new)
            .toList(growable: false),
        description: input.description,
        categoryId: input.categoryId,
        unitName: input.unitName,
      );
      return await _repository.save(product);
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }
}
