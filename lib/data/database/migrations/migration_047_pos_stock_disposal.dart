import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Schema v47: audit metadata for atomic POS stock disposals and reversals.
///
/// Existing movements remain untouched; the new fields are nullable for all
/// legacy stock events and are populated only by the disposal workflow.
final class Migration047PosStockDisposal implements SchemaMigration {
  @override
  int get version => 47;

  @override
  Future<void> up(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(pos_stock_movements)');
    final names = columns.map((column) => column['name']).toSet();
    if (!names.contains('disposal_reason_code')) {
      await db.execute('''
        ALTER TABLE pos_stock_movements
        ADD COLUMN disposal_reason_code TEXT
          CHECK (disposal_reason_code IS NULL OR disposal_reason_code IN (
            'damage', 'expiry', 'authorized_loss', 'other'
          ))
      ''');
    }
    if (!names.contains('reason_detail')) {
      await db.execute('''
        ALTER TABLE pos_stock_movements
        ADD COLUMN reason_detail TEXT
          CHECK (reason_detail IS NULL OR
                 length(trim(reason_detail)) BETWEEN 1 AND 500)
      ''');
    }
    if (!names.contains('voucher_id')) {
      await db.execute('''
        ALTER TABLE pos_stock_movements ADD COLUMN voucher_id TEXT
      ''');
    }
    if (!names.contains('reverses_source_id')) {
      await db.execute('''
        ALTER TABLE pos_stock_movements ADD COLUMN reverses_source_id TEXT
      ''');
    }

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pos_stock_movement_voucher
      ON pos_stock_movements (voucher_id)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_stock_movement_reversal_source
      ON pos_stock_movements (reverses_source_id)
      WHERE reverses_source_id IS NOT NULL
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_pos_stock_disposal_fields_valid
      BEFORE INSERT ON pos_stock_movements
      WHEN NEW.source_type = 'stock_disposal' AND (
        NEW.disposal_reason_code IS NULL OR
        NEW.source_id IS NULL OR trim(NEW.source_id) = '' OR
        NEW.voucher_id IS NULL OR trim(NEW.voucher_id) = '' OR
        NEW.quantity_scaled >= 0 OR
        (NEW.disposal_reason_code = 'damage' AND NEW.movement_type <> 'damage') OR
        (NEW.disposal_reason_code = 'expiry' AND NEW.movement_type <> 'expiry') OR
        (NEW.disposal_reason_code IN ('authorized_loss', 'other') AND
          NEW.movement_type <> 'adjustment') OR
        (NEW.disposal_reason_code = 'other' AND
          trim(COALESCE(NEW.reason_detail, '')) = '')
      )
      BEGIN
        SELECT RAISE(ABORT, 'pos_stock_disposal_metadata_invalid');
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_pos_stock_disposal_reversal_valid
      BEFORE INSERT ON pos_stock_movements
      WHEN NEW.source_type = 'stock_disposal_reversal' AND (
        NEW.reverses_source_id IS NULL OR trim(NEW.reverses_source_id) = '' OR
        NEW.source_id IS NULL OR trim(NEW.source_id) = '' OR
        NEW.voucher_id IS NULL OR trim(NEW.voucher_id) = '' OR
        NEW.disposal_reason_code IS NOT NULL OR
        NEW.movement_type <> 'adjustment' OR NEW.quantity_scaled <= 0
      )
      BEGIN
        SELECT RAISE(ABORT, 'pos_stock_disposal_reversal_invalid');
      END
    ''');
  }
}
