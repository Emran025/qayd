import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/notification_message.dart';

abstract class NotificationMessageRepository {
  Future<Result<void>> insert({
    required String id,
    required String bodyText,
    String? channel,
    required String counterpartyAccountId,
    required String createdAtIso,
    String? rawPayloadJson,
  });

  Future<Result<List<NotificationMessage>>> listUnprocessedForCounterparty({
    required String counterpartyAccountId,
    int limit,
  });

  /// Returns durable chat records for selected channels, including processed
  /// rows, so reading an invoice notification never removes it from history.
  Future<Result<List<NotificationMessage>>> listForCounterpartyChannels({
    required String counterpartyAccountId,
    required List<String> channels,
    int limit,
  });

  Future<Result<List<NotificationMessage>>> listAllUnprocessed({int limit});

  Future<Result<void>> markProcessed(String id);

  /// Returns all unprocessed records staged by the consent-based onboarding
  /// flow (channel = 'counterparty_request').
  Future<Result<List<NotificationMessage>>> listPendingCounterpartyRequests();

  /// Finds a single notification by its [id], or returns null if not found.
  Future<NotificationMessage?> findById(String id);

  /// Updates the display text and raw payload of an existing record.
  ///
  /// Used to backfill the sender name on records that were staged before the
  /// name could be resolved (e.g. offline at staging time).
  Future<Result<void>> updateBodyAndPayload({
    required String id,
    required String bodyText,
    required String rawPayloadJson,
  });

  /// Updates the record only if [expectedRawPayloadJson] is still current.
  /// Returns `false` when another writer changed the protocol state first.
  Future<Result<bool>> updateBodyAndPayloadIfUnchanged({
    required String id,
    required String expectedRawPayloadJson,
    required String bodyText,
    required String rawPayloadJson,
  });
}
