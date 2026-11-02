import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/governance/check_governance_status_use_case.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/activate_pos_feature_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/repositories/governance_repository.dart';
import 'package:qayd/domain/repositories/pos_activation_repository.dart';
import 'package:qayd/domain/value_objects/governance_status.dart';
import 'package:qayd/domain/value_objects/submit_activation_request.dart';
import 'package:qayd/presentation/pos/pos_feature_cubit.dart';

final class _GovernanceRepo implements GovernanceRepository {
  _GovernanceRepo(this.status);

  final GovernanceStatus status;

  @override
  Future<Result<GovernanceStatus>> getStatus(
      {bool forceRefresh = false}) async {
    return Success(status);
  }

  @override
  Future<Result<void>> submitActivation(SubmitActivationRequest request) async {
    return const Success(null);
  }
}

final class _PosRepo implements PosActivationRepository {
  _PosRepo({
    this.enabled = false,
    this.failInstall = false,
    this.templateVersion = PosTemplateDefinition.currentVersion,
  });

  bool enabled;
  bool failInstall;
  int templateVersion;
  int installCalls = 0;
  int disableCalls = 0;

  @override
  Future<Result<PosActivationResult>> installTemplate({
    required PosTemplateDefinition template,
    required DateTime now,
    required String deviceId,
  }) async {
    installCalls++;
    if (failInstall) {
      return FailureResult(
        ValidationFailure(messageAr: 'install failed'),
      );
    }
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
    disableCalls++;
    enabled = false;
    return const Success(null);
  }
}

PosFeatureCubit _createCubit(
  _PosRepo repository, {
  GovernanceStatus status = GovernanceStatus.activated,
}) {
  final guard = GovernanceWriteGuard(
    CheckGovernanceStatusUseCase(_GovernanceRepo(status)),
  );
  return PosFeatureCubit(
    activateUseCase: ActivatePosFeatureUseCase(repository, guard),
    repository: repository,
    deviceIdProvider: () => 'device-1',
  );
}

void main() {
  group('PosFeatureCubit', () {
    test('loads disabled state as ready', () async {
      final cubit = _createCubit(_PosRepo());
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, PosFeatureStatus.ready);
      expect(cubit.state.isEnabled, isFalse);
    });

    test('activates once and emits active state', () async {
      final repo = _PosRepo();
      final cubit = _createCubit(repo);
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.activate();
      await cubit.activate();

      expect(cubit.state.status, PosFeatureStatus.active);
      expect(cubit.state.isEnabled, isTrue);
      expect(repo.installCalls, 1);
    });

    test('disables without deleting installed data', () async {
      final repo = _PosRepo(enabled: true);
      final cubit = _createCubit(repo);
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.disable();

      expect(cubit.state.status, PosFeatureStatus.disabled);
      expect(cubit.state.isEnabled, isFalse);
      expect(repo.disableCalls, 1);
    });

    test('requires an explicit activation to upgrade an older template',
        () async {
      final repo = _PosRepo(enabled: true, templateVersion: 2);
      final cubit = _createCubit(repo);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.isEnabled, isTrue);
      expect(cubit.state.requiresUpgrade, isTrue);
      expect(repo.installCalls, 0);

      await cubit.activate();

      expect(cubit.state.status, PosFeatureStatus.upgraded);
      expect(cubit.state.requiresUpgrade, isFalse);
      expect(repo.templateVersion, PosTemplateDefinition.currentVersion);
      expect(repo.installCalls, 1);
    });

    test('maps installation failure to failure state', () async {
      final repo = _PosRepo(failInstall: true);
      final cubit = _createCubit(repo);
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.activate();

      expect(cubit.state.status, PosFeatureStatus.failure);
      expect(cubit.state.failure, isA<ValidationFailure>());
    });

    test('governance suspension prevents installation', () async {
      final repo = _PosRepo();
      final cubit = _createCubit(
        repo,
        status: const GovernanceStatus(kind: GovernanceStatusKind.suspended),
      );
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.activate();

      expect(cubit.state.status, PosFeatureStatus.failure);
      expect(cubit.state.failure, isA<ValidationFailure>());
      expect(repo.installCalls, 0);
    });
  });
}
