import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Schema v49: preserve explicitly supplied credit due dates and terms.
/// Existing invoices keep null values; no historical term is fabricated.
final class Migration049PosCreditTerms implements SchemaMigration {
  @override
  int get version => 49;

  @override
  Future<void> up(Database db) async {
    await _addIfMissing(db, 'credit_due_date', 'TEXT');
    await _addIfMissing(db, 'credit_terms', 'TEXT');
  }

  Future<void> _addIfMissing(Database db, String column, String type) async {
    final columns = await db.rawQuery('PRAGMA table_info(pos_invoices)');
    if (!columns.any((row) => row['name'] == column)) {
      await db.execute('ALTER TABLE pos_invoices ADD COLUMN $column $type');
    }
  }
}
