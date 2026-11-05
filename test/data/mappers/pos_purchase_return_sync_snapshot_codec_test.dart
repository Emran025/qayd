import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/mappers/pos_purchase_return_sync_snapshot_codec.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_purchase_return_posting.dart';
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

PosPurchaseReturnPosting _sample() {
  final date = DateTime.utc(2026, 1, 11, 10);
  const invoiceId = 'purchase-return-1';
  final line = PosInvoiceLine.create(
    id: 'purchase-return-line-1',
    invoiceId: invoiceId,
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    quantity: PosQuantity.whole(1),
    unitPrice: Money.fromMinorUnits(100, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    sourceLineId: 'purchase-line-1',
    createdAt: date,
    expiryTrackingSnapshot: false,
  );
  final invoice = PosInvoice.draft(
    id: invoiceId,
    invoiceNumber: 'PR-1',
    type: PosInvoiceType.purchaseReturn,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [line],
    counterpartyAccountId: AccountId('supplier'),
    sourceInvoiceId: 'purchase-1',
    idempotencyKey: 'purchase-return-key-1',
    invoiceDate: date,
    now: date,
  ).post(date);
  final movement = PosStockMovement.create(
    id: 'purchase-return-movement-1',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: PosStockMovementType.purchaseReturn,
    direction: PosStockMovementDirection.outbound,
    quantity: PosQuantity.whole(1),
    unitCost: Money.fromMinorUnits(100, _currency),
    sourceType: 'pos_invoice',
    sourceId: invoiceId,
    sourceLineId: line.id,
    reversesSourceId: 'purchase-1',
    occurredAt: date,
    createdAt: date,
    idempotencyKey: 'purchase-return-movement-key-1',
  );
  final voucher = Voucher.draft(
    id: VoucherId('purchase-return-voucher-1'),
    type: VoucherType.payment,
    date: date,
    amount: Money.fromMinorUnits(100, _currency),
    currency: _currency,
    counterpartyId: AccountId('payables'),
    affectedAccountId: AccountId('inventory'),
    referenceNumber: invoiceId,
    description: 'Purchase return credit note',
    createdAt: date,
  ).confirm(date);
  final entries = EntryGenerator().generateForConfirmedVoucher(
    voucher: voucher,
    transactionId: TransactionId('purchase-return-tx-1'),
    debitEntryId: EntryId('purchase-return-debit-1'),
    creditEntryId: EntryId('purchase-return-credit-1'),
    ledgerCreatedAt: date,
  );
  return PosPurchaseReturnPosting(
    invoice: invoice,
    sourceInvoiceId: 'purchase-1',
    supplierPayablesAccountId: AccountId('payables'),
    inventoryAccountId: AccountId('inventory'),
    purchaseReturnsAccountId: AccountId('purchase-returns'),
    movements: [movement],
    postings: [
      PosAccountingPosting(
        sourceId: invoiceId,
        voucher: voucher,
        entries: entries,
      ),
    ],
    reason: 'supplier credit note',
  );
}

void main() {
  test('round-trips the complete supplier credit snapshot', () {
    final encoded = PosPurchaseReturnSyncSnapshotCodec.encode(_sample());
    final decoded = PosPurchaseReturnSyncSnapshotCodec.decode(encoded);

    expect(decoded.invoice.sourceInvoiceId, 'purchase-1');
    expect(decoded.invoice.paid.minorUnits, 0);
    expect(decoded.movements.single.unitCost.minorUnits, 100);
    expect(decoded.postings.single.entries, hasLength(2));
    expect(PosPurchaseReturnSyncSnapshotCodec.encode(decoded), encoded);
  });

  test(
    'rejects unsupported, missing, extra, and inconsistent snapshot data',
    () {
      final encoded = PosPurchaseReturnSyncSnapshotCodec.encode(_sample());
      expect(
        () => PosPurchaseReturnSyncSnapshotCodec.decode({
          ...encoded,
          'schema': 'qayd.pos.purchase-return-posting.v0',
        }),
        throwsFormatException,
      );
      final missing = Map<String, Object?>.from(encoded)
        ..remove('supplier_payables_account_id');
      expect(
        () => PosPurchaseReturnSyncSnapshotCodec.decode(missing),
        throwsFormatException,
      );
      final extra = Map<String, Object?>.from(encoded)..['unexpected'] = true;
      expect(
        () => PosPurchaseReturnSyncSnapshotCodec.decode(extra),
        throwsFormatException,
      );
      final incomplete = Map<String, Object?>.from(encoded)
        ..['movements'] = <Object?>[];
      expect(
        () => PosPurchaseReturnSyncSnapshotCodec.decode(incomplete),
        throwsFormatException,
      );
    },
  );
}
