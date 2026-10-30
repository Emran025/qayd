import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/governance/check_governance_status_use_case.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/create_pos_product_category_use_case.dart';
import 'package:qayd/application/pos/create_pos_product_use_case.dart';
import 'package:qayd/application/pos/deactivate_pos_product_use_case.dart';
import 'package:qayd/application/pos/list_pos_product_categories_use_case.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/application/pos/save_pos_product_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_product_category.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/governance_repository.dart';
import 'package:qayd/domain/repositories/pos_product_category_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/governance_status.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_barcode.dart';
import 'package:qayd/domain/value_objects/submit_activation_request.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pages/pos/pos_catalog_page.dart';
import 'package:qayd/presentation/pos/pos_catalog_cubit.dart';
import 'package:qayd/presentation/theme/app_theme.dart';

final class _WidgetIdGenerator implements IdGenerator {
  @override
  String next() => 'widget-product-id';
}

final class _WidgetCategoryIdGenerator implements IdGenerator {
  @override
  String next() => 'widget-category-id';
}

final class _WidgetCurrencyRepository implements CurrencyRepository {
  _WidgetCurrencyRepository(this.currency);

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

final class _WidgetGovernanceRepository implements GovernanceRepository {
  @override
  Future<Result<GovernanceStatus>> getStatus(
          {bool forceRefresh = false}) async =>
      Success(GovernanceStatus.activated);

  @override
  Future<Result<void>> submitActivation(
          SubmitActivationRequest request) async =>
      const Success(null);
}

final class _WidgetProductRepository implements PosProductRepository {
  final products = <PosProduct>[];

  @override
  Future<Result<PosProduct>> getById(String id) async =>
      Success(products.firstWhere((item) => item.id == id));

  @override
  Future<Result<PosProduct?>> getByBarcode(PosBarcode barcode) async {
    for (final product in products) {
      if (product.barcodes.contains(barcode)) return Success(product);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<PosProduct>>> list({
    bool activeOnly = true,
    String? search,
  }) async {
    final query = search?.trim().toLowerCase() ?? '';
    return Success(
      products.where((product) {
        if (activeOnly && !product.isActive) return false;
        if (query.isEmpty) return true;
        return product.name.toLowerCase().contains(query) ||
            product.sku.toLowerCase().contains(query) ||
            product.barcodes.any((item) => item.value.contains(query));
      }).toList(growable: false),
    );
  }

  @override
  Future<Result<void>> save(PosProduct product) async {
    final index = products.indexWhere((item) => item.id == product.id);
    if (index == -1) {
      products.add(product);
    } else {
      products[index] = product;
    }
    return const Success(null);
  }

  @override
  Future<Result<void>> deactivate(String id) async {
    final index = products.indexWhere((item) => item.id == id);
    if (index != -1) products[index] = products[index].deactivate();
    return const Success(null);
  }
}

final class _WidgetCategoryRepository implements PosProductCategoryRepository {
  final categories = <PosProductCategory>[];

  @override
  Future<Result<List<PosProductCategory>>> list(
      {bool activeOnly = true}) async {
    return Success(
      categories
          .where((category) => !activeOnly || category.isActive)
          .toList(growable: false),
    );
  }

  @override
  Future<Result<void>> save(PosProductCategory category) async {
    categories.add(category);
    return const Success(null);
  }

  @override
  Future<Result<void>> deactivate(String id) async => const Success(null);
}

CurrencyCode _currency() => CurrencyCode(
      code: 'SAR',
      nameAr: 'ريال',
      symbol: 'ر.س',
    );

PosCatalogCubit _createCubit(_WidgetProductRepository repository) {
  final currency = _currency();
  final guard = GovernanceWriteGuard(
    CheckGovernanceStatusUseCase(_WidgetGovernanceRepository()),
  );
  return PosCatalogCubit(
    listUseCase: ListPosProductsUseCase(repository),
    saveUseCase: SavePosProductUseCase(repository, guard),
    createUseCase: CreatePosProductUseCase(
      repository,
      _WidgetCurrencyRepository(currency),
      guard,
      _WidgetIdGenerator(),
    ),
    deactivateUseCase: DeactivatePosProductUseCase(repository, guard),
  );
}

PosProduct _product(CurrencyCode currency) => PosProduct.create(
      id: 'existing-product',
      sku: 'SKU-EXISTING',
      name: 'Coffee',
      currency: currency,
      salePrice: Money.fromMinorUnits(100, currency),
      purchasePrice: Money.fromMinorUnits(50, currency),
      barcodes: [PosBarcode('628000000001')],
    );

void main() {
  testWidgets('shows empty state and creates a product from the form',
      (tester) async {
    final repository = _WidgetProductRepository();
    final categoryRepository = _WidgetCategoryRepository();
    final categoryWriteGuard = GovernanceWriteGuard(
      CheckGovernanceStatusUseCase(_WidgetGovernanceRepository()),
    );
    final cubit = _createCubit(repository);
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PosCatalogPage(
          currency: _currency(),
          cubit: cubit,
          listCategoriesUseCase:
              ListPosProductCategoriesUseCase(categoryRepository),
          createCategoryUseCase: CreatePosProductCategoryUseCase(
            categoryRepository,
            categoryWriteGuard,
            _WidgetCategoryIdGenerator(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.posCatalogEmpty), findsOneWidget);
    await tester.tap(find.text(AppStrings.posCatalogAddProduct).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.posCatalogAddCategory));
    await tester.pumpAndSettle();
    final categoryFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(categoryFields.at(0), 'Beverages');
    await tester.enterText(categoryFields.at(1), 'drinks');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(AppStrings.posCatalogAddCategory),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Beverages (DRINKS)'), findsOneWidget);

    final productForm = find.ancestor(
      of: find.text(AppStrings.posCatalogCreateTitle),
      matching: find.byType(Form),
    );
    final fields = find.descendant(
      of: productForm,
      matching: find.byType(TextFormField),
    );
    expect(fields, findsNWidgets(10));
    await tester.enterText(fields.at(0), 'New Coffee');
    await tester.enterText(fields.at(1), 'SKU-NEW');
    await tester.enterText(fields.at(2), '1250');
    await tester.enterText(fields.at(3), '900');
    await tester.enterText(fields.at(4), '5');
    await tester.enterText(fields.at(8), '628000000002');
    await tester.ensureVisible(find.text(AppStrings.save));
    await tester.tap(find.text(AppStrings.save));
    await tester.pumpAndSettle();

    expect(find.text('New Coffee'), findsOneWidget);
    expect(repository.products.single.salePrice.minorUnits, 1250);
    expect(repository.products.single.profitMargin.percentageBasisPoints, 500);
    expect(repository.products.single.categoryId, 'widget-category-id');
    expect(categoryRepository.categories.single.code, 'DRINKS');
  });

  testWidgets('searches and deactivates an existing product', (tester) async {
    final repository = _WidgetProductRepository()
      ..products.add(_product(_currency()));
    final cubit = _createCubit(repository);
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PosCatalogPage(currency: _currency(), cubit: cubit),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coffee'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.posCatalogNoResults), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Coffee');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.posCatalogDeactivate).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.posCatalogDeactivate).last);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.posCatalogNoResults), findsOneWidget);
    expect(repository.products.single.isActive, isFalse);
  });
}
