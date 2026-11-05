/// Processing states for an inbound encrypted sync event.
enum SyncInboundEventClaim {
  /// This caller may validate and handle the event.
  claimed,

  /// This exact event was already applied and may be acknowledged idempotently.
  alreadyApplied,

  /// Another caller is handling this exact event; do not apply or acknowledge.
  inProgress,

  /// The event is retained for review and must not be acknowledged as applied.
  quarantined,

  /// The same node ID was seen with different authenticated content.
  conflictingPayload,
}

/// Safe, non-payload reasons for retaining an inbound encrypted event.
enum SyncInboundQuarantineReason {
  unknownSender,
  unauthorizedSenderKey,
  decryptionFailed,
  unsupportedEventType,
  delegatedEvent,
  conflictingPayload,
  processingInterrupted,
  handlerFailed,
  invalidPayload,
  handlerRejected,
}

/// Ciphertext-only record available to future local review/recovery flows.
/// [encryptedPayload] can be absent for an ambiguous v50 row created before
/// the journal began persisting the envelope at claim time.
final class SyncInboundQuarantinedEvent {
  const SyncInboundQuarantinedEvent({
    required this.nodeId,
    required this.eventType,
    required this.payloadFingerprint,
    required this.encryptedPayload,
    required this.reason,
    required this.createdAt,
    this.conflictingPayloadFingerprint,
    this.conflictingEncryptedPayload,
    this.conflictCount = 0,
  });

  final String nodeId;
  final String eventType;
  final String payloadFingerprint;
  final String? encryptedPayload;
  final SyncInboundQuarantineReason reason;
  final DateTime createdAt;
  final String? conflictingPayloadFingerprint;
  final String? conflictingEncryptedPayload;
  final int conflictCount;
}

/// Durable local processing journal for encrypted inbound sync events.
///
/// Implementations must persist ciphertext only. Plaintext payloads, amounts,
/// party names, and attachment contents must never enter this journal.
abstract interface class SyncInboundEventJournalRepository {
  Future<SyncInboundEventClaim> beginProcessing({
    required String nodeId,
    required String? senderPublicKey,
    required String eventType,
    required String payloadFingerprint,
    required String encryptedPayload,
  });

  Future<void> markApplied(String nodeId);

  Future<void> returnToPending(String nodeId);

  Future<void> quarantine({
    required String nodeId,
    required SyncInboundQuarantineReason reason,
    required String encryptedPayload,
  });

  Future<List<SyncInboundQuarantinedEvent>> listQuarantined({int limit = 100});
}
