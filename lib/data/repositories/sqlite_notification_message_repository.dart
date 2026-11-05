import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/notification_message.dart';
import 'package:qayd/domain/repositories/notification_message_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class SqliteNotificationMessageRepository
    implements NotificationMessageRepository {
  SqliteNotificationMessageRepository(this._db);

  final Database _db;

  static const _table = 'notification_messages';

  @override
  Future<Result<void>> insert({
    required String id,
    required String bodyText,
    String? channel,
    required String counterpartyAccountId,
    required String createdAtIso,
    String? rawPayloadJson,
  }) async {
    try {
      await _db.insert(_table, {
        'id': id,
        'body_text': bodyText,
        'channel': channel,
        'context_kind': 'counterparty',
        'context_ref': counterpartyAccountId,
        'created_at': createdAtIso,
        'raw_payload_json': rawPayloadJson,
        'counterparty_account_id': counterpartyAccountId,
        'processed': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return Success(null);
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.unableToSaveNotification),
      );
    }
  }

  @override
  Future<NotificationMessage?> findById(String id) async {
    try {
      final rows = await _db.query(
        _table,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final r = rows.first;
      final created = r['created_at'] as String?;
      if (created == null) return null;
      return NotificationMessage(
        id: r['id'] as String,
        bodyText: r['body_text'] as String,
        channel: r['channel'] as String?,
        counterpartyAccountId: r['counterparty_account_id'] as String? ?? '',
        createdAt: DateTime.parse(created),
        processed: (r['processed'] as int? ?? 0) != 0,
        rawPayloadJson: r['raw_payload_json'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Result<void>> updateBodyAndPayload({
    required String id,
    required String bodyText,
    required String rawPayloadJson,
  }) async {
    try {
      await _db.update(
        _table,
        {'body_text': bodyText, 'raw_payload_json': rawPayloadJson},
        where: 'id = ?',
        whereArgs: [id],
      );
      return Success(null);
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.unableToUpdateNotification),
      );
    }
  }

  @override
  Future<Result<bool>> updateBodyAndPayloadIfUnchanged({
    required String id,
    required String expectedRawPayloadJson,
    required String bodyText,
    required String rawPayloadJson,
  }) async {
    try {
      final updated = await _db.update(
        _table,
        {'body_text': bodyText, 'raw_payload_json': rawPayloadJson},
        where: 'id = ? AND raw_payload_json IS ?',
        whereArgs: [id, expectedRawPayloadJson],
      );
      return Success(updated == 1);
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.unableToUpdateNotification),
      );
    }
  }

  @override
  Future<Result<List<NotificationMessage>>> listUnprocessedForCounterparty({
    required String counterpartyAccountId,
    int limit = 50,
  }) async {
    try {
      final rows = await _db.query(
        _table,
        where: 'counterparty_account_id = ? AND processed = 0',
        whereArgs: [counterpartyAccountId],
        orderBy: 'created_at DESC',
        limit: limit,
      );
      final out = <NotificationMessage>[];
      for (final r in rows) {
        final cp = r['counterparty_account_id'] as String?;
        if (cp == null || cp.isEmpty) continue;
        final created = r['created_at'] as String?;
        if (created == null) continue;
        out.add(
          NotificationMessage(
            id: r['id'] as String,
            bodyText: r['body_text'] as String,
            channel: r['channel'] as String?,
            counterpartyAccountId: cp,
            createdAt: DateTime.parse(created),
            processed: (r['processed'] as int? ?? 0) != 0,
            rawPayloadJson: r['raw_payload_json'] as String?,
          ),
        );
      }
      return Success(out);
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.unableToLoadNotification),
      );
    }
  }

  @override
  Future<Result<List<NotificationMessage>>> listForCounterpartyChannels({
    required String counterpartyAccountId,
    required List<String> channels,
    int limit = 500,
  }) async {
    if (channels.isEmpty) return const Success([]);
    try {
      final placeholders = List.filled(channels.length, '?').join(',');
      final rows = await _db.query(
        _table,
        where: 'counterparty_account_id = ? AND channel IN ($placeholders)',
        whereArgs: [counterpartyAccountId, ...channels],
        orderBy: 'created_at ASC',
        limit: limit,
      );
      final out = <NotificationMessage>[];
      for (final row in rows) {
        final created = row['created_at'] as String?;
        final cp = row['counterparty_account_id'] as String?;
        if (created == null || cp == null || cp.isEmpty) continue;
        out.add(
          NotificationMessage(
            id: row['id'] as String,
            bodyText: row['body_text'] as String,
            channel: row['channel'] as String?,
            counterpartyAccountId: cp,
            createdAt: DateTime.parse(created),
            processed: (row['processed'] as int? ?? 0) != 0,
            rawPayloadJson: row['raw_payload_json'] as String?,
          ),
        );
      }
      return Success(out);
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.unableToLoadNotification),
      );
    }
  }

  @override
  Future<Result<List<NotificationMessage>>> listAllUnprocessed({
    int limit = 100,
  }) async {
    try {
      final rows = await _db.query(
        _table,
        where: 'processed = 0',
        orderBy: 'created_at DESC',
        limit: limit,
      );
      final out = <NotificationMessage>[];
      for (final r in rows) {
        final cp = r['counterparty_account_id'] as String? ?? '';
        final created = r['created_at'] as String?;
        if (created == null) continue;
        out.add(
          NotificationMessage(
            id: r['id'] as String,
            bodyText: r['body_text'] as String,
            channel: r['channel'] as String?,
            counterpartyAccountId: cp,
            createdAt: DateTime.parse(created),
            processed: (r['processed'] as int? ?? 0) != 0,
            rawPayloadJson: r['raw_payload_json'] as String?,
          ),
        );
      }
      return Success(out);
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.unableToLoadInbox),
      );
    }
  }

  @override
  Future<Result<List<NotificationMessage>>>
  listPendingCounterpartyRequests() async {
    try {
      final rows = await _db.query(
        _table,
        where: "channel = 'counterparty_request' AND processed = 0",
        orderBy: 'created_at ASC',
      );
      final out = <NotificationMessage>[];
      for (final r in rows) {
        final created = r['created_at'] as String?;
        if (created == null) continue;
        out.add(
          NotificationMessage(
            id: r['id'] as String,
            bodyText: r['body_text'] as String,
            channel: r['channel'] as String?,
            counterpartyAccountId:
                r['counterparty_account_id'] as String? ?? '',
            createdAt: DateTime.parse(created),
            processed: (r['processed'] as int? ?? 0) != 0,
            rawPayloadJson: r['raw_payload_json'] as String?,
          ),
        );
      }
      return Success(out);
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.unableToLoadNotification),
      );
    }
  }

  @override
  Future<Result<void>> markProcessed(String id) async {
    try {
      final n = await _db.update(
        _table,
        {'processed': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (n == 0) {
        return FailureResult(
          DatabaseFailure(messageAr: AppStrings.notificationRecordNotFound),
        );
      }
      return Success(null);
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.unableToUpdateNotification),
      );
    }
  }
}
