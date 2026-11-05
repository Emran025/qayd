import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/mappers/pos_sale_sync_snapshot_codec.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';

final _currency = CurrencyCode(
  code: 'SAR',
  nameAr: 'ريال سعودي',
  symbol: 'ر.س',
);

PosSalePosting _sampleSale() {
  final date = DateTime.utc(2026, 1, 1, 10);
  const invoiceId = 'invoice-sync-1';
  final line = PosInvoiceLine.create(
    id: 'line-sync-1',
    invoiceId: invoiceId,
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    barcodeSnapshot: '6290001',
    quantity: PosQuantity.whole(1),
    unitPrice: Money.fromMinorUnits(500, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    createdAt: date,
  );
  final invoice = PosInvoice.draft(
    id: invoiceId,
    invoiceNumber: 'S-000001',
    type: PosInvoiceType.sale,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [line],
    idempotencyKey: 'sale-sync-key-1',
    invoiceDate: date,
    now: date,
  ).post(date);

  return PosSalePosting(
    invoice: invoice,
    movements: [
      PosStockMovement.create(
        id: 'movement-sync-1',
        productId: 'product-1',
        warehouseId: 'warehouse-1',
        type: PosStockMovementType.sale,
        direction: PosStockMovementDirection.outbound,
        quantity: PosQuantity.whole(1),
        unitCost: Money.fromMinorUnits(100, _currency),
        sourceType: 'pos_invoice',
        sourceId: invoiceId,
        sourceLineId: 'line-sync-1',
        occurredAt: date,
        idempotencyKey: 'sale-stock-sync-key-1',
        createdAt: date,
      ),
    ],
    postings: [
      _accountingPosting(
        voucherId: 'voucher-sale-sync-1',
        invoiceId: invoiceId,
        transactionId: 'transaction-sale-sync-1',
        debitEntryId: 'entry-sale-debit-sync-1',
        creditEntryId: 'entry-sale-credit-sync-1',
        type: VoucherType.receipt,
        counterpartyId: 'revenue',
        affectedAccountId: 'cash',
        amount: 500,
        date: date,
      ),
      _accountingPosting(
        voucherId: 'voucher-cogs-sync-1',
        invoiceId: invoiceId,
        transactionId: 'transaction-cogs-sync-1',
        debitEntryId: 'entry-cogs-debit-sync-1',
        creditEntryId: 'entry-cogs-credit-sync-1',
        type: VoucherType.payment,
        counterpartyId: 'cogs',
        affectedAccountId: 'inventory',
        amount: 100,
        date: date,
      ),
    ],
    payments: const [],
  );
}

PosAccountingPosting _accountingPosting({
  required String voucherId,
  required String invoiceId,
  required String transactionId,
  required String debitEntryId,
  required String creditEntryId,
  required VoucherType type,
  required String counterpartyId,
  required String affectedAccountId,
  required int amount,
  required DateTime date,
}) {
  final voucher = Voucher.draft(
    id: VoucherId(voucherId),
    type: type,
    date: date,
    amount: Money.fromMinorUnits(amount, _currency),
    currency: _currency,
    counterpartyId: AccountId(counterpartyId),
    affectedAccountId: AccountId(affectedAccountId),
    referenceNumber: invoiceId,
    description: 'POS sale snapshot test',
    createdAt: date,
  ).confirm(date);
  final entries = EntryGenerator().generateForConfirmedVoucher(
    voucher: voucher,
    transactionId: TransactionId(transactionId),
    debitEntryId: EntryId(debitEntryId),
    creditEntryId: EntryId(creditEntryId),
    ledgerCreatedAt: date,
  );
  return PosAccountingPosting(
    sourceId: invoiceId,
    voucher: voucher,
    entries: entries,
  );
}

void main() {
  test('round-trips the complete POS sale snapshot without data loss', () {
    final posting = _sampleSale();
    final encoded = PosSaleSyncSnapshotCodec.encode(posting);
    final decoded = PosSaleSyncSnapshotCodec.decode(encoded);

    expect(decoded.invoice.id, posting.invoice.id);
    expect(decoded.invoice.lines.single.id, posting.invoice.lines.single.id);
    expect(decoded.movements.single.id, posting.movements.single.id);
    expect(decoded.postings, hasLength(posting.postings.length));
    expect(
      decoded.postings.map((p) => p.voucher.id.value),
      posting.postings.map((p) => p.voucher.id.value),
    );
    expect(PosSaleSyncSnapshotCodec.encode(decoded), equals(encoded));
  });

  test('rejects an unsupported schema before reading payload fields', () {
    expect(
      () => PosSaleSyncSnapshotCodec.decode({
        'schema': 'qayd.pos.sale-posting.v0',
      }),
      throwsFormatException,
    );
  });

  test('rejects missing and unexpected root fields strictly', () {
    expect(
      () => PosSaleSyncSnapshotCodec.decode({
        'schema': PosSaleSyncSnapshotCodec.schema,
        'invoice': <String, Object?>{},
        'lines': <Object?>[],
        'payments': <Object?>[],
        'movements': <Object?>[],
      }),
      throwsFormatException,
    );
    expect(
      () => PosSaleSyncSnapshotCodec.decode({
        'schema': PosSaleSyncSnapshotCodec.schema,
        'invoice': <String, Object?>{},
        'lines': <Object?>[],
        'payments': <Object?>[],
        'movements': <Object?>[],
        'postings': <Object?>[],
        'extra': true,
      }),
      throwsFormatException,
    );
  });

  test('rejects a malformed scalar row rather than applying a default', () {
    expect(
      () => PosSaleSyncSnapshotCodec.decode({
        'schema': PosSaleSyncSnapshotCodec.schema,
        'invoice': <String, Object?>{},
        'lines': <Object?>[
          <String, Object?>{'id': 7},
        ],
        'payments': <Object?>[],
        'movements': <Object?>[],
        'postings': <Object?>[],
      }),
      throwsFormatException,
    );
  });

  test('surfaces aggregate constructor invariants as format errors', () {
    expect(
      () => PosSaleSyncSnapshotCodec.decode({
        'schema': PosSaleSyncSnapshotCodec.schema,
        'invoice': <String, Object?>{},
        'lines': <Object?>[],
        'payments': <Object?>[],
        'movements': <Object?>[],
        'postings': <Object?>[],
      }),
      throwsFormatException,
    );
  });
}
