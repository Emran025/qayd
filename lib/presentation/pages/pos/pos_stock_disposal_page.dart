import 'package:flutter/material.dart';
import 'package:qayd/application/pos/get_pos_stock_balance_use_case.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/application/pos/list_pos_stock_disposal_lots_use_case.dart';
import 'package:qayd/application/pos/post_pos_stock_disposal_atomically_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_lot.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/pos_stock_disposal_reason.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/components/atomic/qayd_empty_state.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/widgets/qayd_scaffold.dart';
import 'package:uuid/uuid.dart';

typedef SubmitPosStockDisposal =
    Future<Result<void>> Function(PostPosStockDisposalInput input);

/// Dedicated, governed stock-loss workflow. Writes are delegated to the atomic
/// use case; this page never edits stock rows or vouchers directly.
final class PosStockDisposalPage extends StatefulWidget {
  const PosStockDisposalPage({
    super.key,
    required this.warehouseId,
    required this.currency,
    required this.listProducts,
    required this.listLots,
    required this.getBalance,
    required this.submitDisposal,
  });

  final String warehouseId;
  final CurrencyCode currency;
  final ListPosProductsUseCase listProducts;
  final ListPosStockDisposalLotsUseCase listLots;
  final GetPosStockBalanceUseCase getBalance;
  final SubmitPosStockDisposal submitDisposal;

  @override
  State<PosStockDisposalPage> createState() => _PosStockDisposalPageState();
}

