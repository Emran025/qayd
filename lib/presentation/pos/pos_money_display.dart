import 'package:qayd/core/utils/money_formatter.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';

/// Formats POS monetary values using the currency's actual fractional scale.
String formatPosMoney(Money money) {
  final divisor = _pow10(money.fractionalDigits);
  final major = money.minorUnits / divisor;
  final value = MoneyFormatter.formatDecimal(
    major,
    locale: 'en',
    minimumFractionDigits: money.fractionalDigits,
    maximumFractionDigits: money.fractionalDigits,
  );
  return '$value ${money.currency.symbol}';
}

String formatPosMinor(int minorUnits, CurrencyCode currency) =>
    formatPosMoney(Money.fromMinorUnits(minorUnits, currency));

int _pow10(int digits) {
  var value = 1;
  for (var i = 0; i < digits; i++) {
    value *= 10;
  }
  return value;
}
