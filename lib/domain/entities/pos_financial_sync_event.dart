import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Financial POS event kinds supported by the safe sync boundary.
enum PosFinancialEventKind {
  sale,
  purchase,
  salesReturn,
  purchaseReturn,
  collection;

  static PosFinancialEventKind? parse(Object? value) {
    final name = value is String ? value : null;
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

final class PosFinancialSyncLine {
  const PosFinancialSyncLine({
    required this.productId,
    required this.quantity,
    required this.unitPriceMinor,
    required this.totalMinor,
  });

  final String productId;
  final int quantity;
  final int unitPriceMinor;
  final int totalMinor;

  factory PosFinancialSyncLine.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('line must be an object');
    String text(String key) {
      final value = raw[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('line.$key is required');
      }
      return value;
    }

    int positiveInt(String key) {
      final value = raw[key];
      if (value is! int || value <= 0) {
        throw FormatException('line.$key must be a positive integer');
      }
      return value;
    }

    final quantity = positiveInt('quantity');
    final unitPrice = positiveInt('unit_price_minor');
    final total = positiveInt('total_minor');
    if (quantity * unitPrice != total) {
      throw const FormatException(
        'line total does not match quantity * unit price',
      );
    }
    return PosFinancialSyncLine(
      productId: text('product_id'),
      quantity: quantity,
      unitPriceMinor: unitPrice,
      totalMinor: total,
    );
  }
}

/// Strict, plaintext-after-decryption contract for financial POS replication.
/// Unknown kinds and malformed fields fail closed before any domain write.
final class PosFinancialSyncEvent {
  const PosFinancialSyncEvent({
    required this.kind,
    required this.eventId,
    required this.aggregateId,
    required this.idempotencyKey,
    required this.currencyCode,
    required this.occurredAt,
    required this.totalMinor,
    required this.lines,
    required this.payloadFingerprint,
    this.accountId,
  });

  final PosFinancialEventKind kind;
  final String eventId;
  final String aggregateId;
  final String idempotencyKey;
  final String currencyCode;
  final DateTime occurredAt;
  final int totalMinor;
  final List<PosFinancialSyncLine> lines;
  final String? accountId;
  final String payloadFingerprint;

  static PosFinancialSyncEvent decode(String json) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('financial POS event is not valid JSON');
    }
    if (decoded is! Map)
      throw const FormatException('financial POS event must be an object');
    return fromJson(
      decoded.cast<String, Object?>(),
      payloadFingerprint: fingerprint(json),
    );
  }

  static PosFinancialSyncEvent fromJson(
    Map<String, Object?> raw, {
    required String payloadFingerprint,
  }) {
    final kind = PosFinancialEventKind.parse(raw['kind']);
    if (kind == null)
      throw const FormatException('unsupported POS financial event kind');
    String requiredText(String key) {
      final value = raw[key];
      if (value is! String || value.trim().isEmpty)
        throw FormatException('$key is required');
      return value;
    }

    final version = raw['version'];
    if (version != 1)
      throw const FormatException('unsupported POS financial event version');
    final occurredAt = DateTime.tryParse(requiredText('occurred_at'))?.toUtc();
    if (occurredAt == null)
      throw const FormatException('occurred_at is invalid');
    final currency = requiredText('currency_code');
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const FormatException('currency_code must be ISO uppercase');
    }
    final rawLines = raw['lines'];
    final lines = rawLines is List
        ? rawLines.map(PosFinancialSyncLine.fromJson).toList(growable: false)
        : const <PosFinancialSyncLine>[];
    if (kind != PosFinancialEventKind.collection && lines.isEmpty) {
      throw const FormatException('financial document requires lines');
    }
    final total = raw['total_minor'];
    if (total is! int || total <= 0)
      throw const FormatException('total_minor must be positive');
    final calculated = lines.fold<int>(0, (sum, line) => sum + line.totalMinor);
    if (kind != PosFinancialEventKind.collection && calculated != total) {
      throw const FormatException('document total does not match lines');
    }
    return PosFinancialSyncEvent(
      kind: kind,
      eventId: requiredText('event_id'),
      aggregateId: requiredText('aggregate_id'),
      idempotencyKey: requiredText('idempotency_key'),
      currencyCode: currency,
      occurredAt: occurredAt,
      totalMinor: total,
      lines: lines,
      accountId: raw['account_id'] as String?,
      payloadFingerprint: payloadFingerprint,
    );
  }

  static String fingerprint(String payload) =>
      sha256.convert(utf8.encode(payload)).toString();
}
