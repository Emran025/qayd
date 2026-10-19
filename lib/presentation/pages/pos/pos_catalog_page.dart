import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/application/pos/create_pos_product_use_case.dart';
import 'package:qayd/di/injection_container.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/navigation/qayd_page_route.dart';
import 'package:qayd/presentation/pos/pos_money_display.dart';
import 'package:qayd/presentation/pos/pos_catalog_cubit.dart';
import 'package:qayd/presentation/theme/qayd_theme_extensions.dart';
import 'package:qayd/presentation/theme/radius_tokens.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';

/// POS product catalog screen. The page is presentation-only: all writes and
/// reads are delegated to [PosCatalogCubit].
class PosCatalogPage extends StatelessWidget {
  const PosCatalogPage({
    super.key,
    required this.currency,
    this.cubit,
  });

  final CurrencyCode currency;
  final PosCatalogCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final catalogCubit = cubit ?? InjectionContainer.posCatalogCubit;
    return BlocProvider.value(
      value: catalogCubit,
      child: _PosCatalogView(currency: currency),
    );
  }
}

class _PosCatalogView extends StatefulWidget {
  const _PosCatalogView({required this.currency});

  final CurrencyCode currency;

  @override
  State<_PosCatalogView> createState() => _PosCatalogViewState();
}

