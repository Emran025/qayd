import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/repositories/pos_currency_rate_repository.dart';
import 'package:qayd/domain/services/pos_currency_converter.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';

class _FakeRates implements PosCurrencyRateRepository {
  _FakeRates(this.quote);

  final PosCurrencyRateQuote? quote;

  @override
  Future<Result<void>> save(PosCurrencyRate rate) async => const Success(null);

  @override
  Future<Result<PosCurrencyRateQuote?>> latestQuote({
    required CurrencyCode fromCurrency,
    required CurrencyCode toCurrency,
  }) async =>
      Success(quote);

  @override
  Future<Result<List<PosCurrencyRate>>> listHistory({
    CurrencyCode? fromCurrency,
    CurrencyCode? toCurrency,
    int? limit,
  }) async =>
      const Success(<PosCurrencyRate>[]);
}

CurrencyCode _currency(String code, int digits) => CurrencyCode(
      code: code,
      nameAr: code,
      symbol: code,
      fractionalDigits: digits,
    );

PosCurrencyRate _rate({required int scaled}) => PosCurrencyRate(
      id: 'rate-1',
      fromCurrency: _currency('USD', 2),
      toCurrency: _currency('KWD', 3),
      rateScaled: scaled,
      effectiveAt: DateTime.utc(2026, 1, 1),
      recordedAt: DateTime.utc(2026, 1, 2),
      createdAt: DateTime.utc(2026, 1, 2),
    );

void main() {
  test('validates positive fixed-point rates and rejects same pair', () {
    expect(() => _rate(scaled: 0), throwsArgumentError);
    expect(
      () => PosCurrencyRate(
        id: 'same',
        fromCurrency: _currency('USD', 2),
        toCurrency: _currency('USD', 2),
        rateScaled: posCurrencyRateScale,
        effectiveAt: DateTime.utc(2026),
        recordedAt: DateTime.utc(2026),
        createdAt: DateTime.utc(2026),
      ),
      throwsArgumentError,
    );
  });

  test(
      'converts with source and target fractional digits using half-up integer rounding',
      () async {
    final usd = _currency('USD', 2);
    final kwd = _currency('KWD', 3);
    final rate = _rate(scaled: 125000000); // 1 USD = 1.25 KWD
    final quote = PosCurrencyRateQuote.fromRate(
      rate: rate,
      requestedFromCurrency: usd,
      requestedToCurrency: kwd,
      isInverted: false,
    );

    final result = await PosCurrencyConverter(_FakeRates(quote)).convert(
      Money.fromMinorUnits(100, usd),
      toCurrency: kwd,
    );

    expect(result, isA<Success<Money>>());
    expect((result as Success<Money>).value.minorUnits, 1250);
  });

  test('inverted quote uses reciprocal without floating point', () async {
    final usd = _currency('USD', 2);
    final eur = _currency('EUR', 2);
    final stored = PosCurrencyRate(
      id: 'rate-2',
      fromCurrency: eur,
      toCurrency: usd,
      rateScaled: 125000000,
      effectiveAt: DateTime.utc(2026),
      recordedAt: DateTime.utc(2026),
      createdAt: DateTime.utc(2026),
    );
    final quote = PosCurrencyRateQuote.fromRate(
      rate: stored,
      requestedFromCurrency: usd,
      requestedToCurrency: eur,
      isInverted: true,
    );

    final result = await PosCurrencyConverter(_FakeRates(quote)).convert(
      Money.fromMinorUnits(125, usd),
      toCurrency: eur,
    );

    expect((result as Success<Money>).value.minorUnits, 100);
  });

  test('same currency is identity and missing quote does not triangulate',
      () async {
    final usd = _currency('USD', 2);
    final identity = await PosCurrencyConverter(_FakeRates(null)).convert(
      Money.fromMinorUnits(123, usd),
      toCurrency: usd,
    );
    expect((identity as Success<Money>).value.minorUnits, 123);

    final missing = await PosCurrencyConverter(_FakeRates(null)).convert(
      Money.fromMinorUnits(100, usd),
      toCurrency: _currency('JPY', 0),
    );
    expect(missing, isA<FailureResult<Money>>());
  });
}
