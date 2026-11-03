import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Schema v48: preserve discount inputs and audit context with each POS sale.
/// Existing invoice rows remain readable; their nullable metadata is not
/// fabricated or retroactively attributed to an operator.
final class Migration048PosDiscountSnapshots implements SchemaMigration {
  @override
  int get version => 48;

  @override
  Future<void> up(Database db) async {
    await _addIfMissing(db, 'pos_invoices', 'cart_discount_minor', 'INTEGER');
    await _addIfMissing(db, 'pos_invoices', 'cart_discount_method', 'TEXT');
    await _addIfMissing(db, 'pos_invoices', 'cart_discount_value', 'INTEGER');
    await _addIfMissing(db, 'pos_invoices', 'cart_discount_reason', 'TEXT');
    await _addIfMissing(db, 'pos_invoices', 'cart_discount_actor_id', 'TEXT');
    await _addIfMissing(
      db,
      'pos_invoices',
      'cart_discount_policy_max_bps',
      'INTEGER',
    );
    await _addIfMissing(
      db,
      'pos_invoice_lines',
      'discount_rule_method',
      'TEXT',
    );
    await _addIfMissing(
      db,
      'pos_invoice_lines',
      'discount_rule_value',
      'INTEGER',
    );
    await _addIfMissing(db, 'pos_invoice_lines', 'discount_reason', 'TEXT');
    await _addIfMissing(db, 'pos_invoice_lines', 'discount_actor_id', 'TEXT');
    await _addIfMissing(
      db,
      'pos_invoice_lines',
      'discount_policy_max_bps',
      'INTEGER',
    );
  }

  Future<void> _addIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((row) => row['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }
}
