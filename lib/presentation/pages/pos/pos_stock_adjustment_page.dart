import 'package:flutter/material.dart';
import 'package:qayd/application/accounts/list_accounts_use_case.dart';
import 'package:qayd/application/pos/get_pos_stock_balance_use_case.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/application/pos/post_pos_stock_adjustment_atomically_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/components/atomic/qayd_empty_state.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pages/pos/widgets/pos_stock_adjustment_form.dart';
import 'package:qayd/presentation/widgets/account_picker_sheet.dart';
import 'package:qayd/presentation/widgets/qayd_scaffold.dart';
import 'package:uuid/uuid.dart';

typedef SubmitPosStockAdjustment =
    Future<Result<void>> Function(PostPosStockAdjustmentInput input);

/// Dedicated write workflow. Stock and ledger changes remain governed by the
/// injected atomic use case; the page itself never writes a movement directly.
final class PosStockAdjustmentPage extends StatefulWidget {
  const PosStockAdjustmentPage({
    super.key,
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
  State<PosStockAdjustmentPage> createState() =>
      _PosStockAdjustmentPageState();
}

final class _PosStockAdjustmentPageState
    extends State<PosStockAdjustmentPage> {
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
      _loadFailure = null;
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
      _showMessage(
        result.failureOrNull?.messageAr ?? AppStrings.posStockReadFailed,
      );
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

  String? _reasonRequired(String? value) =>
      (value?.trim().isEmpty ?? true)
          ? AppStrings.posStockAdjustmentReasonRequired
          : null;

  void _clearPending() {
    _pendingFingerprint = null;
    _pendingRequestId = null;
    _pendingSourceId = null;
    _pendingIdempotencyKey = null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
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
        result.failureOrNull?.messageAr ??
            AppStrings.posAccountingTransactionFailed,
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
    final appBar = QaydAppBar(title: AppStrings.posStockAdjustmentTitle);
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
        body: PosStockAdjustmentForm(
          formKey: _formKey,
          products: _products,
          selectedProduct: _product,
          direction: _direction,
          balance: _balance,
          currency: widget.currency,
          quantityController: _quantityController,
          unitCostController: _costController,
          reasonController: _reasonController,
          counterAccountName: _counterAccountName,
          counterAccountSelected: _counterAccountId != null,
          submitting: _submitting,
          onProductChanged: _selectProduct,
          onDirectionChanged: (value) {
            if (value == null) return;
            setState(() {
              _direction = value;
              _clearPending();
            });
          },
          onQuantityChanged: (_) => _clearPending(),
          onUnitCostChanged: (_) => _clearPending(),
          onSelectCounterAccount: _selectCounterAccount,
          onReasonChanged: (_) => _clearPending(),
          onSubmit: _submit,
          quantityValidator: _positiveInteger,
          unitCostValidator: _positiveInteger,
          reasonValidator: _reasonRequired,
        ),
      ),
    );
  }
}
