import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Schema v43: preserve each invoice line's recorded cost currency.
final class Migration043PosLineCostCurrency implements SchemaMigration {
  @override
  int get version => 43;

  @override
  Future<void> up(Database db) async {
    await db.execute(
      'ALTER TABLE pos_invoice_lines ADD COLUMN unit_cost_currency_code TEXT',
    );
    await db.execute(
      'UPDATE pos_invoice_lines SET unit_cost_currency_code = '
      '(SELECT currency_code FROM pos_invoices WHERE pos_invoices.id = pos_invoice_lines.invoice_id) '
      "WHERE unit_cost_currency_code IS NULL OR unit_cost_currency_code = ''",
    );
  }
}
