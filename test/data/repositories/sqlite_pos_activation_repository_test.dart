import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/repositories/sqlite_pos_activation_repository.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _FixedIdGenerator implements IdGenerator {
  int _nextId = 0;

  @override
  String next() => 'generated-${_nextId++}';
}

void main() {
  sqfliteFfiInit();

  group('SqlitePosActivationRepository', () {
    late Database db;
    late SqlitePosActivationRepository repository;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE accounts (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          nature TEXT NOT NULL,
          parent_id TEXT,
          is_default INTEGER NOT NULL,
          is_active INTEGER NOT NULL,
          is_archived INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          standard_classification TEXT,
          custom_classification_name TEXT,
          custom_classification_nature TEXT,
          metadata TEXT
        )
      ''');
      await Migration040PosFoundation().up(db);
      repository = SqlitePosActivationRepository(db, _FixedIdGenerator());
    });

    tearDown(() => db.close());

    test('installs template atomically and enables POS', () async {
      final result = await repository.installTemplate(
        template: PosTemplateDefinition.current(),
        now: DateTime.utc(2026, 1, 1),
        deviceId: 'device-a',
      );

      expect(result.isSuccess, isTrue);
      final activation = result.valueOrNull!;
      expect(activation.alreadyInstalled, isFalse);
      expect(activation.accountIdsByKey, hasLength(12));
      expect(
        activation.accountIdsByKey[
          PosTemplateAccountKey.inventoryLossExpense.value
        ],
        isNotNull,
      );
      expect((await db.query('accounts')), hasLength(12));
      expect((await db.query('pos_warehouses')), hasLength(1));
      expect((await db.query('pos_template_installs')), hasLength(1));
      expect((await db.query('pos_settings')), hasLength(1));
      expect((await repository.isEnabled()).valueOrNull, isTrue);
      expect(
        (await repository.getEnabledWarehouseId()).valueOrNull,
        activation.warehouseId,
      );
    });

    test('reads enabled template account map without provisioning or mutation',
        () async {
      final template = PosTemplateDefinition.current();
      await repository.installTemplate(
        template: template,
        now: DateTime.utc(2026, 1, 1),
        deviceId: 'device-a',
      );
      final beforeSettings = await db.query('pos_settings');
      final beforeAccounts = await db.query('accounts', orderBy: 'id ASC');

      final result =
          await repository.getEnabledInstallation(template: template);

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull?.warehouseId, isNotEmpty);
      expect(
        result.valueOrNull
            ?.accountIdsByKey[PosTemplateAccountKey.inventoryAsset.value],
        isNotEmpty,
      );
      expect(
        result.valueOrNull?.accountIdsByKey[
            PosTemplateAccountKey.openingBalanceClearing.value],
        isNotEmpty,
      );
      expect(await db.query('pos_settings'), equals(beforeSettings));
      expect(await db.query('accounts', orderBy: 'id ASC'),
          equals(beforeAccounts));
    });

    test('returns null from typed installation lookup while disabled',
        () async {
      final template = PosTemplateDefinition.current();
      await repository.installTemplate(
        template: template,
        now: DateTime.utc(2026, 1, 1),
        deviceId: 'device-a',
      );
      await repository.disable();

      final result =
          await repository.getEnabledInstallation(template: template);

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isNull);
    });

    test('fails closed when settings say enabled but install row is missing',
        () async {
      final template = PosTemplateDefinition.current();
      await db.insert('pos_settings', <String, Object?>{
        'id': 1,
        'is_enabled': 1,
        'template_key': template.templateKey,
        'template_version': template.version,
        'warehouse_id': 'warehouse-missing-install',
        'cost_method': template.costMethod,
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });

      final result =
          await repository.getEnabledInstallation(template: template);

      expect(result.isFailure, isTrue);
    });

    test('returns no warehouse while POS is disabled', () async {
      expect((await repository.getEnabledWarehouseId()).valueOrNull, isNull);

      await repository.installTemplate(
        template: PosTemplateDefinition.current(),
        now: DateTime.utc(2026, 1, 1),
        deviceId: 'device-a',
      );
      await repository.disable();

      expect((await repository.getEnabledWarehouseId()).valueOrNull, isNull);
    });

    test('upgrades prior template accounts without duplicates', () async {
      await repository.installTemplate(
        template: PosTemplateDefinition.current(),
        now: DateTime.utc(2026, 1, 1),
        deviceId: 'device-a',
      );

      final accounts = await db.query('accounts');
      for (final row in accounts) {
        final rawMetadata = row['metadata'];
        if (rawMetadata is! String) continue;
        final metadata =
            Map<String, Object?>.from(jsonDecode(rawMetadata) as Map);
        if (metadata['pos_template_account_key'] ==
            'pos.opening_balance_clearing') {
          await db.delete('accounts', where: 'id = ?', whereArgs: [row['id']]);
          continue;
        }
        metadata['pos_template_version'] = 1;
        await db.update(
          'accounts',
          <String, Object?>{'metadata': jsonEncode(metadata)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      await db.delete('pos_template_installs');
      await db.delete('pos_settings');

      final upgraded = await repository.installTemplate(
        template: PosTemplateDefinition.current(),
        now: DateTime.utc(2026, 1, 2),
        deviceId: 'device-a',
      );

      expect(upgraded.isSuccess, isTrue);
      expect(upgraded.valueOrNull!.accountIdsByKey, hasLength(12));
      expect((await db.query('accounts')), hasLength(12));
      for (final row in await db.query('accounts')) {
        final metadata = jsonDecode(row['metadata']! as String) as Map;
        expect(metadata['pos_template_version'], PosTemplateDefinition.currentVersion);
      }
    });

    test('reuses an installed template without duplicates', () async {
      final template = PosTemplateDefinition.current();
      final first = await repository.installTemplate(
        template: template,
        now: DateTime.utc(2026, 1, 1),
        deviceId: 'device-a',
      );
      final second = await repository.installTemplate(
        template: template,
        now: DateTime.utc(2026, 1, 2),
        deviceId: 'device-a',
      );

      expect(first.isSuccess, isTrue);
      expect(second.isSuccess, isTrue);
      expect(second.valueOrNull!.alreadyInstalled, isTrue);
      expect((await db.query('accounts')), hasLength(12));
      expect((await db.query('pos_warehouses')), hasLength(1));
      expect((await db.query('pos_template_installs')), hasLength(1));
    });

    test('disabling hides POS but preserves the installed template', () async {
      await repository.installTemplate(
        template: PosTemplateDefinition.current(),
        now: DateTime.utc(2026, 1, 1),
        deviceId: 'device-a',
      );

      final disabled = await repository.disable();

      expect(disabled.isSuccess, isTrue);
      expect((await repository.isEnabled()).valueOrNull, isFalse);
      expect((await db.query('accounts')), hasLength(12));
      expect((await db.query('pos_template_installs')), hasLength(1));
      expect((await db.query('pos_warehouses')), hasLength(1));
    });
  });
}
