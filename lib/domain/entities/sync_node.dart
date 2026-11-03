import 'package:flutter/foundation.dart';

enum SyncEventType {
  claim,
  acceptance,
  rejection,
  journalEntry,
  attachmentSync, // Blob reference + wrapped voucher key
  collateralSync, // Encrypted collateral data
  collateralUpdate, // Re-evaluation event
  withdrawal, // Voucher withdrawn by creator
  settlement, // Settlement linked via originVoucherId
  auditBatch, // Encrypted audit-log delta/snapshot payload
  credentialBootstrap, // Companion bootstrap credentials relay
  p2pHandshake, // P2P bidirectional sync handshake
  tripartiteRequest, // Sender -> Mediator Request (A -> B)
  posCreditInvoice, // Encrypted snapshot of an already-posted credit sale
  posCreditInvoiceAcknowledgment, // Non-financial accept/reject acknowledgment
  unknown;

  static SyncEventType fromString(String val) {
    return SyncEventType.values.firstWhere(
      (e) => e.name == val,
      orElse: () => SyncEventType.unknown,
    );
  }
}

/// Represents an encrypted sync event exchanged between two parties via the server.
///
/// §5.C — Flexible Routing: The receiver is identified by ANY of the following
/// routing headers (in order of preference). The server resolves the correct
/// target from these plaintext hints WITHOUT decrypting [encryptedPayload].
///
///   1. [receiverId]         — numeric server-side user ID (fastest, most precise)
///   2. [receiverPhone]      — E.164 phone number (e.g. "+967776026711")
///   3. [receiverWhatsapp]   — WhatsApp number if different from phone
///   4. [receiverPublicKey]  — Ed25519 public key hex (QR/offline discovery)
///
/// The [encryptedPayload] is strictly opaque: it must NEVER contain plaintext
/// identifiers that would bypass the privacy policy checks.
///
/// §5.D — Sender hints: Plaintext counterpart identity mirrored from receiver
/// routing hints. Populated server-side from the authenticated sender so inbound
/// clients can resolve UUID contacts before ECDH decryption.
@immutable
class SyncNode {
  const SyncNode({
    required this.id,
    required this.senderId,
    required this.eventType,
    required this.encryptedPayload,
    required this.syncState,
    // Routing headers — at least one must be present for server delivery
    this.receiverId,
    this.receiverPhone,
    this.receiverWhatsapp,
    this.receiverPublicKey,
    this.senderPhone,
    this.senderWhatsapp,
    this.senderPublicKey,
    this.clientTimestamp,
    this.senderDeviceId,
    this.targetDeviceId,
    this.socketSessionId,
    this.signature,
  });

  /// Unique client-generated UUID for this node (used for idempotency)
  final String id;

  /// Server-side user ID of the authenticated sender
  final int senderId;

  /// §5.C Routing hint 1: Direct server FK (preferred when known)
  final int? receiverId;

  /// §5.C Routing hint 2: E.164 phone number (plaintext routing)
  final String? receiverPhone;

  /// §5.C Routing hint 3: WhatsApp number (if different from phone)
  final String? receiverWhatsapp;

  /// §5.C Routing hint 4: Ed25519 public key hex (offline / QR discovery)
  final String? receiverPublicKey;

  /// §5.D Sender hint: E.164 phone (plaintext envelope symmetry)
  final String? senderPhone;

  /// §5.D Sender hint: WhatsApp number when distinct from phone
  final String? senderWhatsapp;

  /// §5.D Sender hint: Ed25519 public key hex registered for the sender
  final String? senderPublicKey;

  /// Strongly typed event discriminator
  final SyncEventType eventType;

  /// Opaque E2EE-encrypted blob — never contains plaintext identifiers
  final String encryptedPayload;

  /// Sync state: 'pending', 'delivered', 'read', 'pending_routing', 'unroutable'
  final String syncState;

  final DateTime? clientTimestamp;
  final String? senderDeviceId;
  final String? targetDeviceId;
  final String? socketSessionId;
  final String? signature;

  factory SyncNode.fromJson(Map<String, dynamic> json) {
    return SyncNode(
      id: json['id'] as String,
      senderId: (json['sender_id'] as num).toInt(),
      receiverId: json['receiver_id'] != null
          ? (json['receiver_id'] as num).toInt()
          : null,
      receiverPhone: json['receiver_phone'] as String?,
      receiverWhatsapp: json['receiver_whatsapp'] as String?,
      receiverPublicKey: json['receiver_public_key'] as String?,
      senderPhone: json['sender_phone'] as String?,
      senderWhatsapp: json['sender_whatsapp'] as String?,
      senderPublicKey: json['sender_public_key'] as String?,
      eventType: SyncEventType.fromString(json['event_type'] as String),
      encryptedPayload: json['encrypted_payload'] as String,
      syncState: json['sync_state'] as String,
      clientTimestamp: json['client_timestamp'] != null
          ? DateTime.tryParse(json['client_timestamp'])
          : null,
      senderDeviceId: json['sender_device_id'] as String?,
      targetDeviceId: json['target_device_id'] as String?,
      socketSessionId: json['socket_session_id'] as String?,
      signature: json['signature'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      if (receiverId != null) 'receiver_id': receiverId,
      if (receiverPhone != null) 'receiver_phone': receiverPhone,
      if (receiverWhatsapp != null) 'receiver_whatsapp': receiverWhatsapp,
      if (receiverPublicKey != null) 'receiver_public_key': receiverPublicKey,
      if (senderPhone != null) 'sender_phone': senderPhone,
      if (senderWhatsapp != null) 'sender_whatsapp': senderWhatsapp,
      if (senderPublicKey != null) 'sender_public_key': senderPublicKey,
      'event_type': eventType.name,
      'encrypted_payload': encryptedPayload,
      'sync_state': syncState,
      'client_timestamp': clientTimestamp?.toIso8601String(),
      if (senderDeviceId != null) 'sender_device_id': senderDeviceId,
      if (targetDeviceId != null) 'target_device_id': targetDeviceId,
      if (socketSessionId != null) 'socket_session_id': socketSessionId,
      if (signature != null) 'signature': signature,
    };
  }

  /// Returns true if this node has at least one valid routing hint.
  bool get hasRoutingHint =>
      receiverId != null ||
      (receiverPhone?.isNotEmpty ?? false) ||
      (receiverWhatsapp?.isNotEmpty ?? false) ||
      (receiverPublicKey?.isNotEmpty ?? false);
}
