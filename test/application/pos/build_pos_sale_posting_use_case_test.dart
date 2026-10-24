import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/pos/build_pos_sale_posting_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
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

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'id-${_value++}';
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
    );
  }

  BuildPosSalePostingInput input({
    AccountId? customerAccountId,
    PosSaleSettlementInput? settlement,
  }) =>
      BuildPosSalePostingInput(
        invoiceId: 'sale-1',
        invoiceNumber: 'S-1',
        warehouseId: 'warehouse-1',
        currency: currency,
        lines: [
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
}
