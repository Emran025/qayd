import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/governance/check_governance_status_use_case.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/get_pos_stock_balance_use_case.dart';
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
import 'package:qayd/presentation/pos/pos_stock_cubit.dart';

final class _IdGenerator implements IdGenerator {
  @override
  String next() => 'movement-1';
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
  _StockRepository(this.balance);

  PosStockBalance balance;

  @override
  Future<Result<PosStockBalance>> getBalance({
    required String productId,
    required String warehouseId,
  }) async =>
      Success(balance);

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
    balance = balance.apply(movement);
    return const Success(null);
  }
}

CurrencyCode _currency() => CurrencyCode(
      code: 'SAR',
      nameAr: 'ريال سعودي',
      symbol: 'ر.س',
    );

PosProduct _product(CurrencyCode currency) => PosProduct.create(
      id: 'product-1',
      sku: 'SKU-1',
      name: 'Coffee',
      currency: currency,
      salePrice: Money.fromMinorUnits(300, currency),
      purchasePrice: Money.fromMinorUnits(100, currency),
      quantityScale: 0,
      reorderLevel: PosQuantity.whole(1),
    );

PosStockCubit _cubit({GovernanceStatus status = GovernanceStatus.activated}) {
  final currency = _currency();
  final product = _product(currency);
  final stockRepository = _StockRepository(
    emptyPosStockBalance(currency: currency, quantityScale: 0),
  );
  final guard = GovernanceWriteGuard(
    CheckGovernanceStatusUseCase(_GovernanceRepository(status)),
  );
  return PosStockCubit(
    getBalanceUseCase: GetPosStockBalanceUseCase(stockRepository),
    recordMovementUseCase: RecordPosStockMovementUseCase(
      stockRepository,
      _ProductRepository(product),
      guard,
      _IdGenerator(),
    ),
  );
}

GetPosStockBalanceInput _balanceInput() => const GetPosStockBalanceInput(
      productId: 'product-1',
      warehouseId: 'warehouse-1',
    );

RecordPosStockMovementInput _movementInput() => RecordPosStockMovementInput(
      productId: 'product-1',
      warehouseId: 'warehouse-1',
      type: PosStockMovementType.opening,
      direction: PosStockMovementDirection.inbound,
      quantityScaled: 5,
      quantityScale: 0,
      unitCostMinor: 100,
      currencyCode: 'SAR',
      idempotencyKey: 'opening-1',
    );

void main() {
  test('loads balance and records movement, then refreshes balance', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);

    await cubit.loadBalance(_balanceInput());
    expect(cubit.state.status, PosStockStatus.ready);
    expect(cubit.state.balance!.quantity.scaledUnits, 0);

    await cubit.record(_movementInput());

    expect(cubit.state.status, PosStockStatus.ready);
    expect(cubit.state.balance!.quantity.scaledUnits, 5);
  });

  test('maps a governance failure and does not record movement', () async {
    final cubit = _cubit(
      status: const GovernanceStatus(kind: GovernanceStatusKind.suspended),
    );
    addTearDown(cubit.close);

    await cubit.record(_movementInput());

    expect(cubit.state.status, PosStockStatus.failure);
    expect(cubit.state.failure, isNotNull);
  });
}
