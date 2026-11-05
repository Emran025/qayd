import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:qayd/domain/entities/sync_node.dart';
import 'package:qayd/domain/repositories/sync_repository.dart';
import 'package:qayd/data/network/sync_socket_service.dart';
import 'package:qayd/application/sync/sync_payload_processor.dart';
import 'package:qayd/domain/services/native_notification_service.dart';
import 'package:qayd/domain/services/notification_filter_service.dart';
import 'package:qayd/domain/repositories/notification_message_repository.dart';
import 'package:qayd/application/notifications/collateral_expiry_checker.dart';
import 'package:qayd/data/repositories/outbox_dao.dart';
import 'package:qayd/data/repositories/device_sync_outbox_dao.dart';
import 'package:qayd/data/repositories/pos_financial_event_store.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/repositories/sync_watermark_dao.dart';
import 'package:qayd/data/security/e2ee_envelope_format.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/domain/value_objects/voucher_state.dart';
import 'package:qayd/domain/value_objects/voucher_query_filter.dart';
import 'package:qayd/domain/value_objects/date_range.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/core/result/result.dart';

/// Manages multi-tiered polling and live WS connection for Real-Time Synchronization.
/// Uses [SyncRepository], [SyncSocketService], and [SyncPayloadProcessor]
/// for instantaneous two-way cryptographic verification and local database ingestion.
class SyncCoordinatorService {
  SyncCoordinatorService({
    required this.syncRepository,
    required this.socketService,
    required this.payloadProcessor,
    required this.nativeNotificationService,
    required this.notificationFilterService,
    required this.notificationMessageRepository,
    required this.outboxDao,
    required this.deviceSyncOutboxDao,
    required this.watermarkDao,
    required this.currentUserId,
    required this.voucherRepository,
    required this.syncEventDispatcher,
    required this.currentDeviceId,
    this.transactionRunner,
    this.posFinancialEventStore,
    this.collateralExpiryChecker,
    this.syncInterval = const Duration(minutes: 10),
  });

  final SyncRepository syncRepository;
  final SyncSocketService socketService;
  final SyncPayloadProcessor payloadProcessor;
  final NativeNotificationService nativeNotificationService;
  final NotificationFilterService notificationFilterService;
  final NotificationMessageRepository notificationMessageRepository;
  final OutboxDao outboxDao;
  final DeviceSyncOutboxDao deviceSyncOutboxDao;
  final SyncWatermarkDao watermarkDao;
  final int currentUserId;
  final VoucherRepository voucherRepository;
  final SyncEventDispatcher syncEventDispatcher;
  final String currentDeviceId;
  final DatabaseTransactionRunner? transactionRunner;
  final PosFinancialEventStore? posFinancialEventStore;
  final CollateralExpiryChecker? collateralExpiryChecker;
  final Duration syncInterval;

  Timer? _periodicTimer;
  Timer? _expiryTimer;
  StreamSubscription? _socketSubscription;

  final _syncUpdateController = StreamController<void>.broadcast();
  Stream<void> get onSyncUpdate => _syncUpdateController.stream;

  // Background queue state for lookups
  bool _isProcessingQueue = false;
  bool _hasPendingPull = false;

  /// Whether the coordinator is currently active.
  bool get isRunning => _periodicTimer != null || _socketSubscription != null;

  /// Initiate the synchronization lifecycle
  void start() {
    // 1. Instantly enqueue task to fetch any missed nodes while disconnected
    triggerSync();

    // 2. Connect the active WebSocket listener
    socketService.connect(currentUserId);
    _socketSubscription = socketService.incomingNodes.listen((node) async {
      if (node.targetDeviceId != null &&
          node.targetDeviceId != currentDeviceId) {
        return;
      }
      // Pass the encrypted wrapper into the Crypto Engine for authentication/decryption
      final appliedIds = await payloadProcessor.processIncomingNodes([node]);

      // Only acknowledge nodes that were actually decrypted and applied locally.
      // Otherwise the server may delete device-scoped audit batches (see acknowledge())
      // while the companion never persisted business data.
      if (appliedIds.contains(node.id)) {
        await _acknowledge([node.id], 'delivered');
        _syncUpdateController.add(null);
      }

      // Trigger Native Notification and persist to inbox if it's an important event
      // AND user has not disabled peer activity notifications.
      if (node.eventType == SyncEventType.claim) {
        if (notificationFilterService.isPeerActivityEnabled) {
          await nativeNotificationService.showImportantNotification(
            title: AppStrings.syncClaimTitle,
            body: AppStrings.syncClaimBody,
            payload: 'voucher_chat:${node.senderId}',
          );
          await notificationMessageRepository.insert(
            id: node.id,
            bodyText: AppStrings.syncClaimBody,
            counterpartyAccountId: node.senderId.toString(),
            createdAtIso: DateTime.now().toIso8601String(),
            channel: 'server',
          );
        }
      } else if (node.eventType == SyncEventType.acceptance) {
        if (notificationFilterService.isSelfActivityEnabled) {
          await nativeNotificationService.showLocalNotification(
            title: AppStrings.approved,
            body: AppStrings.yourBondHasBeen,
            payload: 'voucher_chat:${node.senderId}',
          );
          await notificationMessageRepository.insert(
            id: node.id,
            bodyText:
                'تم اعتماد سند الصرف الخاص بك (#${node.id.substring(0, 4)}).',
            counterpartyAccountId: node.senderId.toString(),
            createdAtIso: DateTime.now().toIso8601String(),
            channel: 'server',
          );
        }
      }
    });

    // 3. Periodic safe polling (for extreme resilience)
    _periodicTimer = Timer.periodic(syncInterval, (_) => triggerSync());

    // 4. Schedule collateral expiry checks (every 6 hours)
    if (collateralExpiryChecker != null) {
      // Immediate first check
      collateralExpiryChecker!.checkAndNotify();
      _expiryTimer = Timer.periodic(
        const Duration(hours: 6),
        (_) => collateralExpiryChecker!.checkAndNotify(),
      );
    }
  }

