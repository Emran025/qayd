import 'package:flutter/material.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/presentation/components/inputs/qayd_numeric_field.dart';
import 'package:qayd/presentation/components/inputs/qayd_text_field.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pos/pos_money_display.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';

/// Stateless adjustment form; the page owns validation commands and posting.
final class PosStockAdjustmentForm extends StatelessWidget {
  const PosStockAdjustmentForm({
    super.key,
    required this.formKey,
    required this.products,
    required this.selectedProduct,
    required this.direction,
    required this.balance,
    required this.currency,
    required this.quantityController,
    required this.unitCostController,
    required this.reasonController,
    required this.counterAccountName,
    required this.counterAccountSelected,
    required this.submitting,
    required this.onProductChanged,
    required this.onDirectionChanged,
    required this.onQuantityChanged,
    required this.onUnitCostChanged,
    required this.onSelectCounterAccount,
    required this.onReasonChanged,
    required this.onSubmit,
    required this.quantityValidator,
    required this.unitCostValidator,
    required this.reasonValidator,
  });

  final GlobalKey<FormState> formKey;
  final List<PosProduct> products;
  final PosProduct? selectedProduct;
  final PosStockMovementDirection direction;
  final PosStockBalance? balance;
  final CurrencyCode currency;
  final TextEditingController quantityController;
  final TextEditingController unitCostController;
  final TextEditingController reasonController;
  final String? counterAccountName;
  final bool counterAccountSelected;
  final bool submitting;
  final ValueChanged<PosProduct?> onProductChanged;
  final ValueChanged<PosStockMovementDirection?> onDirectionChanged;
  final ValueChanged<String> onQuantityChanged;
  final ValueChanged<String> onUnitCostChanged;
  final VoidCallback onSelectCounterAccount;
  final ValueChanged<String> onReasonChanged;
  final VoidCallback onSubmit;
  final FormFieldValidator<String> quantityValidator;
  final FormFieldValidator<String> unitCostValidator;
  final FormFieldValidator<String> reasonValidator;

  @override
  Widget build(BuildContext context) => Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            Text(AppStrings.posStockAdjustmentDescription),
            const SizedBox(height: SpacingTokens.md),
            DropdownButtonFormField<PosProduct>(
              initialValue: selectedProduct,
              decoration: InputDecoration(
                labelText: AppStrings.posOpeningBalanceProduct,
              ),
              items: products
                  .map(
                    (product) => DropdownMenuItem(
                      value: product,
                      child: Text(
                        '${product.name} (${product.sku})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: submitting ? null : onProductChanged,
              validator: (value) => value == null
                  ? AppStrings.posOpeningBalanceSelectProduct
                  : null,
            ),
            const SizedBox(height: SpacingTokens.md),
            DropdownButtonFormField<PosStockMovementDirection>(
              initialValue: direction,
              decoration: InputDecoration(
                labelText: AppStrings.posStockAdjustmentDirection,
              ),
              items: [
                DropdownMenuItem(
                  value: PosStockMovementDirection.inbound,
                  child: Text(AppStrings.posStockAdjustmentIncrease),
                ),
                DropdownMenuItem(
                  value: PosStockMovementDirection.outbound,
                  child: Text(AppStrings.posStockAdjustmentDecrease),
                ),
              ],
              onChanged: submitting ? null : onDirectionChanged,
            ),
            const SizedBox(height: SpacingTokens.md),
            QaydNumericField(
              controller: quantityController,
              enabled: !submitting,
              label: AppStrings.posStockAdjustmentQuantity,
              helperText: selectedProduct == null
                  ? null
                  : AppStrings.posOpeningBalanceQuantityHint(
                      selectedProduct!.quantityScale,
                    ),
              validator: quantityValidator,
              onChanged: onQuantityChanged,
            ),
            if (direction == PosStockMovementDirection.inbound) ...[
              const SizedBox(height: SpacingTokens.md),
              QaydNumericField(
                controller: unitCostController,
                enabled: !submitting,
                label: AppStrings.posStockAdjustmentUnitCost,
                helperText: AppStrings.posOpeningBalanceCostHint(currency.code),
                validator: unitCostValidator,
                onChanged: onUnitCostChanged,
              ),
            ] else if (selectedProduct != null && balance != null) ...[
              const SizedBox(height: SpacingTokens.md),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.calculate_outlined),
                  title: Text(AppStrings.posOpeningBalanceCurrent),
                  subtitle: Text(
                    '${balance!.quantity.toExactString()} · '
                    '${formatPosMoney(balance!.averageUnitCost)}',
                  ),
                ),
              ),
            ],
            const SizedBox(height: SpacingTokens.md),
            OutlinedButton.icon(
              onPressed: submitting ? null : onSelectCounterAccount,
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(
                counterAccountName ??
                    AppStrings.posStockAdjustmentSelectAccount,
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
            QaydTextField(
              controller: reasonController,
              enabled: !submitting,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              label: AppStrings.posStockAdjustmentReason,
              validator: reasonValidator,
              onChanged: onReasonChanged,
            ),
            const SizedBox(height: SpacingTokens.lg),
            FilledButton.icon(
              onPressed: submitting ||
                      selectedProduct == null ||
                      !counterAccountSelected
                  ? null
                  : onSubmit,
              icon: submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(AppStrings.posStockAdjustmentSave),
            ),
          ],
        ),
      );
}
