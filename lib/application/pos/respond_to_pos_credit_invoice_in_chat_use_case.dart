import 'dart:async';
import 'dart:convert';

import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/application/pos/pos_credit_invoice_audit.dart';
import 'package:qayd/application/pos/pos_credit_invoice_chat_protocol.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/audit_entry.dart';
import 'package:qayd/domain/repositories/notification_message_repository.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class RespondToPosCreditInvoiceInChatUseCase {
  RespondToPosCreditInvoiceInChatUseCase({
    required NotificationMessageRepository notificationMessageRepository,
    required SyncEventDispatcher syncEventDispatcher,
    required ReceiptSigningService signingService,
    required Future<CryptoKeyPair> Function() getCurrentUserKeyPair,
    AuditLogService? auditLogService,
  }) : _notifications = notificationMessageRepository,
       _sync = syncEventDispatcher,
       _signingService = signingService,
       _getCurrentUserKeyPair = getCurrentUserKeyPair,
       _auditLogService = auditLogService;

  final NotificationMessageRepository _notifications;
  final SyncEventDispatcher _sync;
  final ReceiptSigningService _signingService;
  final Future<CryptoKeyPair> Function() _getCurrentUserKeyPair;
  final AuditLogService? _auditLogService;
  final Map<String, Future<void>> _notificationTails = {};

  /// Acknowledges the already-posted invoice. This use case has no POS,
  /// accounting, payment, inventory, or ledger repository dependencies.
  Future<Result<void>> call({
    required String notificationId,
    required bool accepted,
  }) => _withNotificationLock(
    notificationId,
    () => _respond(notificationId: notificationId, accepted: accepted),
  );

  Future<Result<void>> _withNotificationLock(
    String notificationId,
    Future<Result<void>> Function() action,
  ) {
    final previous = _notificationTails[notificationId] ?? Future<void>.value();
    final release = Completer<void>();
    final tail = previous.then((_) => release.future);
    _notificationTails[notificationId] = tail;

    return () async {
      await previous;
      try {
        return await action();
      } finally {
        release.complete();
        if (identical(_notificationTails[notificationId], tail)) {
          _notificationTails.remove(notificationId);
        }
      }
    }();
  }

  Future<Result<void>> _respond({
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
    late final String pdfSha256;
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
      pdfSha256 = PosCreditInvoiceChatProtocol.pdfSha256FromEventPayload(
        payload,
        expectedInvoiceFingerprint: fingerprint,
      );
    } on FormatException {
      return const FailureResult(
        ValidationFailure(messageAr: 'تعذر التحقق من الفاتورة قبل الإقرار.'),
      );
    }

    final decision = accepted ? 'accepted' : 'rejected';
    final pendingDecision = '${decision}_pending_sync';
    final currentStatus =
        payload['acknowledgment_status'] as String? ?? 'pending';
    final isNewDecision = currentStatus == 'pending';
    late final Map<String, dynamic> eventPayload;
    if (currentStatus == 'pending') {
      final respondedAt = DateTime.now().toUtc();
      try {
        final keyPair = await _getCurrentUserKeyPair();
        final canonical =
            PosCreditInvoiceChatProtocol.acknowledgmentSigningPayload(
              invoiceNodeId: notification.id,
              invoiceId: invoiceId,
              fingerprint: fingerprint,
              pdfSha256: pdfSha256,
              status: decision,
              respondedAt: respondedAt.toIso8601String(),
              signerPublicKeyHex: keyPair.publicKeyHex,
            );
        final signature = _signingService.signCanonicalString(
          canonical,
          keyPair,
        );
        eventPayload = PosCreditInvoiceChatProtocol.acknowledgementEventPayload(
          invoiceNodeId: notification.id,
          invoiceId: invoiceId,
          fingerprint: fingerprint,
          pdfSha256: pdfSha256,
          status: decision,
          respondedAt: respondedAt,
          signature: signature,
        );
      } on Object {
        return const FailureResult(
          ValidationFailure(messageAr: 'تعذر توقيع إقرار الفاتورة بأمان.'),
        );
      }
      payload['acknowledgment_status'] = pendingDecision;
      payload['acknowledgment_responded_at'] = respondedAt.toIso8601String();
      payload['acknowledgment_event_payload'] = eventPayload;
      final savedDecision = await _notifications
          .updateBodyAndPayloadIfUnchanged(
            id: notification.id,
            expectedRawPayloadJson: notification.rawPayloadJson!,
            bodyText: AppStrings.posCreditInvoiceResponsePendingSync,
            rawPayloadJson: jsonEncode(payload),
          );
      if (savedDecision.isFailure) {
        return FailureResult(savedDecision.failureOrNull!);
      }
      if (savedDecision.valueOrNull != true) {
        return const FailureResult(
          ValidationFailure(
            messageAr:
                'تغيرت حالة الإقرار بالتزامن؛ أعد فتح المحادثة وراجع القرار.',
          ),
        );
      }
    } else if (currentStatus == pendingDecision) {
      final persistedEvent = payload['acknowledgment_event_payload'];
      if (persistedEvent is! Map) {
        return const FailureResult(
          ValidationFailure(
            messageAr: 'إقرار الفاتورة المعلّق لا يحمل توقيعًا صالحًا.',
          ),
        );
      }
      eventPayload = Map<String, dynamic>.from(persistedEvent);
      if (!PosCreditInvoiceChatProtocol.isValidAcknowledgmentEventPayload(
            eventPayload,
            expectedNodeId: notification.id,
          ) ||
          eventPayload['invoice_id'] != invoiceId ||
          eventPayload['fingerprint'] != fingerprint ||
          eventPayload['pdf_sha256'] != pdfSha256 ||
          eventPayload['status'] != decision) {
        return const FailureResult(
          ValidationFailure(
            messageAr: 'تعذر استعادة توقيع إقرار الفاتورة لإعادة الإرسال.',
          ),
        );
      }
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
    final respondedAt = DateTime.parse(
      eventPayload['responded_at'] as String,
    ).toUtc();
    final signerPublicKeyHex = eventPayload['signer_public_key_hex'] as String;
    await recordPosCreditInvoiceAudit(
      auditLogService: _auditLogService,
      action: isNewDecision ? AuditAction.create : AuditAction.update,
      requestNodeId: notification.id,
      eventId: ackNodeId,
      invoiceId: invoiceId,
      partyAccountId: notification.counterpartyAccountId,
      fingerprint: fingerprint,
      pdfSha256: pdfSha256,
      signerPublicKeyHex: signerPublicKeyHex,
      event: 'acknowledgment_signed',
      result: '${decision}_pending_sync',
      occurredAt: respondedAt,
    );
    final dispatched = await _sync.dispatchGenericEvent(
      counterpartyAccountId: notification.counterpartyAccountId,
      eventType: PosCreditInvoiceChatProtocol.acknowledgementEventType,
      payload: eventPayload,
      nodeId: ackNodeId,
    );
    if (dispatched.isFailure) {
      await recordPosCreditInvoiceAudit(
        auditLogService: _auditLogService,
        action: AuditAction.update,
        requestNodeId: notification.id,
        eventId: ackNodeId,
        invoiceId: invoiceId,
        partyAccountId: notification.counterpartyAccountId,
        fingerprint: fingerprint,
        pdfSha256: pdfSha256,
        signerPublicKeyHex: signerPublicKeyHex,
        event: 'acknowledgment_dispatch',
        result: 'failed',
        occurredAt: respondedAt,
      );
      return dispatched;
    }

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
      final saved = await _notifications.updateBodyAndPayloadIfUnchanged(
        id: notification.id,
        expectedRawPayloadJson: latest.rawPayloadJson!,
        bodyText: AppStrings.posCreditInvoiceResponseSent,
        rawPayloadJson: jsonEncode(latestPayload),
      );
      if (saved.isFailure) return FailureResult(saved.failureOrNull!);
      if (saved.valueOrNull != true) {
        return const FailureResult(
          ValidationFailure(
            messageAr: 'تغيرت حالة إقرار الفاتورة أثناء الإرسال.',
          ),
        );
      }
      await recordPosCreditInvoiceAudit(
        auditLogService: _auditLogService,
        action: AuditAction.update,
        requestNodeId: notification.id,
        eventId: ackNodeId,
        invoiceId: invoiceId,
        partyAccountId: notification.counterpartyAccountId,
        fingerprint: fingerprint,
        pdfSha256: pdfSha256,
        signerPublicKeyHex: signerPublicKeyHex,
        event: 'acknowledgment_dispatch',
        result: 'queued',
        occurredAt: respondedAt,
      );
      return const Success(null);
    } on FormatException {
      return const FailureResult(
        ValidationFailure(messageAr: 'تعذر حفظ حالة إقرار الفاتورة.'),
      );
    }
  }
}
