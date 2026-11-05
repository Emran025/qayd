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
    if (value is! String) return null;
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

final class PosFinancialSyncLine {
  const PosFinancialSyncLine({
    required this.productId,
    required this.quantityScaled,
    required this.quantityScale,
    required this.unitPriceMinor,
    required this.totalMinor,
  });

  final String productId;
  final int quantityScaled;
  final int quantityScale;
  final int unitPriceMinor;
  final int totalMinor;

  /// v1 compatibility aliases.
  int get quantity => quantityScaled;

  factory PosFinancialSyncLine.fromJson(Object? raw, {int version = 2}) {
    if (raw is! Map) throw const FormatException('line must be an object');
    final map = raw.cast<Object?, Object?>();
    final expected = version == 1
        ? {'product_id', 'quantity', 'unit_price_minor', 'total_minor'}
        : {
            'product_id',
            'quantity_scaled',
            'quantity_scale',
            'unit_price_minor',
            'total_minor',
          };
    _rejectUnknown(map.keys, expected, 'line');

    String text(String key) {
      final value = map[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('line.$key is required');
      }
      return value.trim();
    }

    int integer(String key, {required bool positive}) {
      final value = map[key];
      if (value is! int || (positive ? value <= 0 : value < 0)) {
        throw FormatException('line.$key has an invalid amount');
      }
      return value;
    }

    final quantity = integer(
      version == 1 ? 'quantity' : 'quantity_scaled',
      positive: true,
    );
    final scale = version == 1 ? 0 : integer('quantity_scale', positive: false);
    if (scale > 9)
      throw const FormatException('line.quantity_scale must be 0..9');
    return PosFinancialSyncLine(
      productId: text('product_id'),
      quantityScaled: quantity,
      quantityScale: scale,
      unitPriceMinor: integer('unit_price_minor', positive: version == 1),
      totalMinor: integer('total_minor', positive: version == 1),
    );
  }

  Map<String, Object?> toJson({int version = 2}) => version == 1
      ? {
          'product_id': productId,
          'quantity': quantityScaled,
          'unit_price_minor': unitPriceMinor,
          'total_minor': totalMinor,
        }
      : {
          'product_id': productId,
          'quantity_scaled': quantityScaled,
          'quantity_scale': quantityScale,
          'unit_price_minor': unitPriceMinor,
          'total_minor': totalMinor,
        };
}

