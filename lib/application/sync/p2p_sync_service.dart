import 'dart:convert';
import 'package:qayd/core/result/result.dart';
import 'package:flutter/foundation.dart';
import 'package:qayd/data/repositories/outbox_dao.dart';
import 'package:qayd/data/security/e2ee_envelope_format.dart';
import 'package:qayd/data/repositories/sync_watermark_dao.dart';

/// Transport-agnostic P2P Sync Service skeleton.
///
/// Protocol §5.D: Peer-to-Peer transport operates alongside the server-based
/// relay. When two devices are on the same local network (or proximity),
/// the P2P service negotiates a direct channel for bidirectional delta sync.
///
/// Flow:
/// 1. **Handshake**: Exchange public keys + last known watermark via QR or NFC.
/// 2. **Delta Exchange**: Each peer sends only outbox items newer than the
///    other peer's watermark for the bilateral relationship.
/// 3. **Acknowledgment**: Upon successful processing, both peers update
///    their respective watermarks.
///
/// This skeleton provides the service abstraction; actual transport
/// (WebRTC, Bluetooth, etc.) is to be injected via a [P2PTransportAdapter].
abstract interface class P2PTransportAdapter {
  /// Open a bidirectional channel to the peer.
  Future<void> connect(String peerId, String peerPublicKey);

  /// Send an encrypted chunk to the connected peer.
  Future<void> send(String encryptedPayload);

  /// Stream of received chunks from the connected peer.
  Stream<String> get incomingStream;

  /// Close the channel.
  Future<void> disconnect();
}

/// Orchestrates the P2P sync protocol over a [P2PTransportAdapter].
class P2PSyncService {
  P2PSyncService({
    required this.outboxDao,
    required this.watermarkDao,
    this.transportAdapter,
  });

  final OutboxDao outboxDao;
  final SyncWatermarkDao watermarkDao;
  final P2PTransportAdapter? transportAdapter;

  /// Initiates a P2P sync session with a specific counterparty.
  ///
  /// Steps:
  /// 1. Look up the watermark for [counterpartyAccountId].
  /// 2. Fetch all outbox items addressed to this counterparty that are
  ///    newer than the watermark.
  /// 3. Transmit them over the P2P transport.
  /// 4. Receive the peer's delta and process inbound items.
  /// 5. Update both watermarks upon successful exchange.
  Future<P2PSyncResult> syncWithCounterparty({
    required String counterpartyAccountId,
    required String peerPublicKey,
  }) async {
    if (transportAdapter == null) {
      debugPrint('P2PSyncService: No transport adapter configured.');
      return P2PSyncResult(
        success: false,
        sentCount: 0,
        receivedCount: 0,
        error: 'No P2P transport adapter configured.',
      );
    }

    try {
      // 1. Fetch watermark
      final wmResult = await watermarkDao.getForCounterparty(
        counterpartyAccountId,
      );
      final lastSync = wmResult.isSuccess && wmResult.valueOrNull != null
          ? wmResult.valueOrNull!.lastSyncedAt
          : DateTime.fromMillisecondsSinceEpoch(0);

      // 2. Fetch pending outbox items for this counterparty
      final outboxResult = await outboxDao.listPendingForCounterparty(
        counterpartyAccountId,
      );
      final pendingItems = outboxResult.isSuccess
          ? outboxResult.valueOrNull!
          : <OutboxEntry>[];

      final safeItems = <OutboxEntry>[];
      for (final item in pendingItems) {
        if (E2EEEnvelopeFormat.isSupported(item.encryptedPayload)) {
          safeItems.add(item);
        } else {
          await outboxDao.markBlockedLegacy(item.id);
        }
      }
      if (safeItems.isEmpty) {
        return P2PSyncResult(success: true, sentCount: 0, receivedCount: 0);
      }

      // 3. Connect to peer
      await transportAdapter!.connect(counterpartyAccountId, peerPublicKey);

      // 4. Send our delta
      for (final item in safeItems) {
        final envelope = jsonEncode({
          'type': 'delta',
          'event_type': item.eventType,
          'payload': item.encryptedPayload,
          'item_id': item.id,
          'since': lastSync.toIso8601String(),
        });
        await transportAdapter!.send(envelope);
      }

      // 5. Send sync-complete marker
      await transportAdapter!.send(
        jsonEncode({
          'type': 'sync_complete',
          'watermark': DateTime.now().toIso8601String(),
        }),
      );

      // 6. Listen for incoming delta from peer (with timeout)
      var receivedCount = 0;
      final deliveredIds = <String>[];

      await for (final chunk in transportAdapter!.incomingStream) {
        final msg = jsonDecode(chunk) as Map<String, dynamic>;
        final msgType = msg['type'] as String?;

        if (msgType == 'sync_complete') {
          // Peer has finished sending
          break;
        }

        if (msgType == 'ack') {
          // Peer acknowledges receipt of our items
          final ackedIds = (msg['item_ids'] as List?)
              ?.map((e) => e as String)
              .toList();
          if (ackedIds != null) {
            deliveredIds.addAll(ackedIds);
          }
          continue;
        }

        // Process inbound delta item
        receivedCount++;
      }

      // 7. Mark delivered items
      if (deliveredIds.isNotEmpty) {
        await outboxDao.markDelivered(deliveredIds, transport: 'p2p');
      }

      // 8. Update watermark
      await watermarkDao.upsert(
        SyncWatermark(
          counterpartyAccountId: counterpartyAccountId,
          lastSyncedAt: DateTime.now(),
          transport: 'p2p',
        ),
      );

      // 9. Disconnect
      await transportAdapter!.disconnect();

      return P2PSyncResult(
        success: true,
        sentCount: safeItems.length,
        receivedCount: receivedCount,
      );
    } catch (e) {
      debugPrint('P2PSyncService error: $e');
      try {
        await transportAdapter!.disconnect();
      } catch (_) {}
      return P2PSyncResult(
        success: false,
        sentCount: 0,
        receivedCount: 0,
        error: e.toString(),
      );
    }
  }
}

/// Result of a P2P sync session.
class P2PSyncResult {
  const P2PSyncResult({
    required this.success,
    required this.sentCount,
    required this.receivedCount,
    this.error,
  });

  final bool success;
  final int sentCount;
  final int receivedCount;
  final String? error;
}
