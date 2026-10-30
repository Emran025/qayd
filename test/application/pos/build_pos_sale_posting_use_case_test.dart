import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/pos/build_pos_sale_posting_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_currency_rate_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/services/pos_currency_converter.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_barcode.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

class _Products extends Mock implements PosProductRepository {}

class _Stock extends Mock implements PosStockMovementRepository {}

class _Installation extends Mock implements PosTemplateInstallationRepository {}

class _Accounts extends Mock implements AccountRepository {}

final class _Rates implements PosCurrencyRateRepository {
  _Rates(this.quotes);

  final List<PosCurrencyRateQuote> quotes;

  @override
  Future<Result<void>> save(PosCurrencyRate rate) async => const Success(null);

  @override
  Future<Result<PosCurrencyRateQuote?>> latestQuote({
    required CurrencyCode fromCurrency,
    required CurrencyCode toCurrency,
  }) async {
    for (final quote in quotes) {
      if (quote.requestedFromCurrency == fromCurrency &&
          quote.requestedToCurrency == toCurrency) {
        return Success(quote);
      }
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

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'id-${_value++}';
}

PosCurrencyRateQuote _quote({
  required String id,
  required CurrencyCode from,
  required CurrencyCode to,
  required int rateScaled,
}) {
  final recordedAt = DateTime.utc(2026, 1, 5);
  return PosCurrencyRateQuote(
    rateId: id,
    storedFromCurrency: from,
    storedToCurrency: to,
    storedRateScaled: rateScaled,
    requestedFromCurrency: from,
    requestedToCurrency: to,
    effectiveAt: recordedAt,
    recordedAt: recordedAt,
    createdAt: recordedAt,
    isInverted: false,
  );
}

void main() {
  setUpAll(() => registerFallbackValue(PosTemplateDefinition.current()));

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
    salePrice: Money.fromMinorUnits(500, currency),
    purchasePrice: Money.fromMinorUnits(100, currency),
    quantityScale: 0,
    barcodes: [PosBarcode('6290001')],
  );
  final balance = PosStockBalance(
    quantity: PosQuantity.whole(5),
    valuation: Money.fromMinorUnits(500, currency),
  );

  Account account(String id) => Account.createRoot(
        id: AccountId(id),
        name: id,
        classification: AccountClassification.custom(
          name: id,
          nature: id == 'revenue' ? AccountNature.credit : AccountNature.debit,
        ),
        createdAt: DateTime.utc(2026, 1, 1),
      );

  BuildPosSalePostingUseCase createUseCase({
    Map<String, String>? accountIds,
    PosStockBalance? stockBalance,
    PosProduct? secondProduct,
    PosStockBalance? secondStockBalance,
    List<PosCurrencyRateQuote> quotes = const [],
  }) {
    final products = _Products();
    final stock = _Stock();
    final installation = _Installation();
    final accounts = _Accounts();
    when(() => products.getById('product-1'))
        .thenAnswer((_) async => Success(product));
    when(() => stock.getBalance(
          productId: 'product-1',
          warehouseId: 'warehouse-1',
        )).thenAnswer((_) async => Success(stockBalance ?? balance));
    if (secondProduct != null) {
      when(() => products.getById(secondProduct.id))
          .thenAnswer((_) async => Success(secondProduct));
      when(() => stock.getBalance(
            productId: secondProduct.id,
            warehouseId: 'warehouse-1',
          )).thenAnswer((_) async => Success(secondStockBalance!));
    }
    when(() => installation.getEnabledInstallation(
          template: any(named: 'template'),
        )).thenAnswer(
      (_) async => Success(
        PosActivationResult(
          templateKey: PosTemplateDefinition.coreTemplateKey,
          templateVersion: PosTemplateDefinition.currentVersion,
          warehouseId: 'warehouse-1',
          accountIdsByKey: accountIds ??
              <String, String>{
                PosTemplateAccountKey.inventoryAsset.value: 'inventory',
                PosTemplateAccountKey.salesRevenue.value: 'revenue',
                PosTemplateAccountKey.costOfGoodsSold.value: 'cogs',
                PosTemplateAccountKey.posCash.value: 'cash',
              },
          alreadyInstalled: true,
        ),
      ),
    );
    for (final id in ['inventory', 'revenue', 'cogs', 'cash', 'customer']) {
      when(() => accounts.getById(AccountId(id)))
          .thenAnswer((_) async => Success(account(id)));
    }
    return BuildPosSalePostingUseCase(
      productRepository: products,
      stockRepository: stock,
      installationRepository: installation,
      accountRepository: accounts,
      idGenerator: _Ids(),
      currencyConverter: PosCurrencyConverter(_Rates(quotes)),
    );
  }

  BuildPosSalePostingInput input({
    AccountId? customerAccountId,
    PosSaleSettlementInput? settlement,
    CurrencyCode? invoiceCurrency,
    List<BuildPosSaleLineInput>? lines,
  }) =>
      BuildPosSalePostingInput(
        invoiceId: 'sale-1',
        invoiceNumber: 'S-1',
        warehouseId: 'warehouse-1',
        currency: invoiceCurrency ?? currency,
        lines: lines ??
            [
              BuildPosSaleLineInput(
                productId: 'product-1',
                quantity: PosQuantity.whole(2),
              ),
            ],
        idempotencyKey: 'sale-key-1',
        invoiceDate: DateTime.utc(2026, 1, 10, 10),
        createdAt: DateTime.utc(2026, 1, 10, 10),
        customerAccountId: customerAccountId,
        settlement: settlement,
      );

  test('builds a cash sale with exact COGS and two balanced postings',
      () async {
    final result = await createUseCase()(input());

    expect(result.isSuccess, isTrue);
    final sale = result.valueOrNull!;
    expect(sale.invoice.status.isPaid, isTrue);
    expect(sale.invoice.total.minorUnits, 1000);
    expect(sale.invoice.paid.minorUnits, 1000);
    expect(sale.movements.single.direction, PosStockMovementDirection.outbound);
    expect(sale.movements.single.unitCost.minorUnits, 100);
    expect(sale.postings, hasLength(2));
    expect(sale.postings.last.voucher.amount.minorUnits, 200);
    expect(sale.payments, hasLength(1));
  });

  test('builds an advance with a customer due leg atomically', () async {
    final result = await createUseCase()(input(
      customerAccountId: AccountId('customer'),
      settlement: PosSaleSettlementInput(
        advanceMinorUnits: 400,
        paymentMethod: PosPaymentMethod.cash,
        paymentAccountId: AccountId('cash'),
      ),
    ));

    expect(result.isSuccess, isTrue);
    final sale = result.valueOrNull!;
    expect(sale.invoice.status.name, 'partiallyPaid');
    expect(sale.invoice.paid.minorUnits, 400);
    expect(sale.invoice.due.minorUnits, 600);
    expect(sale.payments.single.amount.minorUnits, 400);
    expect(sale.postings, hasLength(3));
    expect(sale.postings.map((p) => p.voucher.amount.minorUnits),
        containsAll(<int>[400, 600, 200]));
  });

  test('rejects a credit settlement without a customer', () async {
    final result = await createUseCase()(input(
      settlement: PosSaleSettlementInput(
        advanceMinorUnits: 0,
        paymentMethod: PosPaymentMethod.credit,
      ),
    ));

    expect(result.isFailure, isTrue);
  });

  test('rejects a zero advance unless the settlement is explicitly credit',
      () async {
    final result = await createUseCase()(input(
      customerAccountId: AccountId('customer'),
      settlement: PosSaleSettlementInput(
        advanceMinorUnits: 0,
        paymentMethod: PosPaymentMethod.cash,
      ),
    ));

    expect(result.isFailure, isTrue);
  });

  test('fails before payload construction when a required account is missing',
      () async {
    final ids = <String, String>{
      PosTemplateAccountKey.inventoryAsset.value: 'inventory',
      PosTemplateAccountKey.salesRevenue.value: 'revenue',
      PosTemplateAccountKey.costOfGoodsSold.value: 'cogs',
    };

    final result = await createUseCase(accountIds: ids)(input());

    expect(result.isFailure, isTrue);
  });

  test('rejects insufficient stock before creating a sale payload', () async {
    final result = await createUseCase(
      stockBalance: PosStockBalance(
        quantity: PosQuantity.whole(1),
        valuation: Money.fromMinorUnits(100, currency),
      ),
    )(input());

    expect(result.isFailure, isTrue);
  });

  test('uses the explicitly recorded rate to convert the catalog sale price',
      () async {
    const usd = CurrencyCode(code: 'USD', nameAr: 'دولار', symbol: r'$');
    final rate = _quote(
      id: 'sar-usd-1',
      from: currency,
      to: usd,
      rateScaled: 140000000,
    );
    final missing = await createUseCase()(input(invoiceCurrency: usd));
    expect(missing.isFailure, isTrue);

    final wrongCurrency = await createUseCase(quotes: [rate])(input(
      invoiceCurrency: usd,
      lines: [
        BuildPosSaleLineInput(
          productId: 'product-1',
          quantity: PosQuantity.whole(2),
          unitPrice: Money.fromMinorUnits(500, currency),
        ),
      ],
    ));
    expect(wrongCurrency.isFailure, isTrue);

    final result = await createUseCase(quotes: [rate])(input(
      invoiceCurrency: usd,
      lines: [
        BuildPosSaleLineInput(
          productId: 'product-1',
          quantity: PosQuantity.whole(2),
          unitPrice: Money.fromMinorUnits(700, usd),
        ),
      ],
    ));
    expect(result.isSuccess, isTrue);
    final sale = result.valueOrNull!;
    expect(sale.invoice.total, Money.fromMinorUnits(1400, usd));
    expect(sale.invoice.lines.single.unitPrice, Money.fromMinorUnits(700, usd));
    expect(
      sale.invoice.lines.single.currencyConversion?.sourceAmount,
      Money.fromMinorUnits(500, currency),
    );
    expect(sale.invoice.lines.single.currencyConversion?.rateSnapshot?.rateId,
        'sar-usd-1');
    expect(sale.invoice.lines.single.unitCost.currency, currency);
    expect(sale.payments.single.amount, Money.fromMinorUnits(1400, usd));
    final cogs = sale.postings.singleWhere(
      (posting) => posting.voucher.type.name == 'payment',
    );
    expect(cogs.voucher.currency, currency);
    expect(cogs.voucher.amount, Money.fromMinorUnits(200, currency));
    final commercial = sale.postings.singleWhere(
      (posting) => posting.voucher.type.name == 'receipt',
    );
    expect(commercial.voucher.currency, usd);
    expect(commercial.voucher.amount, Money.fromMinorUnits(1400, usd));
  });

  test('creates separate balanced COGS postings for each product cost currency',
      () async {
    const usd = CurrencyCode(code: 'USD', nameAr: 'دولار', symbol: r'$');
    const eur = CurrencyCode(code: 'EUR', nameAr: 'يورو', symbol: '€');
    final secondProduct = PosProduct.create(
      id: 'product-2',
      sku: 'SKU-2',
      name: 'Tea',
      currency: eur,
      salePrice: Money.fromMinorUnits(600, eur),
      purchasePrice: Money.fromMinorUnits(300, eur),
    );
    final result = await createUseCase(
      secondProduct: secondProduct,
      secondStockBalance: PosStockBalance(
        quantity: PosQuantity.whole(4),
        valuation: Money.fromMinorUnits(300, eur),
      ),
      quotes: [
        _quote(
          id: 'sar-usd-1',
          from: currency,
          to: usd,
          rateScaled: 140000000,
        ),
        _quote(
          id: 'eur-usd-1',
          from: eur,
          to: usd,
          rateScaled: 133333333,
        ),
      ],
    )(input(
      invoiceCurrency: usd,
      lines: [
        BuildPosSaleLineInput(
          productId: 'product-1',
          quantity: PosQuantity.whole(1),
          unitPrice: Money.fromMinorUnits(700, usd),
        ),
        BuildPosSaleLineInput(
          productId: 'product-2',
          quantity: PosQuantity.whole(1),
          unitPrice: Money.fromMinorUnits(800, usd),
        ),
      ],
    ));

    expect(result.isSuccess, isTrue);
    final sale = result.valueOrNull!;
    expect(sale.invoice.total, Money.fromMinorUnits(1500, usd));
    final costPostings = sale.postings
        .where((posting) => posting.voucher.type.name == 'payment')
        .toList();
    expect(costPostings, hasLength(2));
    expect(
      costPostings.map((posting) => posting.voucher.currency.code).toSet(),
      {'SAR', 'EUR'},
    );
    expect(
      costPostings.map((posting) => posting.voucher.amount.minorUnits).toSet(),
      {100, 75},
    );
  });
}