class _PosCatalogViewState extends State<_PosCatalogView> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PosCatalogCubit>().load();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final query = value.trim();
      context
          .read<PosCatalogCubit>()
          .load(search: query.isEmpty ? null : query);
    });
  }

  Future<void> _openCreate() async {
    final input = await showModalBottomSheet<CreatePosProductInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreateProductSheet(currency: widget.currency),
    );
    if (input == null || !mounted) return;
    await context.read<PosCatalogCubit>().create(input);
  }

  Future<void> _confirmDeactivate(PosProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.posCatalogDeactivateTitle),
        content: Text(AppStrings.posCatalogDeactivateMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.posCatalogDeactivate),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<PosCatalogCubit>().deactivate(product.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<QaydCustomColors>()!;
    return BlocListener<PosCatalogCubit, PosCatalogState>(
      listener: (context, state) {
        if (state.status == PosCatalogStatus.failure && state.failure != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.failure!.messageAr)));
        }
      },
      child: Scaffold(
        appBar: QaydAppBar(title: AppStrings.posCatalogTitle),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'fab_pos_catalog_add',
          onPressed: _openCreate,
          icon: const Icon(Icons.add_rounded),
          label: Text(AppStrings.posCatalogAddProduct),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.md,
                SpacingTokens.sm,
                SpacingTokens.md,
                SpacingTokens.xs,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: AppStrings.posCatalogSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: AppStrings.actionCancel,
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(RadiusTokens.md),
                  ),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: BlocBuilder<PosCatalogCubit, PosCatalogState>(
                builder: (context, state) {
                  if (state.status == PosCatalogStatus.initial ||
                      state.status == PosCatalogStatus.loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state.status == PosCatalogStatus.failure) {
                    return _FailureState(
                      message: state.failure?.messageAr ??
                          AppStrings.posProductReadFailed,
                      onRetry: () => context
                          .read<PosCatalogCubit>()
                          .load(search: state.search),
                    );
                  }
                  if (state.products.isEmpty) {
                    return _EmptyState(
                      hasSearch: state.search?.isNotEmpty == true,
                      onAdd: _openCreate,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () => context
                        .read<PosCatalogCubit>()
                        .load(search: state.search),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        SpacingTokens.md,
                        SpacingTokens.sm,
                        SpacingTokens.md,
                        SpacingTokens.xxl,
                      ),
                      itemCount: state.products.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: SpacingTokens.sm),
                      itemBuilder: (_, index) => _ProductCard(
                        product: state.products[index],
                        colors: colors,
                        onDeactivate: () =>
                            _confirmDeactivate(state.products[index]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.colors,
    required this.onDeactivate,
  });

  final PosProduct product;
  final QaydCustomColors colors;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final barcode = product.primaryBarcode?.value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: colors.goldAccent.withValues(alpha: 0.14),
              foregroundColor: colors.goldAccent,
              child: const Icon(Icons.inventory_2_outlined),
            ),
            const SizedBox(width: SpacingTokens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: SpacingTokens.xs),
                  Text('${AppStrings.posCatalogSku}: ${product.sku}'),
                  if (barcode != null)
                    Text('${AppStrings.posCatalogBarcode}: $barcode'),
                  const SizedBox(height: SpacingTokens.sm),
                  Wrap(
                    spacing: SpacingTokens.md,
                    runSpacing: SpacingTokens.xs,
                    children: [
                      Text(
                        '${AppStrings.posCatalogSalePrice}: ${formatPosMoney(product.salePrice)}',
                      ),
                      Text(
                        '${AppStrings.posCatalogPurchasePrice}: ${formatPosMoney(product.purchasePrice)}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'deactivate') onDeactivate();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'deactivate',
                  child: Text(AppStrings.posCatalogDeactivate),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureState extends StatelessWidget {
  const _FailureState({required this.message, required this.onRetry});

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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasSearch, required this.onAdd});

  final bool hasSearch;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 64),
            const SizedBox(height: SpacingTokens.md),
            Text(
              hasSearch
                  ? AppStrings.posCatalogNoResults
                  : AppStrings.posCatalogEmpty,
              textAlign: TextAlign.center,
            ),
            if (!hasSearch) ...[
              const SizedBox(height: SpacingTokens.md),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: Text(AppStrings.posCatalogAddProduct),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateProductSheet extends StatefulWidget {
  const _CreateProductSheet({required this.currency});

  final CurrencyCode currency;

  @override
  State<_CreateProductSheet> createState() => _CreateProductSheetState();
}

class _CreateProductSheetState extends State<_CreateProductSheet> {
  final _formKey = GlobalKey<FormState>();
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _salePrice = TextEditingController();
  final _purchasePrice = TextEditingController();
  final _quantityScale = TextEditingController(text: '0');
  final _reorderLevel = TextEditingController(text: '0');
  final _barcode = TextEditingController();
  final _description = TextEditingController();
  bool _expiryTracking = false;

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _salePrice.dispose();
    _purchasePrice.dispose();
    _quantityScale.dispose();
    _reorderLevel.dispose();
    _barcode.dispose();
    _description.dispose();
    super.dispose();
  }

  String? _required(String? value, String message) {
    return value == null || value.trim().isEmpty ? message : null;
  }

  String? _nonNegativeInteger(String? value, String message) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return message;
    final parsed = int.tryParse(raw);
    return parsed == null || parsed < 0 ? message : null;
  }

  String? _scaleValidator(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < 0 || parsed > 6
        ? AppStrings.posProductScaleInvalid
        : null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final scale = int.parse(_quantityScale.text.trim());
    final barcode = _barcode.text.trim();
    Navigator.of(context).pop(
      CreatePosProductInput(
        sku: _sku.text.trim(),
        name: _name.text.trim(),
        currencyCode: widget.currency.code,
        salePriceMinor: int.parse(_salePrice.text.trim()),
        purchasePriceMinor: int.parse(_purchasePrice.text.trim()),
        quantityScale: scale,
        reorderLevelScaled: int.parse(_reorderLevel.text.trim()),
        expiryTracking: _expiryTracking,
        barcodes: barcode.isEmpty ? const <String>[] : [barcode],
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SpacingTokens.md,
        SpacingTokens.md,
        SpacingTokens.md,
        bottomInset + SpacingTokens.md,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStrings.posCatalogCreateTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: SpacingTokens.md),
              _field(
                controller: _name,
                label: AppStrings.posCatalogName,
                validator: (value) =>
                    _required(value, AppStrings.posProductNameRequired),
              ),
              _field(
                controller: _sku,
                label: AppStrings.posCatalogSku,
                validator: (value) =>
                    _required(value, AppStrings.posProductSkuRequired),
              ),
              _field(
                controller: _salePrice,
                label: AppStrings.posCatalogSalePriceMinor,
                keyboardType: TextInputType.number,
                validator: (value) => _nonNegativeInteger(
                    value, AppStrings.posProductPriceInvalid),
              ),
              _field(
                controller: _purchasePrice,
                label: AppStrings.posCatalogPurchasePriceMinor,
                keyboardType: TextInputType.number,
                validator: (value) => _nonNegativeInteger(
                    value, AppStrings.posProductPriceInvalid),
              ),
              _field(
                controller: _quantityScale,
                label: AppStrings.posCatalogQuantityScale,
                keyboardType: TextInputType.number,
                validator: _scaleValidator,
              ),
              _field(
                controller: _reorderLevel,
                label: AppStrings.posCatalogReorderLevel,
                keyboardType: TextInputType.number,
                validator: (value) => _nonNegativeInteger(
                  value,
                  AppStrings.posProductThresholdInvalid,
                ),
              ),
              _field(
                controller: _barcode,
                label: AppStrings.posCatalogBarcode,
                keyboardType: TextInputType.number,
              ),
              _field(
                controller: _description,
                label: AppStrings.posCatalogDescription,
                maxLines: 2,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _expiryTracking,
                onChanged: (value) => setState(() => _expiryTracking = value),
                title: Text(AppStrings.posCatalogExpiryTracking),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(AppStrings.actionCancel),
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: Text(AppStrings.save),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RadiusTokens.md),
          ),
          isDense: true,
        ),
      ),
    );
  }
}

// Kept as a local reference for navigation callers that want the standard Qayd
// transition without making the catalog screen depend on a router singleton.
Route<void> posCatalogRoute({required CurrencyCode currency}) =>
    QaydPageRoute.slideFromStart<void>(
      builder: (_) => PosCatalogPage(currency: currency),
    );
