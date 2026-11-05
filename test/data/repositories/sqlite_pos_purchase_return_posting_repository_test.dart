import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_041_pos_invoice_metadata.dart';
import 'package:qayd/data/database/migrations/migration_registry.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/data/repositories/sqlite_pos_purchase_return_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_purchase_return_posting.dart';
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

final _currency = CurrencyCode(
  code: 'SAR',
  nameAr: 'ريال سعودي',
  symbol: 'ر.س',
);
final _date = DateTime.utc(2026, 1, 10, 10);

final class _CurrencyRepository implements CurrencyRepository {
  @override
  Future<Result<CurrencyCode?>> getByCode(String code) async =>
      Success(code == _currency.code ? _currency : null);

  @override
  Future<Result<List<CurrencyCode>>> getAll({bool onlyActive = false}) async =>
      Success([_currency]);

  @override
  Future<Result<void>> save(
    CurrencyCode currency, {
    bool isPredefined = false,
  }) async => const Success(null);

  @override
  Future<Result<void>> toggleActiveStatus(String code, bool isActive) async =>
      const Success(null);

  @override
  Future<Result<String>> getBaseCurrencyCode() async => Success(_currency.code);

  @override
  Future<Result<void>> setBaseCurrencyCode(String code) async =>
      const Success(null);
}

Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE app_settings (
      key TEXT NOT NULL PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
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
  await MigrationRegistry.applyFromTo(
    db,
    fromVersion: 41,
    toVersion: MigrationRegistry.ordered.last.version,
  );
}

Future<void> _seed(Database db) async {
  await db.insert('pos_warehouses', {
    'id': 'warehouse-1',
    'code': 'POS-MAIN',
    'name': 'POS Main',
    'is_default': 1,
    'is_active': 1,
    'created_at': _date.toIso8601String(),
    'updated_at': _date.toIso8601String(),
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
    'created_at': _date.toIso8601String(),
    'updated_at': _date.toIso8601String(),
  });
  for (final id in ['inventory', 'payables', 'supplier', 'purchase-returns']) {
    await db.insert('accounts', {
      'id': id,
      'name': id,
      'nature': id == 'payables' || id == 'purchase-returns'
          ? 'credit'
          : 'debit',
      'created_at': _date.toIso8601String(),
    });
  }
}

