import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/pos/build_pos_invoice_payment_collection_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_details.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/pos_invoice_read_repository.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_side.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/standard_account_classification_kind.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';

class _Invoices extends Mock implements PosInvoiceReadRepository {}

class _Accounts extends Mock implements AccountRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(AccountId('fallback-account'));
  });

  final sar = CurrencyCode(
    code: 'SAR',
    nameAr: 'ريال سعودي',
    symbol: 'ر.س',
  );
  final usd = CurrencyCode(
    code: 'USD',
    nameAr: 'دولار أمريكي',
    symbol: '\$',
  );
  final soldAt = DateTime.utc(2026, 2, 1, 10);
  final collectedAt = DateTime.utc(2026, 2, 2, 11);

  PosInvoice invoice({int initiallyPaid = 0}) {
    final line = PosInvoiceLine.create(
      id: 'line-1',
      invoiceId: 'invoice-1',
      productId: 'product-1',
      productNameSnapshot: 'Coffee',
      quantity: PosQuantity.whole(2),
      unitPrice: Money.fromMinorUnits(500, sar),
      unitCost: Money.fromMinorUnits(100, sar),
      discount: Money.zero(sar),
      tax: Money.zero(sar),
      createdAt: soldAt,
    );
    var result = PosInvoice.draft(
      id: 'invoice-1',
      invoiceNumber: 'S-0001',
      type: PosInvoiceType.sale,
      warehouseId: 'warehouse-1',
      currency: sar,
      lines: [line],
      idempotencyKey: 'sale-key',
      invoiceDate: soldAt,
      now: soldAt,
      counterpartyAccountId: AccountId('customer-1'),
    ).post(soldAt);
    if (initiallyPaid > 0) {
      result = result.applyPayment(
        Money.fromMinorUnits(initiallyPaid, sar),
        soldAt,
      );
    }
    return result;
  }

  Account account(
    String id, {
    required AccountClassification classification,
    bool active = true,
  }) =>
      Account.createRoot(
        id: AccountId(id),
        name: id,
        classification: classification,
        createdAt: soldAt,
        isActive: active,
      );

  Account cashAccount({bool active = true}) => account(
        'cash-1',
        classification: AccountClassification.standard(
          StandardAccountClassificationKind.liquidAssets,
        ),
        active: active,
      );

  Account customerAccount({bool active = true}) => account(
        'customer-1',
        classification: AccountClassification.standard(
          StandardAccountClassificationKind.receivables,
        ),
        active: active,
      );

  BuildPosInvoicePaymentCollectionUseCase useCase({
    required PosInvoiceDetails details,
    Account? cash,
    Account? customer,
  }) {
    final invoices = _Invoices();
    final accounts = _Accounts();
    when(() => invoices.getById('invoice-1'))
        .thenAnswer((_) async => Success(details));
    when(() => accounts.getById(AccountId('cash-1')))
        .thenAnswer((_) async => Success(cash ?? cashAccount()));
    when(() => accounts.getById(AccountId('customer-1'))).thenAnswer(
      (_) async => Success(customer ?? customerAccount()),
    );
    return BuildPosInvoicePaymentCollectionUseCase(
      invoiceRepository: invoices,
      accountRepository: accounts,
    );
  }

  BuildPosInvoicePaymentCollectionInput input({
    int amount = 250,
    String currency = 'SAR',
    PosPaymentMethod method = PosPaymentMethod.bank,
    DateTime? occurredAt,
  }) =>
      BuildPosInvoicePaymentCollectionInput(
        invoiceId: 'invoice-1',
        amountMinorUnits: amount,
        currencyCode: currency,
        paymentAccountId: AccountId('cash-1'),
        paymentMethod: method,
        paymentId: 'payment-collection-1',
        idempotencyKey: 'collection-key-1',
        occurredAt: occurredAt ?? collectedAt,
        createdAt: collectedAt,
      );

  test('builds partial receipt against the exact customer receivable', () async {
    final result = await useCase(
      details: PosInvoiceDetails(invoice: invoice(), payments: const []),
    )(input());

    expect(result.isSuccess, isTrue);
    final posting = result.valueOrNull!;
    expect(posting.invoiceAfter.paid.minorUnits, 250);
    expect(posting.invoiceAfter.due.minorUnits, 750);
    expect(posting.invoiceAfter.status, PosDocumentStatus.partiallyPaid);
    expect(posting.payment.currency.code, 'SAR');
    expect(posting.accountingPosting.voucher.type, VoucherType.receipt);
    expect(posting.accountingPosting.voucher.counterpartyId.value, 'customer-1');
    expect(posting.accountingPosting.voucher.affectedAccountId.value, 'cash-1');
    expect(posting.accountingPosting.entries, hasLength(2));
    expect(posting.accountingPosting.entries.first.side, EntrySide.debit);
    expect(posting.accountingPosting.entries.first.accountId.value, 'cash-1');
    expect(posting.accountingPosting.entries.last.side, EntrySide.credit);
    expect(
      posting.accountingPosting.entries.last.accountId.value,
      'customer-1',
    );
  });

  test('accepts final collection and moves invoice to paid', () async {
    final current = invoice(initiallyPaid: 400);
    final initialPayment = PosInvoicePayment.create(
      id: 'advance-1',
      invoiceId: 'invoice-1',
      accountId: AccountId('cash-1'),
      method: PosPaymentMethod.cash,
      amount: Money.fromMinorUnits(400, sar),
      currency: sar,
      occurredAt: soldAt,
      idempotencyKey: 'advance-key',
    );
    final result = await useCase(
      details: PosInvoiceDetails(invoice: current, payments: [initialPayment]),
    )(input(amount: 600));

    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull!.invoiceAfter.paid.minorUnits, 1000);
    expect(result.valueOrNull!.invoiceAfter.due.minorUnits, 0);
    expect(result.valueOrNull!.invoiceAfter.status, PosDocumentStatus.paid);
  });

  test('rejects over-collection and invoice/payment currency mismatch', () async {
    final builder = useCase(
      details: PosInvoiceDetails(invoice: invoice(), payments: const []),
    );

    final over = await builder(input(amount: 1001));
    final wrongCurrency = await builder(input(currency: usd.code));

    expect(over.isFailure, isTrue);
    expect(wrongCurrency.isFailure, isTrue);
  });

  test('rejects a collection date earlier than the sale invoice', () async {
    final result = await useCase(
      details: PosInvoiceDetails(invoice: invoice(), payments: const []),
    )(input(occurredAt: soldAt.subtract(const Duration(days: 1))));

    expect(result.isFailure, isTrue);
  });

  test('rejects inactive or non-liquid receiving accounts', () async {
    final details = PosInvoiceDetails(invoice: invoice(), payments: const []);
    final inactive = await useCase(
      details: details,
      cash: cashAccount(active: false),
    )(input());
    final wrongType = await useCase(
      details: details,
      cash: account(
        'cash-1',
        classification: AccountClassification.custom(
          name: 'Other asset',
          nature: AccountNature.debit,
        ),
      ),
    )(input());

    expect(inactive.isFailure, isTrue);
    expect(wrongType.isFailure, isTrue);
  });

  test('recovers an exact existing collection after invoice is already paid',
      () async {
    final firstPayment = PosInvoicePayment.create(
      id: 'payment-collection-1',
      invoiceId: 'invoice-1',
      accountId: AccountId('cash-1'),
      method: PosPaymentMethod.bank,
      amount: Money.fromMinorUnits(1000, sar),
      currency: sar,
      occurredAt: collectedAt,
      idempotencyKey: 'collection-key-1',
    );
    final alreadyPaid = invoice().applyPayment(
      Money.fromMinorUnits(1000, sar),
      collectedAt,
    );
    final result = await useCase(
      details: PosInvoiceDetails(
        invoice: alreadyPaid,
        payments: [firstPayment],
      ),
    )(input(amount: 1000));

    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull!.isReplay, isTrue);
    expect(result.valueOrNull!.invoiceAfter.due.minorUnits, 0);
    expect(result.valueOrNull!.payment.id, firstPayment.id);
  });

  test('rejects an inactive recorded customer instead of crediting another party',
      () async {
    final result = await useCase(
      details: PosInvoiceDetails(invoice: invoice(), payments: const []),
      customer: customerAccount(active: false),
    )(input());

    expect(result.isFailure, isTrue);
  });
}
