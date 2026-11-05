import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/data/mappers/pos_sales_return_sync_snapshot_codec.dart';
import 'package:qayd/domain/entities/pos_purchase_return_posting.dart';
import 'package:qayd/domain/value_objects/account_id.dart';

/// Strict versioned JSON-safe snapshot for a complete purchase-return aggregate.
final class PosPurchaseReturnSyncSnapshotCodec {
  static const schema = 'qayd.pos.purchase-return-posting.v1';

  static Map<String, Object?> encode(
    PosPurchaseReturnPosting posting,
  ) => <String, Object?>{
    'schema': schema,
    'invoice': PosInvoiceMapper.toRow(posting.invoice),
    'lines': posting.invoice.lines.map(PosInvoiceMapper.lineToRow).toList(),
    'movements': posting.movements
        .map(PosSalesReturnSyncSnapshotCodec.encodeMovementSnapshot)
        .toList(),
    'postings': posting.postings
        .map(PosSalesReturnSyncSnapshotCodec.encodeAccountingPostingSnapshot)
        .toList(),
    'source_invoice_id': posting.sourceInvoiceId,
    'supplier_payables_account_id': posting.supplierPayablesAccountId.value,
    'inventory_account_id': posting.inventoryAccountId.value,
    'purchase_returns_account_id': posting.purchaseReturnsAccountId.value,
    'reason': posting.reason,
  };

  static PosPurchaseReturnPosting decode(Map<String, Object?> raw) {
    _keys(raw, const {
      'schema',
      'invoice',
      'lines',
      'movements',
      'postings',
      'source_invoice_id',
      'supplier_payables_account_id',
      'inventory_account_id',
      'purchase_returns_account_id',
      'reason',
    }, 'root');
    if (raw['schema'] != schema) {
      throw const FormatException('Unsupported purchase return snapshot.');
    }
    final invoiceRow = _map(raw['invoice'], 'invoice');
    final lineRows = _listOfMaps(raw['lines'], 'lines');
    final invoice = PosSalesReturnSyncSnapshotCodec.decodeInvoiceSnapshot(
      invoiceRow,
      lineRows,
    );
    final movements = _listOfMaps(
      raw['movements'],
      'movements',
    ).map(PosSalesReturnSyncSnapshotCodec.decodeMovementSnapshot).toList();
    final postings = _listOfMaps(raw['postings'], 'postings')
        .map(PosSalesReturnSyncSnapshotCodec.decodeAccountingPostingSnapshot)
        .toList();
    final reason = raw['reason'];
    if (reason != null && reason is! String) {
      throw const FormatException('Invalid purchase-return reason.');
    }
    try {
      return PosPurchaseReturnPosting(
        invoice: invoice,
        sourceInvoiceId: _string(raw['source_invoice_id'], 'source_invoice_id'),
        supplierPayablesAccountId: AccountId(
          _string(
            raw['supplier_payables_account_id'],
            'supplier_payables_account_id',
          ),
        ),
        inventoryAccountId: AccountId(
          _string(raw['inventory_account_id'], 'inventory_account_id'),
        ),
        purchaseReturnsAccountId: AccountId(
          _string(
            raw['purchase_returns_account_id'],
            'purchase_returns_account_id',
          ),
        ),
        movements: movements,
        postings: postings,
        reason: reason as String?,
      );
    } catch (error) {
      throw FormatException('Invalid purchase return invariants: $error');
    }
  }

  static Map<String, Object?> _map(Object? value, String path) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw FormatException('Expected object at $path.');
  }

  static List<Map<String, Object?>> _listOfMaps(Object? value, String path) {
    if (value is! List) throw FormatException('Expected list at $path.');
    return value.map((item) => _map(item, path)).toList(growable: false);
  }

  static String _string(Object? value, String path) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Required string missing at $path.');
    }
    return value.trim();
  }

  static void _keys(
    Map<String, Object?> value,
    Set<String> expected,
    String path,
  ) {
    if (value.length != expected.length ||
        !value.keys.toSet().containsAll(expected)) {
      throw FormatException('Missing or unexpected fields at $path.');
    }
  }
}
