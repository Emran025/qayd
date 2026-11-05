import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/mappers/pos_purchase_sync_snapshot_codec.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_purchase_posting.dart';
import 'package:qayd/domain/entities/pos_stock_lot.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';

final _currency = CurrencyCode(
  code: 'SAR',
  nameAr: 'ريال سعودي',
  symbol: 'ر.س',
);

PosPurchasePosting _samplePurchase() {
  final date = DateTime.utc(2026, 1, 10, 10);
  const invoiceId = 'purchase-sync-1';
  final line = PosInvoiceLine.create(
    id: 'purchase-line-sync-1',
    invoiceId: invoiceId,
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    quantity: PosQuantity.whole(2),
    unitPrice: Money.fromMinorUnits(100, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    expiryTrackingSnapshot: true,
    createdAt: date,
  );
  final invoice = PosInvoice.draft(
    id: invoiceId,
    invoiceNumber: 'P-000001',
    type: PosInvoiceType.purchase,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [line],
    idempotencyKey: 'purchase-sync-key-1',
    invoiceDate: date,
    now: date,
    counterpartyAccountId: AccountId('supplier'),
  ).post(date);
  final lot = PosStockLot.create(
    id: 'purchase-lot-sync-1',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    supplierLotNumber: 'SUP-1',
    expiryDate: PosDate.fromParts(2026, 2, 1),
    receivedQuantity: PosQuantity.whole(2),
    unitCost: Money.fromMinorUnits(100, _currency),
    createdAt: date,
  );
  final movement = PosStockMovement.create(
    id: 'purchase-movement-sync-1',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: PosStockMovementType.purchase,
    direction: PosStockMovementDirection.inbound,
    quantity: PosQuantity.whole(2),
    unitCost: Money.fromMinorUnits(100, _currency),
    sourceType: 'pos_invoice',
    sourceId: invoiceId,
    sourceLineId: line.id,
    lotId: lot.id,
    occurredAt: date,
    idempotencyKey: 'purchase-stock-sync-key-1',
    createdAt: date,
  );
  final voucher = Voucher.draft(
    id: VoucherId('purchase-voucher-sync-1'),
    type: VoucherType.receipt,
    date: date,
    amount: Money.fromMinorUnits(200, _currency),
    currency: _currency,
    counterpartyId: AccountId('payables'),
    affectedAccountId: AccountId('inventory'),
    referenceNumber: invoiceId,
    description: 'Purchase snapshot',
    createdAt: date,
  ).confirm(date);
  final entries = EntryGenerator().generateForConfirmedVoucher(
    voucher: voucher,
    transactionId: TransactionId('purchase-tx-sync-1'),
    debitEntryId: EntryId('purchase-debit-sync-1'),
    creditEntryId: EntryId('purchase-credit-sync-1'),
    ledgerCreatedAt: date,
  );
  return PosPurchasePosting(
    invoice: invoice,
    movements: [movement],
    lots: [lot],
    postings: [
      PosAccountingPosting(
        sourceId: invoiceId,
        voucher: voucher,
        entries: entries,
      ),
    ],
    payments: const [],
  );
}

void main() {
  test('round-trips the complete purchase snapshot byte-for-byte as a map', () {
    final encoded = PosPurchaseSyncSnapshotCodec.encode(_samplePurchase());
    final decoded = PosPurchaseSyncSnapshotCodec.decode(encoded);
    expect(decoded.lots.single.id, 'purchase-lot-sync-1');
    expect(decoded.postings.single.entries, hasLength(2));
    expect(PosPurchaseSyncSnapshotCodec.encode(decoded), equals(encoded));
  });

  test('rejects unsupported schema, missing fields, and extra fields', () {
    final encoded = PosPurchaseSyncSnapshotCodec.encode(_samplePurchase());
    expect(
      () => PosPurchaseSyncSnapshotCodec.decode({
        ...encoded,
        'schema': 'qayd.pos.purchase-posting.v0',
      }),
      throwsFormatException,
    );
    final missing = Map<String, Object?>.from(encoded)..remove('lots');
    expect(
      () => PosPurchaseSyncSnapshotCodec.decode(missing),
      throwsFormatException,
    );
    final extra = Map<String, Object?>.from(encoded)..['extra'] = true;
    expect(
      () => PosPurchaseSyncSnapshotCodec.decode(extra),
      throwsFormatException,
    );
  });

  test('rejects malformed scalar, enum/date, and exact nested fields', () {
    final encoded = PosPurchaseSyncSnapshotCodec.encode(_samplePurchase());
    final malformed = Map<String, Object?>.from(encoded);
    malformed['lots'] = [
      {
        ...(encoded['lots'] as List).single as Map<String, Object?>,
        'unknown': 1,
      },
    ];
    expect(
      () => PosPurchaseSyncSnapshotCodec.decode(malformed),
      throwsFormatException,
    );
    final badDate = Map<String, Object?>.from(encoded);
    badDate['lots'] = [
      {
        ...(encoded['lots'] as List).single as Map<String, Object?>,
        'expiry_date': '2026-2-1',
      },
    ];
    expect(
      () => PosPurchaseSyncSnapshotCodec.decode(badDate),
      throwsFormatException,
    );
  });

  test('surfaces purchase aggregate invariants as FormatException', () {
    final encoded = PosPurchaseSyncSnapshotCodec.encode(_samplePurchase());
    final broken = Map<String, Object?>.from(encoded);
    broken['movements'] = <Object?>[];
    expect(
      () => PosPurchaseSyncSnapshotCodec.decode(broken),
      throwsFormatException,
    );
  });
}
