import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Schema v42: normalized, archive-safe POS product taxonomy.
final class Migration042PosProductCategories implements SchemaMigration {
  @override
  int get version => 42;

  @override
  Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pos_product_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        parent_id TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (code),
        FOREIGN KEY (parent_id) REFERENCES pos_product_categories (id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pos_product_categories_parent '
      'ON pos_product_categories (parent_id, is_active, name)',
    );
    await db.execute(
      'ALTER TABLE pos_products ADD COLUMN category_id TEXT '
      'REFERENCES pos_product_categories (id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pos_products_category '
      'ON pos_products (category_id, is_active)',
    );
  }
}
