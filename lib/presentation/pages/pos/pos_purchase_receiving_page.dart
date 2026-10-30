import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:qayd/application/accounts/list_accounts_use_case.dart';
import 'package:qayd/application/pos/build_pos_purchase_posting_use_case.dart';
import 'package:qayd/application/pos/complete_pos_purchase_use_case.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/application/settings/list_currencies_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/services/pos_currency_converter.dart';
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
    required this.listCurrencies,
    required this.currencyConverter,
    required this.listProducts,
    required this.listAccounts,
    required this.completePurchase,
    required this.requestIdentityRepository,
  });

  final String warehouseId;
  final CurrencyCode currency;
  final ListCurrenciesUseCase listCurrencies;
  final PosCurrencyConverter currencyConverter;
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
  late CurrencyCode _purchaseCurrency;
  List<CurrencyCode> _availableCurrencies = const [];
  List<PosProduct> _products = const [];
  final Map<String, _PurchaseLineDraft> _lines = {};

  @override
  void initState() {
    super.initState();
    _purchaseCurrency = widget.currency;
    _loadProducts();
    _loadCurrencies();
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
        _loadFailure =
            result.failureOrNull?.messageAr ?? AppStrings.posPurchaseLoadFailed;
      } else {
        _products = (result.valueOrNull ?? const []).toList(growable: false);
      }
    });
  }

  Future<void> _loadCurrencies() async {
    final result = await widget.listCurrencies(onlyActive: true);
    if (!mounted || result.isFailure) return;
    final currencies = result.valueOrNull ?? const <CurrencyCode>[];
    setState(() {
      _availableCurrencies = List.unmodifiable(
        currencies.any((item) => item == widget.currency)
            ? currencies
            : [...currencies, widget.currency],
      );
    });
  }

  void _selectPurchaseCurrency(CurrencyCode? currency) {
    if (currency == null || _lines.isNotEmpty || _submitting) return;
    setState(() => _purchaseCurrency = currency);
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
    final line = _PurchaseLineDraft(
      product: product,
      unitCostText: product.currency == _purchaseCurrency
          ? _minorUnitsToText(
              product.purchasePrice.minorUnits,
              _purchaseCurrency.fractionalDigits,
            )
          : '',
    );
    setState(() => _lines[product.id] = line);
    _refreshLinePreview(line);
  }

  Future<void> _refreshLinePreview(_PurchaseLineDraft line) async {
    final sourceCurrency = _purchaseCurrency;
    final raw = line.unitCostController.text;
    final sourceMinor = _parseScaled(raw, sourceCurrency.fractionalDigits);
    if (sourceMinor == null) {
      setState(() {
        line.previewConversion = null;
        line.proposedSalePrice = null;
        line.previewFailure = null;
        line.previewLoading = false;
        line.applyProposedSalePrice = false;
      });
      return;
    }
    setState(() {
      line.previewLoading = true;
      line.previewFailure = null;
      line.previewConversion = null;
      line.proposedSalePrice = null;
    });
    final result = await widget.currencyConverter.convertWithSnapshot(
      Money.nonNegative(sourceMinor, sourceCurrency),
      toCurrency: line.product.currency,
    );
    if (!mounted ||
        !identical(_lines[line.product.id], line) ||
        line.unitCostController.text != raw ||
        _purchaseCurrency != sourceCurrency) {
      return;
    }
    setState(() {
      line.previewLoading = false;
      if (result.isFailure) {
        line.previewConversion = null;
        line.proposedSalePrice = null;
        line.applyProposedSalePrice = false;
        line.previewFailure = result.failureOrNull?.messageAr;
      } else {
        line.previewConversion = result.valueOrNull;
        line.proposedSalePrice = line.product.profitMargin
            .calculateProposedSalePrice(result.valueOrNull!.targetAmount);
        line.previewFailure = null;
      }
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
        _purchaseCurrency.fractionalDigits,
      );
      if (quantityScaled == null || quantityScaled == 0 || costMinor == null) {
        return null;
      }
      total += PosMoneyMath.multiply(
        PosQuantity.positive(
          quantityScaled,
          scale: line.product.quantityScale,
        ),
        Money.nonNegative(costMinor, _purchaseCurrency),
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
        _purchaseCurrency.fractionalDigits,
      );
      if (quantityScaled == null ||
          quantityScaled <= 0 ||
          costMinor == null ||
          line.previewConversion == null ||
          line.proposedSalePrice == null) {
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
          applyProposedSalePrice: line.applyProposedSalePrice,
          rateSnapshot: line.previewConversion!.rateSnapshot,
          productUpdatedAtSnapshot: line.product.updatedAt,
        ),
      );
    }

    final fingerprint = _purchaseFingerprint(purchaseLines);
    final fingerprintHash = sha256.convert(utf8.encode(fingerprint)).toString();
    final requestSnapshotJson = _purchaseSnapshotJson(purchaseLines);
    final candidateIdentity = PosPurchaseRequestIdentity(
      invoiceId: _pendingFingerprint == fingerprint && _pendingInvoiceId != null
          ? _pendingInvoiceId!
          : _uuid.v4(),
      idempotencyKey:
          _pendingFingerprint == fingerprint && _pendingIdempotencyKey != null
              ? _pendingIdempotencyKey!
              : _uuid.v4(),
      createdAt: _pendingFingerprint == fingerprint && _pendingCreatedAt != null
          ? _pendingCreatedAt!
          : DateTime.now().toUtc(),
      requestSnapshotJson: requestSnapshotJson,
    );
    setState(() => _submitting = true);
    final identityResult = await widget.requestIdentityRepository.getOrCreate(
      fingerprintHash: fingerprintHash,
      candidate: candidateIdentity,
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
    if (identity.invoiceId != candidateIdentity.invoiceId &&
        identity.requestSnapshotJson == null) {
      setState(() => _submitting = false);
      _showMessage(AppStrings.posPurchaseSnapshotRestoreFailed);
      return;
    }
    if (identity.requestSnapshotJson != null &&
        identity.requestSnapshotJson != requestSnapshotJson) {
      final restored = _restorePurchaseSnapshot(
        identity.requestSnapshotJson!,
        purchaseLines,
      );
      setState(() => _submitting = false);
      if (!restored) {
        _showMessage(AppStrings.posPurchaseSnapshotRestoreFailed);
      } else {
        _showMessage(AppStrings.posPurchaseSnapshotRestored);
      }
      return;
    }
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
        currency: _purchaseCurrency,
        lines: purchaseLines,
        idempotencyKey: _pendingIdempotencyKey!,
        invoiceDate: now,
        createdAt: now,
        supplierAccountId:
            _supplierAccountId == null ? null : AccountId(_supplierAccountId!),
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
    return '${widget.warehouseId}|${_purchaseCurrency.code}|'
        '${_supplierAccountId ?? ''}|$_payInCash|$lineData';
  }

  String _purchaseSnapshotJson(List<BuildPosPurchaseLineInput> lines) {
    return jsonEncode({
      'invoice_currency_code': _purchaseCurrency.code,
      'lines': lines.map((line) {
        final draft = _lines[line.productId]!;
        final quote = draft.previewConversion!.rateSnapshot;
        return {
          'product_id': line.productId,
          'source_unit_price_minor': line.unitCostMinor,
          'product_updated_at':
              draft.product.updatedAt.toUtc().toIso8601String(),
          'apply_proposed_sale_price': draft.applyProposedSalePrice,
          'quote': quote == null
              ? null
              : {
                  'rate_id': quote.rateId,
                  'stored_from_code': quote.storedFromCurrency.code,
                  'stored_to_code': quote.storedToCurrency.code,
                  'stored_rate_scaled': quote.storedRateScaled,
                  'requested_from_code': quote.requestedFromCurrency.code,
                  'requested_to_code': quote.requestedToCurrency.code,
                  'effective_at': quote.effectiveAt.toUtc().toIso8601String(),
                  'recorded_at': quote.recordedAt.toUtc().toIso8601String(),
                  'created_at': quote.createdAt.toUtc().toIso8601String(),
                  'is_inverted': quote.isInverted,
                  'note': quote.note,
                },
        };
      }).toList(growable: false),
    });
  }

  bool _restorePurchaseSnapshot(
    String snapshotJson,
    List<BuildPosPurchaseLineInput> currentLines,
  ) {
    try {
      final snapshot = jsonDecode(snapshotJson) as Map<String, dynamic>;
      if (snapshot['invoice_currency_code'] != _purchaseCurrency.code) {
        return false;
      }
      final savedLines =
          (snapshot['lines'] as List<dynamic>).cast<Map<String, dynamic>>();
      if (savedLines.length != currentLines.length) return false;
      for (final current in currentLines) {
        final saved = savedLines.firstWhere(
          (line) => line['product_id'] == current.productId,
        );
        final draft = _lines[current.productId];
        if (draft == null ||
            saved['source_unit_price_minor'] != current.unitCostMinor ||
            DateTime.parse(saved['product_updated_at'] as String).toUtc() !=
                draft.product.updatedAt.toUtc()) {
          return false;
        }
        final sourceAmount = Money.nonNegative(
          current.unitCostMinor!,
          _purchaseCurrency,
        );
        final rawQuote = saved['quote'];
        PosCurrencyConversion conversion;
        if (rawQuote == null) {
          if (_purchaseCurrency != draft.product.currency) return false;
          conversion = PosCurrencyConversion(
            sourceAmount: sourceAmount,
            targetAmount: Money.fromMinorUnits(
              sourceAmount.minorUnits,
              draft.product.currency,
            ),
            rateSnapshot: null,
          );
        } else {
          final quoteData = rawQuote as Map<String, dynamic>;
          if (quoteData['requested_from_code'] != _purchaseCurrency.code ||
              quoteData['requested_to_code'] != draft.product.currency.code) {
            return false;
          }
          final storedFrom = _currencyForPurchasePair(
            quoteData['stored_from_code'] as String,
            draft.product.currency,
          );
          final storedTo = _currencyForPurchasePair(
            quoteData['stored_to_code'] as String,
            draft.product.currency,
          );
          if (storedFrom == null || storedTo == null) return false;
          final quote = PosCurrencyRateQuote(
            rateId: quoteData['rate_id'] as String,
            storedFromCurrency: storedFrom,
            storedToCurrency: storedTo,
            storedRateScaled: quoteData['stored_rate_scaled'] as int,
            requestedFromCurrency: _purchaseCurrency,
            requestedToCurrency: draft.product.currency,
            effectiveAt: DateTime.parse(quoteData['effective_at'] as String),
            recordedAt: DateTime.parse(quoteData['recorded_at'] as String),
            createdAt: DateTime.parse(quoteData['created_at'] as String),
            isInverted: quoteData['is_inverted'] as bool,
            note: quoteData['note'] as String?,
          );
          conversion = PosCurrencyConversion(
            sourceAmount: sourceAmount,
            targetAmount: quote.convert(sourceAmount),
            rateSnapshot: quote,
          );
        }
        draft.previewConversion = conversion;
        draft.proposedSalePrice = draft.product.profitMargin
            .calculateProposedSalePrice(conversion.targetAmount);
        draft.applyProposedSalePrice =
            saved['apply_proposed_sale_price'] as bool;
        draft.previewFailure = null;
        draft.previewLoading = false;
      }
      setState(() {});
      return true;
    } on Object {
      return false;
    }
  }

  CurrencyCode? _currencyForPurchasePair(
    String code,
    CurrencyCode productCurrency,
  ) {
    if (code == _purchaseCurrency.code) return _purchaseCurrency;
    if (code == productCurrency.code) return productCurrency;
    return null;
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
                    DropdownButtonFormField<CurrencyCode>(
                      initialValue: _purchaseCurrency,
                      decoration: InputDecoration(
                        labelText: AppStrings.posCheckoutCurrencyLabel,
                        helperText: _lines.isEmpty
                            ? null
                            : AppStrings.posPurchaseCurrencyLocked,
                      ),
                      items: (_availableCurrencies.isEmpty
                              ? [widget.currency]
                              : _availableCurrencies)
                          .map((currency) => DropdownMenuItem(
                                value: currency,
                                child: Text(
                                  '${currency.nameAr} (${currency.code})',
                                ),
                              ))
                          .toList(growable: false),
                      onChanged: _lines.isNotEmpty || _submitting
                          ? null
                          : _selectPurchaseCurrency,
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
                              : formatPosMinor(total, _purchaseCurrency),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    FilledButton.icon(
                      onPressed: _submitting ||
                              _lines.values.any((line) =>
                                  line.previewLoading ||
                                  line.previewConversion == null)
                          ? null
                          : _submit,
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
    final quantityHint = '0${line.product.quantityScale > 0 ? '.0' : ''}';
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
    final costField = _purchaseCurrency.fractionalDigits == 0
        ? QaydNumericField(
            controller: line.unitCostController,
            enabled: !_submitting,
            label: AppStrings.posPurchaseSourceUnitPrice,
            suffixText: _purchaseCurrency.symbol,
            onChanged: (_) => _refreshLinePreview(line),
          )
        : QaydAmountField(
            controller: line.unitCostController,
            enabled: !_submitting,
            label: AppStrings.posPurchaseSourceUnitPrice,
            suffixText: _purchaseCurrency.symbol,
            fractionalDigits: _purchaseCurrency.fractionalDigits,
            onChanged: (_) => _refreshLinePreview(line),
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
            const SizedBox(height: SpacingTokens.sm),
            if (line.previewLoading)
              const LinearProgressIndicator()
            else if (line.previewFailure != null)
              Text(
                line.previewFailure!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (line.previewConversion != null) ...[
              Text(
                '${AppStrings.posPurchaseInventoryCost}: '
                '${formatPosMoney(line.previewConversion!.targetAmount)}',
              ),
              if (line.previewConversion!.rateSnapshot case final quote?) ...[
                Text(
                  '${AppStrings.posCheckoutRateSnapshotLabel}: '
                  '1 ${quote.storedFromCurrency.code} = '
                  '${_formatStoredRate(quote.storedRateScaled)} '
                  '${quote.storedToCurrency.code}'
                  '${quote.isInverted ? ' · ${AppStrings.posCheckoutRateReverseApplied}' : ''}',
                ),
                Text(quote.recordedAt.toLocal().toString()),
              ],
              const SizedBox(height: SpacingTokens.xs),
              Text(
                '${AppStrings.posPurchaseCurrentCatalogSalePrice}: '
                '${formatPosMoney(line.product.salePrice)}',
              ),
              Text(
                '${AppStrings.posPurchaseProposedSalePrice}: '
                '${formatPosMoney(line.proposedSalePrice!)}',
              ),
              CheckboxListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: line.applyProposedSalePrice,
                onChanged: _submitting
                    ? null
                    : (value) => setState(
                          () => line.applyProposedSalePrice = value ?? false,
                        ),
                title: Text(AppStrings.posPurchaseApplyProposedSalePrice),
              ),
            ],
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
    final fractionValue =
        fraction.isEmpty ? 0 : int.parse(fraction.padRight(scale, '0'));
    return int.parse(whole) * divisor + fractionValue;
  }

  static String _minorUnitsToText(int minorUnits, int digits) {
    if (digits == 0) return minorUnits.toString();
    final divisor = _pow10(digits);
    final whole = minorUnits ~/ divisor;
    final fraction = (minorUnits % divisor).toString().padLeft(digits, '0');
    return '$whole.$fraction';
  }

  static String _formatStoredRate(int scaled) {
    final factor = BigInt.from(posCurrencyRateScale);
    final value = BigInt.from(scaled);
    final whole = value ~/ factor;
    final fraction = (value % factor).toString().padLeft(8, '0');
    final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.isEmpty ? '$whole' : '$whole.$trimmed';
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
  PosCurrencyConversion? previewConversion;
  Money? proposedSalePrice;
  String? previewFailure;
  bool previewLoading = false;
  bool applyProposedSalePrice = false;

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
