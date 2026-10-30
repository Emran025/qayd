import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:qayd/application/accounts/list_accounts_use_case.dart';
import 'package:qayd/application/pos/build_pos_purchase_posting_use_case.dart';
import 'package:qayd/application/pos/complete_pos_purchase_use_case.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_purchase_request_identity.dart';
import 'package:qayd/domain/repositories/pos_purchase_request_identity_repository.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/components/inputs/qayd_amount_field.dart';
import 'package:qayd/presentation/components/inputs/qayd_numeric_field.dart';
import 'package:qayd/presentation/widgets/qayd_scaffold.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pos/pos_money_display.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/widgets/account_picker_sheet.dart';
import 'package:uuid/uuid.dart';

/// Purchase receiving surface. Submission is delegated to the complete atomic
/// application flow; the page never writes stock movements directly.
class PosPurchaseReceivingPage extends StatefulWidget {
  const PosPurchaseReceivingPage({
    super.key,
    required this.warehouseId,
    required this.currency,
    required this.listProducts,
    required this.listAccounts,
    required this.completePurchase,
    required this.requestIdentityRepository,
  });

  final String warehouseId;
  final CurrencyCode currency;
  final ListPosProductsUseCase listProducts;
  final ListAccountsUseCase listAccounts;
  final CompletePosPurchaseUseCase completePurchase;
  final PosPurchaseRequestIdentityRepository requestIdentityRepository;

  @override
  State<PosPurchaseReceivingPage> createState() =>
      _PosPurchaseReceivingPageState();
}

class _PosPurchaseReceivingPageState extends State<PosPurchaseReceivingPage> {
  static const _uuid = Uuid();

