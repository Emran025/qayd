import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Data model for an outbox entry.
///
/// §5.C — Flexible Routing: Routing headers are captured at enqueue time
/// (during identity discovery) and stored OUTSIDE the encrypted payload.
/// This allows [SyncCoordinatorService] to construct a [SyncNode] with all
/// routing hints without re-running the discovery process.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.eventType,
    this.voucherId,
    required this.counterpartyAccountId,
    required this.encryptedPayload,
    required this.state,
    this.transport,
    required this.retryCount,
    required this.createdAt,
    this.deliveredAt,
    // §5.C Routing headers
    this.receiverPhone,
    this.receiverWhatsapp,
    this.receiverPublicKey,
    this.receiverServerId,
  });

  final String id;
  final String eventType;
  final String? voucherId;

  /// Local account UUID (may be a phone number or local UUID, not a server ID)
  final String counterpartyAccountId;
  final String encryptedPayload;
  final String state; // 'pending', 'delivered', 'failed'
  final String? transport; // 'server', 'p2p'
  final int retryCount;
  final DateTime createdAt;
  final DateTime? deliveredAt;

  // ── §5.C Routing headers (plaintext, captured during identity discovery) ──

  /// E.164 phone number (primary routing hint)
  final String? receiverPhone;

  /// WhatsApp number if different from [receiverPhone]
  final String? receiverWhatsapp;

  /// Ed25519 public key hex (discovered via server or QR)
  final String? receiverPublicKey;

  /// Numeric server user ID (when known — fastest routing path)
  final int? receiverServerId;

  Map<String, Object?> toMap() => {
    'id': id,
    'event_type': eventType,
    'voucher_id': voucherId,
    'counterparty_account_id': counterpartyAccountId,
    'encrypted_payload': encryptedPayload,
    'state': state,
    'transport': transport,
    'retry_count': retryCount,
    'created_at': createdAt.toIso8601String(),
    'delivered_at': deliveredAt?.toIso8601String(),
    'receiver_phone': receiverPhone,
    'receiver_whatsapp': receiverWhatsapp,
    'receiver_public_key': receiverPublicKey,
    'receiver_server_id': receiverServerId,
  };

  factory OutboxEntry.fromMap(Map<String, Object?> map) {
    return OutboxEntry(
      id: map['id']! as String,
      eventType: map['event_type']! as String,
      voucherId: map['voucher_id'] as String?,
      counterpartyAccountId: map['counterparty_account_id']! as String,
      encryptedPayload: map['encrypted_payload']! as String,
      state: map['state']! as String,
      transport: map['transport'] as String?,
      retryCount: (map['retry_count'] as int?) ?? 0,
      createdAt: DateTime.parse(map['created_at']! as String),
      deliveredAt: map['delivered_at'] != null
          ? DateTime.parse(map['delivered_at']! as String)
          : null,
      receiverPhone: map['receiver_phone'] as String?,
      receiverWhatsapp: map['receiver_whatsapp'] as String?,
      receiverPublicKey: map['receiver_public_key'] as String?,
      receiverServerId: map['receiver_server_id'] as int?,
    );
  }

  OutboxEntry copyWith({
    String? receiverPhone,
    String? receiverWhatsapp,
    String? receiverPublicKey,
    int? receiverServerId,
  }) {
    return OutboxEntry(
      id: id,
      eventType: eventType,
      voucherId: voucherId,
      counterpartyAccountId: counterpartyAccountId,
      encryptedPayload: encryptedPayload,
      state: state,
      transport: transport,
      retryCount: retryCount,
      createdAt: createdAt,
      deliveredAt: deliveredAt,
      receiverPhone: receiverPhone ?? this.receiverPhone,
      receiverWhatsapp: receiverWhatsapp ?? this.receiverWhatsapp,
      receiverPublicKey: receiverPublicKey ?? this.receiverPublicKey,
      receiverServerId: receiverServerId ?? this.receiverServerId,
    );
  }
}

/// Local Outbox DAO — persists mutations until acknowledged by server or P2P peer.
///
/// Protocol §5.A: Every voucher creation, state transition, signature attachment,
/// or metadata mutation is appended here before any network operation is attempted.
class OutboxDao {
  const OutboxDao(this._db);

  final Database _db;
  static const _table = 'outbox';

  /// Enqueue a new mutation into the outbox.
  Future<Result<void>> enqueue(OutboxEntry entry) async {
    try {
      await _db.insert(
        _table,
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return Success(null);
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.theEntryCouldNot),
      );
    }
  }

  /// Fetch all pending outbox entries (for flush on reconnection).
  Future<Result<List<OutboxEntry>>> listPending() async {
    try {
      final rows = await _db.query(
        _table,
        where: "state = ?",
        whereArgs: ['pending'],
        orderBy: 'created_at ASC',
      );
      return Success(rows.map(OutboxEntry.fromMap).toList());
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.theOutboxCouldNot),
      );
    }
  }

  /// Fetch pending entries for a specific counterparty (for P2P context-scoped sync).
  Future<Result<List<OutboxEntry>>> listPendingForCounterparty(
    String counterpartyAccountId,
  ) async {
    try {
      final rows = await _db.query(
        _table,
        where: "state = ? AND counterparty_account_id = ?",
        whereArgs: ['pending', counterpartyAccountId],
        orderBy: 'created_at ASC',
      );
      return Success(rows.map(OutboxEntry.fromMap).toList());
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.thePartysOutboxCould),
      );
    }
  }

  /// Mark entries as delivered after receiving acknowledgment.
  Future<Result<void>> markDelivered(
    List<String> ids, {
    String transport = 'server',
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      for (final id in ids) {
        await _db.update(
          _table,
          {'state': 'delivered', 'transport': transport, 'delivered_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      return Success(null);
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.unableToUpdateDelivery),
      );
    }
  }

  /// Quarantines an entry whose payload predates authenticated encryption.
  /// The row and payload are retained for recovery/audit; it is no longer
  /// returned by [listPending] and cannot be transmitted by the app.
  Future<void> markBlockedLegacy(String id) async {
    await _db.update(
      _table,
      {'state': 'failed', 'transport': 'blocked_legacy_payload'},
      where: "id = ? AND state = 'pending'",
      whereArgs: [id],
    );
  }

  /// Increment retry count for failed delivery attempts.
  Future<void> incrementRetry(String id) async {
    await _db.rawUpdate(
      'UPDATE $_table SET retry_count = retry_count + 1 WHERE id = ?',
      [id],
    );
  }

  /// Checks if an entry for this voucher and event type already exists.
  Future<bool> exists(String voucherId, String eventType) async {
    final rows = await _db.query(
      _table,
      where: 'voucher_id = ? AND event_type = ?',
      whereArgs: [voucherId, eventType],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Purge delivered entries older than [days] from the outbox.
  Future<void> purgeDelivered({int days = 30}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String();
    await _db.delete(
      _table,
      where: "state = 'delivered' AND delivered_at < ?",
      whereArgs: [cutoff],
    );
  }
}
