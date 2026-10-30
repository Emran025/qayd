import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/repositories/pos_currency_rate_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';

/// Result of converting one amount with the exact quote used for the decision.
final class PosCurrencyConversion {
  const PosCurrencyConversion({
    required this.sourceAmount,
    required this.targetAmount,
    required this.rateSnapshot,
  });

  final Money sourceAmount;
  final Money targetAmount;

  /// Null only for an identity conversion where no exchange-rate record was
  /// needed.
  final PosCurrencyRateQuote? rateSnapshot;
}

/// Converts Money using an explicitly recorded rate and integer arithmetic.
final class PosCurrencyConverter {
  const PosCurrencyConverter(this._repository);

  final PosCurrencyRateRepository _repository;

  Future<Result<Money>> convert(
    Money amount, {
    required CurrencyCode toCurrency,
  }) async {
    final result = await convertWithSnapshot(amount, toCurrency: toCurrency);
    if (result.isFailure) return FailureResult(result.failureOrNull!);
    return Success(result.valueOrNull!.targetAmount);
  }

  Future<Result<PosCurrencyConversion>> convertWithSnapshot(
    Money amount, {
    required CurrencyCode toCurrency,
  }) async {
    if (amount.currency == toCurrency) {
      return Success(PosCurrencyConversion(
        sourceAmount: amount,
        targetAmount: Money.fromMinorUnits(amount.minorUnits, toCurrency),
        rateSnapshot: null,
      ));
    }

    final quoteResult = await _repository.latestQuote(
      fromCurrency: amount.currency,
      toCurrency: toCurrency,
    );
    if (quoteResult.isFailure) {
      return FailureResult(quoteResult.failureOrNull!);
    }
    final quote = quoteResult.valueOrNull;
    if (quote == null) {
      return const FailureResult(ValidationFailure(
        messageAr: 'لا يوجد سعر صرف مسجل للعملتين المطلوبتين.',
        code: 'pos_currency_rate_missing',
      ));
    }
    if (quote.requestedFromCurrency != amount.currency ||
        quote.requestedToCurrency != toCurrency ||
        quote.storedRateScaled <= 0) {
      return const FailureResult(ValidationFailure(
        messageAr: 'بيانات سعر الصرف غير متوافقة مع العملتين المطلوبتين.',
        code: 'pos_currency_rate_invalid',
      ));
    }

    try {
      final converted = quote.convert(amount);
      return Success(PosCurrencyConversion(
        sourceAmount: amount,
        targetAmount: converted,
        rateSnapshot: quote,
      ));
    } on RangeError {
      return const FailureResult(ValidationFailure(
        messageAr: 'قيمة التحويل تتجاوز الحد المسموح.',
        code: 'pos_currency_conversion_overflow',
      ));
    } on ArgumentError {
      return const FailureResult(ValidationFailure(
        messageAr: 'بيانات سعر الصرف غير متوافقة مع العملتين المطلوبتين.',
        code: 'pos_currency_rate_invalid',
      ));
    }
  }
}
