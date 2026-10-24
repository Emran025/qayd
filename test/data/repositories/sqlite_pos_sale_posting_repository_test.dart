import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_041_pos_invoice_metadata.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/data/repositories/sqlite_pos_sale_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
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
  for (final id in ['cash', 'revenue', 'cogs', 'inventory']) {
    await db.insert('accounts', {
      'id': id,
      'name': id,
      'nature': id == 'revenue' ? 'credit' : 'debit',
      'created_at': '2026-01-01T00:00:00.000Z',
    });
  }
}

PosStockMovement _opening() => PosStockMovement.create(
      id: 'opening-1',
      productId: 'product-1',
      warehouseId: 'warehouse-1',
      type: PosStockMovementType.opening,
      direction: PosStockMovementDirection.inbound,
      quantity: PosQuantity.whole(5),
      unitCost: Money.fromMinorUnits(100, _currency),
      sourceType: 'opening',
      sourceId: 'opening-1',
      occurredAt: DateTime.utc(2026, 1, 1, 9),
      idempotencyKey: 'opening-key',
      createdAt: DateTime.utc(2026, 1, 1, 9),
    );

PosAccountingPosting _posting({
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
    description: 'POS sale',
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

PosSalePosting _sale({bool invalidCogs = false}) {
  final date = DateTime.utc(2026, 1, 1, 10);
  const invoiceId = 'invoice-1';
  final line = PosInvoiceLine.create(
    id: 'line-1',
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
    idempotencyKey: 'sale-key-1',
    invoiceDate: date,
    now: date,
  ).post(date);
  return PosSalePosting(
    invoice: invoice,
    movements: [
      PosStockMovement.create(
        id: 'sale-movement-1',
        productId: 'product-1',
        warehouseId: 'warehouse-1',
        type: PosStockMovementType.sale,
        direction: PosStockMovementDirection.outbound,
        quantity: PosQuantity.whole(1),
        unitCost: Money.fromMinorUnits(100, _currency),
        sourceType: 'pos_invoice',
        sourceId: invoiceId,
        sourceLineId: 'line-1',
        occurredAt: date,
        idempotencyKey: 'sale-stock-key-1',
        createdAt: date,
      ),
    ],
    postings: [
      _posting(
        voucherId: 'sale-voucher-1',
        invoiceId: invoiceId,
        transactionId: 'sale-tx-1',
        debitEntryId: 'sale-debit-1',
        creditEntryId: 'sale-credit-1',
        type: VoucherType.receipt,
        counterpartyId: 'revenue',
        affectedAccountId: 'cash',
        amount: 500,
        date: date,
      ),
      _posting(
        voucherId: 'cogs-voucher-1',
        invoiceId: invoiceId,
        transactionId: 'cogs-tx-1',
        // Force a ledger primary-key conflict after the second voucher write.
        debitEntryId: invalidCogs ? 'sale-debit-1' : 'cogs-debit-1',
        creditEntryId: invalidCogs ? 'sale-credit-1' : 'cogs-credit-1',
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

void main() {
  sqfliteFfiInit();

  group('SqlitePosSalePostingRepository', () {
    late Database db;
    late SqlitePosStockMovementRepository stockRepository;
    late SqlitePosSalePostingRepository repository;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await _createSchema(db);
      await _seed(db);
      final currencyRepository = _CurrencyRepository(_currency);
      stockRepository =
          SqlitePosStockMovementRepository(db, currencyRepository);
      final voucherRepository = SqliteVoucherRepository(
        db,
        DatabaseTransactionRunner(db),
      );
      repository = SqlitePosSalePostingRepository(
        DatabaseTransactionRunner(db),
        stockRepository,
        voucherRepository,
      );
      expect((await stockRepository.append(_opening())).isSuccess, isTrue);
    });

    tearDown(() => db.close());

    test(
        'commits invoice, lines, stock, vouchers, ledger, and payments atomically',
        () async {
      final result = await repository.saveAtomically(_sale());

      expect(result.isSuccess, isTrue);
      expect((await db.query('pos_invoices')), hasLength(1));
      expect((await db.query('pos_invoice_lines')), hasLength(1));
      expect((await db.query('pos_stock_movements')), hasLength(2));
      expect((await db.query('vouchers')), hasLength(2));
      expect((await db.query('ledger_entries')), hasLength(4));
    });

    test('replays exact sale without changing persisted rows', () async {
      final sale = _sale();
      expect((await repository.saveAtomically(sale)).isSuccess, isTrue);
      final beforeInvoices = await db.query('pos_invoices');
      final beforeLines = await db.query('pos_invoice_lines');
      final beforeStock =
          await db.query('pos_stock_movements', orderBy: 'id ASC');
      final beforeVouchers = await db.query('vouchers', orderBy: 'id ASC');
      final beforeLedger = await db.query('ledger_entries', orderBy: 'id ASC');

      final replay = await repository.saveAtomically(sale);

      expect(replay.isSuccess, isTrue);
      expect(await db.query('pos_invoices'), equals(beforeInvoices));
      expect(await db.query('pos_invoice_lines'), equals(beforeLines));
      expect(await db.query('pos_stock_movements', orderBy: 'id ASC'),
          equals(beforeStock));
      expect(await db.query('vouchers', orderBy: 'id ASC'),
          equals(beforeVouchers));
      expect(await db.query('ledger_entries', orderBy: 'id ASC'),
          equals(beforeLedger));
    });

    test('rolls back stock and invoice when a voucher write is invalid',
        () async {
      final result = await repository.saveAtomically(_sale(invalidCogs: true));

      expect(result.isFailure, isTrue);
      expect((await db.query('pos_invoices')), isEmpty);
      expect((await db.query('pos_invoice_lines')), isEmpty);
      expect((await db.query('pos_stock_movements')), hasLength(1));
      expect((await db.query('vouchers')), isEmpty);
      expect((await db.query('ledger_entries')), isEmpty);
    });

    test('fails closed for a partial invoice state', () async {
      final sale = _sale();
      await db.insert('pos_invoices', PosInvoiceMapper.toRow(sale.invoice));

      final result = await repository.saveAtomically(sale);

      expect(result.isFailure, isTrue);
      expect((await db.query('pos_invoices')), hasLength(1));
      expect((await db.query('pos_stock_movements')), hasLength(1));
      expect((await db.query('vouchers')), isEmpty);
    });

    test('rejects changed payload under an existing idempotency key', () async {
      final sale = _sale();
      await db.insert('pos_invoices', PosInvoiceMapper.toRow(sale.invoice));
      final changed = PosSalePosting(
        invoice: PosInvoice.draft(
          id: sale.invoice.id,
          invoiceNumber: sale.invoice.invoiceNumber,
          type: PosInvoiceType.sale,
          warehouseId: sale.invoice.warehouseId,
          currency: _currency,
          lines: sale.invoice.lines,
          idempotencyKey: sale.invoice.idempotencyKey,
          invoiceDate: sale.invoice.invoiceDate,
          now: sale.invoice.createdAt,
        ).post(sale.invoice.invoiceDate),
        movements: sale.movements,
        postings: sale.postings,
        payments: const [],
      );

      final result = await repository.saveAtomically(changed);
      expect(result.isFailure, isTrue);
      expect((await db.query('pos_stock_movements')), hasLength(1));
    });
  });
}
