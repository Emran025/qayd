import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_041_pos_invoice_metadata.dart';
import 'package:qayd/data/database/migrations/migration_048_pos_discount_snapshots.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'adds discount snapshot columns idempotently without changing old rows',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute(
        'CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT)',
      );
      await Migration040PosFoundation().up(db);
      await Migration041PosInvoiceMetadata().up(db);
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
        'currency_code': 'SAR',
        'subtotal_minor': 1000,
        'discount_minor': 0,
        'tax_minor': 0,
        'total_minor': 1000,
        'paid_minor': 1000,
        'due_minor': 0,
        'idempotency_key': 'legacy-sale-1',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });

      final migration = Migration048PosDiscountSnapshots();
      await migration.up(db);
      await migration.up(db);

      final invoiceColumns = (await db.rawQuery(
        'PRAGMA table_info(pos_invoices)',
      )).map((row) => row['name'] as String).toSet();
      final lineColumns = (await db.rawQuery(
        'PRAGMA table_info(pos_invoice_lines)',
      )).map((row) => row['name'] as String).toSet();
      expect(
        invoiceColumns,
        containsAll(<String>[
          'cart_discount_minor',
          'cart_discount_method',
          'cart_discount_value',
          'cart_discount_reason',
          'cart_discount_actor_id',
          'cart_discount_policy_max_bps',
        ]),
      );
      expect(
        lineColumns,
        containsAll(<String>[
          'discount_rule_method',
          'discount_rule_value',
          'discount_reason',
          'discount_actor_id',
          'discount_policy_max_bps',
        ]),
      );
      final legacy = (await db.query(
        'pos_invoices',
        where: 'id = ?',
        whereArgs: ['legacy-invoice'],
      )).single;
      expect(legacy['subtotal_minor'], 1000);
      expect(legacy['total_minor'], 1000);
      expect(legacy['cart_discount_minor'], isNull);
      expect(legacy['cart_discount_reason'], isNull);
    },
  );
}
