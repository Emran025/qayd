import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pos/pos_feature_cubit.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';

/// Settings entry point for the opt-in POS workspace.
final class PosFeatureSettingsPage extends StatelessWidget {
  const PosFeatureSettingsPage({
    required this.cubit,
    super.key,
  });

  final PosFeatureCubit cubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      child: const _PosFeatureSettingsView(),
    );
  }
}

final class _PosFeatureSettingsView extends StatefulWidget {
  const _PosFeatureSettingsView();

  @override
  State<_PosFeatureSettingsView> createState() =>
      _PosFeatureSettingsViewState();
}

final class _PosFeatureSettingsViewState
    extends State<_PosFeatureSettingsView> {
  @override
  void initState() {
    super.initState();
    context.read<PosFeatureCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PosFeatureCubit, PosFeatureState>(
      listener: (context, state) {
        if (state.status == PosFeatureStatus.active) {
          _showMessage(AppStrings.posFeatureActivationSuccess);
        } else if (state.status == PosFeatureStatus.upgraded) {
          _showMessage(AppStrings.posFeatureUpgradeSuccess);
        } else if (state.status == PosFeatureStatus.disabled) {
          _showMessage(AppStrings.posFeatureDisableSuccess);
        } else if (state.status == PosFeatureStatus.failure &&
            state.failure != null) {
          _showMessage(state.failure!.messageAr);
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: QaydAppBar(title: AppStrings.posFeaturePageTitle),
          body: ListView(
            padding: const EdgeInsets.all(SpacingTokens.lg),
            children: [
              _buildIntro(context),
              const SizedBox(height: SpacingTokens.lg),
              _buildStatusCard(context, state),
              const SizedBox(height: SpacingTokens.lg),
              if (state.status == PosFeatureStatus.failure &&
                  state.failure != null)
                _buildFailureCard(context, state.failure!.messageAr),
              if ((!state.isEnabled || state.requiresUpgrade) &&
                  !state.isBusy) ...[
                _buildWarningCard(context, state),
                const SizedBox(height: SpacingTokens.lg),
              ],
              _buildAction(context, state),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIntro(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.posFeaturePageTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        Text(
          AppStrings.posFeaturePageDescription,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context, PosFeatureState state) {
    final theme = Theme.of(context);
    final active = state.isEnabled;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md,
          vertical: SpacingTokens.sm,
        ),
        leading: CircleAvatar(
          backgroundColor: (active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest)
              .withValues(alpha: 0.16),
          child: Icon(
            active ? Icons.point_of_sale_rounded : Icons.point_of_sale_outlined,
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          active ? AppStrings.posFeatureEnabled : AppStrings.posFeatureDisabled,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: state.isBusy
            ? const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              )
            : state.requiresUpgrade
                ? Text(AppStrings.posFeatureUpgradeRequired)
                : null,
      ),
    );
  }

  Widget _buildWarningCard(BuildContext context, PosFeatureState state) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: Text(
                state.requiresUpgrade
                    ? AppStrings.posFeatureUpgradeWarning
                    : AppStrings.posFeatureActivationWarning,
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailureCard(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Text(
          message,
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context, PosFeatureState state) {
    if (state.isBusy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.isEnabled) {
      if (state.requiresUpgrade) {
        return FilledButton.icon(
          onPressed: () => _confirmActivation(context),
          icon: const Icon(Icons.upgrade_rounded),
          label: Text(AppStrings.posFeatureUpgrade),
        );
      }
      return OutlinedButton.icon(
        onPressed: () => context.read<PosFeatureCubit>().disable(),
        icon: const Icon(Icons.visibility_off_outlined),
        label: Text(AppStrings.posFeatureDisable),
      );
    }
    return FilledButton.icon(
      onPressed: () => _confirmActivation(context),
      icon: const Icon(Icons.point_of_sale_outlined),
      label: Text(AppStrings.posFeatureActivate),
    );
  }

  Future<void> _confirmActivation(BuildContext context) async {
    final cubit = context.read<PosFeatureCubit>();
    final upgrading = cubit.state.requiresUpgrade;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          upgrading ? AppStrings.posFeatureUpgrade : AppStrings.posFeatureActivate,
        ),
        content: Text(
          upgrading
              ? AppStrings.posFeatureUpgradeWarning
              : AppStrings.posFeatureActivationWarning,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.posFeatureCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              upgrading
                  ? AppStrings.posFeatureConfirmUpgrade
                  : AppStrings.posFeatureConfirm,
            ),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await cubit.activate();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
