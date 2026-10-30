import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/components/atomic/qayd_empty_state.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/navigation/qayd_page_route.dart';
import 'package:qayd/presentation/pages/pos/pos_catalog_page.dart';
import 'package:qayd/presentation/pages/pos/pos_opening_balance_page.dart';
import 'package:qayd/presentation/pages/pos/pos_checkout_page.dart';
import 'package:qayd/presentation/pages/pos/pos_invoice_history_page.dart';
import 'package:qayd/presentation/pages/pos/pos_daily_sales_report_page.dart';
import 'package:qayd/presentation/pages/pos/pos_purchase_receiving_page.dart';
import 'package:qayd/presentation/pages/pos/pos_stock_movements_page.dart';
import 'package:qayd/presentation/pages/pos/widgets/pos_workspace_action_card.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/presentation/pages/settings/pos_feature_settings_page.dart';
import 'package:qayd/presentation/pos/pos_invoice_history_cubit.dart';
import 'package:qayd/di/injection_container.dart';
import 'package:qayd/presentation/pos/pos_workspace_cubit.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/widgets/qayd_scaffold.dart';

/// Visually independent POS workspace hosted inside the main Qayd app.
///
/// The workspace shares Qayd's database, identity, theme, and composition root;
/// it is not a separate Flutter app or database.
class PosWorkspacePage extends StatelessWidget {
  const PosWorkspacePage({
    super.key,
    required this.cubit,
  });

  final PosWorkspaceCubit cubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      child: const _PosWorkspaceView(),
    );
  }
}

class _PosWorkspaceView extends StatefulWidget {
  const _PosWorkspaceView();

  @override
  State<_PosWorkspaceView> createState() => _PosWorkspaceViewState();
}

class _PosWorkspaceViewState extends State<_PosWorkspaceView> {
  @override
  void initState() {
    super.initState();
    context.read<PosWorkspaceCubit>().load();
  }

  Future<void> _openOpeningBalance(PosWorkspaceState state) async {
    if (!state.isReady || !mounted) return;
    await Navigator.of(context).push<void>(
      QaydPageRoute.slideFromStart<void>(
        builder: (_) => PosOpeningBalancePage(
          catalogCubit: InjectionContainer.posCatalogCubit,
          stockCubit: InjectionContainer.posStockCubit,
          warehouseId: state.warehouseId!,
          postOpeningBalance:
              InjectionContainer.postPosOpeningBalanceAtomicallyUseCase.call,
        ),
      ),
    );
  }

  Future<void> _openCheckout(PosWorkspaceState state) async {
    if (!state.isReady || !mounted) return;
    await Navigator.of(context).push<void>(
      QaydPageRoute.slideFromStart<void>(
        builder: (_) => PosCheckoutPage(
          cubit: InjectionContainer.posCheckoutCubit,
          warehouseId: state.warehouseId!,
          currency: state.currency!,
        ),
      ),
    );
  }

  Future<void> _openPurchaseReceiving(PosWorkspaceState state) async {
    if (!state.isReady || !mounted) return;
    await Navigator.of(context).push<void>(
      QaydPageRoute.slideFromStart<void>(
        builder: (_) => PosPurchaseReceivingPage(
          warehouseId: state.warehouseId!,
          currency: state.currency!,
          listProducts: InjectionContainer.listPosProductsUseCase,
          listAccounts: InjectionContainer.listAccountsUseCase,
          completePurchase: InjectionContainer.completePosPurchaseUseCase,
          requestIdentityRepository:
              InjectionContainer.posPurchaseRequestIdentityRepository,
        ),
      ),
    );
  }

  Future<void> _openInvoiceHistory(PosWorkspaceState state) async {
    if (!state.isReady || !mounted) return;
    await Navigator.of(context).push<void>(
      QaydPageRoute.slideFromStart<void>(
        builder: (_) => PosInvoiceHistoryPage(
          cubit: PosInvoiceHistoryCubit(
            listInvoices: InjectionContainer.listPosInvoicesUseCase,
          ),
          detailsUseCase: InjectionContainer.getPosInvoiceDetailsUseCase,
          pdfUseCase: InjectionContainer.buildPosInvoicePdfUseCase,
        ),
      ),
    );
  }

