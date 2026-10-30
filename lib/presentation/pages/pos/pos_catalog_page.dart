import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/application/pos/create_pos_product_use_case.dart';
import 'package:qayd/application/pos/create_pos_product_category_use_case.dart';
import 'package:qayd/application/pos/list_pos_product_categories_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/di/injection_container.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_product_category.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_barcode.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/presentation/pages/pos/pos_product_categories_page.dart';
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
    this.listCategoriesUseCase,
    this.createCategoryUseCase,
  });

  final CurrencyCode currency;
  final PosCatalogCubit? cubit;
  final ListPosProductCategoriesUseCase? listCategoriesUseCase;
  final CreatePosProductCategoryUseCase? createCategoryUseCase;

  @override
  Widget build(BuildContext context) {
    final catalogCubit = cubit ?? InjectionContainer.posCatalogCubit;
    final categoriesUseCase = listCategoriesUseCase ??
        (cubit == null
            ? InjectionContainer.listPosProductCategoriesUseCase
            : null);
    final categoryCreationUseCase = createCategoryUseCase ??
        (cubit == null
            ? InjectionContainer.createPosProductCategoryUseCase
            : null);
    return BlocProvider.value(
      value: catalogCubit,
      child: _PosCatalogView(
        currency: currency,
        listCategoriesUseCase: categoriesUseCase,
        createCategoryUseCase: categoryCreationUseCase,
      ),
    );
  }
}

class _PosCatalogView extends StatefulWidget {
  const _PosCatalogView({
    required this.currency,
    required this.listCategoriesUseCase,
    required this.createCategoryUseCase,
  });

  final CurrencyCode currency;
  final ListPosProductCategoriesUseCase? listCategoriesUseCase;
  final CreatePosProductCategoryUseCase? createCategoryUseCase;

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
    final useCase = widget.listCategoriesUseCase;
    final categoriesResult = useCase == null ? null : await useCase();
    final categories =
        categoriesResult?.valueOrNull ?? const <PosProductCategory>[];
    if (!mounted) return;
    final input = await showModalBottomSheet<CreatePosProductInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreateProductSheet(
        currency: widget.currency,
        categories: categories,
        createCategoryUseCase: widget.createCategoryUseCase,
      ),
    );
    if (input == null || !mounted) return;
    await context.read<PosCatalogCubit>().create(input);
  }

  Future<void> _openEdit(PosProduct product) async {
    final categories = widget.listCategoriesUseCase == null ? const <PosProductCategory>[] : (await widget.listCategoriesUseCase!()).valueOrNull ?? const <PosProductCategory>[];
    if (!mounted) return;
    final edited = await showModalBottomSheet<PosProduct>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => _EditProductSheet(product: product, categories: categories));
    if (edited != null && mounted) await context.read<PosCatalogCubit>().save(edited);
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

  Future<void> _reactivate(PosProduct product) async {
    await context.read<PosCatalogCubit>().reactivate(product.id);
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
        appBar: QaydAppBar(title: AppStrings.posCatalogTitle, actions: [IconButton(icon: const Icon(Icons.category_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PosProductCategoriesPage())))]),
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
            BlocBuilder<PosCatalogCubit, PosCatalogState>(
              buildWhen: (previous, current) =>
                  previous.includeInactive != current.includeInactive,
              builder: (context, state) => SwitchListTile.adaptive(
                value: state.includeInactive,
                title: Text(AppStrings.posCatalogShowInactive),
                onChanged: (value) => context
                    .read<PosCatalogCubit>()
                    .load(includeInactive: value),
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
                        onEdit: () => _openEdit(state.products[index]),
                        onDeactivate: () =>
                            _confirmDeactivate(state.products[index]),
                        onReactivate: () => _reactivate(state.products[index]),
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
    required this.onReactivate,
    required this.onEdit,
  });

  final PosProduct product;
  final QaydCustomColors colors;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final barcodes = product.barcodes.map((barcode) => barcode.value).join(', ');
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
                  if (barcodes.isNotEmpty)
                    Text('${AppStrings.posCatalogBarcode}: $barcodes'),
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
                if (value == 'edit') onEdit();
                if (value == 'deactivate') onDeactivate();
                if (value == 'reactivate') onReactivate();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(AppStrings.posCatalogEditTitle)),
                PopupMenuItem(
                  value: product.isActive ? 'deactivate' : 'reactivate',
                  child: Text(product.isActive
                      ? AppStrings.posCatalogDeactivate
                      : AppStrings.posCatalogReactivate),
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
  const _CreateProductSheet({
    required this.currency,
    required this.categories,
    required this.createCategoryUseCase,
  });

  final CurrencyCode currency;
  final List<PosProductCategory> categories;
  final CreatePosProductCategoryUseCase? createCategoryUseCase;

  @override
  State<_CreateProductSheet> createState() => _CreateProductSheetState();
}

