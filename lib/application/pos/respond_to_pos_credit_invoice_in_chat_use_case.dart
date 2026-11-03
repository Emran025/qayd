import 'dart:convert';

import 'package:qayd/application/pos/pos_credit_invoice_chat_protocol.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/repositories/notification_message_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class RespondToPosCreditInvoiceInChatUseCase {
  const RespondToPosCreditInvoiceInChatUseCase({
    required NotificationMessageRepository notificationMessageRepository,
    required SyncEventDispatcher syncEventDispatcher,
  }) : _notifications = notificationMessageRepository,
       _sync = syncEventDispatcher;

  final NotificationMessageRepository _notifications;
  final SyncEventDispatcher _sync;

  /// Acknowledges the already-posted invoice. This use case has no POS,
  /// accounting, payment, inventory, or ledger repository dependencies.
  Future<Result<void>> call({
    required String notificationId,
    required bool accepted,
  }) async {
    final notification = await _notifications.findById(notificationId);
    if (notification == null ||
        notification.channel != PosCreditInvoiceChatProtocol.incomingChannel) {
      return const FailureResult(
        ValidationFailure(messageAr: 'فاتورة الآجل غير موجودة في المحادثة.'),
      );
    }

    late final Map<String, dynamic> payload;
    late final String invoiceId;
    late final String fingerprint;
    try {
      payload = PosCreditInvoiceChatProtocol.decodePayload(
        notification.rawPayloadJson,
      );
      final snapshot = PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
        payload,
        expectedNodeId: notification.id,
      );
      invoiceId = snapshot.invoiceId;
      fingerprint = snapshot.fingerprint;
    } on FormatException {
      return const FailureResult(
        ValidationFailure(messageAr: 'تعذر التحقق من الفاتورة قبل الإقرار.'),
      );
    }

    final decision = accepted ? 'accepted' : 'rejected';
    final pendingDecision = '${decision}_pending_sync';
    final currentStatus =
        payload['acknowledgment_status'] as String? ?? 'pending';
    DateTime respondedAt;
    if (currentStatus == 'pending') {
      respondedAt = DateTime.now().toUtc();
      payload['acknowledgment_status'] = pendingDecision;
      payload['acknowledgment_responded_at'] = respondedAt.toIso8601String();
      final savedDecision = await _notifications.updateBodyAndPayload(
        id: notification.id,
        bodyText: AppStrings.posCreditInvoiceResponsePendingSync,
        rawPayloadJson: jsonEncode(payload),
      );
      if (savedDecision.isFailure) return savedDecision;
    } else if (currentStatus == pendingDecision) {
      final rawDate = payload['acknowledgment_responded_at'];
      respondedAt = rawDate is String
          ? DateTime.tryParse(rawDate)?.toUtc() ?? DateTime.now().toUtc()
          : DateTime.now().toUtc();
    } else if (currentStatus == decision) {
      return const Success(null);
    } else {
      return const FailureResult(
        ValidationFailure(
          messageAr: 'سبق إرسال إقرار مختلف لهذه الفاتورة ولا يمكن تغييره.',
        ),
      );
    }

    final ackNodeId = PosCreditInvoiceChatProtocol.acknowledgementNodeId(
      notification.id,
      fingerprint,
    );
    final eventPayload =
        PosCreditInvoiceChatProtocol.acknowledgementEventPayload(
          invoiceNodeId: notification.id,
          invoiceId: invoiceId,
          fingerprint: fingerprint,
          status: decision,
          respondedAt: respondedAt,
        );
    final dispatched = await _sync.dispatchGenericEvent(
      counterpartyAccountId: notification.counterpartyAccountId,
      eventType: PosCreditInvoiceChatProtocol.acknowledgementEventType,
      payload: eventPayload,
      nodeId: ackNodeId,
    );
    if (dispatched.isFailure) return dispatched;

    final latest = await _notifications.findById(notification.id);
    if (latest == null) {
      return const FailureResult(
        ValidationFailure(messageAr: 'تعذر حفظ إقرار الفاتورة.'),
      );
    }
    try {
      final latestPayload = PosCreditInvoiceChatProtocol.decodePayload(
        latest.rawPayloadJson,
      );
      if (latestPayload['acknowledgment_status'] != pendingDecision) {
        return const FailureResult(
          ValidationFailure(messageAr: 'تغيرت حالة إقرار الفاتورة.'),
        );
      }
      latestPayload['acknowledgment_status'] = decision;
      latestPayload['acknowledgment_delivery_status'] = 'queued';
      final saved = await _notifications.updateBodyAndPayload(
        id: notification.id,
        bodyText: AppStrings.posCreditInvoiceResponseSent,
        rawPayloadJson: jsonEncode(latestPayload),
      );
      return saved;
    } on FormatException {
      return const FailureResult(
        ValidationFailure(messageAr: 'تعذر حفظ حالة إقرار الفاتورة.'),
      );
    }
  }
}
