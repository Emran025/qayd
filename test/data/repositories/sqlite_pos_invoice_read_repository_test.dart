import 'package:mocktail/mocktail.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/repositories/sqlite_pos_invoice_read_repository.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Currencies extends Mock implements CurrencyRepository {}

void main() {
  sqfliteFfiInit();
  const currency = CurrencyCode(
    code: 'YER',
    nameAr: 'ريال يمني',
    symbol: 'ر.ي',
    fractionalDigits: 2,
  );

  late Database db;
  late _Currencies currencies;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE pos_invoices (
        id TEXT NOT NULL,
        invoice_number TEXT NOT NULL,
        document_type TEXT NOT NULL,
        status TEXT NOT NULL,
        counterparty_account_id TEXT,
        warehouse_id TEXT NOT NULL,
        source_invoice_id TEXT,
        currency_code TEXT NOT NULL,
        subtotal_minor INTEGER NOT NULL,
        discount_minor INTEGER NOT NULL,
        tax_minor INTEGER NOT NULL,
        total_minor INTEGER NOT NULL,
        paid_minor INTEGER NOT NULL,
        due_minor INTEGER NOT NULL,
        idempotency_key TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        posted_at TEXT,
        invoice_date TEXT NOT NULL,
        signature_hex TEXT,
        signer_public_key_hex TEXT,
        signature_payload_hash TEXT,
        signed_at TEXT,
        cart_discount_minor INTEGER,
        cart_discount_method TEXT,
        cart_discount_value INTEGER,
        cart_discount_reason TEXT,
        cart_discount_actor_id TEXT,
        cart_discount_policy_max_bps INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE pos_invoice_lines (
        id TEXT NOT NULL,
        invoice_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name_snapshot TEXT NOT NULL,
        barcode_snapshot TEXT,
        quantity_scaled INTEGER NOT NULL,
        quantity_scale INTEGER NOT NULL,
        unit_price_minor INTEGER NOT NULL,
        unit_cost_minor INTEGER NOT NULL,
        discount_minor INTEGER NOT NULL,
        tax_minor INTEGER NOT NULL,
        line_total_minor INTEGER NOT NULL,
        source_line_id TEXT,
        created_at TEXT NOT NULL,
        discount_rule_method TEXT,
        discount_rule_value INTEGER,
        discount_reason TEXT,
        discount_actor_id TEXT,
        discount_policy_max_bps INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE pos_payments (
        id TEXT NOT NULL,
        invoice_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        payment_method TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        currency_code TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        idempotency_key TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    currencies = _Currencies();
    when(() => currencies.getByCode('YER'))
        .thenAnswer((_) async => const Success(currency));
    const date = '2026-01-01T10:00:00.000Z';
    await db.insert('pos_invoices', {
      'id': 'invoice-1',
      'invoice_number': 'S-000001',
      'document_type': 'sale',
      'status': 'partiallyPaid',
      'counterparty_account_id': 'customer-1',
      'warehouse_id': 'warehouse-1',
      'currency_code': 'YER',
      'subtotal_minor': 500,
      'discount_minor': 0,
      'tax_minor': 0,
      'total_minor': 500,
      'paid_minor': 200,
      'due_minor': 300,
      'idempotency_key': 'sale:1',
      'created_at': date,
      'updated_at': date,
      'posted_at': date,
      'invoice_date': date,
    });
    await db.insert('pos_invoice_lines', {
      'id': 'line-1',
      'invoice_id': 'invoice-1',
      'product_id': 'product-1',
      'product_name_snapshot': 'Coffee',
      'barcode_snapshot': '6290001',
      'quantity_scaled': 1250,
      'quantity_scale': 3,
      'unit_price_minor': 400,
      'unit_cost_minor': 250,
      'discount_minor': 0,
      'tax_minor': 0,
      'line_total_minor': 500,
      'created_at': date,
    });
    await db.insert('pos_payments', {
      'id': 'payment-1',
      'invoice_id': 'invoice-1',
      'account_id': 'cash',
      'payment_method': 'cash',
      'amount_minor': 200,
      'currency_code': 'YER',
      'occurred_at': date,
      'idempotency_key': 'payment:1',
      'created_at': date,
    });
  });

  tearDown(() => db.close());

  test('rehydrates invoice, exact fractional line, payment, and due', () async {
    final repository = SqlitePosInvoiceReadRepository(db, currencies);
    final result = await repository.getById('invoice-1');

    expect(result.isSuccess, isTrue);
    final details = result.valueOrNull!;
    expect(details.invoice.invoiceNumber, 'S-000001');
    expect(details.invoice.lines.single.quantity.toExactString(), '1.25');
    expect(details.invoice.paid.minorUnits, 200);
    expect(details.invoice.due.minorUnits, 300);
    expect(details.payments.single.amount.minorUnits, 200);
    expect(details.payments.single.accountId.value, 'cash');
  });

  test('lists by date and type without exposing database concerns', () async {
    final repository = SqlitePosInvoiceReadRepository(db, currencies);
    final result = await repository.list(
      from: DateTime.utc(2026, 1, 1),
      to: DateTime.utc(2026, 1, 2),
    );

    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull, hasLength(1));
    expect(result.valueOrNull!.single.type.name, 'sale');
  });

  test('restores line and cart discount rules with audit context', () async {
    await db.update(
      'pos_invoices',
      {
        'discount_minor': 95,
        'cart_discount_minor': 45,
        'cart_discount_method': 'percentage',
        'cart_discount_value': 1000,
        'cart_discount_reason': 'Cart offer',
        'cart_discount_actor_id': 'device-1',
        'cart_discount_policy_max_bps': 10000,
        'total_minor': 405,
        'due_minor': 205,
      },
      where: 'id = ?',
      whereArgs: ['invoice-1'],
    );
    await db.update(
      'pos_invoice_lines',
      {
        'discount_minor': 50,
        'line_total_minor': 450,
        'discount_rule_method': 'fixedAmount',
        'discount_rule_value': 50,
        'discount_reason': 'Line offer',
        'discount_actor_id': 'device-1',
        'discount_policy_max_bps': 10000,
      },
      where: 'id = ?',
      whereArgs: ['line-1'],
    );

    final result = await SqlitePosInvoiceReadRepository(
      db,
      currencies,
    ).getById('invoice-1');

    expect(result.isSuccess, isTrue);
    final invoice = result.valueOrNull!.invoice;
    expect(invoice.discount.minorUnits, 95);
    expect(invoice.cartDiscount.minorUnits, 45);
    expect(invoice.cartDiscountRule?.method.name, 'percentage');
    expect(invoice.cartDiscountRule?.value, 1000);
    expect(invoice.cartDiscountRule?.reason, 'Cart offer');
    expect(invoice.cartDiscountRule?.actorId, 'device-1');
    expect(invoice.lines.single.discountRule?.method.name, 'fixedAmount');
    expect(invoice.lines.single.discountRule?.value, 50);
    expect(invoice.lines.single.discountRule?.reason, 'Line offer');
    expect(invoice.lines.single.discountRule?.actorId, 'device-1');
    expect(invoice.total.minorUnits, 405);
  });
}
