import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_046_pos_stock_lots_fefo.dart';
import 'package:qayd/data/database/migrations/migration_047_pos_stock_disposal.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/repositories/sqlite_pos_accounting_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_stock_lot.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';
import 'package:qayd/domain/value_objects/pos_stock_disposal_reason.dart';
import 'package:qayd/application/pos/build_pos_opening_balance_posting_use_case.dart';
import 'package:qayd/application/pos/build_pos_stock_adjustment_posting_use_case.dart';
import 'package:qayd/application/pos/build_pos_stock_disposal_posting_use_case.dart';
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
  await Migration046PosStockLotsFefo().up(db);
  await Migration047PosStockDisposal().up(db);
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
  String? lotId,
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
    sourceType: 'opening_balance',
    sourceId: sourceId,
    lotId: lotId,
    occurredAt: date,
    idempotencyKey: key,
    createdAt: date,
  );
}

PosStockLot _openingLot(CurrencyCode currency, {String id = 'opening-lot-1'}) =>
    PosStockLot.create(
      id: id,
      productId: 'product-1',
      warehouseId: 'warehouse-1',
      supplierLotNumber: 'OPEN-1',
      expiryDate: PosDate.fromParts(2026, 12, 31),
      receivedQuantity: PosQuantity.whole(5),
      unitCost: Money.fromMinorUnits(100, currency),
      createdAt: DateTime.utc(2026, 1, 1, 10),
    );

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

PosStockMovement _disposalMovement(
  CurrencyCode currency, {
  String key = 'disposal-key-1',
  String sourceId = 'disposal-source-1',
  String voucherId = 'disposal-voucher-1',
  int quantity = 2,
  PosStockDisposalReason reason = PosStockDisposalReason.damage,
  String? lotId,
  String? reasonDetail,
}) {
  final date = DateTime.utc(2026, 1, 1, 11);
  final type = switch (reason) {
    PosStockDisposalReason.damage => PosStockMovementType.damage,
    PosStockDisposalReason.expiry => PosStockMovementType.expiry,
    PosStockDisposalReason.authorizedLoss => PosStockMovementType.adjustment,
    PosStockDisposalReason.other => PosStockMovementType.adjustment,
  };
  return PosStockMovement.create(
    id: 'movement-$key',
    productId: 'product-1',
    warehouseId: 'warehouse-1',
    type: type,
    direction: PosStockMovementDirection.outbound,
    quantity: PosQuantity.whole(quantity),
    unitCost: Money.fromMinorUnits(100, currency),
    sourceType: 'stock_disposal',
    sourceId: sourceId,
    lotId: lotId,
    disposalReason: reason,
    reasonDetail: reasonDetail,
    voucherId: voucherId,
    occurredAt: date,
    idempotencyKey: key,
    createdAt: date,
  );
}

