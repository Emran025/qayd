import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/pos/pos_receipt_formatter.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_details.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_receipt_print_job.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

void main() {
  const currency = CurrencyCode(
    code: 'YER',
    nameAr: 'ريال يمني',
    symbol: 'ر.ي',
    fractionalDigits: 2,
  );

  PosInvoiceDetails buildDetails({
    bool includeAdjustments = true,
    bool partiallyPaid = true,
  }) {
    final invoiceId = 'invoice-receipt-84';
    final line = PosInvoiceLine.create(
      id: 'line-1',
      invoiceId: invoiceId,
      productId: 'product-1',
      productNameSnapshot: 'قهوة عربية',
      quantity: PosQuantity.fromScaled(2, scale: 0),
      unitPrice: Money.fromMinorUnits(500, currency),
      unitCost: Money.fromMinorUnits(300, currency),
      discount: includeAdjustments
          ? Money.fromMinorUnits(100, currency)
          : Money.zero(currency),
      tax: includeAdjustments
          ? Money.fromMinorUnits(50, currency)
          : Money.zero(currency),
      createdAt: DateTime.utc(2026, 2, 3, 9),
    );
    final draft = PosInvoice.draft(
      id: invoiceId,
      invoiceNumber: 'S-000084',
      type: PosInvoiceType.sale,
      warehouseId: 'warehouse-1',
      currency: currency,
      lines: [line],
      idempotencyKey: 'sale:$invoiceId',
      invoiceDate: DateTime.utc(2026, 2, 3, 9),
      now: DateTime.utc(2026, 2, 3, 9),
      counterpartyAccountId: AccountId('customer-42'),
      discount: includeAdjustments
          ? Money.fromMinorUnits(50, currency)
          : Money.zero(currency),
      tax: includeAdjustments
          ? Money.fromMinorUnits(25, currency)
          : Money.zero(currency),
    );
    var invoice = draft.post(DateTime.utc(2026, 2, 3, 9, 1));
    if (partiallyPaid) {
      invoice = invoice.applyPayment(
        Money.fromMinorUnits(300, currency),
        DateTime.utc(2026, 2, 3, 9, 2),
      );
    } else {
      invoice = invoice.applyPayment(
        invoice.total,
        DateTime.utc(2026, 2, 3, 9, 2),
      );
    }
    final payments = partiallyPaid
        ? [
            PosInvoicePayment.create(
              id: 'payment-1',
              invoiceId: invoiceId,
              accountId: AccountId('cash-1'),
              method: PosPaymentMethod.cash,
              amount: Money.fromMinorUnits(300, currency),
              currency: currency,
              occurredAt: DateTime.utc(2026, 2, 3, 9, 2),
              idempotencyKey: 'payment:$invoiceId',
            ),
          ]
        : [
            PosInvoicePayment.create(
              id: 'payment-1',
              invoiceId: invoiceId,
              accountId: AccountId('cash-1'),
              method: PosPaymentMethod.cash,
              amount: invoice.total,
              currency: currency,
              occurredAt: DateTime.utc(2026, 2, 3, 9, 2),
              idempotencyKey: 'payment:$invoiceId',
            ),
          ];
    return PosInvoiceDetails(invoice: invoice, payments: payments);
  }

  List<String> texts(PosReceiptPrintJob job) =>
      job.lines.map((line) => line.text).toList(growable: false);

  test(
    'formats an RTL 58 mm receipt from invoice snapshots and marks reprint',
    () {
      final details = buildDetails();
      final job = const PosReceiptFormatter().format(
        details: details,
        paperWidth: PosReceiptPaperWidth.mm58,
        isReprint: true,
      );
      final content = texts(job).join('\n');

      expect(job.paperWidth, PosReceiptPaperWidth.mm58);
      expect(job.nominalWidthDots, 384);
      expect(job.rightToLeft, isTrue);
      expect(job.requiresRasterizedArabicFallback, isTrue);
      expect(job.isReprint, isTrue);
      expect(content, contains('إعادة طباعة'));
      expect(content, contains('S-000084'));
      expect(content, contains('قهوة عربية'));
      expect(content, contains('customer-42'));
      expect(content, contains('1.00 ر.ي'));
      expect(content, contains('0.50 ر.ي'));
      expect(content, contains('1.50 ر.ي'));
      expect(content, contains('0.75 ر.ي'));
      expect(content, contains('9.25 ر.ي'));
      expect(content, contains('3.00 ر.ي'));
      expect(content, contains('6.25 ر.ي'));
      expect(content, contains('نقداً'));
      expect(content, contains('آجل'));
      expect(content, contains('مبلغ آجل مستحق'));
    },
  );

  test('supports the 80 mm layout target without changing receipt values', () {
    final details = buildDetails();
    final job = const PosReceiptFormatter().format(
      details: details,
      paperWidth: PosReceiptPaperWidth.mm80,
      isReprint: false,
    );

    expect(job.paperWidth, PosReceiptPaperWidth.mm80);
    expect(job.nominalWidthDots, 576);
    expect(job.isReprint, isFalse);
    expect(texts(job).join('\n'), contains('9.25 ر.ي'));
    expect(texts(job).join('\n'), isNot(contains('إعادة طباعة')));
  });

  test(
    'omits discount and tax rows when the snapshot has no recorded values',
    () {
      final job = const PosReceiptFormatter().format(
        details: buildDetails(includeAdjustments: false, partiallyPaid: false),
        paperWidth: PosReceiptPaperWidth.mm58,
        isReprint: false,
      );
      final content = texts(job).join('\n');

      expect(content, isNot(contains('الخصم المسجل')));
      expect(content, isNot(contains('الضريبة المسجلة')));
      expect(content, isNot(contains('خصم الصنف')));
      expect(content, isNot(contains('ضريبة الصنف')));
    },
  );

  test('keeps receipt lines immutable after formatting', () {
    final job = const PosReceiptFormatter().format(
      details: buildDetails(),
      paperWidth: PosReceiptPaperWidth.mm58,
      isReprint: false,
    );

    expect(
      () => job.lines.add(const PosReceiptLine('tamper')),
      throwsUnsupportedError,
    );
  });
}