  bool _loading = true;
  bool _submitting = false;
  bool _payInCash = false;
  String? _loadFailure;
  String? _supplierAccountId;
  String? _supplierName;
  String? _pendingFingerprint;
  String? _pendingInvoiceId;
  String? _pendingIdempotencyKey;
  DateTime? _pendingCreatedAt;
  List<PosProduct> _products = const [];
  final Map<String, _PurchaseLineDraft> _lines = {};

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    for (final line in _lines.values) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _loadFailure = null;
    });
    final result = await widget.listProducts(activeOnly: true);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.isFailure) {
        _loadFailure = result.failureOrNull?.messageAr ??
            AppStrings.posPurchaseLoadFailed;
      } else {
        _products = (result.valueOrNull ?? const [])
            .where((product) => product.currency == widget.currency)
            .toList(growable: false);
      }
    });
  }

  Future<void> _selectSupplier() async {
    final selected = await showAccountPickerSheet(
      context,
      listAccounts: widget.listAccounts,
      rootAllowed: false,
      requireNoRoot: true,
      hideSterileRoots: true,
    );
    if (!mounted || selected == null) return;
    setState(() {
      _supplierAccountId = selected.id;
      _supplierName = selected.name;
    });
  }

  void _addProduct(PosProduct product) {
    if (product.expiryTracking) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.posPurchaseExpiryNotice)),
      );
      return;
    }
    if (_lines.containsKey(product.id)) {
      _showMessage(AppStrings.posPurchaseAlreadyAdded);
      return;
    }
    setState(() {
      _lines[product.id] = _PurchaseLineDraft(
        product: product,
        unitCostText: _minorUnitsToText(
          product.purchasePrice.minorUnits,
          widget.currency.fractionalDigits,
        ),
      );
    });
  }

  void _removeProduct(String productId) {
    final line = _lines.remove(productId);
    line?.dispose();
    setState(() {});
  }

  int? _totalMinorUnits() {
    var total = 0;
    for (final line in _lines.values) {
      final quantityScaled = _parseScaled(
        line.quantityController.text,
        line.product.quantityScale,
      );
      final costMinor = _parseScaled(
        line.unitCostController.text,
        widget.currency.fractionalDigits,
      );
      if (quantityScaled == null || quantityScaled == 0 || costMinor == null) {
        return null;
      }
      total += PosMoneyMath.multiply(
        PosQuantity.positive(
          quantityScaled,
          scale: line.product.quantityScale,
        ),
        Money.nonNegative(costMinor, widget.currency),
      ).minorUnits;
    }
    return total;
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) {
      _showMessage(AppStrings.posPurchaseCartEmpty);
      return;
    }
    final totalMinor = _totalMinorUnits();
    if (totalMinor == null || totalMinor <= 0) {
      _showMessage(AppStrings.posInvoiceInvalid);
      return;
    }
    if (!_payInCash && _supplierAccountId == null) {
      _showMessage(AppStrings.posPurchaseSelectSupplier);
      return;
    }

    final purchaseLines = <BuildPosPurchaseLineInput>[];
    for (final line in _lines.values) {
      final quantityScaled = _parseScaled(
        line.quantityController.text,
        line.product.quantityScale,
      );
      final costMinor = _parseScaled(
        line.unitCostController.text,
        widget.currency.fractionalDigits,
      );
      if (quantityScaled == null || quantityScaled <= 0 || costMinor == null) {
        _showMessage(AppStrings.posInvoiceInvalid);
        return;
      }
      purchaseLines.add(
        BuildPosPurchaseLineInput(
          productId: line.product.id,
          quantity: PosQuantity.positive(
            quantityScaled,
            scale: line.product.quantityScale,
          ),
          unitCostMinor: costMinor,
        ),
      );
    }

    final fingerprint = _purchaseFingerprint(purchaseLines);
    final fingerprintHash = sha256.convert(utf8.encode(fingerprint)).toString();
    setState(() => _submitting = true);
    final identityResult = await widget.requestIdentityRepository.getOrCreate(
      fingerprintHash: fingerprintHash,
      candidate: PosPurchaseRequestIdentity(
        invoiceId: _pendingFingerprint == fingerprint &&
                _pendingInvoiceId != null
            ? _pendingInvoiceId!
            : _uuid.v4(),
        idempotencyKey: _pendingFingerprint == fingerprint &&
                _pendingIdempotencyKey != null
            ? _pendingIdempotencyKey!
            : _uuid.v4(),
        createdAt: _pendingFingerprint == fingerprint &&
                _pendingCreatedAt != null
            ? _pendingCreatedAt!
            : DateTime.now().toUtc(),
      ),
    );
    if (!mounted) return;
    if (identityResult.isFailure) {
      setState(() => _submitting = false);
      _showMessage(
        identityResult.failureOrNull?.messageAr ??
            AppStrings.posPurchaseSubmitFailed,
      );
      return;
    }
    final identity = identityResult.valueOrNull!;
    _pendingFingerprint = fingerprint;
    _pendingInvoiceId = identity.invoiceId;
    _pendingIdempotencyKey = identity.idempotencyKey;
    _pendingCreatedAt = identity.createdAt.toUtc();
    final now = _pendingCreatedAt!;
    final invoiceId = _pendingInvoiceId!;
    final invoiceNumber = 'POS-P-${invoiceId.toUpperCase()}';

    final result = await widget.completePurchase(
      BuildPosPurchasePostingInput(
        invoiceId: invoiceId,
        invoiceNumber: invoiceNumber,
        warehouseId: widget.warehouseId,
        currency: widget.currency,
        lines: purchaseLines,
        idempotencyKey: _pendingIdempotencyKey!,
        invoiceDate: now,
        createdAt: now,
        supplierAccountId: _supplierAccountId == null
            ? null
            : AccountId(_supplierAccountId!),
        advanceMinorUnits: _payInCash ? totalMinor : 0,
        paymentMethod:
            _payInCash ? PosPaymentMethod.cash : PosPaymentMethod.credit,
      ),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isFailure) {
      _showMessage(
        result.failureOrNull?.messageAr ?? AppStrings.posPurchaseSubmitFailed,
      );
      return;
    }

    final acknowledgement =
        await widget.requestIdentityRepository.acknowledgeCommitted(
      fingerprintHash: fingerprintHash,
      identity: identity,
    );
    if (!mounted) return;
    if (acknowledgement.isFailure) {
      _showMessage(AppStrings.posPurchaseAcknowledgeFailed);
      return;
    }

    for (final line in _lines.values) {
      line.dispose();
    }
    setState(() {
      _lines.clear();
      _pendingFingerprint = null;
      _pendingInvoiceId = null;
      _pendingIdempotencyKey = null;
      _pendingCreatedAt = null;
    });
    _showMessage(
      '${AppStrings.posPurchaseSaved} ${result.valueOrNull!.invoiceNumber}',
    );
  }

  String _purchaseFingerprint(List<BuildPosPurchaseLineInput> lines) {
    final lineData = lines
        .map((line) =>
            '${line.productId}:${line.quantity.scaledUnits}/${line.quantity.scale}:${line.unitCostMinor}')
        .join(';');
    return '${widget.warehouseId}|${widget.currency.code}|'
        '${_supplierAccountId ?? ''}|$_payInCash|$lineData';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalMinorUnits();
    return QaydScaffold(
      appBar: QaydAppBar(title: AppStrings.posPurchaseTitle),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailure != null
              ? _LoadFailureView(
                  message: _loadFailure!,
                  onRetry: _loadProducts,
                )
              : ListView(
                  padding: const EdgeInsets.all(SpacingTokens.lg),
                  children: [
                    Text(
                      AppStrings.posPurchaseDescription,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    Card(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(SpacingTokens.md),
                        child: Text(AppStrings.posPurchaseExpiryNotice),
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    OutlinedButton.icon(
                      onPressed: _selectSupplier,
                      icon: const Icon(Icons.person_search_outlined),
                      label: Text(
                        _supplierName ?? AppStrings.posPurchaseSelectSupplier,
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    Text(
                      AppStrings.posPurchaseProducts,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: SpacingTokens.sm),
                    if (_products.isEmpty)
                      Text(AppStrings.posPurchaseNoProducts)
                    else
                      ..._products.map(_productCard),
                    const SizedBox(height: SpacingTokens.md),
                    if (_lines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: SpacingTokens.md,
                        ),
                        child: Text(AppStrings.posPurchaseCartEmpty),
                      )
                    else ...[
                      Text(
                        AppStrings.posPurchaseProducts,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: SpacingTokens.sm),
                      ..._lines.values.map(_lineCard),
                    ],
                    const SizedBox(height: SpacingTokens.md),
                    Text(
                      AppStrings.posPurchasePaymentMethod,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    RadioListTile<bool>(
                      value: false,
                      groupValue: _payInCash,
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _payInCash = value!),
                      title: Text(AppStrings.posPurchaseCredit),
                    ),
                    RadioListTile<bool>(
                      value: true,
                      groupValue: _payInCash,
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _payInCash = value!),
                      title: Text(AppStrings.posPurchaseCash),
                    ),
                    Card(
                      child: ListTile(
                        title: Text(AppStrings.posPurchaseTotal),
                        trailing: Text(
                          total == null
                              ? '—'
                              : formatPosMinor(total, widget.currency),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.inventory_2_outlined),
                      label: Text(AppStrings.posPurchaseSubmit),
                    ),
                  ],
                ),
    );
  }

  Widget _productCard(PosProduct product) {
    final unavailable = product.expiryTracking;
    return Card(
      child: ListTile(
        title: Text(product.name),
        subtitle: Text(
          '${product.sku} · ${AppStrings.posPurchaseUnitCost}: '
          '${formatPosMoney(product.purchasePrice)}',
        ),
        trailing: IconButton(
          tooltip: unavailable
              ? AppStrings.posPurchaseExpiryNotice
              : AppStrings.posPurchaseAddProduct,
          onPressed: unavailable ? null : () => _addProduct(product),
          icon: Icon(
            unavailable ? Icons.block_outlined : Icons.add_circle_outline,
          ),
        ),
      ),
    );
  }

  Widget _lineCard(_PurchaseLineDraft line) {
    final quantityLabel =
        '${AppStrings.posPurchaseQuantity} (${line.product.unitName})';
    final quantityHint =
        '0${line.product.quantityScale > 0 ? '.0' : ''}';
    final quantityField = line.product.quantityScale == 0
        ? QaydNumericField(
            controller: line.quantityController,
            enabled: !_submitting,
            label: quantityLabel,
            hint: quantityHint,
            onChanged: (_) => setState(() {}),
          )
        : QaydAmountField(
            controller: line.quantityController,
            enabled: !_submitting,
            label: quantityLabel,
            hint: quantityHint,
            fractionalDigits: line.product.quantityScale,
            onChanged: (_) => setState(() {}),
          );
    final costField = widget.currency.fractionalDigits == 0
        ? QaydNumericField(
            controller: line.unitCostController,
            enabled: !_submitting,
            label: AppStrings.posPurchaseUnitCost,
            suffixText: widget.currency.symbol,
            onChanged: (_) => setState(() {}),
          )
        : QaydAmountField(
            controller: line.unitCostController,
            enabled: !_submitting,
            label: AppStrings.posPurchaseUnitCost,
            suffixText: widget.currency.symbol,
            fractionalDigits: widget.currency.fractionalDigits,
            onChanged: (_) => setState(() {}),
          );
    return Card(
      key: ValueKey('purchase-line-${line.product.id}'),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.product.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: AppStrings.actionDelete,
                  onPressed: _submitting
                      ? null
                      : () => _removeProduct(line.product.id),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            quantityField,
            const SizedBox(height: SpacingTokens.sm),
            costField,
          ],
        ),
      ),
    );
  }

  static int? _parseScaled(String raw, int scale) {
    final value = raw.trim().replaceAll(',', '.');
    if (value.isEmpty || scale < 0 || scale > PosQuantity.maxScale) {
      return null;
    }
    final parts = value.split('.');
    if (parts.length > 2) return null;
    final whole = parts[0].isEmpty ? '0' : parts[0];
    final fraction = parts.length == 2 ? parts[1] : '';
    if (!RegExp(r'^\d+$').hasMatch(whole) ||
        (fraction.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fraction)) ||
        fraction.length > scale ||
        (scale == 0 && parts.length == 2)) {
      return null;
    }
    final divisor = _pow10(scale);
    final fractionValue = fraction.isEmpty
        ? 0
        : int.parse(fraction.padRight(scale, '0'));
    return int.parse(whole) * divisor + fractionValue;
  }

  static String _minorUnitsToText(int minorUnits, int digits) {
    if (digits == 0) return minorUnits.toString();
    final divisor = _pow10(digits);
    final whole = minorUnits ~/ divisor;
    final fraction = (minorUnits % divisor).toString().padLeft(digits, '0');
    return '$whole.$fraction';
  }

  static int _pow10(int digits) {
    var value = 1;
    for (var i = 0; i < digits; i++) {
      value *= 10;
    }
    return value;
  }
}

final class _PurchaseLineDraft {
  _PurchaseLineDraft({required this.product, required String unitCostText})
      : quantityController = TextEditingController(text: '1'),
        unitCostController = TextEditingController(text: unitCostText);

  final PosProduct product;
  final TextEditingController quantityController;
  final TextEditingController unitCostController;

  void dispose() {
    quantityController.dispose();
    unitCostController.dispose();
  }
}

class _LoadFailureView extends StatelessWidget {
  const _LoadFailureView({required this.message, required this.onRetry});

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
