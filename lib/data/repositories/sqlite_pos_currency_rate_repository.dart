import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/pos_currency_rate_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// SQLite adapter for the future `pos_currency_rates` table.
///
/// This adapter only inserts and reads rows; it intentionally has no update or
/// delete operation so rate history remains append-only.
final class SqlitePosCurrencyRateRepository
    implements PosCurrencyRateRepository {
  SqlitePosCurrencyRateRepository(this._db, [this._currencyRepository]);

  final Database _db;
  final CurrencyRepository? _currencyRepository;

  @override
  Future<Result<void>> save(PosCurrencyRate rate) async {
    try {
      await _db.insert(
        'pos_currency_rates',
        _toRow(rate),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return const Success(null);
    } on DatabaseException {
      return const FailureResult(
          DatabaseFailure(messageAr: 'تعذر حفظ سعر الصرف.'));
    } catch (_) {
      return const FailureResult(
          DatabaseFailure(messageAr: 'تعذر حفظ سعر الصرف.'));
    }
  }

  @override
  Future<Result<PosCurrencyRateQuote?>> latestQuote({
    required CurrencyCode fromCurrency,
    required CurrencyCode toCurrency,
  }) async {
    try {
      final direct = await _queryLatest(fromCurrency.code, toCurrency.code);
      if (direct != null) {
        return Success(PosCurrencyRateQuote.fromRate(
          rate: await _fromRow(
            direct,
            fromCurrency: fromCurrency,
            toCurrency: toCurrency,
          ),
          requestedFromCurrency: fromCurrency,
          requestedToCurrency: toCurrency,
          isInverted: false,
        ));
      }
      final reverse = await _queryLatest(toCurrency.code, fromCurrency.code);
      if (reverse == null) return const Success(null);
      return Success(PosCurrencyRateQuote.fromRate(
        rate: await _fromRow(
          reverse,
          fromCurrency: toCurrency,
          toCurrency: fromCurrency,
        ),
        requestedFromCurrency: fromCurrency,
        requestedToCurrency: toCurrency,
        isInverted: true,
      ));
    } on DatabaseException {
      return const FailureResult(
          DatabaseFailure(messageAr: 'تعذر قراءة أسعار الصرف.'));
    } catch (_) {
      return const FailureResult(
          DatabaseFailure(messageAr: 'تعذر قراءة أسعار الصرف.'));
    }
  }

  @override
  Future<Result<List<PosCurrencyRate>>> listHistory({
    CurrencyCode? fromCurrency,
    CurrencyCode? toCurrency,
    int? limit,
  }) async {
    if (limit != null && limit <= 0) {
      return const FailureResult(
          ValidationFailure(messageAr: 'حد السجل يجب أن يكون موجباً.'));
    }
    try {
      final whereParts = <String>[];
      final args = <Object?>[];
      if (fromCurrency != null) {
        whereParts.add('from_currency_code = ?');
        args.add(fromCurrency.code);
      }
      if (toCurrency != null) {
        whereParts.add('to_currency_code = ?');
        args.add(toCurrency.code);
      }
      final rows = await _db.query(
        'pos_currency_rates',
        orderBy: 'recorded_at DESC',
        where: whereParts.isEmpty ? null : whereParts.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        limit: limit,
      );
      final rates = <PosCurrencyRate>[];
      for (final row in rows) {
        rates.add(await _fromRow(row));
      }
      return Success(List.unmodifiable(rates));
    } on DatabaseException {
      return const FailureResult(
          DatabaseFailure(messageAr: 'تعذر قراءة سجل أسعار الصرف.'));
    } catch (_) {
      return const FailureResult(
          DatabaseFailure(messageAr: 'تعذر قراءة سجل أسعار الصرف.'));
    }
  }

  Future<Map<String, Object?>?> _queryLatest(String from, String to) async {
    final rows = await _db.query(
      'pos_currency_rates',
      where: 'from_currency_code = ? AND to_currency_code = ?',
      whereArgs: [from, to],
      orderBy: 'recorded_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Map<String, Object?> _toRow(PosCurrencyRate rate) => {
        'id': rate.id,
        'from_currency_code': rate.fromCurrency.code,
        'to_currency_code': rate.toCurrency.code,
        'rate_scaled': rate.rateScaled,
        'effective_at': rate.effectiveAt.toIso8601String(),
        'recorded_at': rate.recordedAt.toIso8601String(),
        'note': rate.note,
        'created_at': rate.createdAt.toIso8601String(),
      };

  Future<PosCurrencyRate> _fromRow(
    Map<String, Object?> row, {
    CurrencyCode? fromCurrency,
    CurrencyCode? toCurrency,
  }) async {
    final fromCode = row['from_currency_code']! as String;
    final toCode = row['to_currency_code']! as String;
    return PosCurrencyRate(
      id: row['id']! as String,
      fromCurrency: fromCurrency ?? await _currencyForCode(fromCode),
      toCurrency: toCurrency ?? await _currencyForCode(toCode),
      rateScaled: (row['rate_scaled']! as num).toInt(),
      effectiveAt: DateTime.parse(row['effective_at']! as String),
      recordedAt: DateTime.parse(row['recorded_at']! as String),
      note: row['note'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String),
    );
  }

  Future<CurrencyCode> _currencyForCode(String code) async {
    final repository = _currencyRepository;
    if (repository == null) return _currency(code);
    final result = await repository.getByCode(code);
    final currency = result.valueOrNull;
    if (result.isFailure || currency == null) {
      throw StateError('Missing POS currency $code');
    }
    return currency;
  }

  CurrencyCode _currency(String code) => CurrencyCode(
        code: code,
        nameAr: code,
        symbol: code,
      );
}
