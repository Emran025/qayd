import 'dart:convert';

import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_sales_return_request_identity.dart';
import 'package:qayd/domain/repositories/pos_sales_return_request_identity_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Retains opaque sales-return request identities in encrypted app_settings.
final class SqlitePosSalesReturnRequestIdentityRepository
    implements PosSalesReturnRequestIdentityRepository {
  SqlitePosSalesReturnRequestIdentityRepository(this._database);

  static const _keyPrefix = 'pos_sales_return_request:';
  final Database _database;

  @override
  Future<Result<PosSalesReturnRequestIdentity>> getOrCreate({
    required String fingerprintHash,
    required PosSalesReturnRequestIdentity candidate,
  }) async {
    final hash = fingerprintHash.trim().toLowerCase();
    if (!_validHash(hash) ||
        candidate.invoiceId.trim().isEmpty ||
        candidate.idempotencyKey.trim().isEmpty) {
      return _validation<PosSalesReturnRequestIdentity>();
    }
    try {
      final identity = await _database.transaction((txn) async {
        final key = '$_keyPrefix$hash';
        final rows = await txn.query(
          'app_settings',
          columns: ['value'],
          where: 'key = ?',
          whereArgs: [key],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final value = jsonDecode(rows.single['value']! as String)
              as Map<String, dynamic>;
          return PosSalesReturnRequestIdentity(
            invoiceId: value['invoice_id'] as String,
            idempotencyKey: value['idempotency_key'] as String,
            createdAt: DateTime.parse(value['created_at'] as String).toUtc(),
          );
        }
        await txn.insert('app_settings', {
          'key': key,
          'value': jsonEncode({
            'invoice_id': candidate.invoiceId.trim(),
            'idempotency_key': candidate.idempotencyKey.trim(),
            'created_at': candidate.createdAt.toUtc().toIso8601String(),
          }),
        });
        return PosSalesReturnRequestIdentity(
          invoiceId: candidate.invoiceId.trim(),
          idempotencyKey: candidate.idempotencyKey.trim(),
          createdAt: candidate.createdAt.toUtc(),
        );
      });
      return Success(identity);
    } on DatabaseException {
      return _databaseFailure<PosSalesReturnRequestIdentity>();
    } on FormatException {
      return _databaseFailure<PosSalesReturnRequestIdentity>();
    } on TypeError {
      return _databaseFailure<PosSalesReturnRequestIdentity>();
    } catch (_) {
      return _databaseFailure<PosSalesReturnRequestIdentity>();
    }
  }

  @override
  Future<Result<void>> acknowledgeCommitted({
    required String fingerprintHash,
    required PosSalesReturnRequestIdentity identity,
  }) async {
    final hash = fingerprintHash.trim().toLowerCase();
    if (!_validHash(hash) ||
        identity.invoiceId.trim().isEmpty ||
        identity.idempotencyKey.trim().isEmpty) {
      return _validation<void>();
    }
    try {
      final matched = await _database.transaction((txn) async {
        final key = '$_keyPrefix$hash';
        final rows = await txn.query(
          'app_settings',
          columns: ['value'],
          where: 'key = ?',
          whereArgs: [key],
          limit: 1,
        );
        if (rows.isEmpty) return true;
        final value = jsonDecode(rows.single['value']! as String)
            as Map<String, dynamic>;
        if (value['invoice_id'] != identity.invoiceId.trim() ||
            value['idempotency_key'] != identity.idempotencyKey.trim()) {
          return false;
        }
        await txn.delete('app_settings', where: 'key = ?', whereArgs: [key]);
        return true;
      });
      return matched ? const Success<void>(null) : _validation<void>();
    } on DatabaseException {
      return _databaseFailure<void>();
    } on FormatException {
      return _databaseFailure<void>();
    } on TypeError {
      return _databaseFailure<void>();
    } catch (_) {
      return _databaseFailure<void>();
    }
  }

  static bool _validHash(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  static FailureResult<T> _validation<T>() => FailureResult(
        ValidationFailure(messageAr: AppStrings.posInvoiceInvalid),
      );

  static FailureResult<T> _databaseFailure<T>() => FailureResult(
        DatabaseFailure(messageAr: AppStrings.posInvoiceInvalid),
      );
}
