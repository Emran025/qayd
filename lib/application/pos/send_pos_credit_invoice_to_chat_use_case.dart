import 'dart:convert';

import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/application/pos/build_pos_invoice_pdf_use_case.dart';
import 'package:qayd/application/pos/pos_credit_invoice_audit.dart';
import 'package:qayd/application/pos/pos_credit_invoice_chat_protocol.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/audit_entry.dart';
import 'package:qayd/domain/entities/notification_message.dart';
import 'package:qayd/domain/entities/pos_credit_invoice_chat_snapshot.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/repositories/notification_message_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class SendPosCreditInvoiceToChatUseCase {
  const SendPosCreditInvoiceToChatUseCase({
    required NotificationMessageRepository notificationMessageRepository,
    required SyncEventDispatcher syncEventDispatcher,
    required BuildPosInvoicePdfUseCase pdfUseCase,
    AuditLogService? auditLogService,
  }) : _notifications = notificationMessageRepository,
       _sync = syncEventDispatcher,
       _pdfUseCase = pdfUseCase,
       _auditLogService = auditLogService;

  final NotificationMessageRepository _notifications;

  final SyncEventDispatcher _sync;

  final BuildPosInvoicePdfUseCase _pdfUseCase;
  final AuditLogService? _auditLogService;

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

    final nodeId = PosCreditInvoiceChatProtocol.invoiceNodeIdForSnapshot(
      snapshot,
    );
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
        final eventPayload =
            PosCreditInvoiceChatProtocol.networkInvoiceEventPayloadFromLocal(
              payload: stored,
              expectedNodeId: nodeId,
            );
        return await _dispatchAndRecord(
          notification: existing,
          nodeId: nodeId,
          eventPayload: eventPayload,
        );
      } on FormatException {
        return const FailureResult(
          ValidationFailure(
            messageAr: 'تعذر التحقق من رسالة الفاتورة السابقة.',
          ),
        );
      }
    }

    final pdfResult = await _pdfUseCase.forInvoice(snapshot.toPdfInvoice());
    final pdfBytes = pdfResult.valueOrNull;
    if (pdfBytes == null) {
      return FailureResult(
        pdfResult.failureOrNull ??
            const ValidationFailure(
              messageAr: 'تعذر إنشاء PDF آمن لإرساله في المحادثة.',
            ),
      );
    }

    late final Map<String, dynamic> eventPayload;
    try {
      eventPayload = PosCreditInvoiceChatProtocol.invoiceEventPayload(
        invoiceNodeId: nodeId,
        snapshot: snapshot,
        pdfBytes: pdfBytes,
      );
    } on FormatException catch (error) {
      return FailureResult(ValidationFailure(messageAr: error.message));
    }

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
    await recordPosCreditInvoiceAudit(
      auditLogService: _auditLogService,
      action: AuditAction.create,
      requestNodeId: nodeId,
      eventId: nodeId,
      invoiceId: snapshot.invoiceId,
      partyAccountId: invoice.counterpartyAccountId!.value,
      fingerprint: snapshot.fingerprint,
      pdfSha256: PosCreditInvoiceChatProtocol.pdfSha256FromEventPayload(
        eventPayload,
        expectedInvoiceFingerprint: snapshot.fingerprint,
      ),
      event: 'request_created',
      result: 'pending',
      occurredAt: invoice.createdAt,
    );

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
      nodeId: nodeId,
      eventPayload: eventPayload,
    );
  }

  /// Retries only a failed or interrupted send; queued messages remain the
  /// responsibility of the existing sync outbox. It reuses the exact PDF bytes
  /// persisted with the original invoice snapshot.
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
      final eventPayload =
          PosCreditInvoiceChatProtocol.networkInvoiceEventPayloadFromLocal(
            payload: payload,
            expectedNodeId: notification.id,
          );
      return await _dispatchAndRecord(
        notification: notification,
        nodeId: notification.id,
        eventPayload: eventPayload,
      );
    } on FormatException {
      return const FailureResult(
        ValidationFailure(messageAr: 'تعذر التحقق من بيانات الفاتورة.'),
      );
    }
  }

  Future<Result<void>> _dispatchAndRecord({
    required NotificationMessage notification,
    required String nodeId,
    required Map<String, dynamic> eventPayload,
  }) async {
    final snapshot = PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
      eventPayload,
      expectedNodeId: nodeId,
    );
    final pdfSha256 = PosCreditInvoiceChatProtocol.pdfSha256FromEventPayload(
      eventPayload,
      expectedInvoiceFingerprint: snapshot.fingerprint,
    );
    final dispatched = await _sync.dispatchGenericEvent(
      counterpartyAccountId: notification.counterpartyAccountId,
      eventType: PosCreditInvoiceChatProtocol.invoiceEventType,
      payload: eventPayload,
      nodeId: nodeId,
    );

    var latest = await _notifications.findById(notification.id) ?? notification;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final localPayload = PosCreditInvoiceChatProtocol.decodePayload(
          latest.rawPayloadJson,
        );
        // Merge into the latest state and retry if an acknowledgment raced us.
        localPayload['delivery_status'] = dispatched.isSuccess
            ? 'queued'
            : 'failed';
        final updated = await _notifications.updateBodyAndPayloadIfUnchanged(
          id: notification.id,
          expectedRawPayloadJson: latest.rawPayloadJson!,
          bodyText: dispatched.isSuccess
              ? AppStrings.posCreditInvoiceAwaiting
              : AppStrings.posCreditInvoiceDeliveryFailed,
          rawPayloadJson: jsonEncode(localPayload),
        );
        if (updated.isFailure) {
          return FailureResult(updated.failureOrNull!);
        }
        if (updated.valueOrNull == true) {
          await recordPosCreditInvoiceAudit(
            auditLogService: _auditLogService,
            action: AuditAction.update,
            requestNodeId: nodeId,
            eventId: nodeId,
            invoiceId: snapshot.invoiceId,
            partyAccountId: notification.counterpartyAccountId,
            fingerprint: snapshot.fingerprint,
            pdfSha256: pdfSha256,
            event: 'request_dispatch',
            result: dispatched.isSuccess ? 'queued' : 'failed',
          );
          return dispatched;
        }
        final refreshed = await _notifications.findById(notification.id);
        if (refreshed == null) break;
        latest = refreshed;
      } on FormatException {
        return const FailureResult(
          ValidationFailure(messageAr: 'تعذر حفظ حالة إرسال الفاتورة.'),
        );
      }
    }
    return const FailureResult(
      ValidationFailure(
        messageAr:
            'تغيرت حالة الفاتورة بالتزامن؛ أعد المحاولة بعد تحديث المحادثة.',
      ),
    );
  }
}
