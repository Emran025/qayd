import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_signature.dart';
import 'package:qayd/domain/entities/pos_discount_rule.dart';
import 'package:qayd/domain/exceptions/invalid_pos_invoice_exception.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

void main() {
  const currency = CurrencyCode(
    code: 'YER',
    nameAr: 'ريال يمني',
    symbol: 'ر.ي',
  );

  PosInvoiceLine line({
    String invoiceId = 'invoice-1',
    int quantity = 1250,
    int scale = 3,
    int unitPrice = 400,
    int unitCost = 250,
    int discount = 0,
    int tax = 0,
    PosDiscountRule? discountRule,
  }) {
    return PosInvoiceLine.create(
      id: 'line-1',
      invoiceId: invoiceId,
      productId: 'product-1',
      productNameSnapshot: 'Coffee',
      barcodeSnapshot: '629000000001',
      quantity: PosQuantity.fromScaled(quantity, scale: scale),
      unitPrice: Money.fromMinorUnits(unitPrice, currency),
      unitCost: Money.fromMinorUnits(unitCost, currency),
      discount: Money.fromMinorUnits(discount, currency),
      tax: Money.fromMinorUnits(tax, currency),
      discountRule: discountRule,
      createdAt: DateTime.utc(2026, 1, 1, 10),
    );
  }

  PosInvoice invoice({
    List<PosInvoiceLine>? lines,
    Money? discount,
    PosDiscountRule? cartDiscountRule,
    Money? tax,
  }) {
    return PosInvoice.draft(
      id: 'invoice-1',
      invoiceNumber: 'S-000001',
      type: PosInvoiceType.sale,
      warehouseId: 'warehouse-1',
      currency: currency,
      lines: lines ?? [line()],
      idempotencyKey: 'sale:invoice-1',
      invoiceDate: DateTime.utc(2026, 1, 1, 10),
      now: DateTime.utc(2026, 1, 1, 10),
      discount: discount,
      cartDiscountRule: cartDiscountRule,
      tax: tax,
    );
  }

  group('PosInvoice', () {
    test('computes scaled quantity totals with integer half-up rounding', () {
      final result = invoice();

      // 1.250 × 400 = 500 minor units.
      expect(result.subtotal.minorUnits, 500);
      expect(result.total.minorUnits, 500);
      expect(result.due.minorUnits, 500);
      expect(result.lines.single.lineTotal.minorUnits, 500);
    });

    test('includes line and invoice adjustments exactly', () {
      final result = invoice(
        lines: [line(discount: 10, tax: 20)],
        discount: Money.fromMinorUnits(5, currency),
        tax: Money.fromMinorUnits(7, currency),
      );

      expect(result.subtotal.minorUnits, 500);
      expect(result.discount.minorUnits, 15);
      expect(result.tax.minorUnits, 27);
      expect(result.total.minorUnits, 512);
    });

    test(
      'applies cart discount after line discounts and stores both totals',
      () {
        final lineRule = PosDiscountRule.fixed(
          amount: Money.fromMinorUnits(50, currency),
          reason: 'Line offer',
          actorId: 'device-1',
        );
        final cartRule = PosDiscountRule.percentage(
          basisPoints: 1000,
          reason: 'Cart offer',
          actorId: 'device-1',
        );
        final result = invoice(
          lines: [line(discount: 50, discountRule: lineRule)],
          discount: Money.fromMinorUnits(45, currency),
          cartDiscountRule: cartRule,
        );

        expect(result.subtotal.minorUnits, 500);
        expect(result.lines.single.discount.minorUnits, 50);
        expect(result.cartDiscount.minorUnits, 45);
        expect(result.discount.minorUnits, 95);
        expect(result.total.minorUnits, 405);
        expect(result.lines.single.lineTotal.minorUnits, 450);
      },
    );

    test('posts then tracks partial and full payment', () {
      final posted = invoice().post(DateTime.utc(2026, 1, 1, 11));
      final partial = posted.applyPayment(
        Money.fromMinorUnits(200, currency),
        DateTime.utc(2026, 1, 1, 11, 1),
      );
      final paid = partial.applyPayment(
        Money.fromMinorUnits(300, currency),
        DateTime.utc(2026, 1, 1, 11, 2),
      );

      expect(posted.status, PosDocumentStatus.posted);
      expect(partial.status, PosDocumentStatus.partiallyPaid);
      expect(partial.paid.minorUnits, 200);
      expect(partial.due.minorUnits, 300);
      expect(paid.status, PosDocumentStatus.paid);
      expect(paid.due.isZero, isTrue);
    });

    test('rejects payment above total', () {
      final posted = invoice().post(DateTime.utc(2026, 1, 1, 11));

      expect(
        () => posted.applyPayment(
          Money.fromMinorUnits(501, currency),
          DateTime.utc(2026, 1, 1, 11),
        ),
        throwsA(isA<InvalidPosInvoiceException>()),
      );
    });

    test(
      'rejects posting a non-draft invoice and mismatched line ownership',
      () {
        final posted = invoice().post(DateTime.utc(2026, 1, 1, 11));
        expect(
          () => posted.post(DateTime.utc(2026, 1, 1, 12)),
          throwsA(isA<InvalidPosInvoiceException>()),
        );
        expect(
          () => invoice(lines: [line(invoiceId: 'other-invoice')]),
          throwsA(isA<InvalidPosInvoiceException>()),
        );
      },
    );

    test('attaches only a signature for the same invoice', () {
      final value = invoice().attachSignature(
        PosInvoiceSignature(
          invoiceId: 'invoice-1',
          signatureHex: 'aa',
          signerPublicKeyHex: 'bb',
          payloadHashHex: 'cc',
          signedAt: DateTime.utc(2026, 1, 1, 11),
        ),
        DateTime.utc(2026, 1, 1, 11),
      );

      expect(value.signature?.invoiceId, 'invoice-1');
      expect(
        () => invoice().attachSignature(
          PosInvoiceSignature(
            invoiceId: 'other',
            signatureHex: 'aa',
            signerPublicKeyHex: 'bb',
            payloadHashHex: 'cc',
            signedAt: DateTime.utc(2026, 1, 1, 11),
          ),
          DateTime.utc(2026, 1, 1, 11),
        ),
        throwsA(isA<InvalidPosInvoiceException>()),
      );
    });
  });
}
