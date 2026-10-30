import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_041_pos_invoice_metadata.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/data/repositories/sqlite_pos_sales_return_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _CurrencyRepository implements CurrencyRepository {
  _CurrencyRepository(this.currency);

  final CurrencyCode currency;

  @override
  Future<Result<CurrencyCode?>> getByCode(String code) async =>
      Success(code == currency.code ? currency : null);

  @override
  Future<Result<List<CurrencyCode>>> getAll({bool onlyActive = false}) async =>
      Success([currency]);

  @override
  Future<Result<void>> save(CurrencyCode currency,
          {bool isPredefined = false}) async =>
      const Success(null);

  @override
  Future<Result<void>> toggleActiveStatus(String code, bool isActive) async =>
      const Success(null);

  @override
  Future<Result<String>> getBaseCurrencyCode() async => Success(currency.code);

  @override
  Future<Result<void>> setBaseCurrencyCode(String code) async =>
      const Success(null);
}

final _currency = CurrencyCode(
  code: 'SAR',
  nameAr: 'ريال سعودي',
  symbol: 'ر.س',
);
final _sourceDate = DateTime.utc(2026, 1, 1, 10);
final _returnDate = DateTime.utc(2026, 1, 2, 10);

Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, nature TEXT NOT NULL,
      parent_id TEXT, is_default INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1, is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, standard_classification TEXT,
      custom_classification_name TEXT, custom_classification_nature TEXT,
      metadata TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE vouchers (
      id TEXT PRIMARY KEY, type TEXT NOT NULL, reference_number TEXT,
      date TEXT NOT NULL, amount_minor INTEGER NOT NULL, currency_code TEXT NOT NULL,
      counterparty_id TEXT NOT NULL, affected_account_id TEXT NOT NULL,
      state TEXT NOT NULL, description TEXT, notes TEXT, tags_json TEXT NOT NULL,
      attachments_json TEXT NOT NULL, created_at TEXT NOT NULL, confirmed_at TEXT,
      settled_at TEXT, signer_phone TEXT, canonical_sender_phone TEXT,
      canonical_receiver_phone TEXT, transfer_group_id TEXT, tripartite_role TEXT,
      linked_party_id TEXT, mediator_account_id TEXT, fee_amount_minor INTEGER,
      is_contingent INTEGER NOT NULL DEFAULT 0, origin_voucher_id TEXT,
      rejection_reason TEXT, withdrawn_at TEXT, sender_status TEXT NOT NULL,
      receiver_status TEXT NOT NULL, sender_signature_hex TEXT,
      receiver_signature_hex TEXT, sender_public_key_hex TEXT,
      receiver_public_key_hex TEXT, lifecycle_status TEXT NOT NULL,
      is_inbound INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE ledger_entries (
      id TEXT PRIMARY KEY, transaction_id TEXT NOT NULL, account_id TEXT NOT NULL,
      side TEXT NOT NULL, amount_minor INTEGER NOT NULL, currency_code TEXT NOT NULL,
      voucher_id TEXT NOT NULL, date TEXT NOT NULL, created_at TEXT NOT NULL
    )
  ''');
  await Migration040PosFoundation().up(db);
  await Migration041PosInvoiceMetadata().up(db);
}

Future<void> _seed(Database db) async {
  await db.insert('pos_warehouses', {
    'id': 'warehouse-1',
    'code': 'POS-MAIN',
    'name': 'POS Main',
    'is_default': 1,
    'is_active': 1,
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
  });
  await db.insert('pos_products', {
    'id': 'product-1',
    'sku': 'SKU-1',
    'name': 'Coffee',
    'unit_name': 'unit',
    'currency_code': _currency.code,
    'sale_price_minor': 500,
    'purchase_price_minor': 100,
    'quantity_scale': 0,
    'reorder_level_scaled': 0,
    'expiry_tracking': 0,
    'is_active': 1,
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
  });
  for (final id in ['cash', 'sales-returns', 'inventory', 'cogs']) {
    await db.insert('accounts', {
      'id': id,
      'name': id,
      'nature': id == 'cogs' || id == 'sales-returns' ? 'debit' : 'credit',
      'created_at': '2026-01-01T00:00:00.000Z',
    });
  }
}

PosInvoice _sourceInvoice({int globalDiscount = 0, int globalTax = 0}) {
  final line = PosInvoiceLine.create(
    id: 'sale-line-1',
    invoiceId: 'sale-1',
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    quantity: PosQuantity.whole(2),
    unitPrice: Money.fromMinorUnits(500, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    createdAt: _sourceDate,
  );
  return PosInvoice.draft(
    id: 'sale-1',
    invoiceNumber: 'S-000001',
    type: PosInvoiceType.sale,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [line],
    idempotencyKey: 'sale-key-1',
    invoiceDate: _sourceDate,
    now: _sourceDate,
    discount: Money.fromMinorUnits(globalDiscount, _currency),
    tax: Money.fromMinorUnits(globalTax, _currency),
  ).post(_sourceDate).applyPayment(
        Money.fromMinorUnits(1000 - globalDiscount + globalTax, _currency),
        _sourceDate,
      );
}

PosInvoicePayment _sourcePayment({int amount = 1000}) => PosInvoicePayment.create(
      id: 'sale-payment-1',
      invoiceId: 'sale-1',
      accountId: AccountId('cash'),
      method: PosPaymentMethod.cash,
      amount: Money.fromMinorUnits(amount, _currency),
      currency: _currency,
      occurredAt: _sourceDate,
      idempotencyKey: 'sale-payment-key-1',
    );

PosSalesReturnPosting _returnPosting({
  required String invoiceId,
  required String idempotencyKey,
  required int quantity,
  int globalDiscount = 0,
  int globalTax = 0,
  bool voidSource = false,
}) {
  final invoice = PosInvoice.draft(
    id: invoiceId,
    invoiceNumber: 'R-${invoiceId.replaceAll('return-', '')}',
    type: PosInvoiceType.salesReturn,
    warehouseId: 'warehouse-1',
    currency: _currency,
    sourceInvoiceId: 'sale-1',
    idempotencyKey: idempotencyKey,
    invoiceDate: _returnDate,
    now: _returnDate,
    discount: Money.fromMinorUnits(globalDiscount, _currency),
    tax: Money.fromMinorUnits(globalTax, _currency),
    lines: [
      PosInvoiceLine.create(
        id: '$invoiceId:line:0',
        invoiceId: invoiceId,
        productId: 'product-1',
        productNameSnapshot: 'Coffee',
        quantity: PosQuantity.whole(quantity),
        unitPrice: Money.fromMinorUnits(500, _currency),
        unitCost: Money.fromMinorUnits(100, _currency),
        discount: Money.zero(_currency),
        tax: Money.zero(_currency),
        sourceLineId: 'sale-line-1',
        createdAt: _returnDate,
      ),
    ],
  ).post(_returnDate).applyPayment(
        Money.fromMinorUnits(quantity * 500 - globalDiscount + globalTax, _currency),
        _returnDate,
      );
  final refund = PosInvoicePayment.create(
    id: '$invoiceId:refund:0',
    invoiceId: invoiceId,
    accountId: AccountId('cash'),
    method: PosPaymentMethod.cash,
    amount: invoice.total,
    currency: _currency,
    occurredAt: _returnDate,
    idempotencyKey: '$idempotencyKey:refund:0',
  );
  final movement = PosStockMovement.create(
    id: '$invoiceId:movement:0',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: PosStockMovementType.salesReturn,
    direction: PosStockMovementDirection.inbound,
    quantity: PosQuantity.whole(quantity),
    unitCost: Money.fromMinorUnits(100, _currency),
    sourceType: 'pos_invoice',
    sourceId: invoiceId,
    sourceLineId: '$invoiceId:line:0',
    occurredAt: _returnDate,
    idempotencyKey: '$idempotencyKey:movement:0',
    createdAt: _returnDate,
  );
  PosAccountingPosting posting({
    required String part,
    required String counterparty,
    required String affected,
    required int amount,
  }) {
    final voucher = Voucher.draft(
      id: VoucherId('$invoiceId:voucher:$part'),
      type: VoucherType.receipt,
      date: _returnDate,
      amount: Money.fromMinorUnits(amount, _currency),
      currency: _currency,
      counterpartyId: AccountId(counterparty),
      affectedAccountId: AccountId(affected),
      referenceNumber: invoiceId,
      description: 'POS sales return',
      createdAt: _returnDate,
    ).confirm(_returnDate);
    return PosAccountingPosting(
      sourceId: invoiceId,
      voucher: voucher,
      entries: EntryGenerator().generateForConfirmedVoucher(
        voucher: voucher,
        transactionId: TransactionId('${voucher.id.value}:transaction'),
        debitEntryId: EntryId('${voucher.id.value}:debit'),
        creditEntryId: EntryId('${voucher.id.value}:credit'),
        ledgerCreatedAt: _returnDate,
      ),
    );
  }

  final postings = <PosAccountingPosting>[
    posting(
      part: 'refund',
      counterparty: 'cash',
      affected: 'sales-returns',
    amount: invoice.total.minorUnits,
    ),
  ];
  if (quantity > 0) {
    postings.add(
      posting(
        part: 'cogs-reversal',
        counterparty: 'cogs',
        affected: 'inventory',
        amount: quantity * 100,
      ),
    );
  }
  return PosSalesReturnPosting(
    invoice: invoice,
    sourceInvoiceId: 'sale-1',
    salesReturnsAccountId: AccountId('sales-returns'),
    inventoryAccountId: AccountId('inventory'),
    costOfGoodsSoldAccountId: AccountId('cogs'),
    movements: [movement],
    postings: postings,
    refundPayments: [refund],
    voidSource: voidSource,
    reason: 'test return',
  );
}

void main() {
  sqfliteFfiInit();

  group('SqlitePosSalesReturnPostingRepository', () {
    late Database db;
    late SqlitePosSalesReturnPostingRepository repository;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await _createSchema(db);
      await _seed(db);
      await db.insert('pos_invoices', PosInvoiceMapper.toRow(_sourceInvoice()));
      await db.insert(
        'pos_invoice_lines',
        PosInvoiceMapper.lineToRow(_sourceInvoice().lines.single),
      );
      await db.insert(
        'pos_payments',
        PosInvoiceMapper.paymentToRow(_sourcePayment(), _sourceDate),
      );
      final runner = DatabaseTransactionRunner(db);
      final stock = SqlitePosStockMovementRepository(
        db,
        _CurrencyRepository(_currency),
      );
      repository = SqlitePosSalesReturnPostingRepository(
        runner,
        stock,
        SqliteVoucherRepository(db, runner),
      );
    });

    tearDown(() => db.close());

    test('commits return, stock, refund payment, relation, voucher and ledger atomically', () async {
      final result = await repository.saveAtomically(_returnPosting(
        invoiceId: 'return-1',
        idempotencyKey: 'return-key-1',
        quantity: 1,
      ));

      expect(result.isSuccess, isTrue);
      expect(await db.query('pos_invoices'), hasLength(2));
      expect(await db.query('pos_invoice_lines'), hasLength(2));
      expect(await db.query('pos_payments'), hasLength(2));
      expect(await db.query('pos_returns'), hasLength(1));
      expect(await db.query('pos_stock_movements'), hasLength(1));
      expect(await db.query('vouchers'), hasLength(2));
      expect(await db.query('ledger_entries'), hasLength(4));
      final source = await db.query('pos_invoices', where: 'id = ?', whereArgs: ['sale-1']);
      expect(source.single['status'], 'partiallyReturned');
    });

    test('accepts an exact retry without duplicating any persisted component', () async {
      final posting = _returnPosting(
        invoiceId: 'return-1',
        idempotencyKey: 'return-key-1',
        quantity: 1,
      );
      expect((await repository.saveAtomically(posting)).isSuccess, isTrue);
      final before = [
        await db.query('pos_invoices', orderBy: 'id ASC'),
        await db.query('pos_invoice_lines', orderBy: 'id ASC'),
        await db.query('pos_payments', orderBy: 'id ASC'),
        await db.query('pos_returns', orderBy: 'id ASC'),
        await db.query('pos_stock_movements', orderBy: 'id ASC'),
        await db.query('vouchers', orderBy: 'id ASC'),
        await db.query('ledger_entries', orderBy: 'id ASC'),
      ];

      final retry = await repository.saveAtomically(posting);

      expect(retry.isSuccess, isTrue);
      expect(await db.query('pos_invoices', orderBy: 'id ASC'), before[0]);
      expect(await db.query('pos_invoice_lines', orderBy: 'id ASC'), before[1]);
      expect(await db.query('pos_payments', orderBy: 'id ASC'), before[2]);
      expect(await db.query('pos_returns', orderBy: 'id ASC'), before[3]);
      expect(await db.query('pos_stock_movements', orderBy: 'id ASC'), before[4]);
      expect(await db.query('vouchers', orderBy: 'id ASC'), before[5]);
      expect(await db.query('ledger_entries', orderBy: 'id ASC'), before[6]);
    });

    test('rejects altered payload under an existing idempotency key', () async {
      expect(
        (await repository.saveAtomically(_returnPosting(
          invoiceId: 'return-1',
          idempotencyKey: 'return-key-1',
          quantity: 1,
        ))).isSuccess,
        isTrue,
      );

      final changed = await repository.saveAtomically(_returnPosting(
        invoiceId: 'return-1',
        idempotencyKey: 'return-key-1',
        quantity: 2,
      ));

      expect(changed.isFailure, isTrue);
      expect(await db.query('pos_returns'), hasLength(1));
      expect(await db.query('ledger_entries'), hasLength(4));
    });

    test('fails closed when an invoice exists without its atomic children', () async {
      final posting = _returnPosting(
        invoiceId: 'return-1',
        idempotencyKey: 'return-key-1',
        quantity: 1,
      );
      await db.insert('pos_invoices', PosInvoiceMapper.toRow(posting.invoice));

      final retry = await repository.saveAtomically(posting);

      expect(retry.isFailure, isTrue);
      expect(await db.query('pos_invoice_lines'), hasLength(1));
      expect(await db.query('pos_returns'), isEmpty);
      expect(await db.query('pos_stock_movements'), isEmpty);
      expect(await db.query('vouchers'), isEmpty);
    });

    test('rechecks cumulative returned quantities in the write transaction', () async {
      final first = await repository.saveAtomically(_returnPosting(
        invoiceId: 'return-1',
        idempotencyKey: 'return-key-1',
        quantity: 1,
      ));
      expect(first.isSuccess, isTrue);

      final overReturn = await repository.saveAtomically(_returnPosting(
        invoiceId: 'return-2',
        idempotencyKey: 'return-key-2',
        quantity: 2,
      ));

      expect(overReturn.isFailure, isTrue);
      expect(await db.query('pos_returns'), hasLength(1));
      expect(await db.query('pos_stock_movements'), hasLength(1));
      expect(await db.query('vouchers'), hasLength(2));
    });

    test('persists a full void as voided, not merely fully returned', () async {
      final result = await repository.saveAtomically(_returnPosting(
        invoiceId: 'return-void',
        idempotencyKey: 'return-void-key',
        quantity: 2,
        voidSource: true,
      ));

      expect(result.isSuccess, isTrue);
      final source = await db.query('pos_invoices', where: 'id = ?', whereArgs: ['sale-1']);
      expect(source.single['status'], 'voided');
    });

    test('rejects exact full-void replay when source status is not voided', () async {
      final posting = _returnPosting(
        invoiceId: 'return-void',
        idempotencyKey: 'return-void-key',
        quantity: 2,
        voidSource: true,
      );
      expect((await repository.saveAtomically(posting)).isSuccess, isTrue);
      await db.update(
        'pos_invoices',
        {'status': 'fullyReturned'},
        where: 'id = ?',
        whereArgs: ['sale-1'],
      );

      final replay = await repository.saveAtomically(posting);

      expect(replay.isFailure, isTrue);
    });

    test('rejects return replay when source status exceeds returned quantities', () async {
      final posting = _returnPosting(
        invoiceId: 'return-partial',
        idempotencyKey: 'return-partial-key',
        quantity: 1,
      );
      expect((await repository.saveAtomically(posting)).isSuccess, isTrue);
      await db.update(
        'pos_invoices',
        {'status': 'fullyReturned'},
        where: 'id = ?',
        whereArgs: ['sale-1'],
      );

      final replay = await repository.saveAtomically(posting);

      expect(replay.isFailure, isTrue);
    });

    test('allocates invoice-level discount and tax across sequential returns', () async {
      await db.delete('pos_payments', where: 'invoice_id = ?', whereArgs: ['sale-1']);
      await db.delete('pos_invoice_lines', where: 'invoice_id = ?', whereArgs: ['sale-1']);
      await db.delete('pos_invoices', where: 'id = ?', whereArgs: ['sale-1']);
      final source = _sourceInvoice(globalDiscount: 101, globalTax: 51);
      await db.insert('pos_invoices', PosInvoiceMapper.toRow(source));
      await db.insert('pos_invoice_lines', PosInvoiceMapper.lineToRow(source.lines.single));
      await db.insert(
        'pos_payments',
        PosInvoiceMapper.paymentToRow(_sourcePayment(amount: 950), _sourceDate),
      );

      final first = await repository.saveAtomically(_returnPosting(
        invoiceId: 'return-1',
        idempotencyKey: 'return-key-1',
        quantity: 1,
        globalDiscount: 51,
        globalTax: 26,
      ));
      final second = await repository.saveAtomically(_returnPosting(
        invoiceId: 'return-2',
        idempotencyKey: 'return-key-2',
        quantity: 1,
        globalDiscount: 50,
        globalTax: 25,
      ));

      expect(first.isSuccess, isTrue);
      expect(second.isSuccess, isTrue);
      final returns = await db.query(
        'pos_invoices',
        where: 'document_type = ?',
        whereArgs: ['sales_return'],
      );
      expect(
        returns.fold<int>(
          0,
          (sum, row) => sum + (row['discount_minor'] as int),
        ),
        101,
      );
      expect(
        returns.fold<int>(
          0,
          (sum, row) => sum + (row['tax_minor'] as int),
        ),
        51,
      );
      expect(
        returns.fold<int>(
          0,
          (sum, row) => sum + (row['total_minor'] as int),
        ),
        950,
      );
    });
  });
}
