import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/repositories/sqlite_pos_currency_rate_repository.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

CurrencyCode _currency(String code) => CurrencyCode(
      code: code,
      nameAr: code,
      symbol: code,
    );

PosCurrencyRate _rate({
  required String id,
  required String from,
  required String to,
  required int scaled,
  required DateTime recordedAt,
}) =>
    PosCurrencyRate(
      id: id,
      fromCurrency: _currency(from),
      toCurrency: _currency(to),
      rateScaled: scaled,
      effectiveAt: recordedAt,
      recordedAt: recordedAt,
      createdAt: recordedAt,
    );

void main() {
  late Database db;
  late SqlitePosCurrencyRateRepository repository;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE pos_currency_rates (
        id TEXT PRIMARY KEY,
        from_currency_code TEXT NOT NULL,
        to_currency_code TEXT NOT NULL,
        rate_scaled INTEGER NOT NULL,
        effective_at TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    repository = SqlitePosCurrencyRateRepository(db);
  });
  tearDown(() => db.close());

  test('saves append-only rows and selects newest direct quote', () async {
    final older = _rate(
      id: 'old',
      from: 'USD',
      to: 'EUR',
      scaled: 110000000,
      recordedAt: DateTime.utc(2026, 1, 1),
    );
    final newer = _rate(
      id: 'new',
      from: 'USD',
      to: 'EUR',
      scaled: 120000000,
      recordedAt: DateTime.utc(2026, 1, 2),
    );
    expect((await repository.save(older)).isSuccess, isTrue);
    expect((await repository.save(newer)).isSuccess, isTrue);

    final quote = await repository.latestQuote(
      fromCurrency: _currency('USD'),
      toCurrency: _currency('EUR'),
    );
    final directQuote = (quote as Success<PosCurrencyRateQuote?>).value!;
    expect(directQuote.rateId, 'new');
    expect(directQuote.isInverted, isFalse);

    final history = await repository.listHistory();
    expect((history as Success).value.map((r) => r.id), ['new', 'old']);
  });

  test('uses reverse pair only when direct pair is absent', () async {
    await repository.save(_rate(
      id: 'reverse',
      from: 'EUR',
      to: 'USD',
      scaled: 125000000,
      recordedAt: DateTime.utc(2026, 1, 2),
    ));

    final quote = await repository.latestQuote(
      fromCurrency: _currency('USD'),
      toCurrency: _currency('EUR'),
    );
    final reverseQuote = (quote as Success<PosCurrencyRateQuote?>).value!;
    expect(reverseQuote.rateId, 'reverse');
    expect(reverseQuote.isInverted, isTrue);
  });
}
