import 'package:sqflite_sqlcipher/sqflite.dart';

class DeviceSyncOutboxEntry {
  const DeviceSyncOutboxEntry({
    required this.id,
    required this.auditEntryId,
    required this.targetDeviceId,
    required this.encryptedPayload,
    required this.signature,
    required this.state,
    required this.retryCount,
    required this.createdAt,
    this.sentAt,
  });

  final String id;
  final String auditEntryId;
  final String targetDeviceId;
  final String encryptedPayload;
  final String signature;
  final String state;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? sentAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'audit_entry_id': auditEntryId,
      'target_device_id': targetDeviceId,
      'encrypted_payload': encryptedPayload,
      'signature': signature,
      'state': state,
      'retry_count': retryCount,
      'created_at': createdAt.toUtc().toIso8601String(),
      'sent_at': sentAt?.toUtc().toIso8601String(),
    };
  }

  factory DeviceSyncOutboxEntry.fromMap(Map<String, Object?> map) {
    return DeviceSyncOutboxEntry(
      id: map['id'] as String,
      auditEntryId: map['audit_entry_id'] as String,
      targetDeviceId: map['target_device_id'] as String,
      encryptedPayload: map['encrypted_payload'] as String,
      signature: map['signature'] as String,
      state: map['state'] as String,
      retryCount: (map['retry_count'] as int?) ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      sentAt: map['sent_at'] != null
          ? DateTime.parse(map['sent_at'] as String).toLocal()
          : null,
    );
  }
}

class DeviceSyncOutboxDao {
  const DeviceSyncOutboxDao(this._db);

  final Database _db;
  static const _table = 'device_sync_outbox';

  Future<void> enqueue(DeviceSyncOutboxEntry entry) async {
    await _db.insert(
      _table,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<DeviceSyncOutboxEntry>> listPending() async {
    final rows = await _db.query(
      _table,
      where: 'state = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );
    return rows.map(DeviceSyncOutboxEntry.fromMap).toList();
  }

  Future<void> markSent(String id) async {
    await _db.update(
      _table,
      {'state': 'sent', 'sent_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Retains but quarantines a legacy payload so future syncs cannot send it.
  Future<void> markBlockedLegacy(String id) async {
    await _db.update(
      _table,
      {'state': 'blocked'},
      where: "id = ? AND state = 'pending'",
      whereArgs: [id],
    );
  }

  Future<void> incrementRetry(String id) async {
    await _db.rawUpdate(
      'UPDATE $_table SET retry_count = retry_count + 1 WHERE id = ?',
      [id],
    );
  }

  Future<void> purgeDelivered({int days = 7}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toUtc()
        .toIso8601String();
    await _db.delete(
      _table,
      where: 'state = ? AND sent_at IS NOT NULL AND sent_at < ?',
      whereArgs: ['sent', cutoff],
    );
  }
}
