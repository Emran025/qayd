import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:qayd/domain/entities/pos_credit_invoice_chat_snapshot.dart';
import 'package:qayd/domain/value_objects/digital_signature.dart';
import 'package:uuid/uuid.dart';

abstract final class PosCreditInvoiceChatProtocol {
  static const incomingChannel = 'pos_credit_invoice_incoming';
  static const outgoingChannel = 'pos_credit_invoice_outgoing';
  static const invoiceEventType = 'posCreditInvoice';
  static const acknowledgementEventType = 'posCreditInvoiceAcknowledgment';
  static const invoiceEventSchema = 'qayd_pos_credit_invoice_event_v1';
  static const acknowledgementSchema = 'qayd_pos_credit_ack_v2';
  static const pdfAttachmentSchema = 'qayd_pos_credit_invoice_pdf_v1';
  static const pdfAttachmentFileName = 'pos-credit-invoice.pdf';
  static const maxPdfAttachmentBytes = 128 * 1024;
  static const _maxEncodedPdfBytes = ((maxPdfAttachmentBytes + 2) ~/ 3) * 4;
  static const maxEventPayloadBytes =
      PosCreditInvoiceChatSnapshot.maxSerializedBytes +
      _maxEncodedPdfBytes +
      2048;
  static const maxAcknowledgmentPayloadBytes = 1024;

  static const _eventFields = <String>{
    'schema',
    'invoice_node_id',
    'invoice_id',
    'fingerprint',
    'invoice_snapshot',
    'pdf_attachment',
  };
  static const _localInvoiceFields = <String>{
    'acknowledgment_status',
    'delivery_status',
    'acknowledgment_responded_at',
    'acknowledgment_delivery_status',
    'acknowledgment_received_at',
    'acknowledgment_node_id',
    'acknowledgment_event_payload',
  };
  static const _pdfAttachmentFields = <String>{
    'schema',
    'mime_type',
    'file_name',
    'invoice_fingerprint',
    'byte_size',
    'sha256',
    'content_base64',
  };
  static const _acknowledgmentFields = <String>{
    'schema',
    'invoice_node_id',
    'invoice_id',
    'fingerprint',
    'status',
    'responded_at',
    'signature_hex',
    'signer_public_key_hex',
    'payload_hash_hex',
  };

  static String invoiceNodeId(String invoiceId) => const Uuid().v5(
    Namespace.url.value,
    'qayd:pos-credit-invoice:$invoiceId',
  );

  static String acknowledgementNodeId(
    String invoiceNodeId,
    String fingerprint,
  ) => const Uuid().v5(
    Namespace.url.value,
    'qayd:pos-credit-ack:$acknowledgementSchema:$invoiceNodeId:$fingerprint',
  );

  /// The PDF bytes are part of the payload passed to the existing E2EE sync
  /// dispatcher. The relay receives only the encrypted outer envelope.
  static Map<String, dynamic> invoiceEventPayload({
    required String invoiceNodeId,
    required PosCreditInvoiceChatSnapshot snapshot,
    required Uint8List pdfBytes,
  }) {
    if (invoiceNodeId != invoiceNodeIdForSnapshot(snapshot)) {
      throw const FormatException('Invalid POS credit invoice node id.');
    }
    final attachment = _pdfAttachment(snapshot, pdfBytes);
    final payload = <String, dynamic>{
      'schema': invoiceEventSchema,
      'invoice_node_id': invoiceNodeId,
      'invoice_id': snapshot.invoiceId,
      'fingerprint': snapshot.fingerprint,
      'invoice_snapshot': snapshot.toJson(),
      'pdf_attachment': attachment,
    };
    if (utf8.encode(jsonEncode(payload)).length > maxEventPayloadBytes) {
      throw const FormatException('POS credit invoice event is too large.');
    }
    return payload;
  }

  static String invoiceNodeIdForSnapshot(
    PosCreditInvoiceChatSnapshot snapshot,
  ) => invoiceNodeId(snapshot.invoiceId);

  /// Validates a persisted local chat event and returns only the network fields,
  /// excluding delivery/acknowledgment state maintained by this device.
  static Map<String, dynamic> networkInvoiceEventPayloadFromLocal({
    required Map<String, dynamic> payload,
    required String expectedNodeId,
  }) {
    snapshotFromEventPayload(payload, expectedNodeId: expectedNodeId);
    return <String, dynamic>{for (final key in _eventFields) key: payload[key]};
  }

