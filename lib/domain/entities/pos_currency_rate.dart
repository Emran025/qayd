import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';

/// Fixed-point scale used for all stored FX rates.
const int posCurrencyRateScale = 100000000;

/// An explicitly recorded, directed exchange rate.
///
/// [rateScaled] represents target major units per one source major unit,
/// multiplied by [posCurrencyRateScale]. Rate records are immutable; a changed
/// quote is represented by a new record.
final class PosCurrencyRate {
  PosCurrencyRate({
    required this.id,
    required this.fromCurrency,
    required this.toCurrency,
    required this.rateScaled,
    required DateTime effectiveAt,
    required DateTime recordedAt,
    required DateTime createdAt,
    this.note,
  })  : effectiveAt = effectiveAt.toUtc(),
        recordedAt = recordedAt.toUtc(),
        createdAt = createdAt.toUtc() {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (fromCurrency.code.trim().isEmpty || toCurrency.code.trim().isEmpty) {
      throw ArgumentError('Currency codes must not be empty');
    }
    if (fromCurrency == toCurrency) {
      throw ArgumentError('A stored FX rate must have distinct currencies');
    }
    if (rateScaled <= 0) {
      throw ArgumentError.value(rateScaled, 'rateScaled', 'must be positive');
    }
    if (note != null && note!.length > 1000) {
      throw ArgumentError.value(
          note, 'note', 'must be at most 1000 characters');
    }
  }

  final String id;
  final CurrencyCode fromCurrency;
  final CurrencyCode toCurrency;
  final int rateScaled;
  final DateTime effectiveAt;
  final DateTime recordedAt;
  final DateTime createdAt;
  final String? note;
}

/// A rate selected for a requested conversion direction.
///
/// The stored directed pair and rate remain available even when the requested
/// direction uses the reverse quote, so audit/display code can distinguish an
/// inverted lookup from a directly stored quote.
final class PosCurrencyRateQuote {
  const PosCurrencyRateQuote({
    required this.rateId,
    required this.storedFromCurrency,
    required this.storedToCurrency,
    required this.storedRateScaled,
    required this.requestedFromCurrency,
    required this.requestedToCurrency,
    required this.effectiveAt,
    required this.recordedAt,
    required this.createdAt,
    required this.isInverted,
    this.note,
  });

  factory PosCurrencyRateQuote.fromRate({
    required PosCurrencyRate rate,
    required CurrencyCode requestedFromCurrency,
    required CurrencyCode requestedToCurrency,
    required bool isInverted,
  }) {
    return PosCurrencyRateQuote(
      rateId: rate.id,
      storedFromCurrency: rate.fromCurrency,
      storedToCurrency: rate.toCurrency,
      storedRateScaled: rate.rateScaled,
      requestedFromCurrency: requestedFromCurrency,
      requestedToCurrency: requestedToCurrency,
      effectiveAt: rate.effectiveAt,
      recordedAt: rate.recordedAt,
      createdAt: rate.createdAt,
      isInverted: isInverted,
      note: rate.note,
    );
  }

  final String rateId;
  final CurrencyCode storedFromCurrency;
  final CurrencyCode storedToCurrency;
  final int storedRateScaled;
  final CurrencyCode requestedFromCurrency;
  final CurrencyCode requestedToCurrency;
  final DateTime effectiveAt;
  final DateTime recordedAt;
  final DateTime createdAt;
  final bool isInverted;
  final String? note;

  /// Reapplies this immutable quote to an amount using exact integer math.
  Money convert(Money sourceAmount) {
    if (sourceAmount.currency != requestedFromCurrency ||
        storedRateScaled <= 0) {
      throw ArgumentError('Quote does not match the source currency');
    }
    final sourceScale = _pow10(sourceAmount.currency.fractionalDigits);
    final targetScale = _pow10(requestedToCurrency.fractionalDigits);
    final numerator = BigInt.from(sourceAmount.minorUnits) *
        (isInverted
            ? BigInt.from(posCurrencyRateScale)
            : BigInt.from(storedRateScaled)) *
        targetScale;
    final denominator = sourceScale *
        (isInverted
            ? BigInt.from(storedRateScaled)
            : BigInt.from(posCurrencyRateScale));
    final rounded = _roundHalfUp(numerator, denominator);
    if (rounded < _minInt64 || rounded > _maxInt64) {
      throw RangeError('Currency conversion exceeds the supported amount');
    }
    return Money.fromMinorUnits(rounded.toInt(), requestedToCurrency);
  }

  static final BigInt _maxInt64 = BigInt.parse('9223372036854775807');
  static final BigInt _minInt64 = -_maxInt64 - BigInt.one;

  static BigInt _pow10(int digits) {
    if (digits < 0 || digits > 18) {
      throw ArgumentError.value(
        digits,
        'fractionalDigits',
        'must be between 0 and 18',
      );
    }
    return BigInt.from(10).pow(digits);
  }

  static BigInt _roundHalfUp(BigInt numerator, BigInt denominator) {
    final negative = numerator.isNegative;
    final absolute = numerator.abs();
    var quotient = (absolute + (denominator ~/ BigInt.from(2))) ~/ denominator;
    if (negative) quotient = -quotient;
    return quotient;
  }
}
