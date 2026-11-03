import 'dart:convert';

import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/data/mappers/account_mapper.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/repositories/pos_activation_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// SQLite adapter for the explicit POS template installation.
///
/// The entire installation is one database transaction because AccountRepository
/// cannot share a transaction object with POS tables. Account entities are still
/// created through the canonical Account factory and AccountMapper.
final class SqlitePosActivationRepository
    implements PosActivationRepository, PosTemplateInstallationRepository {
  SqlitePosActivationRepository(this._db, this._idGenerator);

  final Database _db;
  final IdGenerator _idGenerator;

  @override
  Future<Result<PosActivationResult>> installTemplate({
    required PosTemplateDefinition template,
    required DateTime now,
    required String deviceId,
  }) async {
    try {
      final result = await _db.transaction<PosActivationResult>((txn) async {
        final installedRows = await txn.query(
          'pos_template_installs',
          where: 'template_key = ? AND template_version = ?',
          whereArgs: [template.templateKey, template.version],
          limit: 1,
        );

        if (installedRows.isNotEmpty &&
            installedRows.first['status'] == 'installed') {
          return _restoreInstalledResult(
            txn,
            installedRows.first,
            template,
          );
        }

        final warehouseId = await _getOrCreateWarehouse(txn, template, now);
        final accountIds = <String, String>{};

        for (final spec in template.accounts) {
          final accountId = await _getOrCreateTemplateAccount(
            txn,
            template: template,
            spec: spec,
            now: now,
          );
          accountIds[spec.key.value] = accountId;
        }

        final accountMapJson = jsonEncode(accountIds);
        final installData = <String, Object?>{
          'template_key': template.templateKey,
          'template_version': template.version,
          'status': 'installed',
          'account_map_json': accountMapJson,
          'installed_at': now.toUtc().toIso8601String(),
          'installed_by_device': deviceId,
          'last_error_code': null,
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
        };

        if (installedRows.isEmpty) {
          await txn.insert(
            'pos_template_installs',
            <String, Object?>{
              'id': _idGenerator.next(),
              ...installData,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } else {
          await txn.update(
            'pos_template_installs',
            installData,
            where: 'template_key = ? AND template_version = ?',
            whereArgs: [template.templateKey, template.version],
          );
        }

        final settingsData = <String, Object?>{
          'is_enabled': 1,
          'template_key': template.templateKey,
          'template_version': template.version,
          'warehouse_id': warehouseId,
          'cost_method': template.costMethod,
          'updated_at': now.toUtc().toIso8601String(),
        };
        final updated = await txn.update(
          'pos_settings',
          settingsData,
          where: 'id = 1',
        );
        if (updated == 0) {
          await txn.insert(
            'pos_settings',
            <String, Object?>{
              'id': 1,
              ...settingsData,
              'created_at': now.toUtc().toIso8601String(),
            },
          );
        }

        return PosActivationResult(
          templateKey: template.templateKey,
          templateVersion: template.version,
          warehouseId: warehouseId,
          accountIdsByKey: accountIds,
          alreadyInstalled: false,
        );
      });
      return Success(result);
    } on _PosTemplateConflictException {
      return FailureResult(
        ValidationFailure(
          messageAr: AppStrings.posTemplateConflict,
        ),
      );
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(
          messageAr: AppStrings.posActivationFailed,
        ),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(
          messageAr: AppStrings.posActivationFailed,
        ),
      );
    }
  }

  @override
  Future<Result<bool>> isEnabled() async {
    try {
      final rows = await _db.query(
        'pos_settings',
        columns: ['is_enabled'],
        where: 'id = 1',
        limit: 1,
      );
      return Success(rows.isNotEmpty && rows.first['is_enabled'] == 1);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(
          messageAr: AppStrings.posFeatureStateReadFailed,
        ),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(
          messageAr: AppStrings.posFeatureStateReadFailed,
        ),
      );
    }
  }

  @override
  Future<Result<int?>> getInstalledTemplateVersion() async {
    try {
      final rows = await _db.query(
        'pos_settings',
        columns: ['template_version'],
        where: 'id = 1',
        limit: 1,
      );
      if (rows.isEmpty || rows.first['template_version'] == null) {
        return const Success(null);
      }
      return Success((rows.first['template_version'] as num).toInt());
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posFeatureStateReadFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posFeatureStateReadFailed),
      );
    }
  }

  @override
  Future<Result<String?>> getEnabledWarehouseId() async {
    try {
      final rows = await _db.query(
        'pos_settings',
        columns: ['is_enabled', 'warehouse_id'],
        where: 'id = 1',
        limit: 1,
      );
      if (rows.isEmpty || rows.first['is_enabled'] != 1) {
        return const Success(null);
      }
      final warehouseId = rows.first['warehouse_id'];
      if (warehouseId is! String || warehouseId.trim().isEmpty) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posWarehouseUnavailable),
        );
      }
      return Success(warehouseId);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posFeatureStateReadFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posFeatureStateReadFailed),
      );
    }
  }

  @override
  Future<Result<PosActivationResult?>> getEnabledInstallation({
    required PosTemplateDefinition template,
  }) async {
    try {
      final settingsRows = await _db.query(
        'pos_settings',
        columns: ['is_enabled', 'template_key', 'template_version'],
        where: 'id = 1',
        limit: 1,
      );
      if (settingsRows.isEmpty || settingsRows.first['is_enabled'] != 1) {
        return const Success(null);
      }
      if (settingsRows.first['template_key'] != template.templateKey ||
          settingsRows.first['template_version'] != template.version) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posTemplateConflict),
        );
      }
      final installedRows = await _db.query(
        'pos_template_installs',
        where: 'template_key = ? AND template_version = ? AND status = ?',
        whereArgs: [template.templateKey, template.version, 'installed'],
        limit: 1,
      );
      if (installedRows.isEmpty) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posTemplateConflict),
        );
      }
      final result = await _db.transaction(
        (txn) => _restoreInstalledResult(
          txn,
          installedRows.first,
          template,
          normalizeEnabled: false,
        ),
      );
      return Success(result);
    } on _PosTemplateConflictException {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posTemplateConflict),
      );
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posFeatureStateReadFailed),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(messageAr: AppStrings.posFeatureStateReadFailed),
      );
    }
  }

  @override
  Future<Result<void>> disable() async {
    try {
      await _db.update(
        'pos_settings',
        <String, Object?>{
          'is_enabled': 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = 1',
      );
      return const Success(null);
    } on DatabaseException {
      return FailureResult(
        DatabaseFailure(
          messageAr: AppStrings.posFeatureDisableFailed,
        ),
      );
    } catch (_) {
      return FailureResult(
        DatabaseFailure(
          messageAr: AppStrings.posFeatureDisableFailed,
        ),
      );
    }
  }

  Future<String> _getOrCreateWarehouse(
    Transaction txn,
    PosTemplateDefinition template,
    DateTime now,
  ) async {
    final rows = await txn.query(
      'pos_warehouses',
      columns: ['id', 'is_active'],
      where: 'code = ?',
      whereArgs: [template.warehouseCode],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final row = rows.first;
      if (row['is_active'] != 1) {
        await txn.update(
          'pos_warehouses',
          <String, Object?>{
            'is_active': 1,
            'updated_at': now.toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      return row['id'] as String;
    }

    final id = _idGenerator.next();
    await txn.insert('pos_warehouses', <String, Object?>{
      'id': id,
      'code': template.warehouseCode,
      'name': 'POS Main Warehouse',
      'is_default': 1,
      'is_active': 1,
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    });
    return id;
  }

  Future<String> _getOrCreateTemplateAccount(
    Transaction txn, {
    required PosTemplateDefinition template,
    required PosTemplateAccountSpec spec,
    required DateTime now,
  }) async {
    final rows = await txn.query(
      'accounts',
      columns: ['id', 'metadata'],
      where: 'metadata IS NOT NULL AND metadata LIKE ?',
      whereArgs: ['%"pos_template_key"%'],
    );

    String? foundId;
    Map<String, Object?>? foundMetadata;
    for (final row in rows) {
      final raw = row['metadata'];
      if (raw is! String || raw.isEmpty) continue;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) continue;
      final metadata = <String, Object?>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) continue;
        metadata[entry.key as String] = entry.value;
      }
      if (metadata['pos_template_key'] == template.templateKey &&
          metadata['pos_template_account_key'] == spec.key.value) {
        if (foundId != null && foundId != row['id']) {
          throw const _PosTemplateConflictException();
        }
        foundId = row['id'] as String;
        foundMetadata = metadata;
      }
    }
    if (foundId != null) {
      if (foundMetadata?['pos_template_version'] != template.version) {
        final upgradedMetadata = <String, Object?>{
          ...?foundMetadata,
          'pos_template_version': template.version,
        };
        await txn.update(
          'accounts',
          <String, Object?>{'metadata': jsonEncode(upgradedMetadata)},
          where: 'id = ?',
          whereArgs: [foundId],
        );
      }
      return foundId;
    }

    final account = Account.createRoot(
      id: AccountId(_idGenerator.next()),
      name: spec.name,
      classification: spec.classification,
      createdAt: now.toUtc(),
      isDefault: false,
      metadata: <String, Object?>{
        'pos_template_key': template.templateKey,
        'pos_template_version': template.version,
        'pos_template_account_key': spec.key.value,
      },
    );
    await txn.insert(
      'accounts',
      AccountMapper.toModel(account).toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return account.id.value;
  }

  Future<PosActivationResult> _restoreInstalledResult(
    Transaction txn,
    Map<String, Object?> installRow,
    PosTemplateDefinition template, {
    bool normalizeEnabled = true,
  }) async {
    final rawMap = installRow['account_map_json'];
    final rawWarehouse = await txn.query(
      'pos_settings',
      columns: ['warehouse_id'],
      where: 'id = 1',
      limit: 1,
    );
    if (rawMap is! String || rawWarehouse.isEmpty) {
      throw const _PosTemplateConflictException();
    }
    final decoded = jsonDecode(rawMap);
    final warehouseId = rawWarehouse.first['warehouse_id'];
    if (decoded is! Map || warehouseId is! String) {
      throw const _PosTemplateConflictException();
    }
    final accountIds = <String, String>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const _PosTemplateConflictException();
      }
      accountIds[entry.key as String] = entry.value as String;
    }
    if (normalizeEnabled) {
      await txn.update(
        'pos_settings',
        <String, Object?>{'is_enabled': 1},
        where: 'id = 1',
      );
    }
    return PosActivationResult(
      templateKey: template.templateKey,
      templateVersion: template.version,
      warehouseId: warehouseId,
      accountIdsByKey: accountIds,
      alreadyInstalled: true,
    );
  }
}

final class _PosTemplateConflictException implements Exception {
  const _PosTemplateConflictException();
}
