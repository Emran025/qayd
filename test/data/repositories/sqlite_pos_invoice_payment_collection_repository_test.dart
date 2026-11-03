import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_041_pos_invoice_metadata.dart';
import 'package:qayd/data/database/migrations/migration_registry.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/data/repositories/sqlite_pos_invoice_payment_collection_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _currency = CurrencyCode(
  code: 'SAR',
  nameAr: 'ريال سعودي',
  symbol: 'ر.س',
);
final _date = DateTime.utc(2026, 2, 1, 10);
final _recordedAt = DateTime.utc(2026, 2, 2, 10);

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
      date TEXT NOT NULL, amount_minor INTEGER NOT NULL,
      currency_code TEXT NOT NULL, counterparty_id TEXT NOT NULL,
      affected_account_id TEXT NOT NULL, state TEXT NOT NULL,
      description TEXT, notes TEXT, tags_json TEXT NOT NULL,
      attachments_json TEXT NOT NULL, created_at TEXT NOT NULL,
      confirmed_at TEXT, settled_at TEXT, signer_phone TEXT,
      canonical_sender_phone TEXT, canonical_receiver_phone TEXT,
      transfer_group_id TEXT, tripartite_role TEXT, linked_party_id TEXT,
      mediator_account_id TEXT, fee_amount_minor INTEGER,
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
      id TEXT PRIMARY KEY, transaction_id TEXT NOT NULL,
      account_id TEXT NOT NULL, side TEXT NOT NULL, amount_minor INTEGER NOT NULL,
      currency_code TEXT NOT NULL, voucher_id TEXT NOT NULL,
      date TEXT NOT NULL, created_at TEXT NOT NULL
    )
  ''');
  await Migration040PosFoundation().up(db);
  await Migration041PosInvoiceMetadata().up(db);
  await MigrationRegistry.applyFromTo(db, fromVersion: 41, toVersion: 47);
}

PosInvoice _invoice() {
  final line = PosInvoiceLine.create(
    id: 'line-1',
    invoiceId: 'invoice-1',
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    quantity: PosQuantity.whole(2),
    unitPrice: Money.fromMinorUnits(500, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    createdAt: _date,
  );
  return PosInvoice.draft(
    id: 'invoice-1',
    invoiceNumber: 'S-0001',
    type: PosInvoiceType.sale,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [line],
    idempotencyKey: 'sale-key-1',
    invoiceDate: _date,
    now: _date,
    counterpartyAccountId: AccountId('customer-1'),
  ).post(_date);
}

PosInvoicePaymentCollectionPosting _posting({
  PosInvoice? before,
  int amount = 300,
  String paymentId = 'collection-1',
  String idempotencyKey = 'collection-key-1',
  String receivingAccountId = 'cash-1',
}) {
  final invoiceBefore = before ?? _invoice();
  final money = Money.fromMinorUnits(amount, _currency);
  final occurredAt = DateTime.utc(2026, 2, 2, 9);
  final event = PosInvoicePayment.create(
    id: paymentId,
    invoiceId: invoiceBefore.id,
    accountId: AccountId(receivingAccountId),
    method: PosPaymentMethod.bank,
    amount: money,
    currency: _currency,
    occurredAt: occurredAt,
    idempotencyKey: idempotencyKey,
  );
  final after = invoiceBefore.applyPayment(money, _recordedAt);
  final voucher = Voucher.draft(
    id: VoucherId('$paymentId:voucher'),
    type: VoucherType.receipt,
    date: occurredAt,
    amount: money,
    currency: _currency,
    counterpartyId: AccountId('customer-1'),
    affectedAccountId: AccountId(receivingAccountId),
    referenceNumber: paymentId,
    description: 'POS collection S-0001',
    createdAt: _recordedAt,
  ).confirm(_recordedAt);
  final accounting = PosAccountingPosting(
    sourceId: paymentId,
    voucher: voucher,
    entries: const EntryGenerator().generateForConfirmedVoucher(
      voucher: voucher,
      transactionId: TransactionId('$paymentId:transaction'),
      debitEntryId: EntryId('$paymentId:debit'),
      creditEntryId: EntryId('$paymentId:credit'),
      ledgerCreatedAt: _recordedAt,
    ),
  );
  return PosInvoicePaymentCollectionPosting(
    invoiceBefore: invoiceBefore,
    invoiceAfter: after,
    payment: event,
    accountingPosting: accounting,
    recordedAt: _recordedAt,
  );
}

void main() {
  sqfliteFfiInit();
  late Database db;
  late SqlitePosInvoicePaymentCollectionRepository repository;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await _createSchema(db);
    await db.insert('accounts', {
      'id': 'cash-1',
      'name': 'Bank',
      'nature': 'debit',
      'is_active': 1,
      'is_archived': 0,
      'created_at': _date.toIso8601String(),
      'standard_classification': 'liquidAssets',
    });
    await db.insert('accounts', {
      'id': 'customer-1',
      'name': 'Customer',
      'nature': 'debit',
      'is_active': 1,
      'is_archived': 0,
      'created_at': _date.toIso8601String(),
      'standard_classification': 'receivables',
    });
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
    final invoice = _invoice();
    await db.insert('pos_invoices', PosInvoiceMapper.toRow(invoice));
    await db.insert(
      'pos_invoice_lines',
      PosInvoiceMapper.lineToRow(invoice.lines.single),
    );
    final runner = DatabaseTransactionRunner(db);
    repository = SqlitePosInvoicePaymentCollectionRepository(
      runner,
      SqliteVoucherRepository(db, runner),
    );
  });

  tearDown(() async => db.close());

  test('commits collection and returns exact replay without duplicating rows',
      () async {
    final posting = _posting();

    final saved = await repository.saveAtomically(posting);
    final recovered = await repository.recoverCommitted(posting);
    final replay = await repository.saveAtomically(posting);
    final invoiceRow = (await db.query('pos_invoices')).single;

    expect(saved.isSuccess, isTrue);
    expect(
      recovered.valueOrNull,
      isTrue,
      reason: recovered.failureOrNull is ValidationFailure
          ? (recovered.failureOrNull! as ValidationFailure).code
          : '${recovered.failureOrNull}',
    );
    expect(replay.isSuccess, isTrue);
    expect(invoiceRow['paid_minor'], 300);
    expect(invoiceRow['due_minor'], 700);
    expect(invoiceRow['status'], 'partiallyPaid');
    expect(await db.rawQuery('SELECT id FROM pos_payments'), hasLength(1));
    expect(await db.rawQuery('SELECT id FROM vouchers'), hasLength(1));
    expect(await db.rawQuery('SELECT id FROM ledger_entries'), hasLength(2));
  });

  test('same idempotency key with changed amount is rejected without writes',
      () async {
    final original = _posting();
    expect((await repository.saveAtomically(original)).isSuccess, isTrue);
    final changed = _posting(amount: 301);

    final result = await repository.saveAtomically(changed);

    expect(result.isFailure, isTrue);
    expect((await db.query('pos_payments')).single['amount_minor'], 300);
    expect((await db.query('pos_invoices')).single['paid_minor'], 300);
    expect(await db.rawQuery('SELECT id FROM ledger_entries'), hasLength(2));
  });

  test('stale concurrent balance snapshot cannot over-collect', () async {
    final first = _posting();
    expect((await repository.saveAtomically(first)).isSuccess, isTrue);
    final stale = _posting(
      amount: 701,
      paymentId: 'collection-2',
      idempotencyKey: 'collection-key-2',
    );

    final result = await repository.saveAtomically(stale);

    expect(result.isFailure, isTrue);
    final invoice = (await db.query('pos_invoices')).single;
    expect(invoice['paid_minor'], 300);
    expect(invoice['due_minor'], 700);
    expect(await db.query('pos_payments'), hasLength(1));
  });

  test('ledger write failure rolls back payment, voucher, and invoice balance',
      () async {
    await db.execute('''
      CREATE TRIGGER reject_collection_ledger
      BEFORE INSERT ON ledger_entries
      BEGIN SELECT RAISE(ABORT, 'forced ledger failure'); END
    ''');

    final result = await repository.saveAtomically(_posting());

    expect(result.isFailure, isTrue);
    expect((await db.query('pos_invoices')).single['paid_minor'], 0);
    expect(await db.query('pos_payments'), isEmpty);
    expect(await db.query('vouchers'), isEmpty);
    expect(await db.query('ledger_entries'), isEmpty);
  });
}
