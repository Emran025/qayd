import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/governance/check_governance_status_use_case.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/activate_pos_feature_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/repositories/governance_repository.dart';
import 'package:qayd/domain/repositories/pos_activation_repository.dart';
import 'package:qayd/domain/value_objects/governance_status.dart';
import 'package:qayd/domain/value_objects/submit_activation_request.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pages/settings/pos_feature_settings_page.dart';
import 'package:qayd/presentation/pos/pos_feature_cubit.dart';
import 'package:qayd/presentation/theme/app_theme.dart';

final class _GovernanceRepo implements GovernanceRepository {
  @override
  Future<Result<GovernanceStatus>> getStatus(
      {bool forceRefresh = false}) async {
    return Success(GovernanceStatus.activated);
  }

  @override
  Future<Result<void>> submitActivation(SubmitActivationRequest request) async {
    return const Success(null);
  }
}

final class _PosRepo implements PosActivationRepository {
  _PosRepo({
    this.enabled = false,
  });

  bool enabled;
  int templateVersion = PosTemplateDefinition.currentVersion;

  @override
  Future<Result<PosActivationResult>> installTemplate({
    required PosTemplateDefinition template,
    required DateTime now,
    required String deviceId,
  }) async {
    enabled = true;
    templateVersion = template.version;
    return Success(
      PosActivationResult(
        templateKey: template.templateKey,
        templateVersion: template.version,
        warehouseId: 'warehouse-1',
        accountIdsByKey: const <String, String>{},
        alreadyInstalled: false,
      ),
    );
  }

  @override
  Future<Result<bool>> isEnabled() async => Success(enabled);

  @override
  Future<Result<int?>> getInstalledTemplateVersion() async =>
      Success(enabled ? templateVersion : null);

  @override
  Future<Result<String?>> getEnabledWarehouseId() async =>
      Success(enabled ? 'warehouse-1' : null);

  @override
  Future<Result<void>> disable() async {
    enabled = false;
    return const Success(null);
  }
}

PosFeatureCubit _cubit(_PosRepo repo) {
  return PosFeatureCubit(
    activateUseCase: ActivatePosFeatureUseCase(
      repo,
      GovernanceWriteGuard(CheckGovernanceStatusUseCase(_GovernanceRepo())),
    ),
    repository: repo,
    deviceIdProvider: () => 'device-1',
  );
}

void main() {
  testWidgets('confirms activation and renders active state', (tester) async {
    final cubit = _cubit(_PosRepo());
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PosFeatureSettingsPage(cubit: cubit),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.posFeatureDisabled), findsOneWidget);
    await tester.tap(find.text(AppStrings.posFeatureActivate));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.posFeatureConfirm), findsOneWidget);

    await tester.tap(find.text(AppStrings.posFeatureConfirm));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.posFeatureEnabled), findsOneWidget);
  });

  testWidgets('hides POS without removing its installation', (tester) async {
    final repo = _PosRepo(enabled: true);
    final cubit = _cubit(repo);
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PosFeatureSettingsPage(cubit: cubit),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.posFeatureEnabled), findsOneWidget);
    await tester.tap(find.text(AppStrings.posFeatureDisable));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.posFeatureDisabled), findsOneWidget);
    expect(repo.enabled, isFalse);
  });
}
