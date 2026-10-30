import 'package:flutter/material.dart';
import 'package:qayd/application/pos/create_pos_product_category_use_case.dart';
import 'package:qayd/application/pos/list_pos_product_categories_use_case.dart';
import 'package:qayd/application/pos/manage_pos_product_category_use_cases.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/di/injection_container.dart';
import 'package:qayd/domain/entities/pos_product_category.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';

class PosProductCategoriesPage extends StatefulWidget {
  const PosProductCategoriesPage({
    super.key,
    this.createUseCase,
    this.listUseCase,
    this.saveUseCase,
    this.deactivateUseCase,
    this.reactivateUseCase,
  });

  final CreatePosProductCategoryUseCase? createUseCase;
  final ListPosProductCategoriesUseCase? listUseCase;
  final SavePosProductCategoryUseCase? saveUseCase;
  final DeactivatePosProductCategoryUseCase? deactivateUseCase;
  final ReactivatePosProductCategoryUseCase? reactivateUseCase;

  @override
  State<PosProductCategoriesPage> createState() =>
      _PosProductCategoriesPageState();
}

class _PosProductCategoriesPageState extends State<PosProductCategoriesPage> {
  late final CreatePosProductCategoryUseCase _create =
      widget.createUseCase ?? InjectionContainer.createPosProductCategoryUseCase;
  late final ListPosProductCategoriesUseCase _list =
      widget.listUseCase ?? InjectionContainer.listPosProductCategoriesUseCase;
  late final SavePosProductCategoryUseCase _save =
      widget.saveUseCase ?? InjectionContainer.savePosProductCategoryUseCase;
  late final DeactivatePosProductCategoryUseCase _deactivate = widget
          .deactivateUseCase ??
      InjectionContainer.deactivatePosProductCategoryUseCase;
  late final ReactivatePosProductCategoryUseCase _reactivate = widget
          .reactivateUseCase ??
      InjectionContainer.reactivatePosProductCategoryUseCase;

  List<PosProductCategory> _categories = const [];
  bool _loading = true;
  bool _includeInactive = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final result = await _list(activeOnly: !_includeInactive);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _categories = result.valueOrNull ?? const [];
    });
    if (result.isFailure) {
      _showMessage(
        result.failureOrNull?.messageAr ?? AppStrings.posProductReadFailed,
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<({String name, String code})?> _showCategoryDialog({
    PosProductCategory? category,
  }) {
    return showDialog<({String name, String code})>(
      context: context,
      builder: (_) => _CategoryDialog(category: category),
    );
  }

  Future<void> _createCategory() async {
    final draft = await _showCategoryDialog();
    if (draft == null || !mounted) return;

    final result = await _create(
      CreatePosProductCategoryInput(name: draft.name, code: draft.code),
    );
    if (!mounted) return;
    if (result.isFailure) {
      _showMessage(
        result.failureOrNull?.messageAr ?? AppStrings.posProductSaveFailed,
      );
      return;
    }
    await _load();
  }

  Future<void> _editCategory(PosProductCategory category) async {
    final draft = await _showCategoryDialog(category: category);
    if (draft == null || !mounted) return;

    final result = await _save(
      category.copyWith(name: draft.name, code: draft.code),
    );
    if (!mounted) return;
    if (result.isFailure) {
      _showMessage(
        result.failureOrNull?.messageAr ?? AppStrings.posProductSaveFailed,
      );
      return;
    }
    await _load();
  }

  Future<void> _toggleCategory(PosProductCategory category) async {
    if (category.isActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppStrings.posCatalogCategoryDeactivateTitle),
          content: Text(AppStrings.posCatalogDeactivateCategoryMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppStrings.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(AppStrings.posCatalogCategoryDeactivate),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final result = await _deactivate(category.id);
      if (!mounted) return;
      if (result.isFailure) {
        _showMessage(
          result.failureOrNull?.messageAr ?? AppStrings.posProductSaveFailed,
        );
        return;
      }
    } else {
      final result = await _reactivate(category);
      if (!mounted) return;
      if (result.isFailure) {
        _showMessage(
          result.failureOrNull?.messageAr ?? AppStrings.posProductSaveFailed,
        );
        return;
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: QaydAppBar(title: AppStrings.posCatalogEditCategoryTitle),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCategory,
        icon: const Icon(Icons.add_rounded),
        label: Text(AppStrings.posCatalogAddCategory),
      ),
      body: Column(
        children: [
          SwitchListTile.adaptive(
            value: _includeInactive,
            onChanged: (value) {
              setState(() => _includeInactive = value);
              _load();
            },
            title: Text(AppStrings.allLabel),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _categories.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 240,
                                child: Center(
                                  child: Text(AppStrings.posCatalogNoCategories),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(
                              bottom: SpacingTokens.xxl,
                            ),
                            itemCount: _categories.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final category = _categories[index];
                              return ListTile(
                                title: Text(category.name),
                                subtitle: Text(category.code),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: AppStrings.posCatalogEditCategory,
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _editCategory(category),
                                    ),
                                    IconButton(
                                      tooltip: category.isActive
                                          ? AppStrings.posCatalogCategoryDeactivate
                                          : AppStrings.posCatalogCategoryReactivate,
                                      icon: Icon(
                                        category.isActive
                                            ? Icons.archive_outlined
                                            : Icons.unarchive_outlined,
                                      ),
                                      onPressed: () => _toggleCategory(category),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.category});

  final PosProductCategory? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.category?.name ?? '');
  late final TextEditingController _code =
      TextEditingController(text: widget.category?.code ?? '');
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.category == null
            ? AppStrings.posCatalogCreateCategory
            : AppStrings.posCatalogEditCategory,
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: widget.category == null,
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
              controller: _code,
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
              name: _name.text.trim(),
              code: _code.text.trim(),
            ));
          },
          child: Text(AppStrings.save),
        ),
      ],
    );
  }
}