/// Strict, plaintext-after-decryption contract for financial POS replication.
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
    this.ownerUserId,
    this.sourceDeviceId,
    this.targetDeviceId,
    Map<String, Object?>? snapshot,
    this.accountId,
    this.version = 2,
  }) : snapshot = snapshot ?? const <String, Object?>{};

  final int version;
  final PosFinancialEventKind kind;
  final String eventId;
  final String aggregateId;
  final String idempotencyKey;
  final String currencyCode;
  final DateTime occurredAt;
  final int totalMinor;
  final List<PosFinancialSyncLine> lines;
  final int? ownerUserId;
  final String? sourceDeviceId;
  final String? targetDeviceId;
  final Map<String, Object?> snapshot;
  final String? accountId;
  final String payloadFingerprint;

  static PosFinancialSyncEvent decode(String json) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('financial POS event is not valid JSON');
    }
    if (decoded is! Map) {
      throw const FormatException('financial POS event must be an object');
    }
    final raw = decoded.cast<String, Object?>();
    final version = raw['version'];
    final payloadFp = version == 2
        ? fingerprintFor(raw)
        : PosFinancialSyncEvent.fingerprint(json);
    return fromJson(raw, payloadFingerprint: payloadFp);
  }

  static PosFinancialSyncEvent fromJson(
    Map<String, Object?> raw, {
    String? payloadFingerprint,
  }) {
    final version = raw['version'];
    if (version is! int || (version != 1 && version != 2)) {
      throw const FormatException('unsupported POS financial event version');
    }
    final eventVersion = version;
    final allowed = version == 1
        ? {
            'version',
            'kind',
            'event_id',
            'aggregate_id',
            'idempotency_key',
            'currency_code',
            'occurred_at',
            'total_minor',
            'lines',
            'account_id',
          }
        : {
            'version',
            'kind',
            'owner_user_id',
            'source_device_id',
            'target_device_id',
            'event_id',
            'aggregate_id',
            'idempotency_key',
            'currency_code',
            'occurred_at',
            'total_minor',
            'lines',
            'snapshot',
          };
    _rejectUnknown(raw.keys, allowed, 'event');
    final kind = PosFinancialEventKind.parse(raw['kind']);
    if (kind == null)
      throw const FormatException('unsupported POS financial event kind');

    String requiredText(String key) {
      final value = raw[key];
      if (value is! String || value.trim().isEmpty)
        throw FormatException('$key is required');
      return value.trim();
    }

    int? positiveInt(String key) {
      final value = raw[key];
      if (value is! int || value <= 0)
        throw FormatException('$key must be positive');
      return value;
    }

    final occurredText = requiredText('occurred_at');
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
    ).hasMatch(occurredText)) {
      throw const FormatException('occurred_at is not ISO-8601');
    }
    final occurredAt = DateTime.tryParse(occurredText)?.toUtc();
    if (occurredAt == null)
      throw const FormatException('occurred_at is invalid');
    final currency = requiredText('currency_code');
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const FormatException('currency_code must be ISO uppercase');
    }

    final rawLines = raw['lines'];
    if (rawLines is! List)
      throw const FormatException('lines must be an array');
    final lines = rawLines
        .map(
          (line) => PosFinancialSyncLine.fromJson(line, version: eventVersion),
        )
        .toList(growable: false);
    if (kind != PosFinancialEventKind.collection && lines.isEmpty) {
      throw const FormatException('financial document requires lines');
    }
    if (kind == PosFinancialEventKind.collection && lines.isNotEmpty) {
      throw const FormatException('collection must not carry product lines');
    }
    final total = raw['total_minor'];
    if (total is! int || total <= 0)
      throw const FormatException('total_minor must be positive');
    if (eventVersion == 1 &&
        kind != PosFinancialEventKind.collection &&
        lines.fold<int>(0, (s, l) => s + l.totalMinor) != total) {
      throw const FormatException('document total does not match lines');
    }

    Map<String, Object?>? snapshot;
    int? owner;
    String? source;
    String? target;
    if (version == 2) {
      owner = positiveInt('owner_user_id');
      source = requiredText('source_device_id');
      target = requiredText('target_device_id');
      final value = raw['snapshot'];
      if (value is! Map)
        throw const FormatException('snapshot must be an object');
      snapshot = _jsonObject(value, 'snapshot');
    }
    final eventId = requiredText('event_id');
    final aggregateId = requiredText('aggregate_id');
    final idempotencyKey = requiredText('idempotency_key');
    final canonicalFingerprint = eventVersion == 2
        ? fingerprintFor({
            'version': eventVersion,
            'kind': kind.name,
            'owner_user_id': owner,
            'source_device_id': source,
            'target_device_id': target,
            'event_id': eventId,
            'aggregate_id': aggregateId,
            'idempotency_key': idempotencyKey,
            'currency_code': currency,
            'occurred_at': _iso8601(occurredAt),
            'total_minor': total,
            'lines': lines.map((line) => line.toJson(version: 2)).toList(),
            'snapshot': snapshot,
          })
        : (payloadFingerprint ?? '');
    return PosFinancialSyncEvent(
      version: eventVersion,
      kind: kind,
      eventId: eventId,
      aggregateId: aggregateId,
      idempotencyKey: idempotencyKey,
      currencyCode: currency,
      occurredAt: occurredAt,
      totalMinor: total,
      lines: lines,
      ownerUserId: owner,
      sourceDeviceId: source,
      targetDeviceId: target,
      snapshot: snapshot ?? const <String, Object?>{},
      accountId: _optionalText(raw, 'account_id'),
      payloadFingerprint: canonicalFingerprint,
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'kind': kind.name,
    if (version == 2) ...{
      'owner_user_id': ownerUserId,
      'source_device_id': sourceDeviceId,
      'target_device_id': targetDeviceId,
    },
    'event_id': eventId,
    'aggregate_id': aggregateId,
    'idempotency_key': idempotencyKey,
    'currency_code': currencyCode,
    'occurred_at': _iso8601(occurredAt),
    'total_minor': totalMinor,
    'lines': lines.map((line) => line.toJson(version: version)).toList(),
    if (version == 2) 'snapshot': snapshot,
    if (version == 1 && accountId != null) 'account_id': accountId,
  };

  static String fingerprintFor(Map<String, Object?> raw) => sha256
      .convert(utf8.encode(_canonicalJson(raw, omitTargetDevice: true)))
      .toString();

  static String fingerprint(String payload) =>
      sha256.convert(utf8.encode(payload)).toString();
}

String? _optionalText(Map<String, Object?> raw, String key) {
  final value = raw[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value.trim();
}

String _iso8601(DateTime value) {
  final text = value.toIso8601String();
  return text.endsWith('.000Z')
      ? '${text.substring(0, text.length - 5)}Z'
      : text;
}

void _rejectUnknown(Iterable<Object?> keys, Set<String> allowed, String where) {
  for (final key in keys) {
    if (key is! String || !allowed.contains(key))
      throw FormatException('$where has unknown field: $key');
  }
}

Map<String, Object?> _jsonObject(Map raw, String path) {
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String)
      throw FormatException('$path has a non-string key');
    result[entry.key as String] = _jsonValue(entry.value, '$path.${entry.key}');
  }
  return result;
}

Object? _jsonValue(Object? value, String path) {
  if (value == null || value is String || value is bool || value is num)
    return value;
  if (value is Map) return _jsonObject(value, path);
  if (value is List)
    return value.map((v) => _jsonValue(v, path)).toList(growable: false);
  throw FormatException('$path contains an invalid JSON value');
}

String _canonicalJson(Object? value, {bool omitTargetDevice = false}) {
  if (value is Map) {
    final entries = <String>[];
    for (final entry in value.entries) {
      if (entry.key is! String)
        throw const FormatException('object key must be a string');
      if (omitTargetDevice && entry.key == 'target_device_id') continue;
      entries.add(entry.key as String);
    }
    entries.sort();
    return '{${entries.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key], omitTargetDevice: false)}').join(',')}}';
  }
  if (value is List)
    return '[${value.map((v) => _canonicalJson(v)).join(',')}]';
  return jsonEncode(value);
}
