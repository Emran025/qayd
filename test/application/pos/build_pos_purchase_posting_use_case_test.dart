import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/pos/build_pos_purchase_posting_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

class _Products extends Mock implements PosProductRepository {}
class _Installation extends Mock implements PosTemplateInstallationRepository {}
class _Accounts extends Mock implements AccountRepository {}

void main() {
  setUpAll(() => registerFallbackValue(PosTemplateDefinition.current()));
  final currency = CurrencyCode(code: 'SAR', nameAr: 'ريال', symbol: 'ر.س');
  Account account(String id) => Account.createRoot(
    id: AccountId(id), name: id,
    classification: AccountClassification.custom(name: id, nature: AccountNature.debit),
    createdAt: DateTime.utc(2026),
  );
  PosProduct product({bool expiry = false}) => PosProduct.create(
    id: 'product-1', sku: 'SKU-1', name: 'Item', currency: currency,
    salePrice: Money.fromMinorUnits(500, currency), purchasePrice: Money.fromMinorUnits(100, currency),
    expiryTracking: expiry,
  );
  BuildPosPurchasePostingUseCase useCase(PosProduct value, {Map<String, String>? mapping}) {
    final products = _Products(), installation = _Installation(), accounts = _Accounts();
    when(() => products.getById('product-1')).thenAnswer((_) async => Success(value));
    when(() => installation.getEnabledInstallation(template: any(named: 'template'))).thenAnswer((_) async => Success(PosActivationResult(
      templateKey: PosTemplateDefinition.coreTemplateKey, templateVersion: PosTemplateDefinition.currentVersion,
      warehouseId: 'warehouse-1', alreadyInstalled: true, accountIdsByKey: mapping ?? {
        PosTemplateAccountKey.inventoryAsset.value: 'inventory',
        PosTemplateAccountKey.supplierPayables.value: 'payables',
        PosTemplateAccountKey.posCash.value: 'cash',
      })));
    for (final id in ['inventory', 'payables', 'cash', 'supplier']) {
      when(() => accounts.getById(AccountId(id))).thenAnswer((_) async => Success(account(id)));
    }
    return BuildPosPurchasePostingUseCase(productRepository: products, installationRepository: installation,
      accountRepository: accounts);
  }
  BuildPosPurchasePostingInput input({PosPaymentMethod method = PosPaymentMethod.credit, int advance = 0, bool withSupplier = true}) => BuildPosPurchasePostingInput(
    invoiceId: 'purchase-1', invoiceNumber: 'P-1', warehouseId: 'warehouse-1', currency: currency,
    lines: [BuildPosPurchaseLineInput(productId: 'product-1', quantity: PosQuantity.whole(2))],
    idempotencyKey: 'purchase-key-1', invoiceDate: DateTime.utc(2026, 1, 10), createdAt: DateTime.utc(2026, 1, 10),
    supplierAccountId: withSupplier ? AccountId('supplier') : null, advanceMinorUnits: advance, paymentMethod: method,
  );

  test('builds a credit purchase with inbound movement and balanced payable', () async {
    final result = await useCase(product())(input());
    expect(result.isSuccess, isTrue);
    final posting = result.valueOrNull!;
    expect(posting.invoice.type, PosInvoiceType.purchase);
    expect(posting.movements.single.direction.name, 'inbound');
    expect(posting.movements.single.type, PosStockMovementType.purchase);
    expect(posting.postings.single.voucher.amount.minorUnits, 200);
  });

  test('rebuilds the same request with stable invoice, movement, and ledger IDs', () async {
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

  test('rejects expiry-tracked products until lot persistence is available', () async {
    final result = await useCase(product(expiry: true))(input());
    expect(result.isFailure, isTrue);
  });

  test('rejects bank payment when no mapped bank account exists', () async {
    final result = await useCase(product())(input(method: PosPaymentMethod.bank, advance: 50));
    expect(result.isFailure, isTrue);
  });

  test('builds a fully paid cash purchase with a matching payment voucher', () async {
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
}
