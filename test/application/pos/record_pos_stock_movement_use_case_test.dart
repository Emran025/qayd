import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/governance/check_governance_status_use_case.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/record_pos_stock_movement_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/governance_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/governance_status.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_barcode.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/submit_activation_request.dart';

final class _IdGenerator implements IdGenerator {
  @override
  String next() => 'movement-generated';
}

final class _GovernanceRepository implements GovernanceRepository {
  _GovernanceRepository(this.status);

  final GovernanceStatus status;

  @override
  Future<Result<GovernanceStatus>> getStatus(
          {bool forceRefresh = false}) async =>
      Success(status);

  @override
  Future<Result<void>> submitActivation(
          SubmitActivationRequest request) async =>
      const Success(null);
}

final class _ProductRepository implements PosProductRepository {
  _ProductRepository(this.product);

  final PosProduct product;

  @override
  Future<Result<PosProduct>> getById(String id) async => Success(product);

  @override
  Future<Result<PosProduct?>> getByBarcode(PosBarcode barcode) async =>
      const Success(null);

  @override
  Future<Result<List<PosProduct>>> list({
    bool activeOnly = true,
    String? search,
  }) async =>
      Success([product]);

  @override
  Future<Result<void>> save(PosProduct product) async => const Success(null);

  @override
  Future<Result<void>> deactivate(String id) async => const Success(null);
}

final class _StockRepository implements PosStockMovementRepository {
  PosStockMovement? appended;

  @override
  Future<Result<PosStockBalance>> getBalance({
    required String productId,
    required String warehouseId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Result<PosStockMovement?>> getByIdempotencyKey(String key) async =>
      const Success(null);

  @override
  Future<Result<List<PosStockMovement>>> listMovements({
    required String warehouseId,
    String? productId,
    PosStockMovementType? type,
    DateTime? fromInclusive,
    DateTime? untilExclusive,
    int limit = 100,
    int offset = 0,
  }) async => const Success([]);

  @override
  Future<Result<void>> append(PosStockMovement movement) async {
    appended = movement;
    return const Success(null);
  }
}

CurrencyCode _currency() => CurrencyCode(
      code: 'SAR',
      nameAr: 'ريال سعودي',
      symbol: 'ر.س',
    );

PosProduct _product(CurrencyCode currency, {bool active = true}) {
  final product = PosProduct.create(
    id: 'product-1',
    sku: 'SKU-1',
    name: 'Coffee',
    currency: currency,
    salePrice: Money.fromMinorUnits(300, currency),
    purchasePrice: Money.fromMinorUnits(100, currency),
    quantityScale: 2,
    reorderLevel: PosQuantity.fromScaled(10, scale: 2),
  );
  return active ? product : product.deactivate();
}

RecordPosStockMovementUseCase _useCase({
  required PosProduct product,
  GovernanceStatus status = GovernanceStatus.activated,
  required _StockRepository stockRepository,
}) {
  final guard = GovernanceWriteGuard(
    CheckGovernanceStatusUseCase(_GovernanceRepository(status)),
  );
  return RecordPosStockMovementUseCase(
    stockRepository,
    _ProductRepository(product),
    guard,
    _IdGenerator(),
  );
}

RecordPosStockMovementInput _input({
  String currencyCode = 'SAR',
  int quantityScale = 2,
  int quantityScaled = 125,
}) {
  return RecordPosStockMovementInput(
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: PosStockMovementType.purchase,
    direction: PosStockMovementDirection.inbound,
    quantityScaled: quantityScaled,
    quantityScale: quantityScale,
    unitCostMinor: 150,
    currencyCode: currencyCode,
    idempotencyKey: 'purchase-key-1',
  );
}

void main() {
  test('records a valid governed movement with exact quantity and cost',
      () async {
    final currency = _currency();
    final stockRepository = _StockRepository();
    final result = await _useCase(
      product: _product(currency),
      stockRepository: stockRepository,
    ).call(_input());

    expect(result.isSuccess, isTrue);
    expect(stockRepository.appended?.id, 'movement-generated');
    expect(stockRepository.appended?.quantity.scaledUnits, 125);
    expect(stockRepository.appended?.quantity.scale, 2);
    expect(stockRepository.appended?.unitCost.minorUnits, 150);
  });

  test('blocks movement when governance is suspended', () async {
    final currency = _currency();
    final stockRepository = _StockRepository();
    final result = await _useCase(
      product: _product(currency),
      status: const GovernanceStatus(kind: GovernanceStatusKind.suspended),
      stockRepository: stockRepository,
    ).call(_input());

    expect(result.isFailure, isTrue);
    expect(stockRepository.appended, isNull);
  });

  test('blocks inactive products and scale or currency mismatches', () async {
    final currency = _currency();
    final inactiveRepo = _StockRepository();
    final inactive = await _useCase(
      product: _product(currency, active: false),
      stockRepository: inactiveRepo,
    ).call(_input());
    final scaleRepo = _StockRepository();
    final scaleMismatch = await _useCase(
      product: _product(currency),
      stockRepository: scaleRepo,
    ).call(_input(quantityScale: 0));
    final currencyRepo = _StockRepository();
    final currencyMismatch = await _useCase(
      product: _product(currency),
      stockRepository: currencyRepo,
    ).call(_input(currencyCode: 'USD'));

    expect(inactive.isFailure, isTrue);
    expect(scaleMismatch.isFailure, isTrue);
    expect(currencyMismatch.isFailure, isTrue);
    expect(inactiveRepo.appended, isNull);
    expect(scaleRepo.appended, isNull);
    expect(currencyRepo.appended, isNull);
  });
}
