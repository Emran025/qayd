import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/pos/build_pos_purchase_return_posting_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_details.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/pos_invoice_read_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

class _Invoices extends Mock implements PosInvoiceReadRepository {}

class _Stock extends Mock implements PosStockMovementRepository {}

class _Installation extends Mock implements PosTemplateInstallationRepository {}

class _Accounts extends Mock implements AccountRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(PosTemplateDefinition.current());
    registerFallbackValue(AccountId('fallback-account'));
  });

  final currency = CurrencyCode(
    code: 'SAR',
    nameAr: 'ريال سعودي',
    symbol: 'ر.س',
  );
  final at = DateTime.utc(2026, 1, 10, 10);

  PosInvoice sourceInvoice({required bool paid, int taxMinor = 0}) {
    final line = PosInvoiceLine.create(
      id: 'purchase-line-1',
      invoiceId: 'purchase-1',
      productId: 'product-1',
      productNameSnapshot: 'Coffee',
      quantity: PosQuantity.whole(2),
      unitPrice: Money.fromMinorUnits(500, currency),
      unitCost: Money.fromMinorUnits(100, currency),
      discount: Money.zero(currency),
      tax: Money.fromMinorUnits(taxMinor, currency),
      createdAt: at,
      expiryTrackingSnapshot: false,
    );
    final invoice = PosInvoice.draft(
      id: 'purchase-1',
      invoiceNumber: 'P-1',
      type: PosInvoiceType.purchase,
      warehouseId: 'warehouse-1',
      currency: currency,
      lines: [line],
      counterpartyAccountId: AccountId('supplier'),
      idempotencyKey: 'purchase-key-1',
      invoiceDate: at,
      now: at,
    ).post(at);
    return paid ? invoice.applyPayment(invoice.total, at) : invoice;
  }

  PosStockMovement sourceMovement() => PosStockMovement.create(
    id: 'purchase-movement-1',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: PosStockMovementType.purchase,
    direction: PosStockMovementDirection.inbound,
    quantity: PosQuantity.whole(2),
    unitCost: Money.fromMinorUnits(100, currency),
    sourceType: 'pos_invoice',
    sourceId: 'purchase-1',
    sourceLineId: 'purchase-line-1',
    occurredAt: at,
    createdAt: at,
    idempotencyKey: 'purchase-movement-key-1',
  );

  Account activeAccount(String id) => Account.restore(
    id: AccountId(id),
    name: id,
    nature: AccountNature.credit,
    classification: AccountClassification.payables,
    isDefault: false,
    createdAt: at,
    isActive: true,
    isArchived: false,
  );

  BuildPosPurchaseReturnPostingUseCase setup({
    required bool paid,
    int taxMinor = 0,
  }) {
    final invoices = _Invoices();
    final installation = _Installation();
    final stock = _Stock();
    final accounts = _Accounts();
    final source = sourceInvoice(paid: paid, taxMinor: taxMinor);
    when(() => invoices.getById('purchase-1')).thenAnswer(
      (_) async =>
          Success(PosInvoiceDetails(invoice: source, payments: const [])),
    );
    when(
      () => invoices.getReturnsForSource('purchase-1'),
    ).thenAnswer((_) async => const Success([]));
    when(
      () =>
          installation.getEnabledInstallation(template: any(named: 'template')),
    ).thenAnswer(
      (_) async => Success(
        PosActivationResult(
          templateKey: PosTemplateDefinition.coreTemplateKey,
          templateVersion: PosTemplateDefinition.currentVersion,
          warehouseId: 'warehouse-1',
          accountIdsByKey: {
            PosTemplateAccountKey.inventoryAsset.value: 'inventory',
            PosTemplateAccountKey.supplierPayables.value: 'payables',
            PosTemplateAccountKey.purchaseReturns.value: 'purchase-returns',
          },
          alreadyInstalled: true,
        ),
      ),
    );
    when(
      () => stock.listMovementsForSource(
        sourceType: 'pos_invoice',
        sourceId: 'purchase-1',
        type: PosStockMovementType.purchase,
      ),
    ).thenAnswer((_) async => Success([sourceMovement()]));
    when(
      () =>
          stock.getBalance(productId: 'product-1', warehouseId: 'warehouse-1'),
    ).thenAnswer(
      (_) async => Success(
        PosStockBalance(
          quantity: PosQuantity.whole(4),
          valuation: Money.fromMinorUnits(600, currency),
        ),
      ),
    );
    when(() => accounts.getById(any())).thenAnswer((invocation) async {
      final id = invocation.positionalArguments.single as AccountId;
      return Success(activeAccount(id.value));
    });
    return BuildPosPurchaseReturnPostingUseCase(
      invoiceRepository: invoices,
      installationRepository: installation,
      stockRepository: stock,
      accountRepository: accounts,
    );
  }

  BuildPosPurchaseReturnPostingInput input({int quantity = 1}) =>
      BuildPosPurchaseReturnPostingInput(
        returnInvoiceId: 'purchase-return-1',
        returnInvoiceNumber: 'PR-1',
        sourceInvoiceId: 'purchase-1',
        idempotencyKey: 'purchase-return-key-1',
        lines: [
          BuildPosPurchaseReturnLineInput(
            sourceLineId: 'purchase-line-1',
            quantity: PosQuantity.whole(quantity),
          ),
        ],
        invoiceDate: DateTime.utc(2026, 1, 11, 10),
        createdAt: DateTime.utc(2026, 1, 11, 10),
        reason: 'supplier credit note',
      );

  test(
    'credits supplier for full source price and removes stock at live average',
    () async {
      final result = await setup(paid: false)(input());

      expect(result.isSuccess, isTrue);
      final posting = result.valueOrNull!;
      expect(posting.invoice.total.minorUnits, 500);
      expect(posting.invoice.paid.minorUnits, 0);
      expect(posting.invoice.due.minorUnits, 500);
      expect(
        posting.movements.single.direction,
        PosStockMovementDirection.outbound,
      );
      expect(posting.movements.single.unitCost.minorUnits, 150);
      expect(posting.postings, hasLength(2));

      final inventoryLeg = posting.postings.firstWhere(
        (item) => item.voucher.affectedAccountId.value == 'inventory',
      );
      expect(inventoryLeg.voucher.amount.minorUnits, 150);
      expect(
        inventoryLeg.entries
            .singleWhere((entry) => entry.isDebit)
            .accountId
            .value,
        'payables',
      );
      expect(
        inventoryLeg.entries
            .singleWhere((entry) => entry.isCredit)
            .accountId
            .value,
        'inventory',
      );
      final varianceLeg = posting.postings.firstWhere(
        (item) => item.voucher.affectedAccountId.value == 'purchase-returns',
      );
      expect(varianceLeg.voucher.amount.minorUnits, 350);
      expect(
        varianceLeg.entries
            .singleWhere((entry) => entry.isDebit)
            .accountId
            .value,
        'payables',
      );
      expect(
        varianceLeg.entries
            .singleWhere((entry) => entry.isCredit)
            .accountId
            .value,
        'purchase-returns',
      );
    },
  );

  test(
    'a paid purchase creates supplier credit but never a cash refund',
    () async {
      final result = await setup(paid: true)(input());

      expect(result.isSuccess, isTrue);
      final posting = result.valueOrNull!;
      expect(posting.invoice.paid.minorUnits, 0);
      expect(posting.invoice.due.minorUnits, posting.invoice.total.minorUnits);
      expect(
        posting.postings
            .expand((item) => item.entries)
            .any(
              (entry) =>
                  entry.accountId.value == 'cash' ||
                  entry.accountId.value == 'bank',
            ),
        isFalse,
      );
      expect(
        posting.postings
            .expand((item) => item.entries)
            .where((entry) => entry.isDebit)
            .where((entry) => entry.accountId.value == 'payables')
            .fold<int>(0, (sum, entry) => sum + entry.amount.minorUnits),
        500,
      );
    },
  );

  test('rejects returning more quantity than the source purchase', () async {
    final result = await setup(paid: false)(input(quantity: 3));

    expect(result.isFailure, isTrue);
  });

  test(
    'rejects tax-bearing purchases until a tax control account is mapped',
    () async {
      final result = await setup(paid: false, taxMinor: 25)(input());

      expect(result.isFailure, isTrue);
    },
  );
}