PosInvoice _sourceInvoice() {
  final line = PosInvoiceLine.create(
    id: 'purchase-line-1',
    invoiceId: 'purchase-1',
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    quantity: PosQuantity.whole(2),
    unitPrice: Money.fromMinorUnits(500, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    createdAt: _date,
    expiryTrackingSnapshot: false,
  );
  return PosInvoice.draft(
    id: 'purchase-1',
    invoiceNumber: 'P-1',
    type: PosInvoiceType.purchase,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [line],
    counterpartyAccountId: AccountId('supplier'),
    idempotencyKey: 'purchase-key-1',
    invoiceDate: _date,
    now: _date,
  ).post(_date);
}

PosStockMovement _sourceMovement() => PosStockMovement.create(
  id: 'purchase-movement-1',
  productId: 'product-1',
  warehouseId: 'warehouse-1',
  type: PosStockMovementType.purchase,
  direction: PosStockMovementDirection.inbound,
  quantity: PosQuantity.whole(2),
  unitCost: Money.fromMinorUnits(100, _currency),
  sourceType: 'pos_invoice',
  sourceId: 'purchase-1',
  sourceLineId: 'purchase-line-1',
  occurredAt: _date,
  createdAt: _date,
  idempotencyKey: 'purchase-movement-key-1',
);

PosPurchaseReturnPosting _returnPosting({
  required String invoiceId,
  required String idempotencyKey,
  int quantity = 1,
  int supplierCredit = 500,
}) {
  final date = DateTime.utc(2026, 1, 11, 10);
  final line = PosInvoiceLine.create(
    id: '$invoiceId:line:0',
    invoiceId: invoiceId,
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    quantity: PosQuantity.whole(quantity),
    unitPrice: Money.fromMinorUnits(500, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    sourceLineId: 'purchase-line-1',
    createdAt: date,
    expiryTrackingSnapshot: false,
  );
  final invoice = PosInvoice.draft(
    id: invoiceId,
    invoiceNumber: 'PR-$invoiceId',
    type: PosInvoiceType.purchaseReturn,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [line],
    counterpartyAccountId: AccountId('supplier'),
    sourceInvoiceId: 'purchase-1',
    idempotencyKey: idempotencyKey,
    invoiceDate: date,
    now: date,
  ).post(date);
  if (invoice.total.minorUnits != supplierCredit) {
    throw StateError('Fixture credit does not match return line total.');
  }

  final movement = PosStockMovement.create(
    id: '$invoiceId:movement:0:000000',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: PosStockMovementType.purchaseReturn,
    direction: PosStockMovementDirection.outbound,
    quantity: PosQuantity.whole(quantity),
    unitCost: Money.fromMinorUnits(100, _currency),
    sourceType: 'pos_invoice',
    sourceId: invoiceId,
    sourceLineId: line.id,
    reversesSourceId: 'purchase-1',
    occurredAt: date,
    createdAt: date,
    idempotencyKey: '$idempotencyKey:movement:0:000000',
  );
  final bookValue = quantity * 100;
  final variance = supplierCredit - bookValue;
  final postings = <PosAccountingPosting>[];
  void addPosting(String key, int amount, String debit, String credit) {
    final voucher = Voucher.draft(
      id: VoucherId('$invoiceId:voucher:$key'),
      type: VoucherType.payment,
      date: invoice.invoiceDate,
      amount: Money.fromMinorUnits(amount, _currency),
      currency: _currency,
      counterpartyId: AccountId(debit),
      affectedAccountId: AccountId(credit),
      referenceNumber: invoiceId,
      description: 'Purchase return',
      createdAt: date,
    ).confirm(date);
    postings.add(
      PosAccountingPosting(
        sourceId: invoiceId,
        voucher: voucher,
        entries: EntryGenerator().generateForConfirmedVoucher(
          voucher: voucher,
          transactionId: TransactionId('$invoiceId:transaction:$key'),
          debitEntryId: EntryId('$invoiceId:entry:$key:debit'),
          creditEntryId: EntryId('$invoiceId:entry:$key:credit'),
          ledgerCreatedAt: date,
        ),
      ),
    );
  }

  final direct = supplierCredit < bookValue ? supplierCredit : bookValue;
  if (direct > 0) addPosting('inventory', direct, 'payables', 'inventory');
  if (variance > 0) {
    addPosting('variance-credit', variance, 'payables', 'purchase-returns');
  } else if (variance < 0) {
    addPosting('variance-debit', -variance, 'purchase-returns', 'inventory');
  }
  return PosPurchaseReturnPosting(
    invoice: invoice,
    sourceInvoiceId: 'purchase-1',
    supplierPayablesAccountId: AccountId('payables'),
    inventoryAccountId: AccountId('inventory'),
    purchaseReturnsAccountId: AccountId('purchase-returns'),
    movements: [movement],
    postings: postings,
    reason: 'supplier credit note',
  );
}

void main() {
  sqfliteFfiInit();

  group('SqlitePosPurchaseReturnPostingRepository', () {
    late Database db;
    late SqlitePosStockMovementRepository stock;
    late SqlitePosPurchaseReturnPostingRepository repository;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await _createSchema(db);
      await _seed(db);
      final source = _sourceInvoice();
      await db.insert('pos_invoices', PosInvoiceMapper.toRow(source));
      await db.insert(
        'pos_invoice_lines',
        PosInvoiceMapper.lineToRow(source.lines.single),
      );
      final runner = DatabaseTransactionRunner(db);
      stock = SqlitePosStockMovementRepository(db, _CurrencyRepository());
      expect((await stock.append(_sourceMovement())).isSuccess, isTrue);
      repository = SqlitePosPurchaseReturnPostingRepository(
        runner,
        stock,
        SqliteVoucherRepository(db, runner),
      );
    });

    tearDown(() => db.close());

    test(
      'commits credit note, relation, stock, ledger, and source status atomically',
      () async {
        final posting = _returnPosting(
          invoiceId: 'purchase-return-1',
          idempotencyKey: 'purchase-return-key-1',
        );
        final result = await repository.saveAtomically(posting);

        expect(
          result.isSuccess,
          isTrue,
          reason: result.failureOrNull?.messageAr,
        );
        expect(await db.query('pos_invoices'), hasLength(2));
        expect(await db.query('pos_invoice_lines'), hasLength(2));
        expect(await db.query('pos_returns'), hasLength(1));
        expect(await db.query('pos_stock_movements'), hasLength(2));
        expect(await db.query('pos_payments'), isEmpty);
        expect(await db.query('vouchers'), hasLength(2));
        expect(await db.query('ledger_entries'), hasLength(4));
        final source = await db.query(
          'pos_invoices',
          where: 'id = ?',
          whereArgs: ['purchase-1'],
        );
        expect(source.single['status'], 'partiallyReturned');
      },
    );

    test(
      'exact replay is idempotent and does not duplicate credit or stock',
      () async {
        final posting = _returnPosting(
          invoiceId: 'purchase-return-replay',
          idempotencyKey: 'purchase-return-replay-key',
        );
        final first = await repository.saveAtomically(posting);
        expect(first.isSuccess, isTrue, reason: first.failureOrNull?.messageAr);
        final replay = await repository.saveAtomically(posting);
        expect(
          replay.isSuccess,
          isTrue,
          reason: replay.failureOrNull?.messageAr,
        );
        expect(await db.query('pos_invoices'), hasLength(2));
        expect(await db.query('pos_returns'), hasLength(1));
        expect(await db.query('pos_stock_movements'), hasLength(2));
        expect(await db.query('vouchers'), hasLength(2));
        expect(await db.query('ledger_entries'), hasLength(4));
      },
    );

    test(
      'caps cumulative partial returns against the original quantity',
      () async {
        final first = await repository.saveAtomically(
          _returnPosting(
            invoiceId: 'purchase-return-first-half',
            idempotencyKey: 'purchase-return-first-half-key',
          ),
        );
        expect(first.isSuccess, isTrue, reason: first.failureOrNull?.messageAr);

        final second = await repository.saveAtomically(
          _returnPosting(
            invoiceId: 'purchase-return-excess-second',
            idempotencyKey: 'purchase-return-excess-second-key',
            quantity: 2,
            supplierCredit: 1000,
          ),
        );

        expect(second.isFailure, isTrue);
        expect(await db.query('pos_invoices'), hasLength(2));
        expect(await db.query('pos_returns'), hasLength(1));
        expect(await db.query('pos_stock_movements'), hasLength(2));
        expect(await db.query('vouchers'), hasLength(2));
        expect(await db.query('ledger_entries'), hasLength(4));
      },
    );

    test('caller failure rolls back every component of the return', () async {
      final posting = _returnPosting(
        invoiceId: 'purchase-return-rollback',
        idempotencyKey: 'purchase-return-rollback-key',
      );
      await expectLater(
        db.transaction<void>((txn) async {
          await repository.saveInTransaction(txn, posting);
          throw StateError('caller failure');
        }),
        throwsA(isA<StateError>()),
      );
      expect(await db.query('pos_invoices'), hasLength(1));
      expect(await db.query('pos_invoice_lines'), hasLength(1));
      expect(await db.query('pos_returns'), isEmpty);
      expect(await db.query('pos_stock_movements'), hasLength(1));
      expect(await db.query('pos_payments'), isEmpty);
      expect(await db.query('vouchers'), isEmpty);
      expect(await db.query('ledger_entries'), isEmpty);
      final source = await db.query(
        'pos_invoices',
        where: 'id = ?',
        whereArgs: ['purchase-1'],
      );
      expect(source.single['status'], 'posted');
    });

    test('rejects excess source quantity without any return writes', () async {
      final posting = _returnPosting(
        invoiceId: 'purchase-return-too-many',
        idempotencyKey: 'purchase-return-too-many-key',
        quantity: 3,
        supplierCredit: 1500,
      );
      final result = await repository.saveAtomically(posting);
      expect(result.isFailure, isTrue);
      expect(await db.query('pos_invoices'), hasLength(1));
      expect(await db.query('pos_returns'), isEmpty);
      expect(await db.query('pos_stock_movements'), hasLength(1));
      expect(await db.query('vouchers'), isEmpty);
    });

    test(
      'rejects tax-bearing source without writing a return or ledger',
      () async {
        await db.update(
          'pos_invoices',
          {'tax_minor': 25},
          where: 'id = ?',
          whereArgs: ['purchase-1'],
        );

        final result = await repository.saveAtomically(
          _returnPosting(
            invoiceId: 'purchase-return-tax-blocked',
            idempotencyKey: 'purchase-return-tax-blocked-key',
          ),
        );

        expect(result.isFailure, isTrue);
        expect(await db.query('pos_invoices'), hasLength(1));
        expect(await db.query('pos_returns'), isEmpty);
        expect(await db.query('pos_stock_movements'), hasLength(1));
        expect(await db.query('vouchers'), isEmpty);
        expect(await db.query('ledger_entries'), isEmpty);
      },
    );

    test(
      'rejects a stale average cost without creating a supplier credit',
      () async {
        final intervening = PosStockMovement.create(
          id: 'adjustment-after-build',
          productId: 'product-1',
          warehouseId: 'warehouse-1',
          type: PosStockMovementType.adjustment,
          direction: PosStockMovementDirection.inbound,
          quantity: PosQuantity.whole(1),
          unitCost: Money.fromMinorUnits(300, _currency),
          sourceType: 'manual_adjustment',
          sourceId: 'adjustment-1',
          occurredAt: DateTime.utc(2026, 1, 11),
          createdAt: DateTime.utc(2026, 1, 11),
          idempotencyKey: 'adjustment-after-build-key',
        );
        expect((await stock.append(intervening)).isSuccess, isTrue);

        final result = await repository.saveAtomically(
          _returnPosting(
            invoiceId: 'purchase-return-stale-cost',
            idempotencyKey: 'purchase-return-stale-cost-key',
          ),
        );

        expect(result.isFailure, isTrue);
        expect(await db.query('pos_invoices'), hasLength(1));
        expect(await db.query('pos_returns'), isEmpty);
        expect(await db.query('pos_stock_movements'), hasLength(2));
        expect(await db.query('vouchers'), isEmpty);
        expect(await db.query('ledger_entries'), isEmpty);
      },
    );
  });
}
