import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/domain/entities/audit_entry.dart';

/// Appends a minimal, privacy-preserving audit record for a credit-invoice
/// request or response. The audit payload intentionally contains identifiers,
/// hashes, outcomes, and timestamps only; it never stores invoice values or PDF
/// bytes.
Future<void> recordPosCreditInvoiceAudit({
  required AuditLogService? auditLogService,
  required AuditAction action,
  required String requestNodeId,
  required String eventId,
  required String invoiceId,
  required String partyAccountId,
  required String fingerprint,
  required String event,
  required String result,
  String? pdfSha256,
  String? signerPublicKeyHex,
  DateTime? occurredAt,
}) async {
  if (auditLogService == null) return;

  final auditData = <String, dynamic>{
    'request_node_id': requestNodeId,
    'event_id': eventId,
    'invoice_id': invoiceId,
    'party_account_id': partyAccountId,
    'fingerprint': fingerprint,
    'request_version': fingerprint,
    'event': event,
    'result': result,
  };
  if (pdfSha256 != null) auditData['pdf_sha256'] = pdfSha256;
  if (signerPublicKeyHex != null) {
    auditData['signer_public_key_hex'] = signerPublicKeyHex.toLowerCase();
  }
  if (occurredAt != null) {
    auditData['occurred_at'] = occurredAt.toUtc().toIso8601String();
  }

  await auditLogService.log(
    batchId: requestNodeId,
    entityType: 'pos_credit_invoice_chat',
    entityId: requestNodeId,
    action: action,
    newData: auditData,
  );
}