Future<PosAccountingPosting> _buildDisposalPosting(
  CurrencyCode currency, {
  String sourceId = 'disposal-source-1',
  String voucherId = 'disposal-voucher-1',
  int amount = 200,
  PosStockMovementDirection direction = PosStockMovementDirection.outbound,
  PosStockDisposalReason? reason = PosStockDisposalReason.damage,
  String? reasonDetail,
  String? reversalOfSourceId,
  DateTime? date,
}) async {
  final postingDate = date ?? DateTime.utc(2026, 1, 1, 11);
  final result = await const BuildPosStockDisposalPostingUseCase()(
    BuildPosStockDisposalPostingInput(
      sourceId: sourceId,
      voucherId: voucherId,
      transactionId: 'transaction-$voucherId',
      debitEntryId: 'debit-$voucherId',
      creditEntryId: 'credit-$voucherId',
      inventoryAccountId: 'inventory-account',
      lossAccountId: 'variance-account',
      direction: direction,
      amountMinorUnits: amount,
      currency: currency,
      date: postingDate,
      createdAt: postingDate,
      reason: reason,
      reasonDetail: reasonDetail,
      reversalOfSourceId: reversalOfSourceId,
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

    test('atomically saves and replays a tracked opening lot', () async {
      await db.update(
        'pos_products',
        {'expiry_tracking': 1},
        where: 'id = ?',
        whereArgs: ['product-1'],
      );
      final lot = _openingLot(currency);
      final movement = _movement(currency, lotId: lot.id);
      final posting = await _buildPosting(currency);

      final first = await repository.saveOpeningBalance(
        movement: movement,
        lots: [lot],
        posting: posting,
      );
      final replay = await repository.saveOpeningBalance(
        movement: movement,
        lots: [lot],
        posting: posting,
      );

      expect(first.isSuccess, isTrue, reason: first.failureOrNull?.messageAr);
      expect(replay.isSuccess, isTrue, reason: replay.failureOrNull?.messageAr);
      expect(await db.query('pos_stock_lots'), hasLength(1));
      expect(await db.query('pos_stock_movements'), hasLength(1));
      expect((await db.query('pos_stock_movements')).single['lot_id'], lot.id);
      expect(
          (await db.query('pos_stock_lots'))
              .single['remaining_quantity_scaled'],
          5);
      expect(await db.query('vouchers'), hasLength(1));
      expect(await db.query('ledger_entries'), hasLength(2));
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

    test('rolls back tracked lot and stock when ledger insertion conflicts',
        () async {
      await db.update(
        'pos_products',
        {'expiry_tracking': 1},
        where: 'id = ?',
        whereArgs: ['product-1'],
      );
      final lot = _openingLot(currency);
      final valid = await _buildPosting(currency, voucherId: 'voucher-bad');
      await db.insert('ledger_entries', <String, Object?>{
        'id': 'debit-voucher-bad',
        'transaction_id': 'existing-transaction',
        'account_id': 'inventory-account',
        'side': 'debit',
        'amount_minor': 1,
        'currency_code': currency.code,
        'voucher_id': 'existing-voucher',
        'date': valid.voucher.date.toIso8601String(),
        'created_at': valid.voucher.createdAt.toIso8601String(),
      });

      final result = await repository.saveOpeningBalance(
        movement: _movement(
          currency,
          key: 'rollback-key',
          lotId: lot.id,
        ),
        lots: [lot],
        posting: valid,
      );

      expect(result.isFailure, isTrue);
      expect((await db.query('pos_stock_lots')), isEmpty);
      expect((await db.query('pos_stock_movements')), isEmpty);
      expect((await db.query('vouchers')), isEmpty);
      expect((await db.query('ledger_entries')), hasLength(1));
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

    test('commits and replays disposal movement and balanced loss posting',
        () async {
      await repository.saveOpeningBalance(
        movement: _movement(currency),
        posting: await _buildPosting(currency),
      );
      final movement = _disposalMovement(currency);
      final posting = await _buildDisposalPosting(currency);

      final first = await repository.saveStockDisposalAtomically(
        movement: movement,
        posting: posting,
      );
      final replay = await repository.saveStockDisposalAtomically(
        movement: movement,
        posting: posting,
      );

      expect(first.isSuccess, isTrue, reason: first.failureOrNull?.messageAr);
      expect(replay.isSuccess, isTrue, reason: replay.failureOrNull?.messageAr);
      expect(await db.query('pos_stock_movements'), hasLength(2));
      final savedMovement = (await db.query(
        'pos_stock_movements',
        where: 'source_id = ?',
        whereArgs: ['disposal-source-1'],
      )).single;
      expect(savedMovement['movement_type'], 'damage');
      expect(savedMovement['quantity_scaled'], -2);
      expect(savedMovement['disposal_reason_code'], 'damage');
      expect(savedMovement['voucher_id'], 'disposal-voucher-1');
      expect(await db.query('vouchers'), hasLength(2));
      final entries = await db.query(
        'ledger_entries',
        where: 'voucher_id = ?',
        whereArgs: ['disposal-voucher-1'],
      );
      expect(entries, hasLength(2));
      expect(
        entries.singleWhere((row) => row['side'] == 'debit')['account_id'],
        'variance-account',
      );
      expect(
        entries.singleWhere((row) => row['side'] == 'credit')['account_id'],
        'inventory-account',
      );
    });

    test('allows full disposal and leaves no negative stock or value', () async {
      await repository.saveOpeningBalance(
        movement: _movement(currency),
        posting: await _buildPosting(currency),
      );
      final movement = _disposalMovement(
        currency,
        key: 'full-disposal-key',
        sourceId: 'full-disposal-source',
        voucherId: 'full-disposal-voucher',
        quantity: 5,
      );

      final result = await repository.saveStockDisposalAtomically(
        movement: movement,
        posting: await _buildDisposalPosting(
          currency,
          sourceId: 'full-disposal-source',
          voucherId: 'full-disposal-voucher',
          amount: 500,
        ),
      );
      final balance = await stockRepository.getBalance(
        productId: 'product-1',
        warehouseId: 'warehouse-1',
      );

      expect(result.isSuccess, isTrue, reason: result.failureOrNull?.messageAr);
      expect(balance.valueOrNull?.quantity.scaledUnits, 0);
      expect(balance.valueOrNull?.valuation.minorUnits, 0);
    });

    test('rejects changed payload on the same disposal idempotency key',
        () async {
      await repository.saveOpeningBalance(
        movement: _movement(currency),
        posting: await _buildPosting(currency),
      );
      final original = _disposalMovement(currency);
      await repository.saveStockDisposalAtomically(
        movement: original,
        posting: await _buildDisposalPosting(currency),
      );

      final changed = _disposalMovement(currency, quantity: 1);
      final result = await repository.saveStockDisposalAtomically(
        movement: changed,
        posting: await _buildDisposalPosting(currency, amount: 100),
      );

      expect(result.isFailure, isTrue);
      expect(await db.query('pos_stock_movements'), hasLength(2));
      expect(await db.query('vouchers'), hasLength(2));
      expect(await db.query('ledger_entries'), hasLength(4));
    });

    test('reverses disposal with a linked inbound movement and new voucher',
        () async {
      await repository.saveOpeningBalance(
        movement: _movement(currency),
        posting: await _buildPosting(currency),
      );
      final original = _disposalMovement(currency);
      await repository.saveStockDisposalAtomically(
        movement: original,
        posting: await _buildDisposalPosting(currency),
      );
      final reversalDate = DateTime.utc(2026, 1, 2, 11);
      final reversal = PosStockMovement.create(
        id: 'disposal-reversal-movement-1',
        productId: 'product-1',
        warehouseId: 'warehouse-1',
        type: PosStockMovementType.adjustment,
        direction: PosStockMovementDirection.inbound,
        quantity: PosQuantity.whole(2),
        unitCost: Money.fromMinorUnits(100, currency),
        sourceType: 'stock_disposal_reversal',
        sourceId: 'disposal-reversal-source-1',
        reasonDetail: 'Correcting the original write-off',
        voucherId: 'disposal-reversal-voucher-1',
        reversesSourceId: 'disposal-source-1',
        occurredAt: reversalDate,
        idempotencyKey: 'disposal-reversal-key-1',
        createdAt: reversalDate,
      );
      final reversalPosting = await _buildDisposalPosting(
        currency,
        sourceId: 'disposal-reversal-source-1',
        voucherId: 'disposal-reversal-voucher-1',
        direction: PosStockMovementDirection.inbound,
        reason: null,
        reversalOfSourceId: 'disposal-source-1',
        date: reversalDate,
      );

      final first = await repository.saveStockDisposalAtomically(
        movement: reversal,
        posting: reversalPosting,
      );
      final replay = await repository.saveStockDisposalAtomically(
        movement: reversal,
        posting: reversalPosting,
      );

      expect(first.isSuccess, isTrue, reason: first.failureOrNull?.messageAr);
      expect(replay.isSuccess, isTrue, reason: replay.failureOrNull?.messageAr);
      final originalRow = (await db.query(
        'pos_stock_movements',
        where: 'source_id = ?',
        whereArgs: ['disposal-source-1'],
      )).single;
      expect(originalRow['quantity_scaled'], -2);
      expect(originalRow['reverses_source_id'], isNull);
      final reversalRow = (await db.query(
        'pos_stock_movements',
        where: 'source_id = ?',
        whereArgs: ['disposal-reversal-source-1'],
      )).single;
      expect(reversalRow['quantity_scaled'], 2);
      expect(reversalRow['reverses_source_id'], 'disposal-source-1');
      expect(await db.query('pos_stock_movements'), hasLength(3));
      expect(await db.query('vouchers'), hasLength(3));
      expect(await db.query('ledger_entries'), hasLength(6));
      final balance = await stockRepository.getBalance(
        productId: 'product-1',
        warehouseId: 'warehouse-1',
      );
      expect(balance.valueOrNull?.quantity.scaledUnits, 5);
    });

    test('rolls back disposal movement when voucher ledger insertion fails',
        () async {
      await repository.saveOpeningBalance(
        movement: _movement(currency),
        posting: await _buildPosting(currency),
      );
      await db.execute('''
        CREATE TRIGGER reject_disposal_ledger
        BEFORE INSERT ON ledger_entries
        WHEN NEW.voucher_id = 'disposal-voucher-1'
        BEGIN
          SELECT RAISE(ABORT, 'simulated disposal posting failure');
        END
      ''');

      final result = await repository.saveStockDisposalAtomically(
        movement: _disposalMovement(currency),
        posting: await _buildDisposalPosting(currency),
      );

      expect(result.isFailure, isTrue);
      expect(await db.query('pos_stock_movements'), hasLength(1));
      expect(await db.query('vouchers'), hasLength(1));
      expect(await db.query('ledger_entries'), hasLength(2));
      final balance = await stockRepository.getBalance(
        productId: 'product-1',
        warehouseId: 'warehouse-1',
      );
      expect(balance.valueOrNull?.quantity.scaledUnits, 5);
    });

    test('rolls back movement and voucher when lot projection is inconsistent',
        () async {
      await db.update(
        'pos_products',
        {'expiry_tracking': 1},
        where: 'id = ?',
        whereArgs: ['product-1'],
      );
      final lot = _openingLot(currency);
      final opening = await repository.saveOpeningBalance(
        movement: _movement(currency, lotId: lot.id),
        lots: [lot],
        posting: await _buildPosting(currency),
      );
      expect(opening.isSuccess, isTrue);
      await db.execute(
        'DROP TRIGGER trg_pos_stock_movement_project_lot',
      );

      final result = await repository.saveStockDisposalAtomically(
        movement: _disposalMovement(currency, lotId: lot.id),
        posting: await _buildDisposalPosting(currency),
      );

      expect(result.isFailure, isTrue);
      expect(await db.query('pos_stock_movements'), hasLength(1));
      expect(await db.query('vouchers'), hasLength(1));
      expect(await db.query('ledger_entries'), hasLength(2));
      final savedLot = (await db.query('pos_stock_lots')).single;
      expect(savedLot['remaining_quantity_scaled'], 5);
    });
  });
}
