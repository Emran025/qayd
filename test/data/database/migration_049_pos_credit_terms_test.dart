import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_049_pos_credit_terms.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'adds credit fields idempotently without fabricating legacy terms',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute(
        'CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT)',
      );
      await Migration040PosFoundation().up(db);
      await db.insert('pos_warehouses', {
        'id': 'warehouse-1',
        'code': 'MAIN',
        'name': 'Main',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      await db.insert('pos_invoices', {
        'id': 'legacy-invoice',
        'invoice_number': 'S-1',
        'document_type': 'sale',
        'status': 'posted',
        'warehouse_id': 'warehouse-1',
        'currency_code': 'YER',
        'subtotal_minor': 1000,
        'total_minor': 1000,
        'idempotency_key': 'legacy-sale-1',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });

      final migration = Migration049PosCreditTerms();
      await migration.up(db);
      await migration.up(db);

      final columns = (await db.rawQuery(
        'PRAGMA table_info(pos_invoices)',
      )).map((row) => row['name'] as String).toSet();
      expect(columns, containsAll(['credit_due_date', 'credit_terms']));
      final legacy = (await db.query(
        'pos_invoices',
        where: 'id = ?',
        whereArgs: ['legacy-invoice'],
      )).single;
      expect(legacy['credit_due_date'], isNull);
      expect(legacy['credit_terms'], isNull);

      await db.insert('pos_invoices', {
        'id': 'new-invoice',
        'invoice_number': 'S-2',
        'document_type': 'sale',
        'status': 'posted',
        'warehouse_id': 'warehouse-1',
        'currency_code': 'YER',
        'subtotal_minor': 1000,
        'total_minor': 1000,
        'idempotency_key': 'new-sale-2',
        'credit_due_date': '2026-12-01T00:00:00.000Z',
        'credit_terms': 'Net 30 days',
        'created_at': '2026-11-01T00:00:00.000Z',
        'updated_at': '2026-11-01T00:00:00.000Z',
      });
      final stored = (await db.query(
        'pos_invoices',
        where: 'id = ?',
        whereArgs: ['new-invoice'],
      )).single;
      expect(stored['credit_due_date'], '2026-12-01T00:00:00.000Z');
      expect(stored['credit_terms'], 'Net 30 days');
    },
  );
}
