import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/application/pos/get_pos_stock_balance_use_case.dart';
import 'package:qayd/application/pos/post_pos_opening_balance_atomically_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/components/atomic/qayd_empty_state.dart';
import 'package:qayd/presentation/components/inputs/qayd_numeric_field.dart';
import 'package:qayd/presentation/widgets/qayd_scaffold.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pos/pos_money_display.dart';
import 'package:qayd/presentation/pos/pos_catalog_cubit.dart';
import 'package:qayd/presentation/pos/pos_stock_cubit.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';

typedef PostPosOpeningBalance =
    Future<Result<void>> Function(PostPosOpeningBalanceInput input);

/// Records an append-only opening stock movement for one product.
class PosOpeningBalancePage extends StatefulWidget {
  const PosOpeningBalancePage({
    super.key,
    required this.catalogCubit,
    required this.stockCubit,
    required this.warehouseId,
    required this.postOpeningBalance,
  });

  final PosCatalogCubit catalogCubit;
  final PosStockCubit stockCubit;
  final String warehouseId;
  final PostPosOpeningBalance postOpeningBalance;

  @override
  State<PosOpeningBalancePage> createState() => _PosOpeningBalancePageState();
}

class _PosOpeningBalancePageState extends State<PosOpeningBalancePage> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _costController = TextEditingController();
  PosProduct? _selectedProduct;
  bool _submitted = false;
  String? _retryFingerprint;
  String? _retryIdempotencyKey;

  @override
  void initState() {
    super.initState();
    widget.catalogCubit.load();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _selectProduct(PosProduct? product) {
    setState(() {
      _selectedProduct = product;
      _retryFingerprint = null;
      _retryIdempotencyKey = null;
    });
    if (product == null) return;
    widget.stockCubit.loadBalance(
      GetPosStockBalanceInput(
        productId: product.id,
        warehouseId: widget.warehouseId,
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final product = _selectedProduct;
    if (product == null) return;
    final quantityScaled = int.parse(_quantityController.text.trim());
    final unitCostMinor = int.parse(_costController.text.trim());
    final fingerprint =
        '${product.id}:$quantityScaled:${product.quantityScale}:$unitCostMinor:${product.currency.code}';
    if (_retryFingerprint != fingerprint || _retryIdempotencyKey == null) {
      _retryFingerprint = fingerprint;
      _retryIdempotencyKey =
          'opening:${DateTime.now().toUtc().microsecondsSinceEpoch}';
    }
    final idempotencyKey = _retryIdempotencyKey!;
    setState(() => _submitted = true);
    final Result<void> result;
    try {
      result = await widget.postOpeningBalance(
        PostPosOpeningBalanceInput(
          productId: product.id,
          quantityScaled: quantityScaled,
          quantityScale: product.quantityScale,
          unitCostMinor: unitCostMinor,
          currencyCode: product.currency.code,
          idempotencyKey: idempotencyKey,
          sourceId: '$idempotencyKey:${product.id}',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitted = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.posStockAppendFailed)),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _submitted = false);
    if (result.isFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.failureOrNull?.messageAr ?? AppStrings.posStockAppendFailed,
          ),
        ),
      );
      return;
    }
    _retryFingerprint = null;
    _retryIdempotencyKey = null;
    await widget.stockCubit.loadBalance(
      GetPosStockBalanceInput(
        productId: product.id,
        warehouseId: widget.warehouseId,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.posOpeningBalanceSaved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: widget.catalogCubit),
        BlocProvider.value(value: widget.stockCubit),
      ],
      child: QaydScaffold(
        appBar: QaydAppBar(title: AppStrings.posOpeningBalanceTitle),
        body: ListView(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          children: [
            Text(AppStrings.posOpeningBalanceDescription),
            const SizedBox(height: SpacingTokens.lg),
            _ProductField(onChanged: _selectProduct),
            const SizedBox(height: SpacingTokens.md),
            _OpeningBalanceForm(
              formKey: _formKey,
              quantityController: _quantityController,
              costController: _costController,
              product: _selectedProduct,
              onSubmit: _submit,
              submitted: _submitted,
            ),
            const SizedBox(height: SpacingTokens.md),
            _CurrentBalanceCard(product: _selectedProduct),
          ],
        ),
      ),
    );
  }
}

