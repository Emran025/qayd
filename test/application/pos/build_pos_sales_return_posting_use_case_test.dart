import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/pos/build_pos_sales_return_posting_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_details.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/repositories/pos_invoice_read_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_side.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

class _Invoices extends Mock implements PosInvoiceReadRepository {}

class _Installation extends Mock implements PosTemplateInstallationRepository {}

void main() {
  setUpAll(() => registerFallbackValue(PosTemplateDefinition.current()));

  final currency = CurrencyCode(
    code: 'SAR',
    nameAr: 'ريال سعودي',
    symbol: 'ر.س',
  );
  final at = DateTime.utc(2026, 1, 10, 10);

  PosInvoice sourceInvoice({
    int unitCost = 100,
    CurrencyCode? costCurrency,
    int globalDiscount = 0,
    int globalTax = 0,
    bool includeFreeLine = false,
  }) {
    final line = PosInvoiceLine.create(
      id: 'sale-line-1',
      invoiceId: 'sale-1',
      productId: 'product-1',
      productNameSnapshot: 'Coffee',
      quantity: PosQuantity.whole(2),
      unitPrice: Money.fromMinorUnits(500, currency),
      unitCost: Money.fromMinorUnits(unitCost, costCurrency ?? currency),
      discount: Money.zero(currency),
      tax: Money.zero(currency),
      createdAt: at,
    );
    final invoiceLines = includeFreeLine
        ? <PosInvoiceLine>[
            PosInvoiceLine.create(
              id: 'sale-line-free',
              invoiceId: 'sale-1',
              productId: 'product-free',
              productNameSnapshot: 'Free sample',
              quantity: PosQuantity.whole(1),
              unitPrice: Money.fromMinorUnits(500, currency),
              unitCost: Money.fromMinorUnits(unitCost, costCurrency ?? currency),
              discount: Money.fromMinorUnits(500, currency),
              tax: Money.zero(currency),
              createdAt: at,
            ),
            PosInvoiceLine.create(
              id: 'sale-line-paid',
              invoiceId: 'sale-1',
              productId: 'product-paid',
              productNameSnapshot: 'Paid item',
              quantity: PosQuantity.whole(1),
              unitPrice: Money.fromMinorUnits(500, currency),
              unitCost: Money.fromMinorUnits(unitCost, costCurrency ?? currency),
              discount: Money.zero(currency),
              tax: Money.zero(currency),
              createdAt: at,
            ),
          ]
        : <PosInvoiceLine>[line];
    final totalMinor = 1000 -
        (includeFreeLine ? 500 : 0) -
        globalDiscount +
        globalTax;
    return PosInvoice.draft(
      id: 'sale-1',
      invoiceNumber: 'S-1',
      type: PosInvoiceType.sale,
      warehouseId: 'warehouse-1',
      currency: currency,
      lines: invoiceLines,
      idempotencyKey: 'sale-key-1',
      invoiceDate: at,
      now: at,
      discount: Money.fromMinorUnits(globalDiscount, currency),
      tax: Money.fromMinorUnits(globalTax, currency),
    ).post(at).applyPayment(
          Money.fromMinorUnits(totalMinor, currency),
          at,
        );
  }

  PosInvoicePayment payment({
    required String id,
    required String accountId,
    required PosPaymentMethod method,
    required int amount,
  }) =>
      PosInvoicePayment.create(
        id: id,
        invoiceId: 'sale-1',
        accountId: AccountId(accountId),
        method: method,
        amount: Money.fromMinorUnits(amount, currency),
        currency: currency,
        occurredAt: at,
        idempotencyKey: '$id-key',
      );

  BuildPosSalesReturnPostingUseCase createUseCase({
    List<PosInvoicePayment>? payments,
    List<PosInvoiceDetails> priorReturns = const [],
    int unitCost = 100,
    CurrencyCode? costCurrency,
    int globalDiscount = 0,
    int globalTax = 0,
    bool includeFreeLine = false,
  }) {
    final invoices = _Invoices();
    final installation = _Installation();
    final source = sourceInvoice(
      unitCost: unitCost,
      costCurrency: costCurrency,
      globalDiscount: globalDiscount,
      globalTax: globalTax,
      includeFreeLine: includeFreeLine,
    );
    when(() => invoices.getById('sale-1')).thenAnswer(
      (_) async => Success(PosInvoiceDetails(
        invoice: source,
        payments: payments ?? [
          payment(
            id: 'sale-payment-1',
            accountId: 'cash',
            method: PosPaymentMethod.cash,
            amount: source.total.minorUnits,
          ),
        ],
      )),
    );
    when(() => invoices.getReturnsForSource('sale-1'))
        .thenAnswer((_) async => Success(priorReturns));
    when(() => installation.getEnabledInstallation(
          template: any(named: 'template'),
        )).thenAnswer(
      (_) async => Success(
        PosActivationResult(
          templateKey: PosTemplateDefinition.coreTemplateKey,
          templateVersion: PosTemplateDefinition.currentVersion,
          warehouseId: 'warehouse-1',
          accountIdsByKey: {
            PosTemplateAccountKey.inventoryAsset.value: 'inventory',
            PosTemplateAccountKey.costOfGoodsSold.value: 'cogs',
            PosTemplateAccountKey.salesReturns.value: 'sales-returns',
          },
          alreadyInstalled: true,
        ),
      ),
    );
    return BuildPosSalesReturnPostingUseCase(
      invoiceRepository: invoices,
      installationRepository: installation,
    );
  }

  BuildPosSalesReturnPostingInput input({
    required List<BuildPosSalesReturnLineInput> lines,
    bool voidSource = false,
    String returnInvoiceId = 'return-1',
    String idempotencyKey = 'return-key-1',
  }) => BuildPosSalesReturnPostingInput(
        returnInvoiceId: returnInvoiceId,
        returnInvoiceNumber: 'R-${returnInvoiceId.replaceAll('return-', '')}',
        sourceInvoiceId: 'sale-1',
        idempotencyKey: idempotencyKey,
        lines: lines,
        invoiceDate: DateTime.utc(2026, 1, 11, 10),
        createdAt: DateTime.utc(2026, 1, 11, 10),
        voidSource: voidSource,
      );

  test('posts refund and COGS reversal with opposite sale signs', () async {
    final result = await createUseCase()(input(
      lines: [
        BuildPosSalesReturnLineInput(
          sourceLineId: 'sale-line-1',
          quantity: PosQuantity.whole(1),
        ),
      ],
    ));

    expect(result.isSuccess, isTrue);
    final posting = result.valueOrNull!;
    expect(posting.movements.single.direction.name, 'inbound');
    expect(posting.refundPayments.single.amount.minorUnits, 500);

    final refund = posting.postings.firstWhere(
      (item) => item.voucher.id.value.contains(':refund:'),
    );
    expect(refund.voucher.affectedAccountId.value, 'sales-returns');
    expect(refund.voucher.counterpartyId.value, 'cash');
    expect(
      refund.entries.singleWhere((entry) => entry.isDebit).accountId.value,
      'sales-returns',
    );
    expect(
      refund.entries.singleWhere((entry) => entry.isCredit).accountId.value,
      'cash',
    );

    final cogs = posting.postings.singleWhere(
      (item) => item.voucher.id.value.contains('cogs-reversal'),
    );
    expect(cogs.voucher.type.name, 'receipt');
    expect(cogs.voucher.affectedAccountId.value, 'inventory');
    expect(cogs.voucher.counterpartyId.value, 'cogs');
    expect(
      cogs.entries.singleWhere((entry) => entry.isDebit).accountId.value,
      'inventory',
    );
    expect(
      cogs.entries.singleWhere((entry) => entry.isCredit).accountId.value,
      'cogs',
    );
  });

  test('reverses COGS in source cost currency while refund stays in invoice currency',
      () async {
    const usd = CurrencyCode(code: 'USD', nameAr: 'دولار', symbol: r'$');
    final result = await createUseCase(costCurrency: usd)(input(
      lines: [
        BuildPosSalesReturnLineInput(
          sourceLineId: 'sale-line-1',
          quantity: PosQuantity.whole(1),
        ),
      ],
    ));

    expect(result.isSuccess, isTrue);
    final posting = result.valueOrNull!;
    expect(posting.invoice.currency, currency);
    expect(posting.refundPayments.single.amount.currency, currency);
    expect(posting.movements.single.unitCost.currency, usd);
    expect(posting.invoice.lines.single.unitCost.currency, usd);
    final cogs = posting.postings.singleWhere(
      (item) => item.voucher.id.value.contains('cogs-reversal'),
    );
    expect(cogs.voucher.type.name, 'receipt');
    expect(cogs.voucher.currency, usd);
    expect(cogs.voucher.amount, Money.fromMinorUnits(100, usd));
    expect(
      cogs.entries.singleWhere((entry) => entry.isDebit).accountId.value,
      'inventory',
    );
    expect(
      cogs.entries.singleWhere((entry) => entry.isCredit).accountId.value,
      'cogs',
    );
  });

  test('gives equal split refunds unique voucher and ledger identities', () async {
    final payments = [
      payment(
        id: 'sale-payment-1',
        accountId: 'cash',
        method: PosPaymentMethod.cash,
        amount: 500,
      ),
      payment(
        id: 'sale-payment-2',
        accountId: 'cash',
        method: PosPaymentMethod.cash,
        amount: 500,
      ),
    ];
    final result = await createUseCase(payments: payments)(input(
      lines: [
        BuildPosSalesReturnLineInput(
          sourceLineId: 'sale-line-1',
          quantity: PosQuantity.whole(1),
        ),
      ],
    ));

    expect(result.isSuccess, isTrue);
    final posting = result.valueOrNull!;
    final refundPostings = posting.postings
        .where((item) => item.voucher.id.value.contains(':refund:'))
        .toList();
    expect(refundPostings, hasLength(2));
    expect(
      refundPostings.map((item) => item.voucher.id.value).toSet(),
      hasLength(2),
    );
    expect(
      refundPostings.expand((item) => item.entries).map((entry) => entry.id.value).toSet(),
      hasLength(4),
    );
    expect(
      refundPostings.expand((item) => item.entries).where((e) => e.side == EntrySide.debit),
      hasLength(2),
    );
  });

  test('rejects a return that exceeds prior returned quantity', () async {
    final priorInvoice = PosInvoice.draft(
      id: 'prior-return',
      invoiceNumber: 'R-0',
      type: PosInvoiceType.salesReturn,
      warehouseId: 'warehouse-1',
      currency: currency,
      lines: [
        PosInvoiceLine.create(
          id: 'prior-return-line',
          invoiceId: 'prior-return',
          productId: 'product-1',
          productNameSnapshot: 'Coffee',
          quantity: PosQuantity.whole(1),
          unitPrice: Money.fromMinorUnits(500, currency),
          unitCost: Money.fromMinorUnits(100, currency),
          discount: Money.zero(currency),
          tax: Money.zero(currency),
          sourceLineId: 'sale-line-1',
          createdAt: at,
        ),
      ],
      idempotencyKey: 'prior-return-key',
      sourceInvoiceId: 'sale-1',
      invoiceDate: at,
      now: at,
    ).post(at).applyPayment(Money.fromMinorUnits(500, currency), at);

    final useCase = createUseCase(
      priorReturns: [PosInvoiceDetails(invoice: priorInvoice, payments: [])],
    );
    final result = await useCase(input(
      lines: [
        BuildPosSalesReturnLineInput(
          sourceLineId: 'sale-line-1',
          quantity: PosQuantity.whole(2),
        ),
      ],
    ));

    expect(result.isFailure, isTrue);
  });

  test('builds full-void request for every source line and no partial lines', () async {
    final result = await createUseCase()(input(lines: const [], voidSource: true));

    expect(result.isSuccess, isTrue);
    final posting = result.valueOrNull!;
    expect(posting.voidSource, isTrue);
    expect(posting.invoice.lines, hasLength(1));
    expect(posting.invoice.lines.single.quantity, PosQuantity.whole(2));
  });

  test('does not create a zero-value COGS voucher', () async {
    final result = await createUseCase(unitCost: 0)(input(
      lines: [
        BuildPosSalesReturnLineInput(
          sourceLineId: 'sale-line-1',
          quantity: PosQuantity.whole(1),
        ),
      ],
    ));

    expect(result.isSuccess, isTrue);
    expect(
      result.valueOrNull!.postings.where((p) => p.voucher.id.value.contains('cogs-reversal')),
      isEmpty,
    );
  });

  test('allocates global invoice discount and tax cumulatively without losing pennies', () async {
    final firstResult = await createUseCase(
      globalDiscount: 101,
      globalTax: 51,
    )(input(
      lines: [
        BuildPosSalesReturnLineInput(
          sourceLineId: 'sale-line-1',
          quantity: PosQuantity.whole(1),
        ),
      ],
    ));
    expect(firstResult.isSuccess, isTrue);
    final first = firstResult.valueOrNull!;
    expect(first.invoice.discount.minorUnits, 51);
    expect(first.invoice.tax.minorUnits, 26);
    expect(first.invoice.total.minorUnits, 475);

    final secondResult = await createUseCase(
      globalDiscount: 101,
      globalTax: 51,
      priorReturns: [
        PosInvoiceDetails(
          invoice: first.invoice,
          payments: first.refundPayments,
        ),
      ],
    )(input(
      returnInvoiceId: 'return-2',
      idempotencyKey: 'return-key-2',
      lines: [
        BuildPosSalesReturnLineInput(
          sourceLineId: 'sale-line-1',
          quantity: PosQuantity.whole(1),
        ),
      ],
    ));

    expect(secondResult.isSuccess, isTrue);
    final second = secondResult.valueOrNull!;
    expect(second.invoice.discount.minorUnits, 50);
    expect(second.invoice.tax.minorUnits, 25);
    expect(
      first.invoice.discount.minorUnits + second.invoice.discount.minorUnits,
      101,
    );
    expect(first.invoice.tax.minorUnits + second.invoice.tax.minorUnits, 51);
    expect(first.invoice.total.minorUnits + second.invoice.total.minorUnits, 950);
  });

  test('returns a fully discounted item without inventing a zero-value refund', () async {
    final result = await createUseCase(includeFreeLine: true)(input(
      lines: [
        BuildPosSalesReturnLineInput(
          sourceLineId: 'sale-line-free',
          quantity: PosQuantity.whole(1),
        ),
      ],
    ));

    expect(result.isSuccess, isTrue);
    final posting = result.valueOrNull!;
    expect(posting.invoice.total.minorUnits, 0);
    expect(posting.refundPayments, isEmpty);
    expect(posting.postings, hasLength(1));
    expect(posting.postings.single.voucher.amount.minorUnits, 100);
    expect(posting.postings.single.voucher.affectedAccountId.value, 'inventory');
  });
}