  Future<void> _openStockMovements(PosWorkspaceState state) async {
    if (!state.isReady || !mounted) return;
    final installation =
        await InjectionContainer.posTemplateInstallationRepository
            .getEnabledInstallation(template: PosTemplateDefinition.current());
    if (!mounted) return;
    if (installation.isFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            installation.failureOrNull?.messageAr ??
                AppStrings.posAccountingAccountsRequired,
          ),
        ),
      );
      return;
    }
    final inventoryAccountId = installation.valueOrNull?.accountIdsByKey[
      PosTemplateAccountKey.inventoryAsset.value
    ];
    if (inventoryAccountId == null || inventoryAccountId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.posAccountingAccountsRequired)),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      QaydPageRoute.slideFromStart<void>(
        builder: (_) => PosStockMovementsPage(
          warehouseId: state.warehouseId!,
          currency: state.currency!,
          listMovements: InjectionContainer.listPosStockMovementsUseCase,
          listProducts: InjectionContainer.listPosProductsUseCase,
          listAccounts: InjectionContainer.listAccountsUseCase,
          getBalance: InjectionContainer.getPosStockBalanceUseCase,
          submitAdjustment: InjectionContainer
              .postPosStockAdjustmentAtomicallyUseCase.call,
          inventoryAccountId: inventoryAccountId,
        ),
      ),
    );
  }

  Future<void> _openDailySalesReport(PosWorkspaceState state) async {
    if (!state.isReady || !mounted) return;
    await Navigator.of(context).push<void>(
      QaydPageRoute.slideFromStart<void>(
        builder: (_) => PosDailySalesReportPage(
          reportUseCase: InjectionContainer.buildPosDailySalesReportUseCase,
          pdfUseCase: InjectionContainer.buildPosInvoicePdfUseCase,
          currency: state.currency!,
        ),
      ),
    );
  }

  Future<void> _openCatalog(PosWorkspaceState state) async {
    final currency = state.currency;
    if (currency == null || !state.isReady || !mounted) return;
    await Navigator.of(context).push<void>(
      QaydPageRoute.slideFromStart<void>(
        builder: (_) => PosCatalogPage(currency: currency),
      ),
    );
  }

  Future<void> _openPosFeatureSettings() async {
    await Navigator.of(context).push<void>(
      QaydPageRoute.slideFromStart<void>(
        builder: (_) => PosFeatureSettingsPage(
          cubit: InjectionContainer.posFeatureCubit,
        ),
      ),
    );
    if (!mounted) return;
    context.read<PosWorkspaceCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PosWorkspaceCubit, PosWorkspaceState>(
      builder: (context, state) {
        return QaydScaffold(
          appBar: QaydAppBar(title: AppStrings.posWorkspaceTitle),
          body: switch (state.status) {
            PosWorkspaceStatus.initial ||
            PosWorkspaceStatus.loading =>
              const Center(child: CircularProgressIndicator()),
            PosWorkspaceStatus.disabled => _DisabledWorkspace(
                onOpenSettings: _openPosFeatureSettings,
              ),
            PosWorkspaceStatus.failure => _WorkspaceFailure(
                message: state.failure?.messageAr ??
                    AppStrings.posWorkspaceLoadFailed,
                onRetry: () => context.read<PosWorkspaceCubit>().load(),
              ),
            PosWorkspaceStatus.ready => _ReadyWorkspace(
                state: state,
                onOpenCatalog: () => _openCatalog(state),
                onOpenOpeningBalance: () => _openOpeningBalance(state),
                onOpenPurchaseReceiving: () => _openPurchaseReceiving(state),
                onOpenStockMovements: () => _openStockMovements(state),
                onOpenCheckout: () => _openCheckout(state),
                onOpenInvoiceHistory: () => _openInvoiceHistory(state),
                onOpenDailySalesReport: () => _openDailySalesReport(state),
              ),
          },
        );
      },
    );
  }
}

