import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/governance/check_governance_status_use_case.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/create_pos_product_use_case.dart';
import 'package:qayd/application/pos/deactivate_pos_product_use_case.dart';
import 'package:qayd/application/pos/get_pos_stock_balance_use_case.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/application/pos/post_pos_opening_balance_atomically_use_case.dart';
import 'package:qayd/application/pos/record_pos_stock_movement_use_case.dart';
import 'package:qayd/application/pos/save_pos_product_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/governance_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/governance_status.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_barcode.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/submit_activation_request.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pages/pos/pos_opening_balance_page.dart';
import 'package:qayd/presentation/pos/pos_catalog_cubit.dart';
import 'package:qayd/presentation/pos/pos_stock_cubit.dart';
import 'package:qayd/presentation/theme/app_theme.dart';

final class _IdGenerator implements IdGenerator {
  @override
  String next() => 'opening-movement-1';
}

final class _GovernanceRepository implements GovernanceRepository {
  @override
  Future<Result<GovernanceStatus>> getStatus(
          {bool forceRefresh = false}) async =>
      const Success(GovernanceStatus.activated);

  @override
  Future<Result<void>> submitActivation(
          SubmitActivationRequest request) async =>
      const Success(null);
}

final class _CurrencyRepository implements CurrencyRepository {
  _CurrencyRepository(this.currency);

  final CurrencyCode currency;

  @override
  Future<Result<CurrencyCode?>> getByCode(String code) async =>
      Success(code == currency.code ? currency : null);

  @override
  Future<Result<List<CurrencyCode>>> getAll({bool onlyActive = false}) async =>
      Success([currency]);

  @override
  Future<Result<void>> save(CurrencyCode currency,
          {bool isPredefined = false}) async =>
      const Success(null);

  @override
  Future<Result<void>> toggleActiveStatus(String code, bool isActive) async =>
      const Success(null);

  @override
  Future<Result<String>> getBaseCurrencyCode() async => Success(currency.code);

  @override
  Future<Result<void>> setBaseCurrencyCode(String code) async =>
      const Success(null);
}

final class _ProductRepository implements PosProductRepository {
  _ProductRepository(this.products);

  final List<PosProduct> products;

  @override
  Future<Result<PosProduct>> getById(String id) async =>
      Success(products.firstWhere((product) => product.id == id));

  @override
  Future<Result<PosProduct?>> getByBarcode(PosBarcode barcode) async =>
      const Success(null);

  @override
  Future<Result<List<PosProduct>>> list({
    bool activeOnly = true,
    String? search,
  }) async =>
      Success(products
          .where((product) => !activeOnly || product.isActive)
          .toList());

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

PosCatalogCubit _catalogCubit(
    List<PosProduct> products, CurrencyCode currency) {
  final productRepository = _ProductRepository(products);
  final currencyRepository = _CurrencyRepository(currency);
  final guard = GovernanceWriteGuard(
    CheckGovernanceStatusUseCase(_GovernanceRepository()),
  );
  return PosCatalogCubit(
    listUseCase: ListPosProductsUseCase(productRepository),
    saveUseCase: SavePosProductUseCase(productRepository, guard),
    createUseCase: CreatePosProductUseCase(
      productRepository,
      currencyRepository,
      guard,
      _IdGenerator(),
    ),
    deactivateUseCase: DeactivatePosProductUseCase(productRepository, guard),
  );
}

PosStockCubit _stockCubit(PosProduct product, CurrencyCode currency) {
  final stockRepository = _StockRepository(
    emptyPosStockBalance(
        currency: currency, quantityScale: product.quantityScale),
  );
  final guard = GovernanceWriteGuard(
    CheckGovernanceStatusUseCase(_GovernanceRepository()),
  );
  return PosStockCubit(
    getBalanceUseCase: GetPosStockBalanceUseCase(stockRepository),
    recordMovementUseCase: RecordPosStockMovementUseCase(
      stockRepository,
      _ProductRepository([product]),
      guard,
      _IdGenerator(),
    ),
  );
}

Widget _host({
  required PosCatalogCubit catalogCubit,
  required PosStockCubit stockCubit,
  required PostPosOpeningBalance postOpeningBalance,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: PosOpeningBalancePage(
      catalogCubit: catalogCubit,
      stockCubit: stockCubit,
      warehouseId: 'warehouse-1',
      postOpeningBalance: postOpeningBalance,
    ),
  );
}

void main() {
  testWidgets('shows an explicit empty state when catalog has no products',
      (tester) async {
    final currency = _currency();
    final catalogCubit = _catalogCubit([], currency);
    final product = _product(currency);
    final stockCubit = _stockCubit(product, currency);
    addTearDown(catalogCubit.close);
    addTearDown(stockCubit.close);

    await tester.pumpWidget(
      _host(
        catalogCubit: catalogCubit,
        stockCubit: stockCubit,
        postOpeningBalance: (_) async => const Success(null),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.posOpeningBalanceNoProducts), findsOneWidget);
  });

  testWidgets('validates and records an opening balance for selected product',
      (tester) async {
    final currency = _currency();
    final product = _product(currency);
    final catalogCubit = _catalogCubit([product], currency);
    final stockCubit = _stockCubit(product, currency);
    PostPosOpeningBalanceInput? postedInput;
    addTearDown(catalogCubit.close);
    addTearDown(stockCubit.close);

    await tester.pumpWidget(
      _host(
        catalogCubit: catalogCubit,
        stockCubit: stockCubit,
        postOpeningBalance: (input) async {
          postedInput = input;
          return const Success(null);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<PosProduct>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coffee (SKU-1)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.posOpeningBalanceSave));
    await tester.pump();
    expect(
        find.text(AppStrings.posOpeningBalancePositiveInteger), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), '5');
    await tester.enterText(find.byType(TextFormField).at(1), '100');
    await tester.tap(find.text(AppStrings.posOpeningBalanceSave));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.posOpeningBalanceSaved), findsOneWidget);
    expect(postedInput?.productId, product.id);
    expect(postedInput?.quantityScaled, 5);
    expect(postedInput?.quantityScale, product.quantityScale);
    expect(postedInput?.unitCostMinor, 100);
    expect(postedInput?.currencyCode, 'SAR');
    expect(postedInput?.idempotencyKey, isNotEmpty);
    expect(postedInput?.sourceId, contains(postedInput!.idempotencyKey));
    expect(stockCubit.state.balance?.quantity.scaledUnits, 0);
  });
}
