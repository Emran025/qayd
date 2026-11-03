import 'dart:convert';

import 'package:qayd/application/pos/pos_credit_invoice_chat_protocol.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/notification_message.dart';
import 'package:qayd/domain/entities/pos_credit_invoice_chat_snapshot.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/repositories/notification_message_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class SendPosCreditInvoiceToChatUseCase {
  const SendPosCreditInvoiceToChatUseCase({
    required NotificationMessageRepository notificationMessageRepository,
    required SyncEventDispatcher syncEventDispatcher,
  }) : _notifications = notificationMessageRepository,
       _sync = syncEventDispatcher;

  final NotificationMessageRepository _notifications;
  final SyncEventDispatcher _sync;

  /// Shares only an already-posted sale that still has an amount due.
  /// A chat-delivery failure never rolls back or changes the POS sale.
  Future<Result<void>> call(PosInvoice invoice) async {
    if (invoice.type != PosInvoiceType.sale ||
        invoice.due.minorUnits <= 0 ||
        invoice.counterpartyAccountId == null) {
      return const Success(null);
    }

    late final PosCreditInvoiceChatSnapshot snapshot;
    try {
      snapshot = PosCreditInvoiceChatSnapshot.fromInvoice(invoice);
    } on FormatException catch (error) {
      return FailureResult(ValidationFailure(messageAr: error.message));
    } catch (_) {
      return const FailureResult(
        ValidationFailure(messageAr: 'تعذر تجهيز نسخة آمنة من الفاتورة.'),
      );
    }

    final nodeId = PosCreditInvoiceChatProtocol.invoiceNodeId(invoice.id);
    final existing = await _notifications.findById(nodeId);
    if (existing != null) {
      if (existing.channel != PosCreditInvoiceChatProtocol.outgoingChannel ||
          existing.counterpartyAccountId !=
              invoice.counterpartyAccountId!.value) {
        return const FailureResult(
          ValidationFailure(messageAr: 'معرّف رسالة الفاتورة مستخدم مسبقاً.'),
        );
      }
      try {
        final stored = PosCreditInvoiceChatProtocol.decodePayload(
          existing.rawPayloadJson,
        );
        final storedSnapshot =
            PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
              stored,
              expectedNodeId: nodeId,
            );
        if (storedSnapshot.fingerprint != snapshot.fingerprint) {
          return const FailureResult(
            ValidationFailure(
              messageAr: 'تغيرت بيانات الفاتورة بعد إنشاء رسالة المحادثة.',
            ),
          );
        }
        if (stored['acknowledgment_status'] != 'pending' ||
            (stored['delivery_status'] != 'pending' &&
                stored['delivery_status'] != 'failed')) {
          return const Success(null);
        }
      } on FormatException {
        return const FailureResult(
          ValidationFailure(
            messageAr: 'تعذر التحقق من رسالة الفاتورة السابقة.',
          ),
        );
      }
      return _dispatchAndRecord(
        notification: existing,
        snapshot: snapshot,
        nodeId: nodeId,
      );
    }

    final eventPayload = PosCreditInvoiceChatProtocol.invoiceEventPayload(
      invoiceNodeId: nodeId,
      snapshot: snapshot,
    );
    final localPayload = PosCreditInvoiceChatProtocol.localInvoicePayload(
      eventPayload: eventPayload,
      acknowledgementStatus: 'pending',
      deliveryStatus: 'pending',
    );
    final inserted = await _notifications.insert(
      id: nodeId,
      bodyText:
          '${AppStrings.posCreditInvoiceChatTitle} #${invoice.invoiceNumber}',
      channel: PosCreditInvoiceChatProtocol.outgoingChannel,
      counterpartyAccountId: invoice.counterpartyAccountId!.value,
      createdAtIso: invoice.createdAt.toUtc().toIso8601String(),
      rawPayloadJson: jsonEncode(localPayload),
    );
    if (inserted.isFailure) return inserted;

    final notification = NotificationMessage(
      id: nodeId,
      bodyText:
          '${AppStrings.posCreditInvoiceChatTitle} #${invoice.invoiceNumber}',
      channel: PosCreditInvoiceChatProtocol.outgoingChannel,
      counterpartyAccountId: invoice.counterpartyAccountId!.value,
      createdAt: invoice.createdAt.toUtc(),
      processed: false,
      rawPayloadJson: jsonEncode(localPayload),
    );
    return _dispatchAndRecord(
      notification: notification,
      snapshot: snapshot,
      nodeId: nodeId,
    );
  }

  /// Retries only a failed or interrupted send; queued messages remain the
  /// responsibility of the existing sync outbox.
  Future<Result<void>> retry(String notificationId) async {
    final notification = await _notifications.findById(notificationId);
    if (notification == null ||
        notification.channel != PosCreditInvoiceChatProtocol.outgoingChannel) {
      return const FailureResult(
        ValidationFailure(messageAr: 'رسالة فاتورة الآجل غير موجودة.'),
      );
    }
    try {
      final payload = PosCreditInvoiceChatProtocol.decodePayload(
        notification.rawPayloadJson,
      );
      if (payload['acknowledgment_status'] != 'pending' ||
          (payload['delivery_status'] != 'pending' &&
              payload['delivery_status'] != 'failed')) {
        return const Success(null);
      }
      final snapshot = PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
        payload,
        expectedNodeId: notification.id,
      );
      return await _dispatchAndRecord(
        notification: notification,
        snapshot: snapshot,
        nodeId: notification.id,
      );
    } on FormatException {
      return const FailureResult(
        ValidationFailure(messageAr: 'تعذر التحقق من بيانات الفاتورة.'),
      );
    }
  }

  Future<Result<void>> _dispatchAndRecord({
    required NotificationMessage notification,
    required PosCreditInvoiceChatSnapshot snapshot,
    required String nodeId,
  }) async {
    final eventPayload = PosCreditInvoiceChatProtocol.invoiceEventPayload(
      invoiceNodeId: nodeId,
      snapshot: snapshot,
    );
    final dispatched = await _sync.dispatchGenericEvent(
      counterpartyAccountId: notification.counterpartyAccountId,
      eventType: PosCreditInvoiceChatProtocol.invoiceEventType,
      payload: eventPayload,
      nodeId: nodeId,
    );

    final latest =
        await _notifications.findById(notification.id) ?? notification;
    try {
      final localPayload = PosCreditInvoiceChatProtocol.decodePayload(
        latest.rawPayloadJson,
      );
      // Keep any acknowledgement that arrived while the send was being queued.
      localPayload['delivery_status'] = dispatched.isSuccess
          ? 'queued'
          : 'failed';
      final updated = await _notifications.updateBodyAndPayload(
        id: notification.id,
        bodyText: dispatched.isSuccess
            ? AppStrings.posCreditInvoiceAwaiting
            : AppStrings.posCreditInvoiceDeliveryFailed,
        rawPayloadJson: jsonEncode(localPayload),
      );
      if (updated.isFailure) return updated;
    } on FormatException {
      return const FailureResult(
        ValidationFailure(messageAr: 'تعذر حفظ حالة إرسال الفاتورة.'),
      );
    }
    return dispatched;
  }
}
