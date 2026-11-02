import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Schema v46: enforce the existing POS lot/movement relationship.
///
/// Historical lot and movement rows are deliberately left untouched. In
/// particular, no expiry date or lot is fabricated for legacy inventory.
final class Migration046PosStockLotsFefo implements SchemaMigration {
  @override
  int get version => 46;

  @override
  Future<void> up(Database db) async {
    final invoiceLineColumns = await db.rawQuery(
      'PRAGMA table_info(pos_invoice_lines)',
    );
    if (!invoiceLineColumns.any(
      (column) => column['name'] == 'expiry_tracking_snapshot',
    )) {
      await db.execute('''
        ALTER TABLE pos_invoice_lines
        ADD COLUMN expiry_tracking_snapshot INTEGER
        CHECK (expiry_tracking_snapshot IN (0, 1))
      ''');
    }

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pos_lots_fefo
      ON pos_stock_lots (
        product_id, warehouse_id, expiry_date,
        remaining_quantity_scaled, created_at, id
      )
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_pos_stock_lot_insert_valid
      BEFORE INSERT ON pos_stock_lots
      BEGIN
        SELECT CASE
          WHEN NEW.remaining_quantity_scaled <> 0
          THEN RAISE(ABORT, 'pos_stock_lot_projection_must_start_at_zero')
        END;
        SELECT CASE
          WHEN EXISTS (
            SELECT 1 FROM pos_products p
            WHERE p.id = NEW.product_id AND p.expiry_tracking = 1
          ) AND (
            NEW.expiry_date IS NULL OR
            length(NEW.expiry_date) <> 10 OR
            strftime('%Y-%m-%d', NEW.expiry_date) IS NULL OR
            strftime('%Y-%m-%d', NEW.expiry_date) <> NEW.expiry_date
          )
          THEN RAISE(ABORT, 'pos_tracked_stock_lot_expiry_required')
        END;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_pos_stock_movement_lot_valid
      BEFORE INSERT ON pos_stock_movements
      BEGIN
        SELECT CASE
          WHEN NEW.lot_id IS NULL AND EXISTS (
            SELECT 1 FROM pos_products p
            WHERE p.id = NEW.product_id AND p.expiry_tracking = 1
          )
          THEN RAISE(ABORT, 'pos_tracked_stock_movement_requires_lot')
        END;
        SELECT CASE
          WHEN NEW.lot_id IS NOT NULL AND NOT EXISTS (
            SELECT 1
            FROM pos_stock_lots l
            JOIN pos_products p ON p.id = l.product_id
            WHERE l.id = NEW.lot_id
              AND l.product_id = NEW.product_id
              AND l.warehouse_id = NEW.warehouse_id
              AND l.quantity_scale = NEW.quantity_scale
              AND l.currency_code = NEW.currency_code
              AND (
                p.expiry_tracking = 0 OR (
                  l.expiry_date IS NOT NULL AND
                  length(l.expiry_date) = 10 AND
                  strftime('%Y-%m-%d', l.expiry_date) = l.expiry_date
                )
              )
          )
          THEN RAISE(ABORT, 'pos_stock_movement_lot_mismatch')
        END;
        SELECT CASE
          WHEN NEW.lot_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM pos_stock_lots l
            WHERE l.id = NEW.lot_id AND (
              l.remaining_quantity_scaled + NEW.quantity_scaled < 0 OR
              l.remaining_quantity_scaled + NEW.quantity_scaled >
                l.received_quantity_scaled
            )
          )
          THEN RAISE(ABORT, 'pos_stock_lot_quantity_out_of_range')
        END;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_pos_stock_movement_project_lot
      AFTER INSERT ON pos_stock_movements
      WHEN NEW.lot_id IS NOT NULL
      BEGIN
        UPDATE pos_stock_lots
        SET remaining_quantity_scaled =
              remaining_quantity_scaled + NEW.quantity_scaled,
            updated_at = NEW.created_at
        WHERE id = NEW.lot_id;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_pos_stock_lot_projection_valid
      BEFORE UPDATE OF remaining_quantity_scaled ON pos_stock_lots
      WHEN NEW.remaining_quantity_scaled < 0 OR
           NEW.remaining_quantity_scaled > NEW.received_quantity_scaled OR
           NEW.remaining_quantity_scaled <> COALESCE((
             SELECT SUM(quantity_scaled)
             FROM pos_stock_movements
             WHERE lot_id = OLD.id
           ), 0)
      BEGIN
        SELECT RAISE(ABORT, 'pos_stock_lot_projection_mismatch');
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_pos_stock_lot_metadata_immutable
      BEFORE UPDATE OF
        id, product_id, warehouse_id, lot_number, expiry_date,
        received_quantity_scaled, quantity_scale, unit_cost_minor,
        currency_code, created_at
      ON pos_stock_lots
      BEGIN
        SELECT RAISE(ABORT, 'pos_stock_lot_metadata_immutable');
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_pos_stock_lot_no_delete
      BEFORE DELETE ON pos_stock_lots
      BEGIN
        SELECT RAISE(ABORT, 'pos_stock_lot_delete_forbidden');
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_pos_stock_movement_no_update
      BEFORE UPDATE ON pos_stock_movements
      BEGIN
        SELECT RAISE(ABORT, 'pos_stock_movement_immutable');
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_pos_stock_movement_no_delete
      BEFORE DELETE ON pos_stock_movements
      BEGIN
        SELECT RAISE(ABORT, 'pos_stock_movement_delete_forbidden');
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_pos_product_expiry_tracking_immutable
      BEFORE UPDATE OF expiry_tracking ON pos_products
      WHEN OLD.expiry_tracking <> NEW.expiry_tracking AND EXISTS (
        SELECT 1 FROM pos_stock_movements m WHERE m.product_id = OLD.id
      )
      BEGIN
        SELECT RAISE(ABORT, 'pos_product_expiry_tracking_has_history');
      END
    ''');
  }
}