class _CreateProductSheetState extends State<_CreateProductSheet> {
  final _formKey = GlobalKey<FormState>();
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _salePrice = TextEditingController();
  final _purchasePrice = TextEditingController();
  final _unitName = TextEditingController(text: 'unit');
  final _quantityScale = TextEditingController(text: '0');
  final _reorderLevel = TextEditingController(text: '0');
  final _barcode = TextEditingController();
  final _description = TextEditingController();
  bool _expiryTracking = false;
  String? _categoryId;
  late final List<PosProductCategory> _categories = [...widget.categories];

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _salePrice.dispose();
    _purchasePrice.dispose();
    _unitName.dispose();
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

  Future<void> _addCategory() async {
    final useCase = widget.createCategoryUseCase;
    if (useCase == null) return;

    final draft = await showDialog<({String name, String code})>(
      context: context,
      builder: (_) => const _CreateProductCategoryDialog(),
    );
    if (draft == null || !mounted) return;

    final result = await useCase(
      CreatePosProductCategoryInput(name: draft.name, code: draft.code),
    );
    if (!mounted) return;
    final category = result.valueOrNull;
    if (category == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.failureOrNull?.messageAr ??
                  AppStrings.posProductSaveFailed,
            ),
          ),
        );
      return;
    }

    setState(() {
      _categories.add(category);
      _categoryId = category.id;
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final scale = int.parse(_quantityScale.text.trim());
    final barcodes = _barcode.text.split(RegExp(r'[,\n]')).map((value) => value.trim()).where((value) => value.isNotEmpty).toList(growable: false);
    Navigator.of(context).pop(
      CreatePosProductInput(
        sku: _sku.text.trim(),
        name: _name.text.trim(),
        currencyCode: widget.currency.code,
        salePriceMinor: int.parse(_salePrice.text.trim()),
        purchasePriceMinor: int.parse(_purchasePrice.text.trim()),
        unitName: _unitName.text.trim(),
        categoryId: _categoryId,
        quantityScale: scale,
        reorderLevelScaled: int.parse(_reorderLevel.text.trim()),
        expiryTracking: _expiryTracking,
        barcodes: barcodes,
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
                controller: _unitName,
                label: AppStrings.posCatalogUnit,
                validator: (value) =>
                    _required(value, AppStrings.posProductUnitRequired),
              ),
              DropdownButtonFormField<String>(
                initialValue: _categoryId ?? '',
                decoration: InputDecoration(
                  labelText: AppStrings.posCatalogCategory,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(RadiusTokens.md),
                  ),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text(AppStrings.posCatalogNoCategory),
                  ),
                  ..._categories.map(
                    (category) => DropdownMenuItem<String>(
                      value: category.id,
                      child: Text('${category.name} (${category.code})'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _categoryId =
                      value == null || value.isEmpty ? null : value,
                ),
              ),
              if (widget.createCategoryUseCase != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _addCategory,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(AppStrings.posCatalogAddCategory),
                  ),
                ),
              const SizedBox(height: SpacingTokens.sm),
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
                label: AppStrings.posCatalogBarcodesHint,
                keyboardType: TextInputType.text,
                maxLines: 3,
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

class _CreateProductCategoryDialog extends StatefulWidget {
  const _CreateProductCategoryDialog();

  @override
  State<_CreateProductCategoryDialog> createState() =>
      _CreateProductCategoryDialogState();
}

class _CreateProductCategoryDialogState
    extends State<_CreateProductCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(AppStrings.posCatalogCreateCategory),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: AppStrings.posCatalogCategoryName,
                ),
                validator: (value) => _required(
                  value,
                  AppStrings.posCatalogCategoryNameRequired,
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              TextFormField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: AppStrings.posCatalogCategoryCode,
                ),
                validator: (value) => _required(
                  value,
                  AppStrings.posCatalogCategoryCodeRequired,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppStrings.actionCancel),
          ),
          FilledButton(
            onPressed: () {
              if (!(_formKey.currentState?.validate() ?? false)) return;
              Navigator.of(context).pop((
                name: _nameController.text.trim(),
                code: _codeController.text.trim(),
              ));
            },
            child: Text(AppStrings.posCatalogAddCategory),
          ),
        ],
      );
}

// Kept as a local reference for navigation callers that want the standard Qayd
// transition without making the catalog screen depend on a router singleton.
Route<void> posCatalogRoute({required CurrencyCode currency}) =>
    QaydPageRoute.slideFromStart<void>(
      builder: (_) => PosCatalogPage(currency: currency),
    );

