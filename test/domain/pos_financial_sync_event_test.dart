import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/domain/entities/pos_financial_sync_event.dart';

Map<String, Object?> sale({String eventId = 'e1', int total = 200}) => {
  'version': 1,
  'kind': 'sale',
  'event_id': eventId,
  'aggregate_id': 'invoice-1',
  'idempotency_key': 'idem-$eventId',
  'currency_code': 'USD',
  'occurred_at': '2026-11-05T00:00:00Z',
  'total_minor': total,
  'lines': [
    {
      'product_id': 'p1',
      'quantity': 2,
      'unit_price_minor': 100,
      'total_minor': total,
    },
  ],
};

void main() {
  test('decodes and validates a sale before application', () {
    final json = jsonEncode(sale());
    final event = PosFinancialSyncEvent.decode(json);
    expect(event.kind, PosFinancialEventKind.sale);
    expect(event.totalMinor, 200);
    expect(event.lines.single.quantity, 2);
    expect(event.payloadFingerprint, PosFinancialSyncEvent.fingerprint(json));
  });

  test('rejects unknown kinds, malformed totals, and unsupported versions', () {
    expect(
      () => PosFinancialSyncEvent.fromJson({
        ...sale(),
        'kind': 'refund',
      }, payloadFingerprint: 'fp'),
      throwsFormatException,
    );
    expect(
      () => PosFinancialSyncEvent.fromJson({
        ...sale(),
        'total_minor': 201,
      }, payloadFingerprint: 'fp'),
      throwsFormatException,
    );
    expect(
      () => PosFinancialSyncEvent.fromJson({
        ...sale(),
        'version': 2,
      }, payloadFingerprint: 'fp'),
      throwsFormatException,
    );
  });

  test(
    'collection is allowed without lines but still requires a positive amount',
    () {
      final event = PosFinancialSyncEvent.fromJson({
        ...sale(),
        'kind': 'collection',
        'total_minor': 50,
        'lines': const [],
        'account_id': 'customer-1',
      }, payloadFingerprint: 'fp');
      expect(event.kind, PosFinancialEventKind.collection);
      expect(event.accountId, 'customer-1');
    },
  );
}