class _ReadyWorkspace extends StatelessWidget {
  const _ReadyWorkspace({
    required this.state,
    required this.onOpenCatalog,
    required this.onOpenOpeningBalance,
    required this.onOpenPurchaseReceiving,
    required this.onOpenStockMovements,
    required this.onOpenCheckout,
    required this.onOpenInvoiceHistory,
    required this.onOpenDailySalesReport,
  });

  final PosWorkspaceState state;
  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenOpeningBalance;
  final VoidCallback onOpenPurchaseReceiving;
  final VoidCallback onOpenStockMovements;
  final VoidCallback onOpenCheckout;
  final VoidCallback onOpenInvoiceHistory;
  final VoidCallback onOpenDailySalesReport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      children: [
        Text(
          AppStrings.posWorkspaceWelcome,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: SpacingTokens.sm),
        Text(AppStrings.posWorkspaceDescription),
        const SizedBox(height: SpacingTokens.lg),
        Text(
          AppStrings.posWorkspaceInventorySection,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: SpacingTokens.sm),
        PosWorkspaceActionCard(
          icon: Icons.inventory_2_outlined,
          title: AppStrings.posCatalogTitle,
          subtitle: AppStrings.posWorkspaceCatalogSubtitle,
          accent: colors.primary,
          onTap: onOpenCatalog,
        ),
        const SizedBox(height: SpacingTokens.md),
        PosWorkspaceActionCard(
          icon: Icons.account_balance_wallet_outlined,
          title: AppStrings.posOpeningBalanceTitle,
          subtitle: AppStrings.posOpeningBalanceDescription,
          accent: colors.secondary,
          onTap: onOpenOpeningBalance,
        ),
        const SizedBox(height: SpacingTokens.md),
        PosWorkspaceActionCard(
          icon: Icons.local_shipping_outlined,
          title: AppStrings.posPurchaseTitle,
          subtitle: AppStrings.posWorkspacePurchaseSubtitle,
          accent: colors.tertiary,
          onTap: onOpenPurchaseReceiving,
        ),
        const SizedBox(height: SpacingTokens.md),
        PosWorkspaceActionCard(
          icon: Icons.swap_vert_rounded,
          title: AppStrings.posStockMovementsTitle,
          subtitle: AppStrings.posStockMovementsDescription,
          accent: colors.primary,
          onTap: onOpenStockMovements,
        ),
        const SizedBox(height: SpacingTokens.lg),
        Text(
          AppStrings.posWorkspaceSalesSection,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: SpacingTokens.sm),
        PosWorkspaceActionCard(
          icon: Icons.point_of_sale_outlined,
          title: AppStrings.posWorkspaceSalesTitle,
          subtitle: AppStrings.posCheckoutInputHint,
          accent: colors.tertiary,
          onTap: onOpenCheckout,
        ),
        const SizedBox(height: SpacingTokens.md),
        PosWorkspaceActionCard(
          icon: Icons.receipt_long_outlined,
          title: AppStrings.posInvoiceHistoryTitle,
          subtitle: AppStrings.posInvoiceExportPdf,
          accent: colors.secondary,
          onTap: onOpenInvoiceHistory,
        ),
        const SizedBox(height: SpacingTokens.md),
        PosWorkspaceActionCard(
          icon: Icons.analytics_outlined,
          title: AppStrings.posDailySalesReportTitle,
          subtitle: AppStrings.posDailySalesGross,
          accent: colors.primary,
          onTap: onOpenDailySalesReport,
        ),
      ],
    );
  }
}

class _DisabledWorkspace extends StatelessWidget {
  const _DisabledWorkspace({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return QaydEmptyState(
      icon: Icons.lock_outline_rounded,
      title: AppStrings.posWorkspaceDisabled,
      description: AppStrings.posWorkspaceEnableFromSettings,
      action: FilledButton.icon(
        onPressed: onOpenSettings,
        icon: const Icon(Icons.settings_outlined),
        label: Text(AppStrings.posWorkspaceOpenSettings),
      ),
    );
  }
}

class _WorkspaceFailure extends StatelessWidget {
  const _WorkspaceFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => QaydEmptyState(
        icon: Icons.error_outline_rounded,
        title: message,
        action: FilledButton.tonal(
          onPressed: onRetry,
          child: Text(AppStrings.retryAction),
        ),
      );
}
