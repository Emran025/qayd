import 'dart:convert';

import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_purchase_request_identity.dart';
import 'package:qayd/domain/repositories/pos_purchase_request_identity_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Stores only opaque purchase IDs and a SHA-256-keyed fingerprint in the
/// already encrypted SQLCipher `app_settings` table. It is retained until the
/// UI acknowledges the committed result so a restart cannot lose that outcome.
final class SqlitePosPurchaseRequestIdentityRepository
    implements PosPurchaseRequestIdentityRepository {
  SqlitePosPurchaseRequestIdentityRepository(this._database);

  static const _keyPrefix = 'pos_purchase_request:';

  final Database _database;

  @override
  Future<Result<PosPurchaseRequestIdentity>> getOrCreate({
    required String fingerprintHash,
    required PosPurchaseRequestIdentity candidate,
  }) async {
    final normalizedHash = fingerprintHash.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedHash) ||
        candidate.invoiceId.trim().isEmpty ||
        candidate.idempotencyKey.trim().isEmpty) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posPurchaseSubmitFailed),
      );
    }

    try {
      final identity = await _database.transaction((txn) async {
        final key = '$_keyPrefix$normalizedHash';
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
          return PosPurchaseRequestIdentity(
            invoiceId: value['invoice_id'] as String,
            idempotencyKey: value['idempotency_key'] as String,
            createdAt: DateTime.parse(value['created_at'] as String).toUtc(),
          );
        }

        await txn.insert(
          'app_settings',
          {
            'key': key,
            'value': jsonEncode({
              'invoice_id': candidate.invoiceId.trim(),
              'idempotency_key': candidate.idempotencyKey.trim(),
              'created_at': candidate.createdAt.toUtc().toIso8601String(),
            }),
          },
        );
        return candidate;
      });
      return Success(identity);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posPurchaseSubmitFailed),
      );
    } on FormatException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posPurchaseSubmitFailed),
      );
    } on TypeError {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posPurchaseSubmitFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posPurchaseSubmitFailed),
      );
    }
  }

  @override
  Future<Result<void>> acknowledgeCommitted({
    required String fingerprintHash,
    required PosPurchaseRequestIdentity identity,
  }) async {
    final normalizedHash = fingerprintHash.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedHash)) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posPurchaseSubmitFailed),
      );
    }
    try {
      final matched = await _database.transaction((txn) async {
        final key = '$_keyPrefix$normalizedHash';
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
        if (value['invoice_id'] != identity.invoiceId ||
            value['idempotency_key'] != identity.idempotencyKey) {
          return false;
        }
        await txn.delete('app_settings', where: 'key = ?', whereArgs: [key]);
        return true;
      });
      if (!matched) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posPurchaseSubmitFailed),
        );
      }
      return const Success(null);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posPurchaseSubmitFailed),
      );
    } on FormatException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posPurchaseSubmitFailed),
      );
    } on TypeError {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posPurchaseSubmitFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posPurchaseSubmitFailed),
      );
    }
  }
}
