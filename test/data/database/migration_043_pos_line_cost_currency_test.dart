import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/database/migrations/migration_043_pos_line_cost_currency.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('adds and backfills unit cost currency from each legacy invoice', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE pos_invoices (
        id TEXT PRIMARY KEY,
        currency_code TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE pos_invoice_lines (
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        unit_cost_minor INTEGER NOT NULL
      )
    ''');
    await db.insert('pos_invoices', {'id': 'invoice-sar', 'currency_code': 'SAR'});
    await db.insert('pos_invoices', {'id': 'invoice-usd', 'currency_code': 'USD'});
    await db.insert('pos_invoice_lines', {
      'id': 'line-sar',
      'invoice_id': 'invoice-sar',
      'unit_cost_minor': 250,
    });
    await db.insert('pos_invoice_lines', {
      'id': 'line-usd',
      'invoice_id': 'invoice-usd',
      'unit_cost_minor': 125,
    });

    await Migration043PosLineCostCurrency().up(db);

    final columns = await db.rawQuery('PRAGMA table_info(pos_invoice_lines)');
    expect(
      columns.map((row) => row['name']),
      contains('unit_cost_currency_code'),
    );
    final lines = await db.query(
      'pos_invoice_lines',
      orderBy: 'id ASC',
    );
    expect(lines[0]['unit_cost_currency_code'], 'SAR');
    expect(lines[1]['unit_cost_currency_code'], 'USD');
  });
}
