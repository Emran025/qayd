import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/mappers/pos_invoice_payment_collection_sync_snapshot_codec.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/entities/pos_discount_rule.dart';
import 'package:qayd/domain/entities/pos_invoice_signature.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/attachment_id.dart';
import 'package:qayd/domain/value_objects/attachment_ref.dart';
import 'package:qayd/domain/value_objects/attachment_source_type.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/tripartite_meta.dart';
import 'package:qayd/domain/value_objects/tripartite_role.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';

final _currency = CurrencyCode(
  code: 'SAR',
  nameAr: 'ريال سعودي',
  symbol: 'ر.س',
);
final _date = DateTime.utc(2026, 2, 1, 10);

PosInvoicePaymentCollectionPosting fixture() {
  final line = PosInvoiceLine.create(
    id: 'line-1',
    invoiceId: 'invoice-1',
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    quantity: PosQuantity.whole(2),
    barcodeSnapshot: '6281234567890',
    unitPrice: Money.fromMinorUnits(500, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.fromMinorUnits(100, _currency),
    tax: Money.zero(_currency),
    discountRule: PosDiscountRule.fixed(
      amount: Money.fromMinorUnits(100, _currency),
      reason: 'campaign',
      actorId: 'operator-1',
    ),
    createdAt: _date,
  );
  final before =
      PosInvoice.draft(
            id: 'invoice-1',
            invoiceNumber: 'S-0001',
            type: PosInvoiceType.sale,
            warehouseId: 'warehouse-1',
            currency: _currency,
            lines: [line],
            idempotencyKey: 'sale-key-1',
            invoiceDate: _date,
            now: _date,
            counterpartyAccountId: AccountId('customer-1'),
            discount: Money.fromMinorUnits(50, _currency),
            cartDiscountRule: PosDiscountRule.fixed(
              amount: Money.fromMinorUnits(50, _currency),
              reason: 'cart campaign',
              actorId: 'operator-1',
            ),
          )
          .post(_date)
          .attachSignature(
            PosInvoiceSignature(
              invoiceId: 'invoice-1',
              signatureHex: 'aa11',
              signerPublicKeyHex: 'bb22',
              payloadHashHex: 'cc33',
              signedAt: _date,
            ),
            _date,
          );
  final payment = PosInvoicePayment.create(
    id: 'collection-1',
    invoiceId: before.id,
    accountId: AccountId('cash-1'),
    method: PosPaymentMethod.bank,
    amount: Money.fromMinorUnits(300, _currency),
    currency: _currency,
    occurredAt: _date.add(const Duration(hours: 1)),
    idempotencyKey: 'collection-key-1',
  );
  final voucher = Voucher.draft(
    id: VoucherId('collection-1:voucher'),
    type: VoucherType.receipt,
    date: payment.occurredAt,
    amount: payment.amount,
    currency: _currency,
    counterpartyId: AccountId('customer-1'),
    affectedAccountId: AccountId('cash-1'),
    referenceNumber: payment.id,
    description: 'POS collection S-0001',
    createdAt: _date,
    attachmentRefs: [
      AttachmentRef(
        id: AttachmentId('attachment-1'),
        storagePath: '/secure/receipt.enc',
        mimeType: 'image/png',
        byteSize: 1234,
        encryptedBlobHash: 'hash',
        thumbnailPath: '/secure/thumb.enc',
        sourceType: AttachmentSourceType.camera,
      ),
    ],
    tags: const ['pos', 'receipt'],
    tripartiteMeta: TripartiteMeta(
      transferGroupId: 'transfer-1',
      role: TripartiteRole.intermediaryReceipt,
      linkedPartyId: AccountId('beneficiary-1'),
      mediatorAccountId: AccountId('mediator-1'),
      feeAmount: Money.fromMinorUnits(10, _currency),
      isContingent: true,
    ),
  ).confirm(_date);
  final accounting = PosAccountingPosting(
    sourceId: payment.id,
    voucher: voucher,
    entries: const EntryGenerator().generateForConfirmedVoucher(
      voucher: voucher,
      transactionId: TransactionId('collection-1:transaction'),
      debitEntryId: EntryId('collection-1:debit'),
      creditEntryId: EntryId('collection-1:credit'),
      ledgerCreatedAt: _date,
    ),
  );
  return PosInvoicePaymentCollectionPosting(
    invoiceBefore: before,
    invoiceAfter: before.applyPayment(payment.amount, payment.occurredAt),
    payment: payment,
    accountingPosting: accounting,
    recordedAt: payment.occurredAt,
  );
}

void main() {
  test('deep round-trip is canonical and JSON-safe', () {
    final encoded = PosInvoicePaymentCollectionSyncSnapshotCodec.encode(
      fixture(),
    );
    expect(
      () => PosInvoicePaymentCollectionSyncSnapshotCodec.encodeJson(fixture()),
      returnsNormally,
    );
    final decoded = PosInvoicePaymentCollectionSyncSnapshotCodec.decode(
      encoded,
    );
    expect(
      PosInvoicePaymentCollectionSyncSnapshotCodec.encode(decoded),
      encoded,
    );
    expect(decoded.invoiceBefore.lines.single.id, 'line-1');
    expect(decoded.invoiceBefore.lines.single.barcodeSnapshot, '6281234567890');
    expect(decoded.invoiceBefore.cartDiscountRule?.reason, 'cart campaign');
    expect(decoded.invoiceBefore.signature?.signatureHex, 'aa11');
    expect(decoded.accountingPosting.voucher.attachmentRefs, hasLength(1));
    expect(
      decoded.accountingPosting.voucher.tripartiteMeta?.transferGroupId,
      'transfer-1',
    );
    expect(decoded.accountingPosting.entries, hasLength(2));
  });

  test(
    'rejects schema, missing, extra, malformed, and invalid enum payloads',
    () {
      final base = PosInvoicePaymentCollectionSyncSnapshotCodec.encode(
        fixture(),
      );
      expect(
        () => PosInvoicePaymentCollectionSyncSnapshotCodec.decode({
          ...base,
          'version': 2,
        }),
        throwsFormatException,
      );
      final missing = Map<String, Object?>.from(base)..remove('recordedAt');
      expect(
        () => PosInvoicePaymentCollectionSyncSnapshotCodec.decode(missing),
        throwsFormatException,
      );
      expect(
        () => PosInvoicePaymentCollectionSyncSnapshotCodec.decode({
          ...base,
          'extra': true,
        }),
        throwsFormatException,
      );
      final malformed = Map<String, Object?>.from(base)..['isReplay'] = 'false';
      expect(
        () => PosInvoicePaymentCollectionSyncSnapshotCodec.decode(malformed),
        throwsFormatException,
      );
      final payment = Map<String, Object?>.from(base['payment']! as Map)
        ..['method'] = 'bogus';
      expect(
        () => PosInvoicePaymentCollectionSyncSnapshotCodec.decode({
          ...base,
          'payment': payment,
        }),
        throwsFormatException,
      );
      expect(
        () => PosInvoicePaymentCollectionSyncSnapshotCodec.decode({
          ...base,
          'payment': <Object, Object?>{...payment, 1: 'not allowed'},
        }),
        throwsFormatException,
      );
    },
  );
}
