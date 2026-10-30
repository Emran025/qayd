import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/pos/build_pos_purchase_posting_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_profit_margin.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/repositories/pos_currency_rate_repository.dart';
import 'package:qayd/domain/services/pos_currency_converter.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

class _Products extends Mock implements PosProductRepository {}

class _Installation extends Mock implements PosTemplateInstallationRepository {}

class _Accounts extends Mock implements AccountRepository {}

class _Rates extends Mock implements PosCurrencyRateRepository {}

void main() {
  setUpAll(() => registerFallbackValue(PosTemplateDefinition.current()));
  final currency = CurrencyCode(code: 'SAR', nameAr: 'ريال', symbol: 'ر.س');
  Account account(String id) => Account.createRoot(
        id: AccountId(id),
        name: id,
        classification:
            AccountClassification.custom(name: id, nature: AccountNature.debit),
        createdAt: DateTime.utc(2026),
      );
  PosProduct product({bool expiry = false}) => PosProduct.create(
        id: 'product-1',
        sku: 'SKU-1',
        name: 'Item',
        currency: currency,
        salePrice: Money.fromMinorUnits(500, currency),
        purchasePrice: Money.fromMinorUnits(100, currency),
        expiryTracking: expiry,
      );
  BuildPosPurchasePostingUseCase useCase(PosProduct value,
      {Map<String, String>? mapping}) {
    final products = _Products(),
        installation = _Installation(),
        accounts = _Accounts();
    when(() => products.getById('product-1'))
        .thenAnswer((_) async => Success(value));
    when(() => installation.getEnabledInstallation(
            template: any(named: 'template')))
        .thenAnswer((_) async => Success(PosActivationResult(
            templateKey: PosTemplateDefinition.coreTemplateKey,
            templateVersion: PosTemplateDefinition.currentVersion,
            warehouseId: 'warehouse-1',
            alreadyInstalled: true,
            accountIdsByKey: mapping ??
                {
                  PosTemplateAccountKey.inventoryAsset.value: 'inventory',
                  PosTemplateAccountKey.supplierPayables.value: 'payables',
                  PosTemplateAccountKey.posCash.value: 'cash',
                })));
    for (final id in ['inventory', 'payables', 'cash', 'supplier']) {
      when(() => accounts.getById(AccountId(id)))
          .thenAnswer((_) async => Success(account(id)));
    }
    return BuildPosPurchasePostingUseCase(
      productRepository: products,
      installationRepository: installation,
      accountRepository: accounts,
      currencyConverter: PosCurrencyConverter(_Rates()),
    );
  }

  BuildPosPurchasePostingInput input(
          {PosPaymentMethod method = PosPaymentMethod.credit,
          int advance = 0,
          bool withSupplier = true}) =>
      BuildPosPurchasePostingInput(
        invoiceId: 'purchase-1',
        invoiceNumber: 'P-1',
        warehouseId: 'warehouse-1',
        currency: currency,
        lines: [
          BuildPosPurchaseLineInput(
              productId: 'product-1', quantity: PosQuantity.whole(2))
        ],
        idempotencyKey: 'purchase-key-1',
        invoiceDate: DateTime.utc(2026, 1, 10),
        createdAt: DateTime.utc(2026, 1, 10),
        supplierAccountId: withSupplier ? AccountId('supplier') : null,
        advanceMinorUnits: advance,
        paymentMethod: method,
      );

  test('builds a credit purchase with inbound movement and balanced payable',
      () async {
    final result = await useCase(product())(input());
    expect(result.isSuccess, isTrue);
    final posting = result.valueOrNull!;
    expect(posting.invoice.type, PosInvoiceType.purchase);
    expect(posting.movements.single.direction.name, 'inbound');
    expect(posting.movements.single.type, PosStockMovementType.purchase);
    expect(posting.postings.single.voucher.amount.minorUnits, 200);
  });

  test(
      'rebuilds the same request with stable invoice, movement, and ledger IDs',
      () async {
    final builder = useCase(product());
    final request = input();
    final first = (await builder(request)).valueOrNull!;
    final replay = (await builder(request)).valueOrNull!;
    expect(replay.invoice.lines.single.id, first.invoice.lines.single.id);
    expect(replay.movements.single.id, first.movements.single.id);
    expect(replay.postings.single.voucher.id, first.postings.single.voucher.id);
    expect(
      replay.postings.single.entries.map((entry) => entry.id).toList(),
      first.postings.single.entries.map((entry) => entry.id).toList(),
    );
  });

  test('rejects expiry-tracked products until lot persistence is available',
      () async {
    final result = await useCase(product(expiry: true))(input());
    expect(result.isFailure, isTrue);
  });

  test('rejects bank payment when no mapped bank account exists', () async {
    final result = await useCase(product())(
        input(method: PosPaymentMethod.bank, advance: 50));
    expect(result.isFailure, isTrue);
  });

  test('builds a fully paid cash purchase with a matching payment voucher',
      () async {
    final result = await useCase(product())(
      input(method: PosPaymentMethod.cash, advance: 200),
    );
    expect(result.isSuccess, isTrue);
    final posting = result.valueOrNull!;
    expect(posting.invoice.status.name, 'paid');
    expect(posting.payments.single.amount.minorUnits, 200);
    expect(posting.postings.single.voucher.counterpartyId, AccountId('cash'));
  });

  test('requires a supplier account when any amount remains due', () async {
    final result = await useCase(product())(input(withSupplier: false));
    expect(result.isFailure, isTrue);
  });

  test('converts purchase cost and preserves the proposed price until approved',
      () async {
    const usd = CurrencyCode(code: 'USD', nameAr: 'دولار', symbol: r'$');
    final usdProduct = PosProduct.create(
      id: 'product-1',
      sku: 'SKU-1',
      name: 'Item',
      currency: usd,
      salePrice: Money.fromMinorUnits(500, usd),
      purchasePrice: Money.fromMinorUnits(80, usd),
      profitMargin: PosProfitMargin.percentage(5000),
    );
    final recordedAt = DateTime.utc(2026, 1, 9, 12);
    final quote = PosCurrencyRateQuote(
      rateId: 'rate-sar-usd',
      storedFromCurrency: currency,
      storedToCurrency: usd,
      storedRateScaled: 50000000,
      requestedFromCurrency: currency,
      requestedToCurrency: usd,
      effectiveAt: recordedAt,
      recordedAt: recordedAt,
      createdAt: recordedAt,
      isInverted: false,
    );
    final request = BuildPosPurchasePostingInput(
      invoiceId: 'purchase-fx',
      invoiceNumber: 'P-FX',
      warehouseId: 'warehouse-1',
      currency: currency,
      lines: [
        BuildPosPurchaseLineInput(
          productId: usdProduct.id,
          quantity: PosQuantity.whole(2),
          unitCostMinor: 200,
          rateSnapshot: quote,
          productUpdatedAtSnapshot: usdProduct.updatedAt,
        ),
      ],
      idempotencyKey: 'purchase-fx-key',
      invoiceDate: DateTime.utc(2026, 1, 10),
      createdAt: DateTime.utc(2026, 1, 10),
      supplierAccountId: AccountId('supplier'),
    );

    final result = await useCase(usdProduct)(request);

    expect(result.isSuccess, isTrue);
    final line = result.valueOrNull!.invoice.lines.single;
    expect(line.unitPrice.currency, currency);
    expect(line.unitCost.currency, usd);
    expect(line.unitCost.minorUnits, 100);
    expect(line.currencyConversion?.sourceAmount.minorUnits, 200);
    expect(line.currencyConversion?.targetAmount.minorUnits, 100);
    expect(line.currencyConversion?.rateSnapshot?.rateId, 'rate-sar-usd');
    expect(line.proposedSalePrice?.minorUnits, 150);
    expect(line.proposedSalePriceApplied, isFalse);
    expect(result.valueOrNull!.movements.single.unitCost.currency, usd);
    expect(result.valueOrNull!.postings.single.voucher.currency, currency);
  });
}
