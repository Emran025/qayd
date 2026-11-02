import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/application/pos/activate_pos_feature_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/repositories/pos_activation_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Explicit presentation states for the POS feature setting.
enum PosFeatureStatus {
  initial,
  loading,
  ready,
  activating,
  active,
  upgraded,
  disabling,
  disabled,
  failure,
}

final class PosFeatureState {
  const PosFeatureState({
    this.status = PosFeatureStatus.initial,
    this.isEnabled = false,
    this.requiresUpgrade = false,
    this.activation,
    this.failure,
  });

  final PosFeatureStatus status;
  final bool isEnabled;
  final bool requiresUpgrade;
  final PosActivationResult? activation;
  final Failure? failure;

  bool get isBusy =>
      status == PosFeatureStatus.loading ||
      status == PosFeatureStatus.activating ||
      status == PosFeatureStatus.disabling;

  PosFeatureState copyWith({
    PosFeatureStatus? status,
    bool? isEnabled,
    bool? requiresUpgrade,
    PosActivationResult? activation,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return PosFeatureState(
      status: status ?? this.status,
      isEnabled: isEnabled ?? this.isEnabled,
      requiresUpgrade: requiresUpgrade ?? this.requiresUpgrade,
      activation: activation ?? this.activation,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PosFeatureState &&
            other.status == status &&
            other.isEnabled == isEnabled &&
            other.requiresUpgrade == requiresUpgrade &&
            other.activation == activation &&
            other.failure == failure;
  }

  @override
  int get hashCode =>
      Object.hash(status, isEnabled, requiresUpgrade, activation, failure);
}

/// Presentation coordinator for the opt-in POS switch and template upgrades.
///
/// Upgrading is an explicit activation action; this cubit never provisions an
/// account while merely reading feature state.
final class PosFeatureCubit extends Cubit<PosFeatureState> {
  PosFeatureCubit({
    required ActivatePosFeatureUseCase activateUseCase,
    required PosActivationRepository repository,
    required String Function() deviceIdProvider,
  })  : _activateUseCase = activateUseCase,
        _repository = repository,
        _deviceIdProvider = deviceIdProvider,
        super(const PosFeatureState());

  final ActivatePosFeatureUseCase _activateUseCase;
  final PosActivationRepository _repository;
  final String Function() _deviceIdProvider;

  Future<void> load() async {
    if (isClosed || state.isBusy) return;
    emit(state.copyWith(status: PosFeatureStatus.loading, clearFailure: true));

    final enabledResult = await _repository.isEnabled();
    if (isClosed) return;
    if (enabledResult.isFailure) {
      emit(
        state.copyWith(
          status: PosFeatureStatus.failure,
          failure: enabledResult.failureOrNull,
        ),
      );
      return;
    }

    final enabled = enabledResult.valueOrNull == true;
    if (!enabled) {
      emit(
        state.copyWith(
          status: PosFeatureStatus.ready,
          isEnabled: false,
          requiresUpgrade: false,
          clearFailure: true,
        ),
      );
      return;
    }

    final versionResult = await _repository.getInstalledTemplateVersion();
    if (isClosed) return;
    if (versionResult.isFailure) {
      emit(
        state.copyWith(
          status: PosFeatureStatus.failure,
          isEnabled: true,
          failure: versionResult.failureOrNull,
        ),
      );
      return;
    }
    final version = versionResult.valueOrNull;
    if (version == null || version > PosTemplateDefinition.currentVersion) {
      emit(
        state.copyWith(
          status: PosFeatureStatus.failure,
          isEnabled: true,
          failure: ValidationFailure(messageAr: AppStrings.posTemplateConflict),
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: PosFeatureStatus.active,
        isEnabled: true,
        requiresUpgrade: version < PosTemplateDefinition.currentVersion,
        clearFailure: true,
      ),
    );
  }

  Future<void> activate() async {
    if (isClosed ||
        state.isBusy ||
        (state.isEnabled && !state.requiresUpgrade)) {
      return;
    }
    emit(
      state.copyWith(
        status: PosFeatureStatus.activating,
        clearFailure: true,
      ),
    );

    final result = await _activateUseCase.call(
      deviceId: _deviceIdProvider(),
    );
    if (isClosed) return;
    result.fold(
      (failure) => emit(
        state.copyWith(
          status: PosFeatureStatus.failure,
          failure: failure,
        ),
      ),
      (activation) => emit(
        state.copyWith(
          status: state.isEnabled
              ? PosFeatureStatus.upgraded
              : PosFeatureStatus.active,
          isEnabled: true,
          requiresUpgrade: false,
          activation: activation,
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> disable() async {
    if (isClosed || state.isBusy || !state.isEnabled) return;
    emit(
      state.copyWith(
        status: PosFeatureStatus.disabling,
        clearFailure: true,
      ),
    );

    final result = await _repository.disable();
    if (isClosed) return;
    result.fold(
      (failure) => emit(
        state.copyWith(
          status: PosFeatureStatus.failure,
          failure: failure,
        ),
      ),
      (_) => emit(
        state.copyWith(
          status: PosFeatureStatus.disabled,
          isEnabled: false,
          requiresUpgrade: false,
          clearFailure: true,
        ),
      ),
    );
  }
}