class _ProductField extends StatelessWidget {
  const _ProductField({required this.onChanged});

  final ValueChanged<PosProduct?> onChanged;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PosCatalogCubit, PosCatalogState>(
      builder: (context, state) {
        if (state.status == PosCatalogStatus.loading ||
            state.status == PosCatalogStatus.initial) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == PosCatalogStatus.failure) {
          return QaydEmptyState(
            icon: Icons.error_outline_rounded,
            title: state.failure?.messageAr ?? AppStrings.posProductReadFailed,
            action: FilledButton.tonal(
              onPressed: () => context.read<PosCatalogCubit>().load(),
              child: Text(AppStrings.retryAction),
            ),
          );
        }
        if (state.products.isEmpty) {
          return QaydEmptyState(
            icon: Icons.inventory_2_outlined,
            title: AppStrings.posOpeningBalanceNoProducts,
          );
        }
        return DropdownButtonFormField<PosProduct>(
          decoration: InputDecoration(
            labelText: AppStrings.posOpeningBalanceProduct,
          ),
          items: state.products
              .map(
                (product) => DropdownMenuItem<PosProduct>(
                  value: product,
                  child: Text('${product.name} (${product.sku})'),
                ),
              )
              .toList(growable: false),
          onChanged: onChanged,
          validator: (value) =>
              value == null ? AppStrings.posOpeningBalanceSelectProduct : null,
        );
      },
    );
  }
}

class _OpeningBalanceForm extends StatelessWidget {
  const _OpeningBalanceForm({
    required this.formKey,
    required this.quantityController,
    required this.costController,
    required this.product,
    required this.onSubmit,
    required this.submitted,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController quantityController;
  final TextEditingController costController;
  final PosProduct? product;
  final VoidCallback onSubmit;
  final bool submitted;

  String? _positiveInteger(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed <= 0) {
      return AppStrings.posOpeningBalancePositiveInteger;
    }
    return null;
  }

  String? _nonNegativeInteger(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) {
      return AppStrings.posOpeningBalanceNonNegativeInteger;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scale = product?.quantityScale ?? 0;
    final currency = product?.currency.code ?? '';
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaydNumericField(
            controller: quantityController,
            label: AppStrings.posOpeningBalanceQuantity,
            helperText: AppStrings.posOpeningBalanceQuantityHint(scale),
            validator: _positiveInteger,
          ),
          const SizedBox(height: SpacingTokens.md),
          QaydNumericField(
            controller: costController,
            label: AppStrings.posOpeningBalanceUnitCost,
            helperText: AppStrings.posOpeningBalanceCostHint(currency),
            validator: _nonNegativeInteger,
          ),
          const SizedBox(height: SpacingTokens.md),
          FilledButton.icon(
            onPressed: product == null || submitted ? null : onSubmit,
            icon: submitted
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_box_outlined),
            label: Text(AppStrings.posOpeningBalanceSave),
          ),
        ],
      ),
    );
  }
}

class _CurrentBalanceCard extends StatelessWidget {
  const _CurrentBalanceCard({required this.product});

  final PosProduct? product;

  @override
  Widget build(BuildContext context) {
    if (product == null) return const SizedBox.shrink();
    return BlocBuilder<PosStockCubit, PosStockState>(
      builder: (context, state) {
        if (state.status == PosStockStatus.loading ||
            state.status == PosStockStatus.recording) {
          return const Center(child: CircularProgressIndicator());
        }
        final balance = state.balance;
        if (balance == null) return const SizedBox.shrink();
        return Card(
          child: ListTile(
            leading: const Icon(Icons.inventory_outlined),
            title: Text(AppStrings.posOpeningBalanceCurrent),
            subtitle: Text(
              '${balance.quantity.toExactString()} · '
              '${formatPosMoney(balance.averageUnitCost)}',
            ),
          ),
        );
      },
    );
  }
}
