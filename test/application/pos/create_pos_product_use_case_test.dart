import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/governance/check_governance_status_use_case.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/create_pos_product_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/governance_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/governance_status.dart';
import 'package:qayd/domain/value_objects/pos_barcode.dart';
import 'package:qayd/domain/value_objects/submit_activation_request.dart';

final class _IdGenerator implements IdGenerator {
  @override
  String next() => 'product-generated';
}

final class _GovernanceRepo implements GovernanceRepository {
  _GovernanceRepo(this.status);

  final GovernanceStatus status;

  @override
  Future<Result<GovernanceStatus>> getStatus({bool forceRefresh = false}) async =>
      Success(status);

  @override
  Future<Result<void>> submitActivation(SubmitActivationRequest request) async =>
      const Success(null);
}

final class _CurrencyRepo implements CurrencyRepository {
  _CurrencyRepo(this.currency);

  final CurrencyCode currency;

  @override
  Future<Result<CurrencyCode?>> getByCode(String code) async =>
      Success(code == currency.code ? currency : null);

  @override
  Future<Result<List<CurrencyCode>>> getAll({bool onlyActive = false}) async =>
      Success([currency]);

  @override
  Future<Result<void>> save(CurrencyCode currency, {bool isPredefined = false}) async =>
      const Success(null);

  @override
  Future<Result<void>> toggleActiveStatus(String code, bool isActive) async =>
      const Success(null);

  @override
  Future<Result<String>> getBaseCurrencyCode() async => Success(currency.code);

  @override
  Future<Result<void>> setBaseCurrencyCode(String code) async => const Success(null);
}

final class _ProductRepo implements PosProductRepository {
  PosProduct? saved;

  @override
  Future<Result<PosProduct>> getById(String id) async => throw UnimplementedError();

  @override
  Future<Result<PosProduct?>> getByBarcode(PosBarcode barcode) async =>
      const Success(null);

  @override
  Future<Result<List<PosProduct>>> list({
    bool activeOnly = true,
    String? search,
  }) async => const Success([]);

  @override
  Future<Result<void>> save(PosProduct product) async {
    saved = product;
    return const Success(null);
  }

  @override
  Future<Result<void>> deactivate(String id) async => const Success(null);
}

CreatePosProductUseCase _useCase({
  required _ProductRepo productRepo,
  required CurrencyCode currency,
  GovernanceStatus status = GovernanceStatus.activated,
}) {
  return CreatePosProductUseCase(
    productRepo,
    _CurrencyRepo(currency),
    GovernanceWriteGuard(
      CheckGovernanceStatusUseCase(_GovernanceRepo(status)),
    ),
    _IdGenerator(),
  );
}

void main() {
  final sar = CurrencyCode(code: 'SAR', nameAr: 'ريال', symbol: 'ر.س');

  group('CreatePosProductUseCase', () {
    test('creates and saves a product from validated input', () async {
      final repository = _ProductRepo();
      final useCase = _useCase(productRepo: repository, currency: sar);

      final result = await useCase(
        const CreatePosProductInput(
          sku: 'SKU-1',
          name: 'Coffee',
          currencyCode: 'SAR',
          salePriceMinor: 1500,
          purchasePriceMinor: 900,
          quantityScale: 3,
          reorderLevelScaled: 1250,
          barcodes: ['12345'],
          expiryTracking: true,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(repository.saved!.id, 'product-generated');
      expect(repository.saved!.salePrice.minorUnits, 1500);
      expect(repository.saved!.reorderLevel.toExactString(), '1.25');
      expect(repository.saved!.barcodes.single.value, '12345');
      expect(repository.saved!.expiryTracking, isTrue);
    });

    test('preserves the explicit unit of measure', () async {
      final repository = _ProductRepo();
      final useCase = _useCase(productRepo: repository, currency: sar);

      final result = await useCase(
        const CreatePosProductInput(
          sku: 'SKU-UNIT',
          name: 'Coffee',
          currencyCode: 'SAR',
          salePriceMinor: 300,
          purchasePriceMinor: 100,
          unitName: 'box',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(repository.saved!.unitName, 'box');
    });

    test('returns validation failure when currency is not registered', () async {
      final repository = _ProductRepo();
      final useCase = _useCase(productRepo: repository, currency: sar);

      final result = await useCase(
        const CreatePosProductInput(
          sku: 'SKU-1',
          name: 'Coffee',
          currencyCode: 'USD',
          salePriceMinor: 1500,
          purchasePriceMinor: 900,
        ),
      );

      expect(result.isFailure, isTrue);
      expect(repository.saved, isNull);
    });

    test('maps invalid product values to a Failure instead of throwing', () async {
      final repository = _ProductRepo();
      final useCase = _useCase(productRepo: repository, currency: sar);

      final result = await useCase(
        const CreatePosProductInput(
          sku: 'SKU-1',
          name: 'Coffee',
          currencyCode: 'SAR',
          salePriceMinor: -1,
          purchasePriceMinor: 900,
        ),
      );

      expect(result.isFailure, isTrue);
      expect(repository.saved, isNull);
    });

    test('does not access the product repository when governance is suspended', () async {
      final repository = _ProductRepo();
      final useCase = _useCase(
        productRepo: repository,
        currency: sar,
        status: const GovernanceStatus(kind: GovernanceStatusKind.suspended),
      );

      final result = await useCase(
        const CreatePosProductInput(
          sku: 'SKU-1',
          name: 'Coffee',
          currencyCode: 'SAR',
          salePriceMinor: 1500,
          purchasePriceMinor: 900,
        ),
      );

      expect(result.isFailure, isTrue);
      expect(repository.saved, isNull);
    });
  });
}
