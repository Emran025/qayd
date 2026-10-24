import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/application/pos/get_pos_stock_balance_use_case.dart';
import 'package:qayd/application/pos/record_pos_stock_movement_use_case.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pos/pos_money_display.dart';
import 'package:qayd/presentation/pos/pos_catalog_cubit.dart';
import 'package:qayd/presentation/pos/pos_stock_cubit.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';

/// Records an append-only opening stock movement for one product.
class PosOpeningBalancePage extends StatefulWidget {
  const PosOpeningBalancePage({
    super.key,
    required this.catalogCubit,
    required this.stockCubit,
    required this.warehouseId,
  });

  final PosCatalogCubit catalogCubit;
  final PosStockCubit stockCubit;
  final String warehouseId;

  @override
  State<PosOpeningBalancePage> createState() => _PosOpeningBalancePageState();
}

class _PosOpeningBalancePageState extends State<PosOpeningBalancePage> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _costController = TextEditingController();
  PosProduct? _selectedProduct;
  bool _submitted = false;

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
    setState(() => _selectedProduct = product);
    if (product == null) return;
    widget.stockCubit.loadBalance(
      GetPosStockBalanceInput(
        productId: product.id,
        warehouseId: widget.warehouseId,
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final product = _selectedProduct;
    if (product == null) return;
    final quantityScaled = int.parse(_quantityController.text.trim());
    final unitCostMinor = int.parse(_costController.text.trim());
    setState(() => _submitted = true);
    widget.stockCubit.record(
      RecordPosStockMovementInput(
        productId: product.id,
        warehouseId: widget.warehouseId,
        type: PosStockMovementType.opening,
        direction: PosStockMovementDirection.inbound,
        quantityScaled: quantityScaled,
        quantityScale: product.quantityScale,
        unitCostMinor: unitCostMinor,
        currencyCode: product.currency.code,
        idempotencyKey:
            'opening:${product.id}:$quantityScaled:$unitCostMinor:${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: widget.catalogCubit),
        BlocProvider.value(value: widget.stockCubit),
      ],
      child: BlocListener<PosStockCubit, PosStockState>(
        listener: (context, state) {
          if (!_submitted) return;
          if (state.status == PosStockStatus.ready) {
            setState(() => _submitted = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppStrings.posOpeningBalanceSaved)),
            );
          } else if (state.status == PosStockStatus.failure) {
            setState(() => _submitted = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.failure?.messageAr ?? AppStrings.posStockAppendFailed,
                ),
              ),
            );
          }
        },
        child: Scaffold(
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
          return Text(
              state.failure?.messageAr ?? AppStrings.posProductReadFailed);
        }
        if (state.products.isEmpty) {
          return Text(AppStrings.posOpeningBalanceNoProducts);
        }
        return DropdownButtonFormField<PosProduct>(
          decoration: InputDecoration(
            labelText: AppStrings.posOpeningBalanceProduct,
            border: const OutlineInputBorder(),
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
          TextFormField(
            controller: quantityController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: AppStrings.posOpeningBalanceQuantity,
              helperText: AppStrings.posOpeningBalanceQuantityHint(scale),
              border: const OutlineInputBorder(),
            ),
            validator: _positiveInteger,
          ),
          const SizedBox(height: SpacingTokens.md),
          TextFormField(
            controller: costController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: AppStrings.posOpeningBalanceUnitCost,
              helperText: AppStrings.posOpeningBalanceCostHint(currency),
              border: const OutlineInputBorder(),
            ),
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
