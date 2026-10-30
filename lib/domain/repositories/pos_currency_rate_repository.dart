import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';

/// Append-only persistence contract for explicitly entered FX rates.
abstract interface class PosCurrencyRateRepository {
  /// Persists a new rate record without replacing an existing record.
  Future<Result<void>> save(PosCurrencyRate rate);

  /// Finds the newest recorded direct quote, or reverse quote if no direct one exists.
  Future<Result<PosCurrencyRateQuote?>> latestQuote({
    required CurrencyCode fromCurrency,
    required CurrencyCode toCurrency,
  });

  /// Lists immutable rate history, newest recorded entries first.
  Future<Result<List<PosCurrencyRate>>> listHistory({
    CurrencyCode? fromCurrency,
    CurrencyCode? toCurrency,
    int? limit,
  });
}
