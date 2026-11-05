import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/domain/entities/pos_financial_sync_event.dart';

Map<String, Object?> saleV1({String eventId = 'e1', int total = 200}) => {
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

Map<String, Object?> saleV2({
  String target = 'device-b',
  Map<String, Object?>? snapshot,
}) => {
  'version': 2,
  'kind': 'sale',
  'owner_user_id': 7,
  'source_device_id': 'device-a',
  'target_device_id': target,
  'event_id': 'e2',
  'aggregate_id': 'invoice-2',
  'idempotency_key': 'idem-e2',
  'currency_code': 'USD',
  'occurred_at': '2026-11-05T00:00:00Z',
  'total_minor': 125,
  'lines': [
    {
      'product_id': 'p1',
      'quantity_scaled': 1250,
      'quantity_scale': 2,
      'unit_price_minor': 10,
      'total_minor': 125,
    },
  ],
  'snapshot': snapshot ?? {'tax_minor': 5, 'discount_minor': 0},
};

void main() {
  test('keeps v1 compatibility and validates a legacy sale', () {
    final json = jsonEncode(saleV1());
    final event = PosFinancialSyncEvent.decode(json);
    expect(event.version, 1);
    expect(event.kind, PosFinancialEventKind.sale);
    expect(event.totalMinor, 200);
    expect(event.lines.single.quantity, 2);
    expect(event.payloadFingerprint, PosFinancialSyncEvent.fingerprint(json));
  });

  test('decodes, validates, and round-trips a v2 event', () {
    final original = saleV2();
    final event = PosFinancialSyncEvent.fromJson(original);
    expect(event.version, 2);
    expect(event.ownerUserId, 7);
    expect(event.sourceDeviceId, 'device-a');
    expect(event.snapshot['tax_minor'], 5);
    final roundTrip = PosFinancialSyncEvent.fromJson(event.toJson());
    expect(roundTrip.toJson(), event.toJson());
    expect(roundTrip.payloadFingerprint, event.payloadFingerprint);
  });

  test('v2 fingerprint ignores only target device and covers snapshot', () {
    final first = PosFinancialSyncEvent.fromJson(saleV2(target: 'device-b'));
    final second = PosFinancialSyncEvent.fromJson(saleV2(target: 'device-c'));
    final changed = PosFinancialSyncEvent.fromJson(
      saleV2(
        target: 'device-c',
        snapshot: {'tax_minor': 6, 'discount_minor': 0},
      ),
    );
    expect(first.payloadFingerprint, second.payloadFingerprint);
    expect(first.payloadFingerprint, isNot(changed.payloadFingerprint));
  });

  test(
    'canonicalizes equivalent UTC timestamp encodings before fingerprint',
    () {
      final wholeSecond = PosFinancialSyncEvent.fromJson({
        ...saleV2(),
        'occurred_at': '2026-11-05T00:00:00Z',
      });
      final explicitMillis = PosFinancialSyncEvent.fromJson({
        ...saleV2(),
        'occurred_at': '2026-11-05T00:00:00.000Z',
      });
      final explicitOffset = PosFinancialSyncEvent.fromJson({
        ...saleV2(),
        'occurred_at': '2026-11-05T00:00:00+00:00',
      });

      expect(explicitMillis.payloadFingerprint, wholeSecond.payloadFingerprint);
      expect(explicitOffset.payloadFingerprint, wholeSecond.payloadFingerprint);
      expect(
        PosFinancialSyncEvent.fromJson(
          explicitMillis.toJson(),
        ).payloadFingerprint,
        wholeSecond.payloadFingerprint,
      );
    },
  );

  test('v2 document totals may include invoice-level adjustments', () {
    final raw = {
      ...saleV2(),
      'total_minor': 120,
      'snapshot': {'cart_discount_minor': 5, 'tax_minor': 0},
    };
    final event = PosFinancialSyncEvent.fromJson(raw);
    expect(event.totalMinor, 120);
    expect(event.lines.single.totalMinor, 125);
  });

  test('collection may have no lines but still requires a positive amount', () {
    final event = PosFinancialSyncEvent.fromJson({
      ...saleV2(),
      'kind': 'collection',
      'total_minor': 50,
      'lines': const [],
      'snapshot': {'account_id': 'customer-1'},
    });
    expect(event.kind, PosFinancialEventKind.collection);
  });

  test('rejects unknown fields, wrong types, and invalid v2 requirements', () {
    final invalid = <Map<String, Object?>>[
      {...saleV2(), 'unexpected': true},
      {...saleV2(), 'owner_user_id': '7'},
      {...saleV2(), 'source_device_id': ''},
      {...saleV2(), 'snapshot': const []},
      {...saleV2(), 'occurred_at': '2026-11-05'},
      {...saleV2(), 'currency_code': 'usd'},
      {
        ...saleV2(),
        'lines': [
          {
            'product_id': 'p1',
            'quantity_scaled': 1,
            'quantity_scale': 10,
            'unit_price_minor': 0,
            'total_minor': 0,
          },
        ],
      },
      {
        ...saleV2(),
        'lines': [
          {
            'product_id': 'p1',
            'quantity_scaled': 1,
            'quantity_scale': 0,
            'unit_price_minor': -1,
            'total_minor': 0,
          },
        ],
      },
    ];
    for (final raw in invalid) {
      expect(() => PosFinancialSyncEvent.fromJson(raw), throwsFormatException);
    }
  });

  test('rejects unsupported kinds, totals, and v2 missing fields', () {
    expect(
      () => PosFinancialSyncEvent.fromJson({...saleV1(), 'kind': 'refund'}),
      throwsFormatException,
    );
    expect(
      () => PosFinancialSyncEvent.fromJson({...saleV1(), 'total_minor': 201}),
      throwsFormatException,
    );
    expect(
      () => PosFinancialSyncEvent.fromJson({...saleV1(), 'version': 2}),
      throwsFormatException,
    );
    final missingSnapshot = Map<String, Object?>.from(saleV2())
      ..remove('snapshot');
    expect(
      () => PosFinancialSyncEvent.fromJson(missingSnapshot),
      throwsFormatException,
    );
  });
}
