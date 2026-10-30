import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Schema v44: immutable, explicitly recorded POS currency-rate history.
final class Migration044PosCurrencyRates implements SchemaMigration {
  @override
  int get version => 44;

  @override
  Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE pos_currency_rates (
        id TEXT PRIMARY KEY,
        from_currency_code TEXT NOT NULL,
        to_currency_code TEXT NOT NULL,
        rate_scaled INTEGER NOT NULL CHECK (rate_scaled > 0),
        effective_at TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL,
        CHECK (from_currency_code <> to_currency_code)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_pos_currency_rates_pair_recorded
      ON pos_currency_rates(
        from_currency_code,
        to_currency_code,
        recorded_at DESC
      )
    ''');
    await db.execute('''
      CREATE TRIGGER pos_currency_rates_no_update
      BEFORE UPDATE ON pos_currency_rates
      BEGIN
        SELECT RAISE(ABORT, 'POS currency-rate history is append-only');
      END
    ''');
    await db.execute('''
      CREATE TRIGGER pos_currency_rates_no_delete
      BEFORE DELETE ON pos_currency_rates
      BEGIN
        SELECT RAISE(ABORT, 'POS currency-rate history is append-only');
      END
    ''');
  }
}
