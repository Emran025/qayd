import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/mappers/pos_sales_return_sync_snapshot_codec.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';
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
final _date = DateTime.utc(2026, 1, 2, 10);

PosAccountingPosting _posting({
  required String id,
  required String counterparty,
  required String affected,
  required int amount,
}) {
  final voucher = Voucher.draft(
    id: VoucherId(id),
    type: VoucherType.receipt,
    date: _date,
    amount: Money.fromMinorUnits(amount, _currency),
    currency: _currency,
    counterpartyId: AccountId(counterparty),
    affectedAccountId: AccountId(affected),
    referenceNumber: 'return-1',
    description: 'POS sales return',
    createdAt: _date,
  ).confirm(_date);
  return PosAccountingPosting(
    sourceId: 'return-1',
    voucher: voucher,
    entries: EntryGenerator().generateForConfirmedVoucher(
      voucher: voucher,
      transactionId: TransactionId('$id:transaction'),
      debitEntryId: EntryId('$id:debit'),
      creditEntryId: EntryId('$id:credit'),
      ledgerCreatedAt: _date,
    ),
  );
}

PosSalesReturnPosting _sample() {
  final invoice = PosInvoice.draft(
    id: 'return-1',
    invoiceNumber: 'R-000001',
    type: PosInvoiceType.salesReturn,
    warehouseId: 'warehouse-1',
    currency: _currency,
    sourceInvoiceId: 'sale-1',
    idempotencyKey: 'return-key-1',
    invoiceDate: _date,
    now: _date,
    lines: [
      PosInvoiceLine.create(
        id: 'return-1:line:0',
        invoiceId: 'return-1',
        productId: 'product-1',
        productNameSnapshot: 'Coffee',
        barcodeSnapshot: '6290001',
        quantity: PosQuantity.whole(1),
        unitPrice: Money.fromMinorUnits(500, _currency),
        unitCost: Money.fromMinorUnits(100, _currency),
        discount: Money.zero(_currency),
        tax: Money.zero(_currency),
        sourceLineId: 'sale-line-1',
        expiryTrackingSnapshot: false,
        createdAt: _date,
      ),
    ],
  ).post(_date).applyPayment(Money.fromMinorUnits(500, _currency), _date);
  final refund = PosInvoicePayment.create(
    id: 'return-1:refund:0',
    invoiceId: 'return-1',
    accountId: AccountId('cash'),
    method: PosPaymentMethod.cash,
    amount: invoice.total,
    currency: _currency,
    occurredAt: _date,
    idempotencyKey: 'return-key-1:refund:0',
  );
  final movement = PosStockMovement.create(
    id: 'return-1:movement:0',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: PosStockMovementType.salesReturn,
    direction: PosStockMovementDirection.inbound,
    quantity: PosQuantity.whole(1),
    unitCost: Money.fromMinorUnits(100, _currency),
    sourceType: 'pos_invoice',
    sourceId: 'return-1',
    sourceLineId: 'return-1:line:0',
    occurredAt: _date,
    idempotencyKey: 'return-key-1:movement:0',
    createdAt: _date,
  );
  return PosSalesReturnPosting(
    invoice: invoice,
    sourceInvoiceId: 'sale-1',
    salesReturnsAccountId: AccountId('sales-returns'),
    inventoryAccountId: AccountId('inventory'),
    costOfGoodsSoldAccountId: AccountId('cogs'),
    movements: [movement],
    postings: [
      _posting(
        id: 'return-1:voucher:refund',
        counterparty: 'cash',
        affected: 'sales-returns',
        amount: 500,
      ),
      _posting(
        id: 'return-1:voucher:cogs',
        counterparty: 'cogs',
        affected: 'inventory',
        amount: 100,
      ),
    ],
    refundPayments: [refund],
    voidSource: true,
    reason: 'customer return',
  );
}

void main() {
  test('round-trips every nested persistence field deeply', () {
    final encoded = PosSalesReturnSyncSnapshotCodec.encode(_sample());
    final decoded = PosSalesReturnSyncSnapshotCodec.decode(encoded);
    expect(decoded.invoice.lines.single.barcodeSnapshot, '6290001');
    expect(decoded.refundPayments.single.id, 'return-1:refund:0');
    expect(decoded.movements.single.sourceLineId, 'return-1:line:0');
    expect(decoded.postings, hasLength(2));
    expect(
      decoded.postings.every((posting) => posting.entries.length == 2),
      isTrue,
    );
    expect(decoded.voidSource, isTrue);
    expect(decoded.reason, 'customer return');
    expect(PosSalesReturnSyncSnapshotCodec.encode(decoded), equals(encoded));
  });

  test('rejects unsupported schema, missing fields, and extra fields', () {
    final raw = PosSalesReturnSyncSnapshotCodec.encode(_sample());
    expect(
      () => PosSalesReturnSyncSnapshotCodec.decode({...raw, 'schema': 'v0'}),
      throwsFormatException,
    );
    final missing = Map<String, Object?>.from(raw)..remove('reason');
    expect(
      () => PosSalesReturnSyncSnapshotCodec.decode(missing),
      throwsFormatException,
    );
    expect(
      () => PosSalesReturnSyncSnapshotCodec.decode({...raw, 'extra': true}),
      throwsFormatException,
    );
  });

  test('rejects malformed scalar and malformed nested rows', () {
    final raw = PosSalesReturnSyncSnapshotCodec.encode(_sample());
    expect(
      () =>
          PosSalesReturnSyncSnapshotCodec.decode({...raw, 'void_source': true}),
      throwsFormatException,
    );
    final malformed = Map<String, Object?>.from(raw)
      ..['refund_payments'] = [
        {
          ...(raw['refund_payments'] as List).single as Map,
          'amount_minor': '500',
        },
      ];
    expect(
      () => PosSalesReturnSyncSnapshotCodec.decode(malformed),
      throwsFormatException,
    );
  });

  test('surfaces domain invariant failures as FormatException', () {
    final raw = PosSalesReturnSyncSnapshotCodec.encode(_sample());
    final broken = Map<String, Object?>.from(raw)
      ..['source_invoice_id'] = 'different-sale';
    expect(
      () => PosSalesReturnSyncSnapshotCodec.decode(broken),
      throwsFormatException,
    );
  });
}
