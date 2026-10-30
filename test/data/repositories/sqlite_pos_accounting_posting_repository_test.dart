import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/repositories/sqlite_pos_accounting_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/ledger_entry.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/entry_side.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/application/pos/build_pos_opening_balance_posting_use_case.dart';
import 'package:qayd/application/pos/build_pos_stock_adjustment_posting_use_case.dart';
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

CurrencyCode _currency() => CurrencyCode(
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
      created_at TEXT NOT NULL,
      standard_classification TEXT,
      custom_classification_name TEXT,
      custom_classification_nature TEXT,
      metadata TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE vouchers (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      reference_number TEXT,
      date TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      currency_code TEXT NOT NULL,
      counterparty_id TEXT NOT NULL,
      affected_account_id TEXT NOT NULL,
      state TEXT NOT NULL,
      description TEXT,
      notes TEXT,
      tags_json TEXT NOT NULL,
      attachments_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      confirmed_at TEXT,
      settled_at TEXT,
      signer_phone TEXT,
      canonical_sender_phone TEXT,
      canonical_receiver_phone TEXT,
      transfer_group_id TEXT,
      tripartite_role TEXT,
      linked_party_id TEXT,
      mediator_account_id TEXT,
      fee_amount_minor INTEGER,
      is_contingent INTEGER NOT NULL DEFAULT 0,
      origin_voucher_id TEXT,
      rejection_reason TEXT,
      withdrawn_at TEXT,
      sender_status TEXT NOT NULL,
      receiver_status TEXT NOT NULL,
      sender_signature_hex TEXT,
      receiver_signature_hex TEXT,
      sender_public_key_hex TEXT,
      receiver_public_key_hex TEXT,
      lifecycle_status TEXT NOT NULL,
      is_inbound INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE ledger_entries (
      id TEXT PRIMARY KEY,
      transaction_id TEXT NOT NULL,
      account_id TEXT NOT NULL,
      side TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      currency_code TEXT NOT NULL,
      voucher_id TEXT NOT NULL,
      date TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await Migration040PosFoundation().up(db);
}

Future<void> _seed(Database db, CurrencyCode currency) async {
  for (final account in [
    ('inventory-account', 'POS Inventory', 'debit'),
    ('clearing-account', 'POS Opening Clearing', 'credit'),
    ('variance-account', 'POS Inventory Variance', 'debit'),
  ]) {
    await db.insert('accounts', <String, Object?>{
      'id': account.$1,
      'name': account.$2,
      'nature': account.$3,
      'created_at': '2026-01-01T00:00:00.000Z',
    });
  }
  await db.insert('pos_warehouses', <String, Object?>{
    'id': 'warehouse-1',
    'code': 'POS-MAIN',
    'name': 'POS Main Warehouse',
    'is_default': 1,
    'is_active': 1,
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
  });
  await db.insert('pos_products', <String, Object?>{
    'id': 'product-1',
    'sku': 'SKU-1',
    'name': 'Coffee',
    'unit_name': 'unit',
    'currency_code': currency.code,
    'sale_price_minor': 300,
    'purchase_price_minor': 100,
    'quantity_scale': 0,
    'reorder_level_scaled': 0,
    'expiry_tracking': 0,
    'is_active': 1,
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
  });
}

PosStockMovement _movement(
  CurrencyCode currency, {
  String key = 'opening-key',
  String sourceId = 'source-1',
  DateTime? occurredAt,
}) {
  final date = occurredAt ?? DateTime.utc(2026, 1, 1, 10);
  return PosStockMovement.create(
    id: 'movement-$key',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: PosStockMovementType.opening,
    direction: PosStockMovementDirection.inbound,
    quantity: PosQuantity.whole(5),
    unitCost: Money.fromMinorUnits(100, currency),
    sourceType: 'opening',
    sourceId: sourceId,
    occurredAt: date,
    idempotencyKey: key,
    createdAt: date,
  );
}

Future<PosAccountingPosting> _buildPosting(
  CurrencyCode currency, {
  String voucherId = 'voucher-1',
  String sourceId = 'source-1',
  DateTime? date,
}) async {
  final postingDate = date ?? DateTime.utc(2026, 1, 1, 10);
  final result = await BuildPosOpeningBalancePostingUseCase()(
    BuildPosOpeningBalancePostingInput(
      sourceId: sourceId,
      voucherId: voucherId,
      transactionId: 'transaction-$voucherId',
      debitEntryId: 'debit-$voucherId',
      creditEntryId: 'credit-$voucherId',
      inventoryAccountId: 'inventory-account',
      clearingAccountId: 'clearing-account',
      amountMinorUnits: 500,
      currency: currency,
      date: postingDate,
      createdAt: postingDate,
    ),
  );
  return result.valueOrNull!;
}

PosStockMovement _adjustmentMovement(
  CurrencyCode currency, {
  String key = 'adjustment-key',
  String sourceId = 'adjustment-source-1',
}) {
  final date = DateTime.utc(2026, 1, 1, 11);
  return PosStockMovement.create(
    id: 'movement-$key',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: PosStockMovementType.adjustment,
    direction: PosStockMovementDirection.outbound,
    quantity: PosQuantity.whole(2),
    unitCost: Money.fromMinorUnits(100, currency),
    sourceType: 'manual_adjustment',
    sourceId: sourceId,
    occurredAt: date,
    idempotencyKey: key,
    createdAt: date,
  );
}

Future<PosAccountingPosting> _buildAdjustmentPosting(
  CurrencyCode currency, {
  String voucherId = 'adjustment-voucher-1',
  String sourceId = 'adjustment-source-1',
}) async {
  final date = DateTime.utc(2026, 1, 1, 11);
  final result = await const BuildPosStockAdjustmentPostingUseCase()(
    BuildPosStockAdjustmentPostingInput(
      sourceId: sourceId,
      voucherId: voucherId,
      transactionId: 'transaction-$voucherId',
      debitEntryId: 'debit-$voucherId',
      creditEntryId: 'credit-$voucherId',
      inventoryAccountId: 'inventory-account',
      counterAccountId: 'variance-account',
      direction: PosStockMovementDirection.outbound,
      amountMinorUnits: 200,
      currency: currency,
      reason: 'Stock count variance',
      date: date,
      createdAt: date,
    ),
  );
  return result.valueOrNull!;
}

void main() {
  sqfliteFfiInit();

  group('SqlitePosAccountingPostingRepository', () {
    late Database db;
    late SqlitePosAccountingPostingRepository repository;
    late SqlitePosStockMovementRepository stockRepository;
    late SqliteVoucherRepository voucherRepository;
    late CurrencyCode currency;

    setUp(() async {
      currency = _currency();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await _createSchema(db);
      await _seed(db, currency);
      final currencyRepository = _CurrencyRepository(currency);
      stockRepository =
          SqlitePosStockMovementRepository(db, currencyRepository);
      voucherRepository =
          SqliteVoucherRepository(db, DatabaseTransactionRunner(db));
      repository = SqlitePosAccountingPostingRepository(
        DatabaseTransactionRunner(db),
        stockRepository,
        voucherRepository,
      );
    });

    tearDown(() => db.close());

    test('commits stock movement and official voucher ledger together',
        () async {
      final result = await repository.saveOpeningBalance(
        movement: _movement(currency),
        posting: await _buildPosting(currency),
      );

      expect(result.isSuccess, isTrue);
      expect((await db.query('pos_stock_movements')), hasLength(1));
      expect((await db.query('vouchers')), hasLength(1));
      expect((await db.query('ledger_entries')), hasLength(2));
    });

    test('replays the same source idempotently without duplicate rows',
        () async {
      final movement = _movement(currency);
      final posting = await _buildPosting(currency);
      await repository.saveOpeningBalance(movement: movement, posting: posting);
      final beforeReplay = await db.query(
        'ledger_entries',
        orderBy: 'id ASC',
      );
      final replay = await repository.saveOpeningBalance(
        movement: movement,
        posting: posting,
      );
      final afterReplay = await db.query(
        'ledger_entries',
        orderBy: 'id ASC',
      );

      expect(replay.isSuccess, isTrue);
      expect((await db.query('pos_stock_movements')), hasLength(1));
      expect((await db.query('vouchers')), hasLength(1));
      expect(afterReplay, equals(beforeReplay));
    });

    test('compares posting and movement by UTC business date', () async {
      final movement = _movement(
        currency,
        occurredAt: DateTime.utc(2026, 1, 1, 14),
      );
      final posting = await _buildPosting(
        currency,
        date: DateTime.utc(2026, 1, 1, 10),
      );

      final result = await repository.saveOpeningBalance(
        movement: movement,
        posting: posting,
      );

      expect(result.isSuccess, isTrue);
      expect((await db.query('pos_stock_movements')), hasLength(1));
      expect((await db.query('ledger_entries')), hasLength(2));
    });

    test('rejects a source mismatch before any write', () async {
      final result = await repository.saveOpeningBalance(
        movement: _movement(currency, sourceId: 'movement-source'),
        posting: await _buildPosting(currency, sourceId: 'posting-source'),
      );

      expect(result.isFailure, isTrue);
      expect((await db.query('pos_stock_movements')), isEmpty);
      expect((await db.query('vouchers')), isEmpty);
      expect((await db.query('ledger_entries')), isEmpty);
    });

    test('rejects a different voucher for an existing source', () async {
      await repository.saveOpeningBalance(
        movement: _movement(currency),
        posting: await _buildPosting(currency),
      );

      final result = await repository.saveOpeningBalance(
        movement: _movement(currency, key: 'second-key'),
        posting: await _buildPosting(
          currency,
          voucherId: 'voucher-2',
          sourceId: 'source-1',
        ),
      );

      expect(result.isFailure, isTrue);
      expect((await db.query('pos_stock_movements')), hasLength(1));
      expect((await db.query('vouchers')), hasLength(1));
      expect((await db.query('ledger_entries')), hasLength(2));
    });

    test('fails closed when stock exists without its accounting posting',
        () async {
      final movement = _movement(currency);
      final posting = await _buildPosting(currency);
      expect((await stockRepository.append(movement)).isSuccess, isTrue);

      final result = await repository.saveOpeningBalance(
        movement: movement,
        posting: posting,
      );

      expect(result.isFailure, isTrue);
      expect((await db.query('pos_stock_movements')), hasLength(1));
      expect((await db.query('vouchers')), isEmpty);
      expect((await db.query('ledger_entries')), isEmpty);
    });

    test('fails closed when accounting voucher exists without stock', () async {
      final movement = _movement(currency);
      final posting = await _buildPosting(currency);
      expect((await voucherRepository.save(posting.voucher)).isSuccess, isTrue);

      final result = await repository.saveOpeningBalance(
        movement: movement,
        posting: posting,
      );

      expect(result.isFailure, isTrue);
      expect((await db.query('pos_stock_movements')), isEmpty);
      expect((await db.query('vouchers')), hasLength(1));
      expect((await db.query('ledger_entries')), isEmpty);
    });

    test('rolls back stock when voucher validation fails', () async {
      final valid = await _buildPosting(currency, voucherId: 'voucher-bad');
      final invalidEntry = LedgerEntry.create(
        id: EntryId('bad-entry'),
        transactionId: TransactionId('transaction-bad'),
        accountId: AccountId('inventory-account'),
        side: EntrySide.debit,
        amount: Money.fromMinorUnits(500, currency),
        currency: currency,
        voucherId: VoucherId('different-voucher'),
        date: valid.voucher.date,
        createdAt: valid.voucher.createdAt,
      );
      final invalidPosting = PosAccountingPosting(
        sourceId: valid.sourceId,
        voucher: valid.voucher,
        entries: [invalidEntry],
      );

      final result = await repository.saveOpeningBalance(
        movement: _movement(currency, key: 'rollback-key'),
        posting: invalidPosting,
      );

      expect(result.isFailure, isTrue);
      expect((await db.query('pos_stock_movements')), isEmpty);
      expect((await db.query('vouchers')), isEmpty);
      expect((await db.query('ledger_entries')), isEmpty);
    });

    test('commits a stock-count adjustment and balanced ledger atomically',
        () async {
      await repository.saveOpeningBalance(
        movement: _movement(currency),
        posting: await _buildPosting(currency),
      );
      final result = await repository.saveStockAdjustmentAtomically(
        movement: _adjustmentMovement(currency),
        posting: await _buildAdjustmentPosting(currency),
      );

      expect(result.isSuccess, isTrue);
      expect((await db.query('pos_stock_movements')), hasLength(2));
      expect((await db.query('vouchers')), hasLength(2));
      final adjustmentEntries = await db.query(
        'ledger_entries',
        where: 'voucher_id = ?',
        whereArgs: ['adjustment-voucher-1'],
      );
      expect(adjustmentEntries, hasLength(2));
      expect(
        adjustmentEntries.map((row) => row['amount_minor']).toSet(),
        {200},
      );
    });

    test('replays the same adjustment without duplicate rows', () async {
      await repository.saveOpeningBalance(
        movement: _movement(currency),
        posting: await _buildPosting(currency),
      );
      final movement = _adjustmentMovement(currency);
      final posting = await _buildAdjustmentPosting(currency);
      await repository.saveStockAdjustmentAtomically(
        movement: movement,
        posting: posting,
      );
      final before = await db.query('ledger_entries', orderBy: 'id ASC');

      final replay = await repository.saveStockAdjustmentAtomically(
        movement: movement,
        posting: posting,
      );

      expect(replay.isSuccess, isTrue);
      expect((await db.query('pos_stock_movements')), hasLength(2));
      expect((await db.query('vouchers')), hasLength(2));
      expect(await db.query('ledger_entries', orderBy: 'id ASC'), before);
    });
  });
}
