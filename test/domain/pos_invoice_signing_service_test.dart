import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/services/crypto_identity_service.dart';
import 'package:qayd/domain/services/pos_invoice_signing_service.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/digital_signature.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/mnemonic_phrase.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

final class _CryptoFake implements CryptoIdentityService {
  @override
  MnemonicPhrase generateMnemonic() => throw UnimplementedError();

  @override
  CryptoKeyPair deriveKeyPair(MnemonicPhrase mnemonic) =>
      throw UnimplementedError();

  @override
  DigitalSignature sign(Uint8List payloadHash, CryptoKeyPair keyPair) =>
      DigitalSignature(
        signatureBytes: Uint8List.fromList(keyPair.privateKey),
        signerPublicKey: keyPair.publicKey,
        payloadHash: payloadHash,
      );

  @override
  bool verify(
    Uint8List signatureBytes,
    Uint8List payloadHash,
    Uint8List publicKey,
  ) => true;
}

void main() {
  const currency = CurrencyCode(code: 'YER', nameAr: 'ريال', symbol: 'ر.ي');
  final invoice = PosInvoice.draft(
    id: 'invoice-1',
    invoiceNumber: 'S-1',
    type: PosInvoiceType.sale,
    warehouseId: 'warehouse-1',
    currency: currency,
    lines: [
      PosInvoiceLine.create(
        id: 'line-1',
        invoiceId: 'invoice-1',
        productId: 'product-1',
        productNameSnapshot: 'Coffee',
        quantity: PosQuantity.fromScaled(1250, scale: 3),
        unitPrice: Money.fromMinorUnits(400, currency),
        unitCost: Money.fromMinorUnits(250, currency),
        discount: Money.zero(currency),
        tax: Money.zero(currency),
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    ],
    idempotencyKey: 'sale:invoice-1',
    invoiceDate: DateTime.utc(2026, 1, 1),
    now: DateTime.utc(2026, 1, 1),
  ).post(DateTime.utc(2026, 1, 1, 1));

  final payment = PosInvoicePayment.create(
    id: 'payment-1',
    invoiceId: invoice.id,
    accountId: AccountId('cash'),
    method: PosPaymentMethod.cash,
    amount: Money.fromMinorUnits(200, currency),
    currency: currency,
    occurredAt: DateTime.utc(2026, 1, 1, 1, 1),
    idempotencyKey: 'payment:1',
  );

  test('canonical payload includes fractional line snapshots and payments', () {
    final service = PosInvoiceSigningService(
      receiptSigningService: ReceiptSigningService(
        cryptoService: _CryptoFake(),
      ),
    );
    final withoutPayment = service.canonicalPayload(invoice, const []);
    final withPayment = service.canonicalPayload(invoice, [payment]);

    expect(withoutPayment, contains('QAYD_POS_INVOICE_V1'));
    expect(withoutPayment, contains('1250,3'));
    expect(withoutPayment, isNot(withPayment));
    expect(withPayment, contains('payment-1,cash,cash,200'));
  });

  test('credit due date and terms are part of the signed invoice payload', () {
    final service = PosInvoiceSigningService(
      receiptSigningService: ReceiptSigningService(
        cryptoService: _CryptoFake(),
      ),
    );
    PosInvoice creditInvoice({DateTime? dueDate, String? terms}) =>
        PosInvoice.draft(
          id: invoice.id,
          invoiceNumber: invoice.invoiceNumber,
          type: invoice.type,
          warehouseId: invoice.warehouseId,
          currency: currency,
          lines: invoice.lines,
          creditDueDate: dueDate,
          creditTerms: terms,
          idempotencyKey: invoice.idempotencyKey,
          invoiceDate: invoice.invoiceDate,
          now: invoice.createdAt,
        ).post(DateTime.utc(2026, 1, 1, 1));

    final baseline = service.canonicalPayload(invoice, const []);
    final withTerms = service.canonicalPayload(
      creditInvoice(dueDate: DateTime.utc(2026, 2, 1), terms: 'Net 30 days'),
      const [],
    );
    final changedDate = service.canonicalPayload(
      creditInvoice(dueDate: DateTime.utc(2026, 2, 2), terms: 'Net 30 days'),
      const [],
    );
    final changedTerms = service.canonicalPayload(
      creditInvoice(dueDate: DateTime.utc(2026, 2, 1), terms: 'Net 45 days'),
      const [],
    );

    expect(baseline, contains('QAYD_POS_INVOICE_V1'));
    expect(withTerms, contains('QAYD_POS_INVOICE_V3'));
    expect(withTerms, contains('Net 30 days'));
    expect(withTerms, isNot(baseline));
    expect(changedDate, isNot(withTerms));
    expect(changedTerms, isNot(withTerms));
  });
}
