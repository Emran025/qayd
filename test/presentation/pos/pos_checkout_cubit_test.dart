import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/application/pos/resolve_pos_product_for_checkout_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/repositories/pos_currency_rate_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/services/pos_currency_converter.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_barcode.dart';
import 'package:qayd/presentation/pos/pos_checkout_cubit.dart';

final class _Products implements PosProductRepository {
  _Products(this.product);

  final PosProduct product;

  @override
  Future<Result<PosProduct>> getById(String id) async => Success(product);

  @override
  Future<Result<PosProduct?>> getByBarcode(PosBarcode barcode) async =>
      Success(product.barcodes.any((item) => item.value == barcode.value)
          ? product
          : null);

  @override
  Future<Result<List<PosProduct>>> list({
    bool activeOnly = true,
    String? search,
  }) async {
    final query = search?.toLowerCase() ?? '';
    final matches = query.isEmpty ||
        product.name.toLowerCase().contains(query) ||
        product.sku.toLowerCase().contains(query) ||
        product.barcodes.any((item) => item.value.contains(query));
    return Success(
        matches && (!activeOnly || product.isActive) ? [product] : []);
  }

  @override
  Future<Result<void>> save(PosProduct product) async => const Success(null);

  @override
  Future<Result<void>> deactivate(String id) async => const Success(null);
}

final class _Rates implements PosCurrencyRateRepository {
  _Rates(this.quote);

  final PosCurrencyRateQuote? quote;

  @override
  Future<Result<void>> save(PosCurrencyRate rate) async => const Success(null);

  @override
  Future<Result<PosCurrencyRateQuote?>> latestQuote({
    required CurrencyCode fromCurrency,
    required CurrencyCode toCurrency,
  }) async {
    final value = quote;
    if (value != null &&
        value.requestedFromCurrency == fromCurrency &&
        value.requestedToCurrency == toCurrency) {
      return Success(value);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<PosCurrencyRate>>> listHistory({
    CurrencyCode? fromCurrency,
    CurrencyCode? toCurrency,
    int? limit,
  }) async =>
      const Success([]);
}

void main() {
  final currency = CurrencyCode(
    code: 'SAR',
    nameAr: 'ريال سعودي',
    symbol: 'ر.س',
  );
  final product = PosProduct.create(
    id: 'product-1',
    sku: 'SKU-1',
    name: 'Coffee',
    currency: currency,
    salePrice: Money.fromMinorUnits(400, currency),
    purchasePrice: Money.fromMinorUnits(250, currency),
    quantityScale: 3,
    barcodes: [PosBarcode('6290001')],
  );

  PosCheckoutCubit createCubit({PosCurrencyConverter? currencyConverter}) {
    final repository = _Products(product);
    return PosCheckoutCubit(
      resolveProduct: ResolvePosProductForCheckoutUseCase(repository),
      listProducts: ListPosProductsUseCase(repository),
      currencyConverter: currencyConverter,
    );
  }

  test('merges repeated barcode scans into one exact quantity line', () async {
    final cubit = createCubit();
    addTearDown(cubit.close);

    await cubit.resolveAndAdd('6290001');
    await cubit.resolveAndAdd('6290001');

    expect(cubit.state.lines, hasLength(1));
    expect(cubit.state.lines.single.quantity.scaledUnits, 2000);
    expect(cubit.state.lines.single.quantity.scale, 3);
    expect(cubit.state.subtotalMinorUnits, 800);
  });

  test('resolves a product through advanced name search when barcode misses',
      () async {
    final cubit = createCubit();
    addTearDown(cubit.close);

    await cubit.resolveAndAdd('Coffee');

    expect(cubit.state.lines.single.product.id, 'product-1');
    expect(cubit.state.lines.single.quantity.scaledUnits, 1000);
    expect(cubit.state.lines.single.quantity.scale, 3);
  });

  test('search exposes active results without mutating the cart', () async {
    final cubit = createCubit();
    addTearDown(cubit.close);

    await cubit.search('SKU-1');

    expect(cubit.state.searchResults, hasLength(1));
    expect(cubit.state.lines, isEmpty);
  });

  test('converts the catalog price using the recorded manual rate', () async {
    const usd = CurrencyCode(code: 'USD', nameAr: 'دولار', symbol: r'$');
    final recordedAt = DateTime.utc(2026, 1, 5);
    final quote = PosCurrencyRateQuote(
      rateId: 'sar-usd-1',
      storedFromCurrency: currency,
      storedToCurrency: usd,
      storedRateScaled: 150000000,
      requestedFromCurrency: currency,
      requestedToCurrency: usd,
      effectiveAt: recordedAt,
      recordedAt: recordedAt,
      createdAt: recordedAt,
      isInverted: false,
    );
    final cubit = createCubit(
      currencyConverter: PosCurrencyConverter(_Rates(quote)),
    );
    addTearDown(cubit.close);

    await cubit.setSaleCurrency(usd);
    await cubit.addProduct(product);

    expect(cubit.state.lines.single.unitPrice, Money.fromMinorUnits(600, usd));
    expect(cubit.state.lines.single.rateSnapshot?.rateId, 'sar-usd-1');
    expect(cubit.state.subtotalMinorUnits, 600);

    await cubit.setSaleCurrency(currency);
    expect(cubit.state.lines.single.unitPrice, product.salePrice);
  });
}
