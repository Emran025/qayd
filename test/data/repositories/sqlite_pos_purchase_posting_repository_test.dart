import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_041_pos_invoice_metadata.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/data/repositories/sqlite_pos_purchase_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_purchase_posting.dart';
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

Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      nature TEXT NOT NULL,
      parent_id TEXT,
      is_default INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      standard_classification TEXT,
      custom_classification_name TEXT,
      custom_classification_nature TEXT,
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
  for (final id in ['inventory', 'payables', 'supplier']) {
    await db.insert('accounts', {
      'id': id,
      'name': id,
      'nature': id == 'payables' ? 'credit' : 'debit',
      'created_at': '2026-01-01T00:00:00.000Z',
    });
  }
}

PosPurchasePosting _purchase({bool duplicateLedgerEntryId = false}) {
  final date = DateTime.utc(2026, 1, 10, 10);
  const invoiceId = 'purchase-1';
  final line = PosInvoiceLine.create(
    id: 'purchase-line-1',
    invoiceId: invoiceId,
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    quantity: PosQuantity.whole(2),
    unitPrice: Money.fromMinorUnits(100, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    createdAt: date,
  );
  final invoice = PosInvoice.draft(
    id: invoiceId,
    invoiceNumber: 'P-000001',
    type: PosInvoiceType.purchase,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [line],
    idempotencyKey: 'purchase-key-1',
    invoiceDate: date,
    now: date,
    counterpartyAccountId: AccountId('supplier'),
  ).post(date);
  final movement = PosStockMovement.create(
    id: 'purchase-movement-1',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: PosStockMovementType.purchase,
    direction: PosStockMovementDirection.inbound,
    quantity: PosQuantity.whole(2),
    unitCost: Money.fromMinorUnits(100, _currency),
    sourceType: 'pos_invoice',
    sourceId: invoiceId,
    sourceLineId: line.id,
    occurredAt: date,
    idempotencyKey: 'purchase-stock-key-1',
    createdAt: date,
  );
  final voucher = Voucher.draft(
    id: const VoucherId('purchase-voucher-1'),
    type: VoucherType.receipt,
    date: date,
    amount: Money.fromMinorUnits(200, _currency),
    currency: _currency,
    counterpartyId: const AccountId('payables'),
    affectedAccountId: const AccountId('inventory'),
    referenceNumber: invoiceId,
    description: 'POS purchase payable P-000001',
    createdAt: date,
  ).confirm(date);
  final entries = EntryGenerator().generateForConfirmedVoucher(
    voucher: voucher,
    transactionId: const TransactionId('purchase-tx-1'),
    debitEntryId: EntryId(
      duplicateLedgerEntryId ? 'preexisting-ledger-id' : 'purchase-debit-1',
    ),
    creditEntryId: const EntryId('purchase-credit-1'),
    ledgerCreatedAt: date,
  );
  return PosPurchasePosting(
    invoice: invoice,
    movements: [movement],
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
  sqfliteFfiInit();

  group('SqlitePosPurchasePostingRepository', () {
    late Database db;
    late SqlitePosPurchasePostingRepository repository;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await _createSchema(db);
      await _seed(db);
      final stockRepository = SqlitePosStockMovementRepository(
        db,
        _CurrencyRepository(_currency),
      );
      repository = SqlitePosPurchasePostingRepository(
        DatabaseTransactionRunner(db),
        stockRepository,
        SqliteVoucherRepository(db, DatabaseTransactionRunner(db)),
      );
    });

    tearDown(() => db.close());

    test('commits invoice, lines, stock, voucher and ledger atomically', () async {
      final result = await repository.saveAtomically(_purchase());

      expect(result.isSuccess, isTrue);
      expect(await db.query('pos_invoices'), hasLength(1));
      expect(await db.query('pos_invoice_lines'), hasLength(1));
      expect(await db.query('pos_stock_movements'), hasLength(1));
      expect(await db.query('vouchers'), hasLength(1));
      expect(await db.query('ledger_entries'), hasLength(2));
    });

    test('exact replay does not duplicate or mutate ledger rows', () async {
      final purchase = _purchase();
      expect((await repository.saveAtomically(purchase)).isSuccess, isTrue);
      final beforeInvoices = await db.query('pos_invoices');
      final beforeLines = await db.query('pos_invoice_lines');
      final beforeMovements = await db.query('pos_stock_movements');
      final beforeVouchers = await db.query('vouchers');
      final beforeLedger = await db.query('ledger_entries');

      final replay = await repository.saveAtomically(purchase);

      expect(replay.isSuccess, isTrue);
      expect(await db.query('pos_invoices'), equals(beforeInvoices));
      expect(await db.query('pos_invoice_lines'), equals(beforeLines));
      expect(await db.query('pos_stock_movements'), equals(beforeMovements));
      expect(await db.query('vouchers'), equals(beforeVouchers));
      expect(await db.query('ledger_entries'), equals(beforeLedger));
    });

    test('rolls back stock and invoice when ledger insertion conflicts', () async {
      final date = DateTime.utc(2026, 1, 10, 10).toIso8601String();
      await db.insert('ledger_entries', {
        'id': 'preexisting-ledger-id',
        'transaction_id': 'existing-tx',
        'account_id': 'inventory',
        'side': 'debit',
        'amount_minor': 1,
        'currency_code': _currency.code,
        'voucher_id': 'existing-voucher',
        'date': date,
        'created_at': date,
      });

      final result = await repository.saveAtomically(
        _purchase(duplicateLedgerEntryId: true),
      );

      expect(result.isFailure, isTrue);
      expect(await db.query('pos_invoices'), isEmpty);
      expect(await db.query('pos_invoice_lines'), isEmpty);
      expect(await db.query('pos_stock_movements'), isEmpty);
      expect(await db.query('vouchers'), isEmpty);
      expect(await db.query('ledger_entries'), hasLength(1));
    });

    test('fails closed when invoice exists without its stock/accounting rows',
        () async {
      final purchase = _purchase();
      await db.insert('pos_invoices', PosInvoiceMapper.toRow(purchase.invoice));

      final result = await repository.saveAtomically(purchase);

      expect(result.isFailure, isTrue);
      expect(await db.query('pos_invoices'), hasLength(1));
      expect(await db.query('pos_invoice_lines'), isEmpty);
      expect(await db.query('pos_stock_movements'), isEmpty);
      expect(await db.query('vouchers'), isEmpty);
      expect(await db.query('ledger_entries'), isEmpty);
    });
  });
}