  /// Stop sync lifecycle (e.g. app goes completely dormant or user logs out)
  void stop() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _socketSubscription?.cancel();
    _socketSubscription = null;
    // closeStreams: true — fully disposes the service on logout.
    // On app pause, call stop() without this flag and reconnect on resume.
    socketService.disconnect(closeStreams: true);
  }

  /// Manually requested pull-to-refresh / On-Enter Sync
  Future<void> forceSync() async {
    triggerSync();
  }

  /// Triggers a lookup operation in the background queue.
  void triggerSync() {
    _hasPendingPull = true;
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_hasPendingPull) {
        _hasPendingPull = false;
        await _catchUpSync();
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  /// Delta fetch capturing any encrypted nodes missed while socket disconnected
  Future<void> _catchUpSync() async {
    try {
      // 1. Attempt to discover identities and enqueue vouchers that failed initial sync
      await _reSyncUnsyncedVouchers();

      // 2. Flush local outbox to server
      await _flushOutbox();
      await _flushDeviceSyncOutbox();

      // 2. Fetch server-side watermark or last sync time
      // Using a generic 'server' watermark here:
      final wmResult = await watermarkDao.getForCounterparty('server_global');
      final lastSync = wmResult.isSuccess && wmResult.valueOrNull != null
          ? wmResult.valueOrNull!.lastSyncedAt.toIso8601String()
          : null;

      // 3. Pull new nodes since last watermark
      final nodes = await syncRepository.pullNodes(since: lastSync);
      final targetNodes = nodes
          .where(
            (n) =>
                n.targetDeviceId == null || n.targetDeviceId == currentDeviceId,
          )
          .toList();
      if (targetNodes.isNotEmpty) {
        // Feed caught-up nodes firmly into local verification pipelines
        final appliedIds = await payloadProcessor.processIncomingNodes(
          targetNodes,
        );

        if (appliedIds.isNotEmpty) {
          await _acknowledge(appliedIds.toList(), 'delivered');
          _syncUpdateController.add(null);
        }
      }
    } catch (e) {
      debugPrint('Sync: ❌ Catch-Up error: $e');
    }
  }

  Future<void> _flushDeviceSyncOutbox() async {
    final pending = await deviceSyncOutboxDao.listPending();
    if (pending.isEmpty) return;

    for (final entry in pending) {
      try {
        if (!E2EEEnvelopeFormat.isSupported(entry.encryptedPayload)) {
          await deviceSyncOutboxDao.markBlockedLegacy(entry.id);
          debugPrint(
            'Sync: blocked legacy device payload ${entry.id}; local data retained.',
          );
          continue;
        }
        final node = SyncNode(
          id: entry.id,
          senderId: currentUserId,
          receiverId: currentUserId,
          receiverPublicKey: null,
          eventType: SyncEventType.fromString(entry.eventType),
          encryptedPayload: entry.encryptedPayload,
          syncState: 'pending',
          clientTimestamp: entry.createdAt,
          senderDeviceId: currentDeviceId,
          targetDeviceId: entry.targetDeviceId,
          signature: entry.signature,
        );
        await syncRepository.pushNode(node);
        final runner = transactionRunner;
        final financialEventStore = posFinancialEventStore;
        if (runner == null || financialEventStore == null) {
          await deviceSyncOutboxDao.markSent(entry.id);
        } else {
          await runner.run<void>((txn) async {
            await deviceSyncOutboxDao.markSentInTransaction(txn, entry.id);
            final hasPending = await deviceSyncOutboxDao
                .hasPendingForAuditEntryInTransaction(txn, entry.auditEntryId);
            if (!hasPending) {
              await financialEventStore.markOutboundDeliveredInTransaction(
                txn,
                entry.auditEntryId,
              );
            }
          });
        }
      } catch (_) {
        await deviceSyncOutboxDao.incrementRetry(entry.id);
      }
    }

    await deviceSyncOutboxDao.purgeDelivered(days: 7);
  }

  /// Scans for confirmed vouchers that were never enqueued to the outbox
  /// (usually due to a missing public key during creation).
  ///
  /// §P-3: Bounded to the last 7 days to avoid O(n) full-history scans.
  /// Older unsynced vouchers are assumed delivered or abandoned.
  Future<void> _reSyncUnsyncedVouchers() async {
    try {
      debugPrint('Sync: 🔍 Scanning recent unsynced vouchers...');

      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final filter = VoucherQueryFilter(
        state: VoucherState.confirmed,
        dateRange: DateRange(
          start: cutoff,
          end: DateTime.now().add(const Duration(days: 1)),
        ),
      );
      final vouchersRes = await voucherRepository.getAll(filter: filter);
      if (vouchersRes.isFailure) return;

      final vouchers = vouchersRes.valueOrNull ?? [];
      if (vouchers.isEmpty) {
        debugPrint('Sync: ✅ No recent unsynced vouchers found.');
        return;
      }

      for (final voucher in vouchers) {
        final exists = await outboxDao.exists(voucher.id.value, 'claim');
        if (!exists) {
          debugPrint('Sync: ♻️ Re-queuing voucher ${voucher.id.value}');
          await syncEventDispatcher.dispatchVoucherClaim(voucher);
        }
      }
    } catch (e) {
      debugPrint('Sync: ❌ Unsynced scan error: $e');
    }
  }

  Future<void> _acknowledge(List<String> nodeIds, String state) async {
    try {
      await syncRepository.acknowledgeNodes(nodeIds, state);
    } catch (e) {
      debugPrint('Sync: ❌ Acknowledge error: $e');
    }
  }

  /// Flushes pending entries in the Local Change Queue (Outbox) to the central server.
  ///
  /// §5.C — Flexible Routing: Constructs the SyncNode with all available routing
  /// hints captured during identity discovery. The server resolves the receiver
  /// from these hints without decrypting the payload.
  Future<void> _flushOutbox() async {
    final pendingResult = await outboxDao.listPending();
    if (pendingResult.isFailure) return;

    final entries = pendingResult.valueOrNull ?? [];
    if (entries.isEmpty) return;

    final deliveredIds = <String>[];
    for (final entry in entries) {
      try {
        if (!E2EEEnvelopeFormat.isSupported(entry.encryptedPayload)) {
          await outboxDao.markBlockedLegacy(entry.id);
          debugPrint(
            'Sync: blocked legacy outbox payload ${entry.id}; local data retained.',
          );
          continue;
        }
        // §5.C: Build routing-aware SyncNode from stored hints.
        // Skip entries that have NO routing hint — they cannot be delivered
        // and would cause a 422. They will be retried after identity discovery.
        final hasHint =
            (entry.receiverServerId != null) ||
            (entry.receiverPhone?.isNotEmpty ?? false) ||
            (entry.receiverWhatsapp?.isNotEmpty ?? false) ||
            (entry.receiverPublicKey?.isNotEmpty ?? false);

        if (!hasHint) {
          debugPrint(
            'Sync: ⏭ Skipping ${entry.id} — no routing hint yet. Will retry after discovery.',
          );
          continue;
        }

        final node = SyncNode(
          id: entry.id,
          senderId: currentUserId,
          // §5.C Routing headers — server picks first non-null in resolution order
          receiverId: entry.receiverServerId,
          receiverPhone: entry.receiverPhone,
          receiverWhatsapp: entry.receiverWhatsapp,
          receiverPublicKey: entry.receiverPublicKey,
          eventType: _parseEventType(entry.eventType),
          encryptedPayload: entry.encryptedPayload,
          syncState: 'pending',
          clientTimestamp: entry.createdAt,
        );

        await syncRepository.pushNode(node);
        deliveredIds.add(entry.id);
        debugPrint(
          'Sync: ✅ Pushed node ${entry.id} (${entry.eventType}) '
          '[routed via: ${_describeRoute(entry)}]',
        );
      } catch (e) {
        debugPrint('Sync: ❌ Push failed for ${entry.id}: $e');
        await outboxDao.incrementRetry(entry.id);
      }
    }

    if (deliveredIds.isNotEmpty) {
      await outboxDao.markDelivered(deliveredIds, transport: 'server');
    }
  }

  /// Returns a human-readable routing description for debug logs.
  String _describeRoute(OutboxEntry entry) {
    if (entry.receiverServerId != null)
      return 'serverId=${entry.receiverServerId}';
    if (entry.receiverPhone?.isNotEmpty ?? false)
      return 'phone=${entry.receiverPhone}';
    if (entry.receiverWhatsapp?.isNotEmpty ?? false)
      return 'whatsapp=${entry.receiverWhatsapp}';
    if (entry.receiverPublicKey?.isNotEmpty ?? false)
      return 'pubkey=${entry.receiverPublicKey!.substring(0, 8)}...';
    return 'none';
  }

  SyncEventType _parseEventType(String type) {
    return SyncEventType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => SyncEventType.unknown,
    );
  }
}
