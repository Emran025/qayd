import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/pos_currency_rate_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';

/// Records a new, immutable, explicitly entered directed FX rate.
///
/// Updating a rate means appending a new record; existing rates remain intact
/// for transactions that already reference them.
final class RecordPosCurrencyRateUseCase {
  RecordPosCurrencyRateUseCase({
    required PosCurrencyRateRepository rateRepository,
    required CurrencyRepository currencyRepository,
    required GovernanceWriteGuard writeGuard,
    required IdGenerator idGenerator,
  })  : _rates = rateRepository,
        _currencies = currencyRepository,
        _writeGuard = writeGuard,
        _idGenerator = idGenerator;

  final PosCurrencyRateRepository _rates;
  final CurrencyRepository _currencies;
  final GovernanceWriteGuard _writeGuard;
  final IdGenerator _idGenerator;

  Future<Result<PosCurrencyRate>> call({
    required String fromCurrencyCode,
    required String toCurrencyCode,
    required int rateScaled,
    required DateTime effectiveAt,
    required DateTime recordedAt,
    String? note,
  }) async {
    final gate = await _writeGuard.assertWritesPermitted();
    if (gate.isFailure) return FailureResult(gate.failureOrNull!);
    final fromResult = await _currencies.getByCode(fromCurrencyCode.trim());
    if (fromResult.isFailure) return FailureResult(fromResult.failureOrNull!);
    final toResult = await _currencies.getByCode(toCurrencyCode.trim());
    if (toResult.isFailure) return FailureResult(toResult.failureOrNull!);
    final from = fromResult.valueOrNull;
    final to = toResult.valueOrNull;
    if (from == null || to == null || !from.isActive || !to.isActive) {
      return const FailureResult(ValidationFailure(
        messageAr: 'يجب اختيار عملتين نشطتين لتسجيل سعر الصرف.',
        code: 'pos_currency_rate_currency_unavailable',
      ));
    }
    try {
      final rate = PosCurrencyRate(
        id: _idGenerator.next(),
        fromCurrency: from,
        toCurrency: to,
        rateScaled: rateScaled,
        effectiveAt: effectiveAt,
        recordedAt: recordedAt,
        createdAt: recordedAt,
        note: note?.trim().isEmpty == true ? null : note?.trim(),
      );
      final saveResult = await _rates.save(rate);
      if (saveResult.isFailure) return FailureResult(saveResult.failureOrNull!);
      return Success(rate);
    } on ArgumentError catch (error) {
      return FailureResult(ValidationFailure(
        messageAr: error.message?.toString() ?? 'سعر الصرف غير صالح.',
        code: 'pos_currency_rate_invalid',
      ));
    }
  }
}

/// Reads immutable directed exchange-rate history for the management screen.
final class ListPosCurrencyRateHistoryUseCase {
  const ListPosCurrencyRateHistoryUseCase(this._rates);

  final PosCurrencyRateRepository _rates;

  Future<Result<List<PosCurrencyRate>>> call({
    String? fromCurrencyCode,
    String? toCurrencyCode,
    int? limit,
  }) {
    return _rates.listHistory(
      fromCurrency:
          fromCurrencyCode == null ? null : _codeOnly(fromCurrencyCode),
      toCurrency: toCurrencyCode == null ? null : _codeOnly(toCurrencyCode),
      limit: limit,
    );
  }

  static CurrencyCode _codeOnly(String code) => CurrencyCode(
        code: code,
        nameAr: code,
        symbol: code,
      );
}
