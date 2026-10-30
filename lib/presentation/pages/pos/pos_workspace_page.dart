import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/navigation/qayd_page_route.dart';
import 'package:qayd/presentation/pages/pos/pos_catalog_page.dart';
import 'package:qayd/presentation/pages/pos/pos_opening_balance_page.dart';
import 'package:qayd/presentation/pages/pos/pos_checkout_page.dart';
import 'package:qayd/presentation/pages/pos/pos_invoice_history_page.dart';
import 'package:qayd/presentation/pages/pos/pos_daily_sales_report_page.dart';
import 'package:qayd/presentation/pos/pos_invoice_history_cubit.dart';
import 'package:qayd/di/injection_container.dart';
import 'package:qayd/presentation/pos/pos_workspace_cubit.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';

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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PosWorkspaceCubit, PosWorkspaceState>(
      builder: (context, state) {
        return Scaffold(
          appBar: QaydAppBar(title: AppStrings.posWorkspaceTitle),
          body: switch (state.status) {
            PosWorkspaceStatus.initial ||
            PosWorkspaceStatus.loading =>
              const Center(child: CircularProgressIndicator()),
            PosWorkspaceStatus.disabled => _DisabledWorkspace(
                onOpenSettings: () => Navigator.of(context).maybePop(),
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
    required this.onOpenCheckout,
    required this.onOpenInvoiceHistory,
    required this.onOpenDailySalesReport,
  });

  final PosWorkspaceState state;
  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenOpeningBalance;
  final VoidCallback onOpenCheckout;
  final VoidCallback onOpenInvoiceHistory;
  final VoidCallback onOpenDailySalesReport;

  @override
  Widget build(BuildContext context) {
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
        Card(
          child: ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(AppStrings.posCatalogTitle),
            subtitle: Text(AppStrings.posWorkspaceCatalogSubtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpenCatalog,
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(AppStrings.posOpeningBalanceTitle),
            subtitle: Text(AppStrings.posOpeningBalanceDescription),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpenOpeningBalance,
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        Card(
          child: ListTile(
            leading: const Icon(Icons.point_of_sale_outlined),
            title: Text(AppStrings.posWorkspaceSalesTitle),
            subtitle: Text(AppStrings.posCheckoutInputHint),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpenCheckout,
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(AppStrings.posInvoiceHistoryTitle),
            subtitle: Text(AppStrings.posInvoiceExportPdf),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpenInvoiceHistory,
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        Card(
          child: ListTile(
            leading: const Icon(Icons.analytics_outlined),
            title: Text(AppStrings.posDailySalesReportTitle),
            subtitle: Text(AppStrings.posDailySalesGross),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpenDailySalesReport,
          ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 56),
            const SizedBox(height: SpacingTokens.md),
            Text(
              AppStrings.posWorkspaceDisabled,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              AppStrings.posWorkspaceEnableFromSettings,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SpacingTokens.lg),
            FilledButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
              label: Text(AppStrings.actionCancel),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceFailure extends StatelessWidget {
  const _WorkspaceFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: SpacingTokens.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: SpacingTokens.md),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(AppStrings.retryAction),
            ),
          ],
        ),
      ),
    );
  }
}
