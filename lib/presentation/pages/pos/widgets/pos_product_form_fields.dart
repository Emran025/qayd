import 'package:flutter/material.dart';
import 'package:qayd/domain/entities/pos_product_category.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/presentation/components/inputs/qayd_amount_field.dart';
import 'package:qayd/presentation/components/inputs/qayd_numeric_field.dart';
import 'package:qayd/presentation/components/inputs/qayd_text_field.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';

/// Shared, presentation-only fields for both product creation and editing.
/// The owning form keeps responsibility for persistence and domain commands.
final class PosProductFormFields extends StatelessWidget {
  const PosProductFormFields({
    super.key,
    required this.currency,
    required this.nameController,
    required this.skuController,
    required this.salePriceController,
    required this.purchasePriceController,
    required this.profitMarginController,
    required this.profitMarginType,
    required this.onProfitMarginTypeChanged,
    required this.unitNameController,
    required this.reorderLevelController,
    required this.barcodeController,
    required this.descriptionController,
    required this.categories,
    required this.categoryId,
    required this.onCategoryChanged,
    required this.quantityScaleValue,
    required this.expiryTracking,
    required this.onExpiryTrackingChanged,
    this.quantityScaleController,
    this.quantityScaleReadOnly = false,
    this.onAddCategory,
  });

  final CurrencyCode currency;
  final TextEditingController nameController;
  final TextEditingController skuController;
  final TextEditingController salePriceController;
  final TextEditingController purchasePriceController;
  final TextEditingController profitMarginController;
  final String profitMarginType;
  final ValueChanged<String> onProfitMarginTypeChanged;
  final TextEditingController unitNameController;
  final TextEditingController reorderLevelController;
  final TextEditingController barcodeController;
  final TextEditingController descriptionController;
  final List<PosProductCategory> categories;
  final String? categoryId;
  final ValueChanged<String?> onCategoryChanged;
  final TextEditingController? quantityScaleController;
  final String quantityScaleValue;
  final bool quantityScaleReadOnly;
  final bool expiryTracking;
  final ValueChanged<bool> onExpiryTrackingChanged;
  final VoidCallback? onAddCategory;

  bool get _marginIsPercentage => profitMarginType == 'percentage';

  String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  String? _nonNegativeInteger(String? value, String message) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < 0 ? message : null;
  }

  String? _nonNegativeDecimal(String? value, int scale) {
    final text = value?.trim().replaceAll(',', '.') ?? '';
    if (text.isEmpty) return AppStrings.posProductPriceInvalid;
    final parts = text.split('.');
    if (parts.length > 2 ||
        !RegExp(r'^\d+$').hasMatch(parts.first) ||
        (parts.length == 2 &&
            (!RegExp(r'^\d*$').hasMatch(parts[1]) ||
                parts[1].length > scale))) {
      return AppStrings.posProductPriceInvalid;
    }
    return null;
  }

  String? _scaleValidator(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < 0 || parsed > 6
        ? AppStrings.posProductScaleInvalid
        : null;
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaydTextField(
            controller: nameController,
            label: AppStrings.posCatalogName,
            validator: (value) =>
                _required(value, AppStrings.posProductNameRequired),
          ),
          const SizedBox(height: SpacingTokens.sm),
          QaydTextField(
            controller: skuController,
            label: AppStrings.posCatalogSku,
            validator: (value) =>
                _required(value, AppStrings.posProductSkuRequired),
          ),
          const SizedBox(height: SpacingTokens.sm),
          QaydNumericField(
            controller: salePriceController,
            label: AppStrings.posCatalogSalePriceMinor,
            validator: (value) => _nonNegativeInteger(
              value,
              AppStrings.posProductPriceInvalid,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          QaydNumericField(
            controller: purchasePriceController,
            label: AppStrings.posCatalogPurchasePriceMinor,
            validator: (value) => _nonNegativeInteger(
              value,
              AppStrings.posProductPriceInvalid,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          DropdownButtonFormField<String>(
            initialValue: profitMarginType,
            decoration:
                InputDecoration(labelText: AppStrings.posProfitMarginTitle),
            items: [
              DropdownMenuItem(
                value: 'percentage',
                child: Text(AppStrings.posProfitMarginPercentage),
              ),
              DropdownMenuItem(
                value: 'fixed_amount',
                child: Text(AppStrings.posProfitMarginFixedAmount),
              ),
            ],
            onChanged: (value) {
              if (value != null) onProfitMarginTypeChanged(value);
            },
          ),
          const SizedBox(height: SpacingTokens.sm),
          QaydAmountField(
            controller: profitMarginController,
            fractionalDigits:
                _marginIsPercentage ? 2 : currency.fractionalDigits,
            suffixText: _marginIsPercentage ? '%' : currency.symbol,
            label: AppStrings.posProfitMarginAmount,
            validator: (value) => _nonNegativeDecimal(
              value,
              _marginIsPercentage ? 2 : currency.fractionalDigits,
            ),
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(AppStrings.posProfitMarginHint),
          const SizedBox(height: SpacingTokens.sm),
          QaydTextField(
            controller: unitNameController,
            label: AppStrings.posCatalogUnit,
            validator: (value) =>
                _required(value, AppStrings.posProductUnitRequired),
          ),
          const SizedBox(height: SpacingTokens.sm),
          DropdownButtonFormField<String?>(
            initialValue: categoryId,
            decoration:
                InputDecoration(labelText: AppStrings.posCatalogCategory),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(AppStrings.posCatalogNoCategory),
              ),
              ...categories.map(
                (category) => DropdownMenuItem<String?>(
                  value: category.id,
                  child: Text('${category.name} (${category.code})'),
                ),
              ),
            ],
            onChanged: onCategoryChanged,
          ),
          if (onAddCategory != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onAddCategory,
                icon: const Icon(Icons.add_rounded),
                label: Text(AppStrings.posCatalogAddCategory),
              ),
            ),
          const SizedBox(height: SpacingTokens.sm),
          QaydNumericField(
            controller: quantityScaleController,
            initialValue: quantityScaleValue,
            readOnly: quantityScaleReadOnly,
            label: AppStrings.posCatalogQuantityScale,
            helperText: quantityScaleReadOnly
                ? AppStrings.posCatalogQuantityScaleReadOnly
                : null,
            validator: quantityScaleReadOnly ? null : _scaleValidator,
          ),
          const SizedBox(height: SpacingTokens.sm),
          QaydNumericField(
            controller: reorderLevelController,
            label: AppStrings.posCatalogReorderLevel,
            validator: (value) => _nonNegativeInteger(
              value,
              AppStrings.posProductThresholdInvalid,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          QaydTextField(
            controller: barcodeController,
            label: AppStrings.posCatalogBarcodesHint,
            maxLines: 3,
          ),
          const SizedBox(height: SpacingTokens.sm),
          QaydTextField(
            controller: descriptionController,
            label: AppStrings.posCatalogDescription,
            minLines: 2,
            maxLines: 3,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: expiryTracking,
            onChanged: onExpiryTrackingChanged,
            title: Text(AppStrings.posCatalogExpiryTracking),
          ),
        ],
      );
}
