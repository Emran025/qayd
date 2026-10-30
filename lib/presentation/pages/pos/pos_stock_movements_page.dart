import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qayd/application/accounts/list_accounts_use_case.dart';
import 'package:qayd/application/pos/get_pos_stock_balance_use_case.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/application/pos/list_pos_stock_movements_use_case.dart';
import 'package:qayd/application/pos/post_pos_stock_adjustment_atomically_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pos/pos_money_display.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/widgets/account_picker_sheet.dart';
import 'package:uuid/uuid.dart';

typedef SubmitPosStockAdjustment =
    Future<Result<void>> Function(PostPosStockAdjustmentInput input);

/// Read-only movement history with filters and a separately governed
/// adjustment workflow. This page never appends stock movements directly.
final class PosStockMovementsPage extends StatefulWidget {
  const PosStockMovementsPage({
    super.key,
    required this.warehouseId,
    required this.currency,
    required this.listMovements,
    required this.listProducts,
    required this.listAccounts,
    required this.getBalance,
    required this.submitAdjustment,
    this.inventoryAccountId,
  });

  final String warehouseId;
  final CurrencyCode currency;
  final ListPosStockMovementsUseCase listMovements;
  final ListPosProductsUseCase listProducts;
  final ListAccountsUseCase listAccounts;
  final GetPosStockBalanceUseCase getBalance;
  final SubmitPosStockAdjustment submitAdjustment;
  final String? inventoryAccountId;

  @override
  State<PosStockMovementsPage> createState() => _PosStockMovementsPageState();
}