  static Uint8List pdfBytesFromEventPayload(
    Map<String, dynamic> payload, {
    required String expectedInvoiceFingerprint,
  }) {
    final rawAttachment = payload['pdf_attachment'];
    if (rawAttachment is! Map ||
        rawAttachment.length != _pdfAttachmentFields.length ||
        rawAttachment.keys.any((key) => !_pdfAttachmentFields.contains(key)) ||
        !_pdfAttachmentFields.every(rawAttachment.containsKey)) {
      throw const FormatException('Missing or invalid POS invoice PDF.');
    }
    final attachment = Map<String, dynamic>.from(rawAttachment);
    final encoded = attachment['content_base64'];
    final declaredBytes = attachment['byte_size'];
    final declaredHash = attachment['sha256'];
    if (attachment['schema'] != pdfAttachmentSchema ||
        attachment['mime_type'] != 'application/pdf' ||
        attachment['file_name'] != pdfAttachmentFileName ||
        attachment['invoice_fingerprint'] != expectedInvoiceFingerprint ||
        encoded is! String ||
        encoded.isEmpty ||
        encoded.length > _maxEncodedPdfBytes ||
        declaredBytes is! int ||
        declaredBytes <= 0 ||
        declaredBytes > maxPdfAttachmentBytes ||
        declaredHash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(declaredHash)) {
      throw const FormatException('Invalid POS invoice PDF metadata.');
    }

    late final Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      throw const FormatException('Invalid POS invoice PDF encoding.');
    }
    if (base64Encode(bytes) != encoded ||
        bytes.length != declaredBytes ||
        !_hasPdfSignature(bytes) ||
        crypto.sha256.convert(bytes).toString() != declaredHash) {
      throw const FormatException('POS invoice PDF integrity check failed.');
    }
    return bytes;
  }

  static Map<String, dynamic> localInvoicePayload({
    required Map<String, dynamic> eventPayload,
    required String acknowledgementStatus,
    required String deliveryStatus,
  }) => <String, dynamic>{
    ...eventPayload,
    'acknowledgment_status': acknowledgementStatus,
    'delivery_status': deliveryStatus,
  };

  static Map<String, dynamic> acknowledgementEventPayload({
    required String invoiceNodeId,
    required String invoiceId,
    required String fingerprint,
    required String status,
    required DateTime respondedAt,
    required DigitalSignature signature,
  }) {
    final normalizedRespondedAt = respondedAt.toUtc().toIso8601String();
    if (invoiceNodeId != invoiceNodeIdFor(invoiceId) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint) ||
        (status != 'accepted' && status != 'rejected') ||
        signature.signatureBytes.length != 64 ||
        signature.signerPublicKey.length != 32 ||
        signature.payloadHash.length != 32) {
      throw const FormatException('Invalid POS credit invoice acknowledgment.');
    }
    final signingPayload = acknowledgmentSigningPayload(
      invoiceNodeId: invoiceNodeId,
      invoiceId: invoiceId,
      fingerprint: fingerprint,
      status: status,
      respondedAt: normalizedRespondedAt,
      signerPublicKeyHex: signature.signerPublicKeyHex,
    );
    if (signature.payloadHashHex !=
        crypto.sha256.convert(utf8.encode(signingPayload)).toString()) {
      throw const FormatException('Invalid POS credit invoice signature hash.');
    }
    final payload = <String, dynamic>{
      'schema': acknowledgementSchema,
      'invoice_node_id': invoiceNodeId,
      'invoice_id': invoiceId,
      'fingerprint': fingerprint,
      'status': status,
      'responded_at': normalizedRespondedAt,
      'signature_hex': signature.signatureHex,
      'signer_public_key_hex': signature.signerPublicKeyHex,
      'payload_hash_hex': signature.payloadHashHex,
    };
    if (!isValidAcknowledgmentEventPayload(
      payload,
      expectedNodeId: invoiceNodeId,
    )) {
      throw const FormatException('Invalid POS credit invoice acknowledgment.');
    }
    return payload;
  }

  /// Stable signing representation; array order is part of protocol v2.
  static String acknowledgmentSigningPayload({
    required String invoiceNodeId,
    required String invoiceId,
    required String fingerprint,
    required String status,
    required String respondedAt,
    required String signerPublicKeyHex,
  }) => jsonEncode(<String>[
    acknowledgementSchema,
    invoiceNodeId,
    invoiceId,
    fingerprint,
    status,
    respondedAt,
    signerPublicKeyHex.toLowerCase(),
  ]);

  static bool isValidAcknowledgmentEventPayload(
    Map<String, dynamic> payload, {
    required String expectedNodeId,
  }) {
    if (payload.length != _acknowledgmentFields.length ||
        payload.keys.any((key) => !_acknowledgmentFields.contains(key))) {
      return false;
    }
    if (utf8.encode(jsonEncode(payload)).length >
        maxAcknowledgmentPayloadBytes) {
      return false;
    }
    final eventInvoiceNodeId = payload['invoice_node_id'];
    final invoiceId = payload['invoice_id'];
    final fingerprint = payload['fingerprint'];
    final status = payload['status'];
    final respondedAt = payload['responded_at'];
    final signatureHex = payload['signature_hex'];
    final signerPublicKeyHex = payload['signer_public_key_hex'];
    final payloadHashHex = payload['payload_hash_hex'];
    final parsedRespondedAt = respondedAt is String
        ? DateTime.tryParse(respondedAt)
        : null;
    if (payload['schema'] != acknowledgementSchema ||
        eventInvoiceNodeId is! String ||
        eventInvoiceNodeId.length != 36 ||
        invoiceId is! String ||
        invoiceId.isEmpty ||
        invoiceId.length > 128 ||
        fingerprint is! String ||
        fingerprint.length != 64 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint) ||
        (status != 'accepted' && status != 'rejected') ||
        respondedAt is! String ||
        respondedAt.length > 64 ||
        parsedRespondedAt == null ||
        parsedRespondedAt.toUtc().toIso8601String() != respondedAt ||
        signatureHex is! String ||
        !RegExp(r'^[0-9a-f]{128}$').hasMatch(signatureHex) ||
        signerPublicKeyHex is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(signerPublicKeyHex) ||
        payloadHashHex is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(payloadHashHex) ||
        eventInvoiceNodeId != expectedNodeId ||
        eventInvoiceNodeId != invoiceNodeIdFor(invoiceId)) {
      return false;
    }
    final signingPayload = acknowledgmentSigningPayload(
      invoiceNodeId: eventInvoiceNodeId,
      invoiceId: invoiceId,
      fingerprint: fingerprint,
      status: status as String,
      respondedAt: respondedAt,
      signerPublicKeyHex: signerPublicKeyHex,
    );
    return crypto.sha256.convert(utf8.encode(signingPayload)).toString() ==
        payloadHashHex;
  }

  static Map<String, dynamic> decodePayload(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) {
      throw const FormatException('Missing POS credit invoice payload.');
    }
    if (utf8.encode(rawJson).length > maxEventPayloadBytes + 1024) {
      throw const FormatException('POS credit invoice payload is too large.');
    }
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Invalid POS credit invoice payload.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static PosCreditInvoiceChatSnapshot snapshotFromEventPayload(
    Map<String, dynamic> payload, {
    required String expectedNodeId,
  }) {
    if (utf8.encode(jsonEncode(payload)).length >
            maxEventPayloadBytes + maxAcknowledgmentPayloadBytes ||
        payload.length < _eventFields.length ||
        payload.length > _eventFields.length + _localInvoiceFields.length ||
        payload.keys.any(
          (key) =>
              !_eventFields.contains(key) && !_localInvoiceFields.contains(key),
        ) ||
        !_eventFields.every(payload.containsKey) ||
        payload['schema'] != invoiceEventSchema ||
        payload['invoice_node_id'] != expectedNodeId ||
        payload['invoice_snapshot'] is! Map) {
      throw const FormatException('Invalid POS credit invoice event.');
    }
    final snapshot = PosCreditInvoiceChatSnapshot.fromJson(
      Map<String, dynamic>.from(payload['invoice_snapshot'] as Map),
    );
    if (payload['invoice_id'] != snapshot.invoiceId ||
        expectedNodeId != invoiceNodeIdForSnapshot(snapshot) ||
        payload['fingerprint'] != snapshot.fingerprint) {
      throw const FormatException('POS credit invoice fingerprint mismatch.');
    }
    pdfBytesFromEventPayload(
      payload,
      expectedInvoiceFingerprint: snapshot.fingerprint,
    );
    return snapshot;
  }

  static Map<String, dynamic> _pdfAttachment(
    PosCreditInvoiceChatSnapshot snapshot,
    Uint8List bytes,
  ) {
    if (bytes.isEmpty ||
        bytes.length > maxPdfAttachmentBytes ||
        !_hasPdfSignature(bytes)) {
      throw const FormatException('POS invoice PDF is missing or too large.');
    }
    return <String, dynamic>{
      'schema': pdfAttachmentSchema,
      'mime_type': 'application/pdf',
      'file_name': pdfAttachmentFileName,
      'invoice_fingerprint': snapshot.fingerprint,
      'byte_size': bytes.length,
      'sha256': crypto.sha256.convert(bytes).toString(),
      'content_base64': base64Encode(bytes),
    };
  }

  static bool _hasPdfSignature(Uint8List bytes) {
    if (bytes.length < 9 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      return false;
    }
    final tailStart = bytes.length > 32 ? bytes.length - 32 : 0;
    return String.fromCharCodes(bytes.skip(tailStart)).contains('%%EOF');
  }

  static String invoiceNodeIdFor(String invoiceId) => const Uuid().v5(
    Namespace.url.value,
    'qayd:pos-credit-invoice:$invoiceId',
  );
}
