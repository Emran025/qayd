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

final class _FakeGovernanceRepository implements GovernanceRepository {
  _FakeGovernanceRepository(this.status);

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

final class _FakePosActivationRepository implements PosActivationRepository {
  int installCalls = 0;

  @override
  Future<Result<PosActivationResult>> installTemplate({
    required PosTemplateDefinition template,
    required DateTime now,
    required String deviceId,
  }) async {
    installCalls++;
    return PosActivationResult(
      templateKey: template.templateKey,
      templateVersion: template.version,
      warehouseId: 'warehouse-1',
      accountIdsByKey: const <String, String>{},
      alreadyInstalled: false,
    ).pipeSuccess();
  }

  @override
  Future<Result<void>> disable() async => const Success(null);

  @override
  Future<Result<bool>> isEnabled() async => const Success(false);

  @override
  Future<Result<int?>> getInstalledTemplateVersion() async => const Success(null);

  @override
  Future<Result<String?>> getEnabledWarehouseId() async => const Success(null);
}

extension on PosActivationResult {
  Result<PosActivationResult> pipeSuccess() => Success(this);
}

void main() {
  group('ActivatePosFeatureUseCase', () {
    test('passes through to the repository when governance allows writes',
        () async {
      final repo = _FakePosActivationRepository();
      final guard = GovernanceWriteGuard(
        CheckGovernanceStatusUseCase(
          _FakeGovernanceRepository(GovernanceStatus.activated),
        ),
      );
      final useCase = ActivatePosFeatureUseCase(repo, guard);

      final result = await useCase.call(deviceId: 'device-1');

      expect(result.isSuccess, isTrue);
      expect(repo.installCalls, 1);
    });

    test('does not install the template when governance is suspended',
        () async {
      final repo = _FakePosActivationRepository();
      final guard = GovernanceWriteGuard(
        CheckGovernanceStatusUseCase(
          _FakeGovernanceRepository(
            const GovernanceStatus(kind: GovernanceStatusKind.suspended),
          ),
        ),
      );
      final useCase = ActivatePosFeatureUseCase(repo, guard);

      final result = await useCase.call(deviceId: 'device-1');

      expect(result.isFailure, isTrue);
      expect(repo.installCalls, 0);
    });
  });
}
