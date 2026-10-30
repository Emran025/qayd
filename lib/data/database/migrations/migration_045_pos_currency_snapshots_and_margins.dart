import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Schema v45: preserve line-level FX snapshots and product pricing margins.
/// Existing invoices remain untouched; all new snapshot columns are nullable.
final class Migration045PosCurrencySnapshotsAndMargins
    implements SchemaMigration {
  @override
  int get version => 45;

  @override
  Future<void> up(Database db) async {
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN conversion_purpose TEXT
      CHECK (conversion_purpose IS NULL OR
             conversion_purpose IN ('catalogSalePrice', 'purchaseCost'))
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN conversion_source_minor INTEGER
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN conversion_source_currency_code TEXT
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN conversion_target_minor INTEGER
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN conversion_target_currency_code TEXT
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN fx_rate_id TEXT
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN fx_requested_from_code TEXT
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN fx_requested_to_code TEXT
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN fx_stored_from_code TEXT
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN fx_stored_to_code TEXT
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN fx_rate_scaled INTEGER
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN fx_effective_at TEXT
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN fx_recorded_at TEXT
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN fx_created_at TEXT
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN fx_is_inverted INTEGER
      CHECK (fx_is_inverted IS NULL OR fx_is_inverted IN (0, 1))
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN fx_note TEXT
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN proposed_sale_price_minor INTEGER
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN proposed_sale_price_applied INTEGER NOT NULL DEFAULT 0
      CHECK (proposed_sale_price_applied IN (0, 1))
    ''');
    await db.execute('''
      ALTER TABLE pos_invoice_lines
      ADD COLUMN product_updated_at_snapshot TEXT
    ''');

    await db.execute('''
      ALTER TABLE pos_products
      ADD COLUMN profit_margin_type TEXT NOT NULL DEFAULT 'percentage'
      CHECK (profit_margin_type IN ('percentage', 'fixed_amount'))
    ''');
    await db.execute('''
      ALTER TABLE pos_products
      ADD COLUMN profit_margin_value INTEGER NOT NULL DEFAULT 0
      CHECK (profit_margin_value >= 0)
    ''');
  }
}
