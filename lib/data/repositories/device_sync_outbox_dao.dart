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
    this.eventType = defaultEventType,
  });

  static const defaultEventType = 'auditBatch';
  static const trustedEventTypes = <String>{
    defaultEventType,
    'posSale',
    'posPurchase',
    'posSalesReturn',
    'posPurchaseReturn',
    'posCollection',
  };

  static bool isValidEventType(String value) =>
      trustedEventTypes.contains(value);

  final String id;
  final String auditEntryId;
  final String targetDeviceId;
  final String encryptedPayload;
  final String signature;
  final String state;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? sentAt;
  final String eventType;

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
      'event_type': eventType,
    };
  }

  factory DeviceSyncOutboxEntry.fromMap(Map<String, Object?> map) {
    final eventType =
        (map['event_type'] as String?) ??
        DeviceSyncOutboxEntry.defaultEventType;
    if (!isValidEventType(eventType)) {
      throw ArgumentError.value(
        eventType,
        'eventType',
        'Unsupported event type',
      );
    }
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
      eventType: eventType,
    );
  }
}

class DeviceSyncOutboxDao {
  const DeviceSyncOutboxDao(this._db);

  final Database _db;
  static const _table = 'device_sync_outbox';

  Future<void> enqueue(DeviceSyncOutboxEntry entry) async {
    if (!DeviceSyncOutboxEntry.isValidEventType(entry.eventType)) {
      throw ArgumentError.value(
        entry.eventType,
        'eventType',
        'Unsupported event type',
      );
    }
    await _db.insert(
      _table,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> enqueueInTransaction(
    Transaction txn,
    DeviceSyncOutboxEntry entry,
  ) async {
    if (!DeviceSyncOutboxEntry.isValidEventType(entry.eventType)) {
      throw ArgumentError.value(
        entry.eventType,
        'eventType',
        'Unsupported event type',
      );
    }
    final inserted = await txn.insert(
      _table,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted != 0) return;
    final rows = await txn.query(
      _table,
      columns: ['audit_entry_id', 'target_device_id', 'event_type'],
      where: 'id = ?',
      whereArgs: [entry.id],
      limit: 1,
    );
    if (rows.isEmpty ||
        rows.single['audit_entry_id'] != entry.auditEntryId ||
        rows.single['target_device_id'] != entry.targetDeviceId ||
        rows.single['event_type'] != entry.eventType) {
      throw StateError('Device outbox id was reused for a different event.');
    }
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

  Future<void> markSentInTransaction(Transaction txn, String id) async {
    await txn.update(
      _table,
      {'state': 'sent', 'sent_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> hasPendingForAuditEntryInTransaction(
    Transaction txn,
    String auditEntryId,
  ) async {
    final rows = await txn.query(
      _table,
      columns: ['id'],
      where: "audit_entry_id = ? AND state = 'pending'",
      whereArgs: [auditEntryId],
      limit: 1,
    );
    return rows.isNotEmpty;
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