final class _PosStockMovementsPageState extends State<PosStockMovementsPage> {
  static const int _pageSize = 100;
  bool _loading = true;
  bool _loadingMore = false;
  String? _failure;
  String? _productId;
  PosStockMovementType? _type;
  List<PosProduct> _products = const [];
  List<PosStockMovement> _movements = const [];
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = true}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _failure = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    final offset = reset ? 0 : _movements.length;
    final productResult = await widget.listProducts(activeOnly: false);
    if (!mounted) return;
    if (productResult.isFailure) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _failure = productResult.failureOrNull?.messageAr ??
            AppStrings.posProductReadFailed;
      });
      return;
    }

    final movementResult = await widget.listMovements(
      ListPosStockMovementsInput(
        warehouseId: widget.warehouseId,
        productId: _productId,
        type: _type,
        limit: _pageSize,
        offset: offset,
      ),
    );
    if (!mounted) return;
    if (movementResult.isFailure) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _failure = movementResult.failureOrNull?.messageAr ??
            AppStrings.posStockReadFailed;
      });
      return;
    }
    final page = movementResult.valueOrNull ?? const <PosStockMovement>[];
    setState(() {
      _products = productResult.valueOrNull ?? const <PosProduct>[];
      _movements = reset ? page : [..._movements, ...page];
      _hasMore = page.length == _pageSize;
      _loading = false;
      _loadingMore = false;
      _failure = null;
    });
  }

  Future<void> _openAdjustment() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _PosStockAdjustmentPage(
          warehouseId: widget.warehouseId,
          currency: widget.currency,
          listProducts: widget.listProducts,
          listAccounts: widget.listAccounts,
          getBalance: widget.getBalance,
          submitAdjustment: widget.submitAdjustment,
          inventoryAccountId: widget.inventoryAccountId,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  String _productName(String productId) {
    final product = _products.where((item) => item.id == productId).firstOrNull;
    return product == null ? productId : '${product.name} · ${product.sku}';
  }

  @override
  Widget build(BuildContext context) {
    final activeProducts = _products
        .where((product) => product.currency == widget.currency)
        .toList(growable: false);
    return Scaffold(
      appBar: QaydAppBar(title: AppStrings.posStockMovementsTitle),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdjustment,
        icon: const Icon(Icons.tune_rounded),
        label: Text(AppStrings.posStockAdjustmentTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failure != null
              ? _FailureView(message: _failure!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      SpacingTokens.md,
                      SpacingTokens.md,
                      SpacingTokens.md,
                      96,
                    ),
                    children: [
                      Text(AppStrings.posStockMovementsDescription),
                      const SizedBox(height: SpacingTokens.md),
                      DropdownButtonFormField<String?>(
                        value: _productId,
                        decoration: InputDecoration(
                          labelText: AppStrings.posOpeningBalanceProduct,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(AppStrings.posStockMovementAllProducts),
                          ),
                          ...activeProducts.map(
                            (product) => DropdownMenuItem<String?>(
                              value: product.id,
                              child: Text(product.name),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _productId = value);
                          _load();
                        },
                      ),
                      const SizedBox(height: SpacingTokens.sm),
                      DropdownButtonFormField<PosStockMovementType?>(
                        value: _type,
                        decoration: InputDecoration(
                          labelText: AppStrings.posStockMovementAllTypes,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem<PosStockMovementType?>(
                            value: null,
                            child: Text(AppStrings.posStockMovementAllTypes),
                          ),
                          ...PosStockMovementType.values.map(
                            (type) => DropdownMenuItem<PosStockMovementType?>(
                              value: type,
                              child: Text(
                                AppStrings.posStockMovementTypeLabel(
                                  type.name,
                                ),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _type = value);
                          _load();
                        },
                      ),
                      const SizedBox(height: SpacingTokens.md),
                      if (_movements.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: SpacingTokens.xl,
                          ),
                          child: Center(
                            child: Text(AppStrings.posStockMovementsEmpty),
                          ),
                        )
                      else
                        ..._movements.map(
                          (movement) => _MovementTile(
                            movement: movement,
                            productName: _productName(movement.productId),
                          ),
                        ),
                      if (_hasMore)
                        Padding(
                          padding: const EdgeInsets.only(top: SpacingTokens.md),
                          child: OutlinedButton(
                            onPressed: _loadingMore
                                ? null
                                : () => _load(reset: false),
                            child: _loadingMore
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(AppStrings.posStockMovementsLoadMore),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

final class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, required this.productName});

  final PosStockMovement movement;
  final String productName;

  @override
  Widget build(BuildContext context) {
    final inbound = movement.direction == PosStockMovementDirection.inbound;
    final theme = Theme.of(context);
    final localDate = movement.occurredAt.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(localDate);
    final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(localDate));
    final amount = '${inbound ? '+' : '−'}${movement.quantity.toExactString()}';
    return Card(
      margin: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (inbound
                  ? theme.colorScheme.primary
                  : theme.colorScheme.tertiary)
              .withValues(alpha: 0.14),
          child: Icon(
            inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: inbound ? theme.colorScheme.primary : theme.colorScheme.tertiary,
          ),
        ),
        title: Text(productName),
        subtitle: Text(
          '${AppStrings.posStockMovementTypeLabel(movement.type.name)} · $date · $time',
        ),
        trailing: Text(
          amount,
          style: theme.textTheme.titleMedium?.copyWith(
            color: inbound ? theme.colorScheme.primary : theme.colorScheme.tertiary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

final class _PosStockAdjustmentPage extends StatefulWidget {
  const _PosStockAdjustmentPage({
    required this.warehouseId,
    required this.currency,
    required this.listProducts,
    required this.listAccounts,
    required this.getBalance,
    required this.submitAdjustment,
    this.inventoryAccountId,
  });

  final String warehouseId;
  final CurrencyCode currency;
  final ListPosProductsUseCase listProducts;
  final ListAccountsUseCase listAccounts;
  final GetPosStockBalanceUseCase getBalance;
  final SubmitPosStockAdjustment submitAdjustment;
  final String? inventoryAccountId;

  @override
  State<_PosStockAdjustmentPage> createState() =>
      _PosStockAdjustmentPageState();
}

final class _PosStockAdjustmentPageState
    extends State<_PosStockAdjustmentPage> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _costController = TextEditingController();
  final _reasonController = TextEditingController();
  List<PosProduct> _products = const [];
  PosProduct? _product;
  PosStockMovementDirection _direction = PosStockMovementDirection.inbound;
  String? _counterAccountId;
  String? _counterAccountName;
  PosStockBalance? _balance;
  String? _loadFailure;
  bool _loading = true;
  bool _submitting = false;
  String? _pendingFingerprint;
  String? _pendingRequestId;
  String? _pendingSourceId;
  String? _pendingIdempotencyKey;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _costController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final result = await widget.listProducts(activeOnly: true);
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
          .where((item) => item.currency == widget.currency)
          .toList(growable: false);
      _loading = false;
    });
  }

  Future<void> _selectProduct(PosProduct? product) async {
    setState(() {
      _product = product;
      _balance = null;
      _clearPending();
    });
    if (product == null) return;
    final result = await widget.getBalance(
      GetPosStockBalanceInput(
        productId: product.id,
        warehouseId: widget.warehouseId,
      ),
    );
    if (!mounted) return;
    if (result.isFailure) {
      _showMessage(result.failureOrNull?.messageAr ?? AppStrings.posStockReadFailed);
      return;
    }
    setState(() => _balance = result.valueOrNull);
  }

  Future<void> _selectCounterAccount() async {
    final account = await showAccountPickerSheet(
      context,
      listAccounts: widget.listAccounts,
      excludeAccountId: widget.inventoryAccountId,
      requireNoRoot: true,
      hideSterileRoots: true,
    );
    if (account == null || !mounted) return;
    setState(() {
      _counterAccountId = account.id;
      _counterAccountName = account.name;
      _clearPending();
    });
  }

  String? _positiveInteger(String? raw) {
    final value = int.tryParse(raw?.trim() ?? '');
    return value == null || value <= 0
        ? AppStrings.posOpeningBalancePositiveInteger
        : null;
  }

  void _clearPending() {
    _pendingFingerprint = null;
    _pendingRequestId = null;
    _pendingSourceId = null;
    _pendingIdempotencyKey = null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final product = _product;
    final accountId = _counterAccountId;
    if (product == null || accountId == null) return;
    final quantity = int.parse(_quantityController.text.trim());
    final inbound = _direction == PosStockMovementDirection.inbound;
    final unitCost = inbound ? int.parse(_costController.text.trim()) : null;
    final reason = _reasonController.text.trim();
    final fingerprint = [
      product.id,
      _direction.name,
      quantity,
      unitCost,
      accountId,
      reason,
    ].join('|');
    if (_pendingFingerprint != fingerprint || _pendingIdempotencyKey == null) {
      final requestId = const Uuid().v4();
      _pendingFingerprint = fingerprint;
      _pendingRequestId = requestId;
      _pendingIdempotencyKey = 'stock-adjustment:$requestId';
      _pendingSourceId = 'stock-adjustment:$requestId:${product.id}';
    }

    setState(() => _submitting = true);
    final Result<void> result;
    try {
      result = await widget.submitAdjustment(
        PostPosStockAdjustmentInput(
          productId: product.id,
          direction: _direction,
          quantityScaled: quantity,
          quantityScale: product.quantityScale,
          currencyCode: product.currency.code,
          counterAccountId: accountId,
          reason: reason,
          idempotencyKey: _pendingIdempotencyKey!,
          sourceId: _pendingSourceId!,
          movementId: 'pos-stock-movement:$_pendingRequestId',
          voucherId: 'pos-stock-voucher:$_pendingRequestId',
          transactionId: 'pos-stock-transaction:$_pendingRequestId',
          debitEntryId: 'pos-stock-debit:$_pendingRequestId',
          creditEntryId: 'pos-stock-credit:$_pendingRequestId',
          inboundUnitCostMinor: unitCost,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showMessage(AppStrings.posAccountingTransactionFailed);
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isFailure) {
      _showMessage(
        result.failureOrNull?.messageAr ?? AppStrings.posAccountingTransactionFailed,
      );
      return;
    }
    _showMessage(AppStrings.posStockAdjustmentSaved);
    Navigator.of(context).pop(true);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    if (_loading) {
      return Scaffold(
        appBar: QaydAppBar(title: AppStrings.posStockAdjustmentTitle),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadFailure != null) {
      return Scaffold(
        appBar: QaydAppBar(title: AppStrings.posStockAdjustmentTitle),
        body: _FailureView(message: _loadFailure!, onRetry: _loadProducts),
      );
    }
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        appBar: QaydAppBar(title: AppStrings.posStockAdjustmentTitle),
        body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            Text(AppStrings.posStockAdjustmentDescription),
            const SizedBox(height: SpacingTokens.md),
            DropdownButtonFormField<PosProduct>(
              value: _product,
              decoration: InputDecoration(
                labelText: AppStrings.posOpeningBalanceProduct,
                border: const OutlineInputBorder(),
              ),
              items: products
                  .map(
                    (product) => DropdownMenuItem(
                      value: product,
                      child: Text('${product.name} (${product.sku})'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _submitting ? null : _selectProduct,
              validator: (value) => value == null
                  ? AppStrings.posOpeningBalanceSelectProduct
                  : null,
            ),
            const SizedBox(height: SpacingTokens.md),
            DropdownButtonFormField<PosStockMovementDirection>(
              value: _direction,
              decoration: InputDecoration(
                labelText: AppStrings.posStockAdjustmentDirection,
                border: const OutlineInputBorder(),
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
              onChanged: _submitting
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _direction = value;
                        _clearPending();
                      });
                    },
            ),
            const SizedBox(height: SpacingTokens.md),
            TextFormField(
              controller: _quantityController,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: AppStrings.posStockAdjustmentQuantity,
                helperText: _product == null
                    ? null
                    : AppStrings.posOpeningBalanceQuantityHint(
                        _product!.quantityScale,
                      ),
                border: const OutlineInputBorder(),
              ),
              validator: _positiveInteger,
              onChanged: (_) => _clearPending(),
            ),
            if (_direction == PosStockMovementDirection.inbound) ...[
              const SizedBox(height: SpacingTokens.md),
              TextFormField(
                controller: _costController,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: AppStrings.posStockAdjustmentUnitCost,
                  helperText: AppStrings.posOpeningBalanceCostHint(
                    widget.currency.code,
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: _positiveInteger,
                onChanged: (_) => _clearPending(),
              ),
            ] else if (_product != null && _balance != null) ...[
              const SizedBox(height: SpacingTokens.md),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.calculate_outlined),
                  title: Text(AppStrings.posOpeningBalanceCurrent),
                  subtitle: Text(
                    '${_balance!.quantity.toExactString()} · '
                    '${formatPosMoney(_balance!.averageUnitCost)}',
                  ),
                ),
              ),
            ],
            const SizedBox(height: SpacingTokens.md),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _selectCounterAccount,
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(
                _counterAccountName ??
                    AppStrings.posStockAdjustmentSelectAccount,
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
            TextFormField(
              controller: _reasonController,
              enabled: !_submitting,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: AppStrings.posStockAdjustmentReason,
                border: const OutlineInputBorder(),
              ),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? AppStrings.posStockAdjustmentReasonRequired
                  : null,
              onChanged: (_) => _clearPending(),
            ),
            const SizedBox(height: SpacingTokens.lg),
            FilledButton.icon(
              onPressed: _submitting || _product == null || _counterAccountId == null
                  ? null
                  : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(AppStrings.posStockAdjustmentSave),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

final class _FailureView extends StatelessWidget {
  const _FailureView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
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
