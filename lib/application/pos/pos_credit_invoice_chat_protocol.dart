import 'dart:convert';

import 'package:qayd/domain/entities/pos_credit_invoice_chat_snapshot.dart';
import 'package:uuid/uuid.dart';

abstract final class PosCreditInvoiceChatProtocol {
  static const incomingChannel = 'pos_credit_invoice_incoming';
  static const outgoingChannel = 'pos_credit_invoice_outgoing';
  static const invoiceEventType = 'posCreditInvoice';
  static const acknowledgementEventType = 'posCreditInvoiceAcknowledgment';
  static const invoiceEventSchema = 'qayd_pos_credit_invoice_event_v1';
  static const acknowledgementSchema = 'qayd_pos_credit_invoice_ack_v1';
  static const maxEventPayloadBytes =
      PosCreditInvoiceChatSnapshot.maxSerializedBytes + 1024;
  static const maxAcknowledgmentPayloadBytes = 1024;
  static const _eventFields = <String>{
    'schema',
    'invoice_node_id',
    'invoice_id',
    'fingerprint',
    'invoice_snapshot',
  };
  static const _localInvoiceFields = <String>{
    'acknowledgment_status',
    'delivery_status',
    'acknowledgment_responded_at',
    'acknowledgment_delivery_status',
    'acknowledgment_received_at',
    'acknowledgment_node_id',
  };
  static const _acknowledgmentFields = <String>{
    'schema',
    'invoice_node_id',
    'invoice_id',
    'fingerprint',
    'status',
    'responded_at',
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
    'qayd:pos-credit-ack:$invoiceNodeId:$fingerprint',
  );

  static Map<String, dynamic> invoiceEventPayload({
    required String invoiceNodeId,
    required PosCreditInvoiceChatSnapshot snapshot,
  }) {
    if (invoiceNodeId !=
        PosCreditInvoiceChatProtocol.invoiceNodeId(snapshot.invoiceId)) {
      throw const FormatException('Invalid POS credit invoice node id.');
    }
    final payload = <String, dynamic>{
      'schema': invoiceEventSchema,
      'invoice_node_id': invoiceNodeId,
      'invoice_id': snapshot.invoiceId,
      'fingerprint': snapshot.fingerprint,
      'invoice_snapshot': snapshot.toJson(),
    };
    if (utf8.encode(jsonEncode(payload)).length > maxEventPayloadBytes) {
      throw const FormatException('POS credit invoice event is too large.');
    }
    return payload;
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
  }) {
    if (invoiceNodeId !=
            PosCreditInvoiceChatProtocol.invoiceNodeId(invoiceId) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint) ||
        (status != 'accepted' && status != 'rejected')) {
      throw const FormatException('Invalid POS credit invoice acknowledgment.');
    }
    final payload = <String, dynamic>{
      'schema': acknowledgementSchema,
      'invoice_node_id': invoiceNodeId,
      'invoice_id': invoiceId,
      'fingerprint': fingerprint,
      'status': status,
      'responded_at': respondedAt.toUtc().toIso8601String(),
    };
    if (!isValidAcknowledgmentEventPayload(
      payload,
      expectedNodeId: invoiceNodeId,
    )) {
      throw const FormatException('Invalid POS credit invoice acknowledgment.');
    }
    return payload;
  }

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
        DateTime.tryParse(respondedAt) == null ||
        eventInvoiceNodeId != expectedNodeId ||
        eventInvoiceNodeId != invoiceNodeId(invoiceId)) {
      return false;
    }
    return true;
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
    if (utf8.encode(jsonEncode(payload)).length > maxEventPayloadBytes ||
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
        expectedNodeId !=
            PosCreditInvoiceChatProtocol.invoiceNodeId(snapshot.invoiceId) ||
        payload['fingerprint'] != snapshot.fingerprint) {
      throw const FormatException('POS credit invoice fingerprint mismatch.');
    }
    return snapshot;
  }
}
