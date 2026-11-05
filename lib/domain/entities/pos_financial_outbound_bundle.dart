import 'package:qayd/domain/entities/pos_financial_sync_event.dart';

/// A per-device E2EE transport envelope prepared before the accounting write.
final class PosFinancialOutboundDelivery {
  const PosFinancialOutboundDelivery({
    required this.nodeId,
    required this.eventType,
    required this.targetDeviceId,
    required this.encryptedPayload,
    required this.signature,
    required this.createdAt,
  });

  final String nodeId;
  final String eventType;
  final String targetDeviceId;
  final String encryptedPayload;
  final String signature;
  final DateTime createdAt;
}

/// E2EE event plus all target-specific envelopes, committed with the posting.
final class PosFinancialOutboundBundle {
  PosFinancialOutboundBundle({
    required this.event,
    required this.localEncryptedPayload,
    required List<PosFinancialOutboundDelivery> deliveries,
  }) : deliveries = List.unmodifiable(deliveries);

  /// Event copy targeted to the sending device; used only for durable local
  /// recovery in the SQLCipher-backed financial outbox.
  final PosFinancialSyncEvent event;
  final String localEncryptedPayload;
  final List<PosFinancialOutboundDelivery> deliveries;
}