final class _PosStockDisposalPageState extends State<PosStockDisposalPage> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _detailController = TextEditingController();
  List<PosProduct> _products = const [];
  List<PosStockLot> _lots = const [];
  PosProduct? _product;
  PosStockLot? _lot;
  PosStockDisposalReason _reason = PosStockDisposalReason.damage;
  PosStockBalance? _balance;
  DateTime _date = DateTime.now();
  String? _loadFailure;
  String? _lotsFailure;
  String? _pendingFingerprint;
  String? _pendingRequestId;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final result = await widget.listProducts(activeOnly: false);
    if (!mounted) return;
    if (result.isFailure) {
      setState(() {
        _loading = false;
        _loadFailure = result.failureOrNull?.messageAr ??
            AppStrings.posProductReadFailed;
      });
      return;
    }
    setState(() {
      _products = (result.valueOrNull ?? const <PosProduct>[])
          .where((product) => product.currency == widget.currency)
          .toList(growable: false);
      _loading = false;
      _loadFailure = null;
    });
  }

  Future<void> _selectProduct(PosProduct? product) async {
    setState(() {
      _product = product;
      _balance = null;
      _lots = const [];
      _lot = null;
      _lotsFailure = null;
      _quantityController.clear();
      _clearPending();
    });
    if (product == null) return;

    final balanceResult = await widget.getBalance(
      GetPosStockBalanceInput(
        productId: product.id,
        warehouseId: widget.warehouseId,
      ),
    );
    if (!mounted || _product?.id != product.id) return;
    if (balanceResult.isFailure) {
      _showMessage(
        balanceResult.failureOrNull?.messageAr ?? AppStrings.posStockReadFailed,
      );
    } else {
      setState(() => _balance = balanceResult.valueOrNull);
    }

    final lotsResult = await widget.listLots(
      productId: product.id,
      warehouseId: widget.warehouseId,
    );
    if (!mounted || _product?.id != product.id) return;
    if (lotsResult.isFailure) {
      setState(() {
        _lots = const [];
        _lot = null;
        _lotsFailure = lotsResult.failureOrNull?.messageAr ??
            AppStrings.posStockReadFailed;
      });
    } else {
      setState(() {
        _lots = lotsResult.valueOrNull ?? const <PosStockLot>[];
        _lotsFailure = null;
      });
    }
  }

  PosDate get _businessDate => PosDate.fromDateTime(_movementDate.toLocal());

  DateTime get _movementDate => DateTime(
        _date.year,
        _date.month,
        _date.day,
        12,
      );

  List<PosStockLot> get _visibleLots {
    if (_reason == PosStockDisposalReason.expiry) {
      return _lots
          .where((lot) =>
              lot.expiryDate != null && lot.expiryDate!.isBefore(_businessDate))
          .toList(growable: false);
    }
    if (_reason == PosStockDisposalReason.damage) {
      return _lots
          .where((lot) =>
              lot.expiryDate == null || !lot.expiryDate!.isBefore(_businessDate))
          .toList(growable: false);
    }
    return _lots;
  }

  int? get _quantity => int.tryParse(_quantityController.text.trim());

  int get _availableScaled => _lot?.remainingQuantity.scaledUnits ??
      _balance?.quantity.scaledUnits ??
      0;

  void _clearPending() {
    _pendingFingerprint = null;
    _pendingRequestId = null;
  }

  String? _positiveQuantity(String? raw) {
    final quantity = int.tryParse(raw?.trim() ?? '');
    if (quantity == null || quantity <= 0) {
      return AppStrings.posOpeningBalancePositiveInteger;
    }
    if (quantity > _availableScaled) {
      return AppStrings.posStockLotsInsufficient;
    }
    return null;
  }

  String? _detailValidator(String? raw) {
    final value = raw?.trim() ?? '';
    if (_reason == PosStockDisposalReason.other && value.isEmpty) {
      return AppStrings.posStockDisposalOtherDetailRequired;
    }
    if (value.length > 500) return AppStrings.posStockDisposalInvalid;
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      _clearPending();
    });
  }

  String _lotLabel(PosStockLot lot) {
    final name = lot.supplierLotNumber?.trim().isNotEmpty == true
        ? lot.supplierLotNumber!.trim()
        : lot.id;
    final expiry = lot.expiryDate?.isoDate ?? '—';
    return '$name · ${lot.remainingQuantity.toExactString()} · $expiry';
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final product = _product;
    final balance = _balance;
    final quantity = _quantity;
    if (product == null || balance == null || quantity == null) return;
    if ((product.expiryTracking ||
            _reason == PosStockDisposalReason.expiry) &&
        _lot == null) {
      _showMessage(AppStrings.posStockDisposalExpiryLotRequired);
      return;
    }
    final detail = _detailController.text.trim();
    final fingerprint = [
      product.id,
      widget.warehouseId,
      _reason.code,
      _lot?.id,
      quantity,
      detail,
      _businessDate.isoDate,
    ].join('|');
    if (_pendingFingerprint != fingerprint || _pendingRequestId == null) {
      _pendingRequestId = const Uuid().v4();
      _pendingFingerprint = fingerprint;
    }
    final requestId = _pendingRequestId!;
    final movementDate = _movementDate;

    setState(() => _submitting = true);
    final Result<void> result;
    try {
      result = await widget.submitDisposal(
        PostPosStockDisposalInput(
          productId: product.id,
          warehouseId: widget.warehouseId,
          reason: _reason,
          quantityScaled: quantity,
          quantityScale: product.quantityScale,
          currencyCode: product.currency.code,
          sourceId: 'pos-stock-disposal:$requestId',
          idempotencyKey: 'pos-stock-disposal:$requestId',
          reasonDetail: detail.isEmpty ? null : detail,
          lotId: _lot?.id,
          movementId: 'pos-stock-disposal-movement:$requestId',
          voucherId: 'pos-stock-disposal-voucher:$requestId',
          transactionId: 'pos-stock-disposal-transaction:$requestId',
          debitEntryId: 'pos-stock-disposal-debit:$requestId',
          creditEntryId: 'pos-stock-disposal-credit:$requestId',
          occurredAt: movementDate,
          createdAt: DateTime.now().toUtc(),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showMessage(AppStrings.posStockDisposalFailed);
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isFailure) {
      _showMessage(
        result.failureOrNull?.messageAr ?? AppStrings.posStockDisposalFailed,
      );
      return;
    }
    _showMessage(AppStrings.posStockDisposalSaved);
    Navigator.of(context).pop(true);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final appBar = QaydAppBar(title: AppStrings.posStockDisposalTitle);
    if (_loading) {
      return QaydScaffold(
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadFailure != null) {
      return QaydScaffold(
        appBar: appBar,
        body: QaydEmptyState(
          icon: Icons.error_outline_rounded,
          title: _loadFailure!,
          action: FilledButton.tonal(
            onPressed: _loadProducts,
            child: Text(AppStrings.retryAction),
          ),
        ),
      );
    }
    return PopScope(
      canPop: !_submitting,
      child: QaydScaffold(
        appBar: appBar,
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            children: [
              Text(AppStrings.posStockDisposalDescription),
              const SizedBox(height: SpacingTokens.md),
              DropdownButtonFormField<PosProduct?>(
                initialValue: _product,
                decoration: InputDecoration(
                  labelText: AppStrings.posOpeningBalanceProduct,
                ),
                items: [
                  DropdownMenuItem<PosProduct?>(
                    value: null,
                    child: Text(AppStrings.posOpeningBalanceSelectProduct),
                  ),
                  ..._products.map(
                    (product) => DropdownMenuItem<PosProduct?>(
                      value: product,
                      child: Text(
                        '${product.name} · ${product.sku}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: _submitting ? null : _selectProduct,
                validator: (product) => product == null
                    ? AppStrings.posOpeningBalanceSelectProduct
                    : null,
              ),
              const SizedBox(height: SpacingTokens.sm),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: AppStrings.posStockDisposalWarehouse,
                ),
                child: Text(widget.warehouseId),
              ),
              const SizedBox(height: SpacingTokens.sm),
              DropdownButtonFormField<PosStockDisposalReason>(
                initialValue: _reason,
                decoration: InputDecoration(
                  labelText: AppStrings.posStockDisposalReason,
                ),
                items: PosStockDisposalReason.values
                    .map(
                      (reason) => DropdownMenuItem(
                        value: reason,
                        child: Text(_reasonLabel(reason)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _submitting
                    ? null
                    : (reason) {
                        if (reason == null) return;
                        setState(() {
                          _reason = reason;
                          if (_lot != null && !_visibleLots.contains(_lot)) {
                            _lot = null;
                          }
                          _clearPending();
                        });
                      },
              ),
              const SizedBox(height: SpacingTokens.sm),
              if (_product?.expiryTracking == true ||
                  _reason == PosStockDisposalReason.expiry ||
                  _lots.isNotEmpty)
                DropdownButtonFormField<PosStockLot?>(
                  initialValue: _lot,
                  decoration: InputDecoration(
                    labelText: AppStrings.posStockDisposalLot,
                  ),
                  items: [
                    DropdownMenuItem<PosStockLot?>(
                      value: null,
                      child: Text(AppStrings.posStockDisposalSelectLot),
                    ),
                    ..._visibleLots.map(
                      (lot) => DropdownMenuItem<PosStockLot?>(
                        value: lot,
                        child: Text(
                          _lotLabel(lot),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (lot) {
                          setState(() {
                            _lot = lot;
                            _clearPending();
                          });
                        },
                  validator: (lot) =>
                      (_product?.expiryTracking == true ||
                              _reason == PosStockDisposalReason.expiry) &&
                          lot == null
                      ? AppStrings.posStockDisposalExpiryLotRequired
                      : null,
                ),
              if (_lotsFailure != null) ...[
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  _lotsFailure!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ] else if ((_product?.expiryTracking == true ||
                      _reason == PosStockDisposalReason.expiry) &&
                  _visibleLots.isEmpty) ...[
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  _reason == PosStockDisposalReason.expiry
                      ? AppStrings.posStockDisposalNotExpired
                      : AppStrings.posStockDisposalNoLots,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: SpacingTokens.sm),
              TextFormField(
                controller: _quantityController,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: AppStrings.posStockDisposalQuantity,
                  helperText: _product == null
                      ? null
                      : '${AppStrings.posStockDisposalAvailableLabel}: ${_availableQuantityLabel()}',
                ),
                onChanged: (_) {
                  setState(_clearPending);
                },
                validator: _positiveQuantity,
              ),
              const SizedBox(height: SpacingTokens.sm),
              TextFormField(
                controller: _detailController,
                enabled: !_submitting,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: AppStrings.posStockDisposalDetail,
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => _clearPending(),
                validator: _detailValidator,
              ),
              const SizedBox(height: SpacingTokens.xs),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  '${AppStrings.posStockDisposalDate}: ${localizations.formatMediumDate(_date)}',
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              if (_balance != null) _valuationCard(context),
              const SizedBox(height: SpacingTokens.md),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_sweep_outlined),
                label: Text(AppStrings.posStockDisposalSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _valuationCard(BuildContext context) {
    final balance = _balance!;
    final quantity = _quantity;
    final average = balance.averageUnitCost;
    final available = _lot?.remainingQuantity ?? balance.quantity;
    final amount = quantity == null ||
            quantity <= 0 ||
            quantity > _availableScaled
        ? null
        : PosMoneyMath.multiply(
            PosQuantity.fromScaled(
              quantity,
              scale: _product!.quantityScale,
            ),
            average,
          );
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppStrings.posStockDisposalAvailableLabel}: ${available.toExactString()} ${_product?.unitName ?? ''}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              '${AppStrings.posStockAdjustmentUnitCost}: ${average.minorUnits} ${widget.currency.code}',
            ),
            if (amount != null) ...[
              const SizedBox(height: SpacingTokens.xs),
              Text(
                '${AppStrings.posStockDisposalEstimatedValue}: ${amount.minorUnits} ${widget.currency.code}',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _availableQuantityLabel() {
    final quantity = _lot?.remainingQuantity ?? _balance?.quantity;
    return quantity == null
        ? ''
        : '${quantity.toExactString()} ${_product?.unitName ?? ''}';
  }

  String _reasonLabel(PosStockDisposalReason reason) => switch (reason) {
        PosStockDisposalReason.damage => AppStrings.posStockDisposalReasonDamage,
        PosStockDisposalReason.expiry => AppStrings.posStockDisposalReasonExpiry,
        PosStockDisposalReason.authorizedLoss =>
          AppStrings.posStockDisposalReasonAuthorizedLoss,
        PosStockDisposalReason.other => AppStrings.posStockDisposalReasonOther,
      };
}