class _EditProductSheet extends StatefulWidget {
  const _EditProductSheet({required this.product, required this.categories});
  final PosProduct product;
  final List<PosProductCategory> categories;
  @override State<_EditProductSheet> createState() => _EditProductSheetState();
}

class _EditProductSheetState extends State<_EditProductSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product.name);
  late final _sku = TextEditingController(text: widget.product.sku);
  late final _sale = TextEditingController(text: '${widget.product.salePrice.minorUnits}');
  late final _purchase = TextEditingController(text: '${widget.product.purchasePrice.minorUnits}');
  late final _unit = TextEditingController(text: widget.product.unitName);
  late final _reorder = TextEditingController(text: '${widget.product.reorderLevel.scaledUnits}');
  late final _barcodes = TextEditingController(text: widget.product.barcodes.map((b) => b.value).join('\n'));
  late final _description = TextEditingController(text: widget.product.description ?? '');
  String? _categoryId;
  late bool _expiryTracking = widget.product.expiryTracking;

  @override
  void initState() { super.initState(); _categoryId = widget.product.categoryId; }
  @override
  void dispose() {
    for (final c in [_name, _sku, _sale, _purchase, _unit, _reorder, _barcodes, _description]) c.dispose();
    super.dispose();
  }
  String? _required(String? value, String message) => value == null || value.trim().isEmpty ? message : null;
  String? _nonNegative(String? value, String message) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < 0 ? message : null;
  }
  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      final barcodes = _barcodes.text.split(RegExp(r'[,\n]')).map((v) => v.trim()).where((v) => v.isNotEmpty).map(PosBarcode.new).toList(growable: false);
      final edited = widget.product.updateDetails(
        name: _name.text, sku: _sku.text,
        salePrice: Money.fromMinorUnits(int.parse(_sale.text.trim()), widget.product.currency),
        purchasePrice: Money.fromMinorUnits(int.parse(_purchase.text.trim()), widget.product.currency),
        unitName: _unit.text, categoryId: _categoryId, clearCategory: _categoryId == null,
        description: _description.text, clearDescription: _description.text.trim().isEmpty,
        reorderLevel: PosQuantity.fromScaled(int.parse(_reorder.text.trim()), scale: widget.product.quantityScale),
        expiryTracking: _expiryTracking, barcodes: barcodes,
      );
      Navigator.of(context).pop(edited);
    } catch (error) {
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, bottomInset + SpacingTokens.md),
      child: SingleChildScrollView(child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(AppStrings.posCatalogEditTitle, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: SpacingTokens.md),
        _field(_name, AppStrings.posCatalogName, (v) => _required(v, AppStrings.posProductNameRequired)),
        _field(_sku, AppStrings.posCatalogSku, (v) => _required(v, AppStrings.posProductSkuRequired)),
        _field(_sale, AppStrings.posCatalogSalePriceMinor, (v) => _nonNegative(v, AppStrings.posProductPriceInvalid), keyboardType: TextInputType.number),
        _field(_purchase, AppStrings.posCatalogPurchasePriceMinor, (v) => _nonNegative(v, AppStrings.posProductPriceInvalid), keyboardType: TextInputType.number),
        _field(_unit, AppStrings.posCatalogUnit, (v) => _required(v, AppStrings.posProductUnitRequired)),
        DropdownButtonFormField<String?>(
          value: _categoryId,
          decoration: InputDecoration(labelText: AppStrings.posCatalogCategory),
          items: [DropdownMenuItem<String?>(value: null, child: Text(AppStrings.posCatalogNoCategory)), ...widget.categories.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text('${c.name} (${c.code})')))],
          onChanged: (value) => setState(() => _categoryId = value),
        ),
        const SizedBox(height: SpacingTokens.sm),
        TextFormField(initialValue: '${widget.product.quantityScale}', readOnly: true, decoration: InputDecoration(labelText: AppStrings.posCatalogQuantityScale, helperText: AppStrings.posCatalogQuantityScaleReadOnly)),
        _field(_reorder, AppStrings.posCatalogReorderLevel, (v) => _nonNegative(v, AppStrings.posProductThresholdInvalid), keyboardType: TextInputType.number),
        _field(_barcodes, AppStrings.posCatalogBarcodesHint, null, maxLines: 4),
        _field(_description, AppStrings.posCatalogDescription, null, maxLines: 3),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _expiryTracking, onChanged: (v) => setState(() => _expiryTracking = v), title: Text(AppStrings.posCatalogExpiryTracking)),
        FilledButton(onPressed: _submit, child: Text(AppStrings.save)),
      ]))),
    );
  }
  Widget _field(TextEditingController controller, String label, String? Function(String?)? validator, {TextInputType? keyboardType, int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
    child: TextFormField(controller: controller, validator: validator, keyboardType: keyboardType, maxLines: maxLines, decoration: InputDecoration(labelText: label)),
  );
}
