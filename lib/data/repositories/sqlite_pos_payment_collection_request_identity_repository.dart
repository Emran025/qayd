import 'dart:convert';

import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_payment_collection_request_identity.dart';
import 'package:qayd/domain/repositories/pos_payment_collection_request_identity_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Keeps only opaque payment/request identifiers and timestamps in the
/// encrypted `app_settings` table until the caller acknowledges the commit.
final class SqlitePosPaymentCollectionRequestIdentityRepository
    implements PosPaymentCollectionRequestIdentityRepository {
  SqlitePosPaymentCollectionRequestIdentityRepository(this._database);

  static const _keyPrefix = 'pos_payment_collection_request:';

  final Database _database;

  @override
  Future<Result<PosPaymentCollectionRequestIdentity>> getOrCreate({
    required String fingerprintHash,
    required PosPaymentCollectionRequestIdentity candidate,
  }) async {
    final hash = fingerprintHash.trim().toLowerCase();
    if (!_validHash(hash) ||
        candidate.paymentId.trim().isEmpty ||
        candidate.idempotencyKey.trim().isEmpty) {
      return _validation<PosPaymentCollectionRequestIdentity>();
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
          return PosPaymentCollectionRequestIdentity(
            paymentId: value['payment_id'] as String,
            idempotencyKey: value['idempotency_key'] as String,
            createdAt: DateTime.parse(value['created_at'] as String).toUtc(),
            occurredAt: DateTime.parse(value['occurred_at'] as String).toUtc(),
          );
        }
        final stable = PosPaymentCollectionRequestIdentity(
          paymentId: candidate.paymentId.trim(),
          idempotencyKey: candidate.idempotencyKey.trim(),
          createdAt: candidate.createdAt.toUtc(),
          occurredAt: candidate.occurredAt.toUtc(),
        );
        await txn.insert('app_settings', {
          'key': key,
          'value': jsonEncode({
            'payment_id': stable.paymentId,
            'idempotency_key': stable.idempotencyKey,
            'created_at': stable.createdAt.toIso8601String(),
            'occurred_at': stable.occurredAt.toIso8601String(),
          }),
        });
        return stable;
      });
      return Success(identity);
    } on DatabaseException {
      return _databaseFailure<PosPaymentCollectionRequestIdentity>();
    } on FormatException {
      return _databaseFailure<PosPaymentCollectionRequestIdentity>();
    } on TypeError {
      return _databaseFailure<PosPaymentCollectionRequestIdentity>();
    } catch (_) {
      return _databaseFailure<PosPaymentCollectionRequestIdentity>();
    }
  }

  @override
  Future<Result<void>> acknowledgeCommitted({
    required String fingerprintHash,
    required PosPaymentCollectionRequestIdentity identity,
  }) =>
      _removePendingIdentity(fingerprintHash: fingerprintHash, identity: identity);

  @override
  Future<Result<void>> discardUncommitted({
    required String fingerprintHash,
    required PosPaymentCollectionRequestIdentity identity,
  }) =>
      _removePendingIdentity(fingerprintHash: fingerprintHash, identity: identity);

  Future<Result<void>> _removePendingIdentity({
    required String fingerprintHash,
    required PosPaymentCollectionRequestIdentity identity,
  }) async {
    final hash = fingerprintHash.trim().toLowerCase();
    if (!_validHash(hash) ||
        identity.paymentId.trim().isEmpty ||
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
        if (value['payment_id'] != identity.paymentId.trim() ||
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
        ValidationFailure(messageAr: AppStrings.posInvoicePaymentInvalid),
      );

  static FailureResult<T> _databaseFailure<T>() => FailureResult(
        DatabaseFailure(messageAr: AppStrings.posInvoicePaymentInvalid),
      );
}
