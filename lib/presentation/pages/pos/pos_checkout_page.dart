import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/application/settings/list_currencies_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/di/injection_container.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/entities/pos_discount_rule.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/components/atomic/qayd_empty_state.dart';
import 'package:qayd/presentation/components/inputs/qayd_numeric_field.dart';
import 'package:qayd/presentation/components/inputs/qayd_text_field.dart';
import 'package:qayd/presentation/widgets/qayd_scaffold.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pos/pos_money_display.dart';
import 'package:qayd/presentation/pos/pos_background_barcode_scanner.dart';
import 'package:qayd/presentation/pos/pos_checkout_cubit.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/widgets/account_picker_sheet.dart';

/// Fast POS checkout surface. Completion delegates to the governed atomic
/// application boundary after the operator provides settlement details.
class PosCheckoutPage extends StatelessWidget {
  const PosCheckoutPage({
    super.key,
    required this.cubit,
    required this.warehouseId,
    required this.currency,
    this.scannerEnabled = true,
    this.listCurrenciesUseCase,
  });

  final PosCheckoutCubit cubit;
  final String warehouseId;
  final CurrencyCode currency;
  final bool scannerEnabled;
  final ListCurrenciesUseCase? listCurrenciesUseCase;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      child: _PosCheckoutView(
        scannerEnabled: scannerEnabled,
        warehouseId: warehouseId,
        currency: currency,
        listCurrenciesUseCase: listCurrenciesUseCase,
      ),
    );
  }
}

class _PosCheckoutView extends StatefulWidget {
  const _PosCheckoutView({
    required this.scannerEnabled,
    required this.warehouseId,
    required this.currency,
    required this.listCurrenciesUseCase,
  });

  final bool scannerEnabled;
  final String warehouseId;
  final CurrencyCode currency;
  final ListCurrenciesUseCase? listCurrenciesUseCase;

  @override
  State<_PosCheckoutView> createState() => _PosCheckoutViewState();
}

class _PosCheckoutViewState extends State<_PosCheckoutView> {
  final _inputController = TextEditingController();
  final _advanceController = TextEditingController(text: '0');
  final _customerController = TextEditingController();
  final _creditTermsController = TextEditingController();
  final _paymentAccountController = TextEditingController();
  late CurrencyCode _selectedCurrency;
  List<CurrencyCode> _availableCurrencies = const [];
  String? _customerAccountId;
  String? _paymentAccountId;
  DateTime? _creditDueDate;
  PosPaymentMethod _paymentMethod = PosPaymentMethod.cash;
  final _scannerKey = GlobalKey<PosBackgroundBarcodeScannerState>();
  bool _isBackCamera = true;
  String? _scannerError;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _selectedCurrency = widget.currency;
    _availableCurrencies = [widget.currency];
    context.read<PosCheckoutCubit>().setSaleCurrency(widget.currency);
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    final useCase = widget.listCurrenciesUseCase;
    if (useCase == null) return;
    final result = await useCase(onlyActive: true);
    if (!mounted || result.isFailure) return;
    final currencies = result.valueOrNull ?? const <CurrencyCode>[];
    setState(() {
      _availableCurrencies = List.unmodifiable(
        currencies.any((item) => item.code == widget.currency.code)
            ? currencies
            : [...currencies, widget.currency],
      );
    });
  }

  void _changeSaleCurrency(CurrencyCode currency) {
    if (currency == _selectedCurrency) return;
    unawaited(context.read<PosCheckoutCubit>().setSaleCurrency(currency));
    setState(() {
      _selectedCurrency = currency;
      _advanceController.text = '0';
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _inputController.dispose();
    _advanceController.dispose();
    _customerController.dispose();
    _creditTermsController.dispose();
    _paymentAccountController.dispose();
    super.dispose();
  }

  Future<void> _pickAccount({required bool customer}) async {
    final selected = await showAccountPickerSheet(
      context,
      listAccounts: InjectionContainer.listAccountsUseCase,
      hideSterileRoots: true,
    );
    if (!mounted || selected == null) return;
    setState(() {
      if (customer) {
        _customerAccountId = selected.id;
        _customerController.text = selected.name;
      } else {
        _paymentAccountId = selected.id;
        _paymentAccountController.text = selected.name;
      }
    });
  }

  void _onChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) context.read<PosCheckoutCubit>().search(value);
    });
  }

  Future<void> _complete() async {
    final advance = int.tryParse(_advanceController.text.trim());
    if (advance == null || advance < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.posInvoicePaymentInvalid)),
      );
      return;
    }
    final hasCreditBalance =
        context.read<PosCheckoutCubit>().state.totalMinorUnits > advance;
    await context.read<PosCheckoutCubit>().completeCheckout(
      warehouseId: widget.warehouseId,
      currency: _selectedCurrency,
      advanceMinorUnits: advance,
      paymentMethod: _paymentMethod,
      customerAccountId: _customerAccountId == null
          ? null
          : AccountId(_customerAccountId!),
      paymentAccountId: _paymentAccountId == null
          ? null
          : AccountId(_paymentAccountId!),
      creditDueDate: hasCreditBalance ? _creditDueDate : null,
      creditTerms: hasCreditBalance ? _creditTermsController.text : null,
    );
    if (mounted &&
        context.read<PosCheckoutCubit>().state.status ==
            PosCheckoutStatus.completed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.posCheckoutCompleted)));
    }
  }

  Future<void> _toggleCamera() async {
    await _scannerKey.currentState?.toggleCamera();
    if (mounted) setState(() => _isBackCamera = !_isBackCamera);
  }

  void _onBarcode(String value) {
    _searchDebounce?.cancel();
    _inputController.clear();
    if (mounted) setState(() => _scannerError = null);
    unawaited(HapticFeedback.selectionClick());
    unawaited(context.read<PosCheckoutCubit>().resolveAndAdd(value));
  }

  Future<void> _submitInput() async {
    final value = _inputController.text.trim();
    if (value.isEmpty) return;
    // Hardware scanners commonly emit the value through onChanged followed by
    // an Enter/Tab suffix. Resolve the scan exactly once through the canonical
    // command instead of letting the delayed search race with it.
    _searchDebounce?.cancel();
    _inputController.clear();
    await context.read<PosCheckoutCubit>().resolveAndAdd(value);
  }

  @override
  Widget build(BuildContext context) {
    return QaydScaffold(
      appBar: QaydAppBar(title: AppStrings.posCheckoutTitle),
      body: Stack(
        children: [
          BlocBuilder<PosCheckoutCubit, PosCheckoutState>(
            builder: (context, state) => _CheckoutContent(
              state: state,
              currency: _selectedCurrency,
              availableCurrencies: _availableCurrencies,
              onCurrencyChanged: _changeSaleCurrency,
              inputController: _inputController,
              onChanged: _onChanged,
              onSubmitted: (_) => _submitInput(),
              onAddProduct: (product) => unawaited(
                context.read<PosCheckoutCubit>().addProduct(product),
              ),
              onSetQuantity: context.read<PosCheckoutCubit>().setQuantity,
              onRemoveProduct: context.read<PosCheckoutCubit>().removeProduct,
              onClearCart: context.read<PosCheckoutCubit>().clearCart,
              onComplete: _complete,
              paymentMethod: _paymentMethod,
              onPaymentMethodChanged: (value) =>
                  setState(() => _paymentMethod = value),
              advanceController: _advanceController,
              customerController: _customerController,
              creditTermsController: _creditTermsController,
              creditDueDate: _creditDueDate,
              onCreditDueDateChanged: (value) =>
                  setState(() => _creditDueDate = value),
              paymentAccountController: _paymentAccountController,
              onPickCustomer: () => _pickAccount(customer: true),
              onPickPaymentAccount: () => _pickAccount(customer: false),
              isBackCamera: _isBackCamera,
              scannerError: _scannerError,
              onToggleCamera: _toggleCamera,
            ),
          ),
          PosBackgroundBarcodeScanner(
            key: _scannerKey,
            onBarcode: _onBarcode,
            onError: (error) {
              if (mounted) setState(() => _scannerError = error.toString());
            },
            enabled: widget.scannerEnabled,
          ),
        ],
      ),
    );
  }
}

class _CheckoutContent extends StatelessWidget {
  const _CheckoutContent({
    required this.state,
    required this.currency,
    required this.availableCurrencies,
    required this.onCurrencyChanged,
    required this.inputController,
    required this.onChanged,
    required this.onSubmitted,
    required this.onAddProduct,
    required this.onSetQuantity,
    required this.onRemoveProduct,
    required this.onClearCart,
    required this.onComplete,
    required this.paymentMethod,
    required this.onPaymentMethodChanged,
    required this.advanceController,
    required this.customerController,
    required this.creditTermsController,
    required this.creditDueDate,
    required this.onCreditDueDateChanged,
    required this.paymentAccountController,
    required this.onPickCustomer,
    required this.onPickPaymentAccount,
    required this.isBackCamera,
    required this.scannerError,
    required this.onToggleCamera,
  });

  final PosCheckoutState state;
  final CurrencyCode currency;
  final List<CurrencyCode> availableCurrencies;
  final ValueChanged<CurrencyCode> onCurrencyChanged;
  final TextEditingController inputController;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<PosProduct> onAddProduct;
  final void Function(String, PosQuantity) onSetQuantity;
  final ValueChanged<String> onRemoveProduct;
  final VoidCallback onClearCart;
  final VoidCallback onComplete;
  final PosPaymentMethod paymentMethod;
  final ValueChanged<PosPaymentMethod> onPaymentMethodChanged;
  final TextEditingController advanceController;
  final TextEditingController customerController;
  final TextEditingController creditTermsController;
  final DateTime? creditDueDate;
  final ValueChanged<DateTime?> onCreditDueDateChanged;
  final TextEditingController paymentAccountController;
  final VoidCallback onPickCustomer;
  final VoidCallback onPickPaymentAccount;
  final bool isBackCamera;
  final String? scannerError;
  final VoidCallback onToggleCamera;

  Future<void> _editCartDiscount(BuildContext context) async {
    final cubit = context.read<PosCheckoutCubit>();
    final result = await _showDiscountRuleDialog(
      context: context,
      title: AppStrings.posDiscountCart,
      existing: state.cartDiscountRule,
      eligibleMinorUnits:
          state.subtotalMinorUnits - state.lineDiscountMinorUnits,
      currency: currency,
      actorId: cubit.discountActorId,
      policyMaximumBasisPoints: cubit.discountPolicyMaximumBasisPoints,
    );
    if (!context.mounted || !result.confirmed) return;
    if (!cubit.setCartDiscountRule(result.rule)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.posDiscountInvalid)));
    }
  }

  Future<void> _editLineDiscount(
    BuildContext context,
    PosCheckoutLineState line,
  ) async {
    final cubit = context.read<PosCheckoutCubit>();
    final lineCurrency = line.unitPrice?.currency;
    if (lineCurrency == null) return;
    final result = await _showDiscountRuleDialog(
      context: context,
      title:
          '${line.discountRule == null ? AppStrings.posDiscountAdd : AppStrings.posDiscountEdit}: ${line.product.name}',
      existing: line.discountRule,
      eligibleMinorUnits: line.grossMinorUnits,
      currency: lineCurrency,
      actorId: cubit.discountActorId,
      policyMaximumBasisPoints: cubit.discountPolicyMaximumBasisPoints,
    );
    if (!context.mounted || !result.confirmed) return;
    if (!cubit.setLineDiscountRule(line.product.id, result.rule)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.posDiscountInvalid)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      children: [
        DropdownButtonFormField<CurrencyCode>(
          initialValue: currency,
          decoration: InputDecoration(
            labelText: AppStrings.posCheckoutCurrencyLabel,
          ),
          items: availableCurrencies
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text('${item.nameAr} (${item.code})'),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value != null) onCurrencyChanged(value);
          },
        ),
        const SizedBox(height: SpacingTokens.sm),
        QaydTextField(
          controller: inputController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          label: AppStrings.posCheckoutInputHint,
          prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
          suffixIcon: IconButton(
            tooltip: AppStrings.posCheckoutClearCart,
            icon: const Icon(Icons.backspace_outlined),
            onPressed: inputController.clear,
          ),
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
        ),
        const SizedBox(height: SpacingTokens.sm),
        Row(
          children: [
            const Icon(Icons.camera_alt_outlined, size: 18),
            const SizedBox(width: SpacingTokens.xs),
            Expanded(
              child: Text(
                scannerError ?? AppStrings.posCheckoutCameraActive,
                style: scannerError == null
                    ? null
                    : TextStyle(color: Theme.of(context).colorScheme.error),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: AppStrings.posCheckoutCameraActive,
              icon: Icon(
                isBackCamera
                    ? Icons.camera_rear_outlined
                    : Icons.camera_front_outlined,
              ),
              onPressed: onToggleCamera,
            ),
          ],
        ),
        if (state.failure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: Text(
              state.failure!.messageAr,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (state.searchResults.isNotEmpty) ...[
          Text(
            AppStrings.posCheckoutSearchResults,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: SpacingTokens.xs),
          ...state.searchResults.map(
            (product) => Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(product.name),
                subtitle: Text(
                  '${product.sku} · ${formatPosMoney(product.salePrice)}',
                ),
                trailing: const Icon(Icons.add_circle_outline),
                onTap: () => onAddProduct(product),
              ),
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
        ],
        _CheckoutCartSection(
          state: state,
          currency: currency,
          onAddProduct: onAddProduct,
          onSetQuantity: onSetQuantity,
          onRemoveProduct: onRemoveProduct,
          onClearCart: onClearCart,
          onEditCartDiscount: () => _editCartDiscount(context),
          onEditLineDiscount: (line) => _editLineDiscount(context, line),
        ),
        const SizedBox(height: SpacingTokens.lg),
        _CheckoutPaymentPanel(
          state: state,
          currency: currency,
          advanceController: advanceController,
          paymentMethod: paymentMethod,
          onPaymentMethodChanged: onPaymentMethodChanged,
          customerController: customerController,
          creditTermsController: creditTermsController,
          creditDueDate: creditDueDate,
          onCreditDueDateChanged: onCreditDueDateChanged,
          paymentAccountController: paymentAccountController,
          onPickCustomer: onPickCustomer,
          onPickPaymentAccount: onPickPaymentAccount,
          onComplete: onComplete,
        ),
      ],
    );
  }
}

class _CheckoutCartSection extends StatelessWidget {
  const _CheckoutCartSection({
    required this.state,
    required this.currency,
    required this.onAddProduct,
    required this.onSetQuantity,
    required this.onRemoveProduct,
    required this.onClearCart,
    required this.onEditCartDiscount,
    required this.onEditLineDiscount,
  });

  final PosCheckoutState state;
  final CurrencyCode currency;
  final ValueChanged<PosProduct> onAddProduct;
  final void Function(String, PosQuantity) onSetQuantity;
  final ValueChanged<String> onRemoveProduct;
  final VoidCallback onClearCart;
  final VoidCallback onEditCartDiscount;
  final ValueChanged<PosCheckoutLineState> onEditLineDiscount;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text(
            AppStrings.posCheckoutTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          IconButton(
            tooltip: state.cartDiscountRule == null
                ? AppStrings.posDiscountAdd
                : AppStrings.posDiscountEdit,
            onPressed:
                state.lines.isEmpty ||
                    state.lines.any((line) => line.unitPrice == null)
                ? null
                : onEditCartDiscount,
            icon: const Icon(Icons.discount_outlined),
          ),
          TextButton(
            onPressed: state.lines.isEmpty ? null : onClearCart,
            child: Text(AppStrings.posCheckoutClearCart),
          ),
        ],
      ),
      const SizedBox(height: SpacingTokens.sm),
      if (state.lines.isEmpty)
        SizedBox(
          height: 180,
          child: QaydEmptyState(
            icon: Icons.shopping_cart_outlined,
            title: AppStrings.posCheckoutCartEmpty,
          ),
        )
      else
        ...state.lines.map(
          (line) => _CheckoutLineTile(
            line: line,
            currency: currency,
            onEditDiscount: () => onEditLineDiscount(line),
            onIncrement: () => onAddProduct(line.product),
            onDecrement: () {
              final step = PosMoneyMath.scaleFactor(line.quantity.scale);
              final next = line.quantity.scaledUnits - step;
              onSetQuantity(
                line.product.id,
                PosQuantity.fromScaled(
                  next < 0 ? 0 : next,
                  scale: line.quantity.scale,
                ),
              );
            },
            onRemove: () => onRemoveProduct(line.product.id),
          ),
        ),
    ],
  );
}

class _CheckoutPaymentPanel extends StatelessWidget {
  const _CheckoutPaymentPanel({
    required this.state,
    required this.currency,
    required this.advanceController,
    required this.paymentMethod,
    required this.onPaymentMethodChanged,
    required this.customerController,
    required this.creditTermsController,
    required this.creditDueDate,
    required this.onCreditDueDateChanged,
    required this.paymentAccountController,
    required this.onPickCustomer,
    required this.onPickPaymentAccount,
    required this.onComplete,
  });

  final PosCheckoutState state;
  final CurrencyCode currency;
  final TextEditingController advanceController;
  final PosPaymentMethod paymentMethod;
  final ValueChanged<PosPaymentMethod> onPaymentMethodChanged;
  final TextEditingController customerController;
  final TextEditingController creditTermsController;
  final DateTime? creditDueDate;
  final ValueChanged<DateTime?> onCreditDueDateChanged;
  final TextEditingController paymentAccountController;
  final VoidCallback onPickCustomer;
  final VoidCallback onPickPaymentAccount;
  final VoidCallback onComplete;

  Future<void> _pickCreditDueDate(BuildContext context) async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: creditDueDate ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null) {
      onCreditDueDateChanged(
        DateTime(selected.year, selected.month, selected.day),
      );
    }
  }

  String _dateLabel(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Widget _creditTermsFields(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: advanceController,
    builder: (context, advanceValue, _) {
      final advance = int.tryParse(advanceValue.text.trim()) ?? 0;
      if (state.totalMinorUnits - advance <= 0) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: SpacingTokens.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _pickCreditDueDate(context),
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      '${AppStrings.posCreditInvoiceDueDate}: '
                      '${creditDueDate == null ? AppStrings.posCreditInvoiceUnspecified : _dateLabel(creditDueDate!)}',
                    ),
                  ),
                ),
                if (creditDueDate != null)
                  IconButton(
                    tooltip: AppStrings.posCreditInvoiceUnspecified,
                    onPressed: () => onCreditDueDateChanged(null),
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
            QaydTextField(
              controller: creditTermsController,
              label: AppStrings.posCreditInvoiceTerms,
              helperText: AppStrings.posCreditInvoiceTermsOptionalHelp,
              maxLength: 240,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(AppStrings.posCheckoutSubtotal),
            trailing: Text(
              formatPosMinor(state.subtotalMinorUnits, currency),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (state.totalDiscountMinorUnits > 0)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppStrings.posCheckoutDiscountTotal),
              trailing: Text(
                '−${formatPosMinor(state.totalDiscountMinorUnits, currency)}',
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(AppStrings.posCheckoutFinalTotal),
            trailing: Text(
              formatPosMinor(state.totalMinorUnits, currency),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          QaydNumericField(
            controller: advanceController,
            label: AppStrings.posCheckoutAdvance,
          ),
          const SizedBox(height: SpacingTokens.sm),
          DropdownButtonFormField<PosPaymentMethod>(
            initialValue: paymentMethod,
            decoration: InputDecoration(
              labelText: AppStrings.posCheckoutPaymentMethod,
            ),
            items: [
              DropdownMenuItem(
                value: PosPaymentMethod.cash,
                child: Text(AppStrings.posCheckoutCash),
              ),
              DropdownMenuItem(
                value: PosPaymentMethod.bank,
                child: Text(AppStrings.posCheckoutBank),
              ),
              DropdownMenuItem(
                value: PosPaymentMethod.credit,
                child: Text(AppStrings.posCheckoutCredit),
              ),
              DropdownMenuItem(
                value: PosPaymentMethod.other,
                child: Text(AppStrings.posCheckoutOther),
              ),
            ],
            onChanged: (value) {
              if (value != null) onPaymentMethodChanged(value);
            },
          ),
          const SizedBox(height: SpacingTokens.sm),
          QaydTextField(
            controller: paymentAccountController,
            readOnly: true,
            onTap: onPickPaymentAccount,
            label: AppStrings.posCheckoutPaymentAccount,
            suffixIcon: const Icon(Icons.account_balance_outlined),
          ),
          const SizedBox(height: SpacingTokens.sm),
          QaydTextField(
            controller: customerController,
            readOnly: true,
            onTap: onPickCustomer,
            label: AppStrings.posCheckoutCustomerAccount,
            suffixIcon: const Icon(Icons.person_outline_rounded),
          ),
          _creditTermsFields(context),
          const SizedBox(height: SpacingTokens.md),
          FilledButton.icon(
            onPressed:
                state.lines.isEmpty ||
                    state.isBusy ||
                    !state.hasValidDiscounts ||
                    state.lines.any((line) => line.unitPrice == null)
                ? null
                : onComplete,
            icon: const Icon(Icons.verified_outlined),
            label: Text(AppStrings.posCheckoutComplete),
          ),
        ],
      ),
    ),
  );
}

class _CheckoutLineTile extends StatelessWidget {
  const _CheckoutLineTile({
    required this.line,
    required this.currency,
    required this.onEditDiscount,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final PosCheckoutLineState line;
  final CurrencyCode currency;
  final VoidCallback onEditDiscount;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(line.product.name),
              subtitle: Text(
                line.unitPrice == null
                    ? AppStrings.posCheckoutPriceRequired
                    : <String>[
                        '${line.quantity.toExactString()} × ${formatPosMoney(line.unitPrice!)} = ${formatPosMinor(line.grossMinorUnits, currency)}',
                        if (line.discountMinorUnits > 0)
                          '${AppStrings.posCheckoutDiscountTotal}: −${formatPosMinor(line.discountMinorUnits, currency)}',
                        if (line.discountRule != null)
                          '${AppStrings.posDiscountReason}: ${line.discountRule!.reason}',
                        '${AppStrings.posCheckoutFinalTotal}: ${formatPosMinor(line.totalMinorUnits, currency)}',
                        if (!line.hasValidDiscount)
                          AppStrings.posDiscountInvalid,
                      ].join('\n'),
              ),
              leading: IconButton(
                tooltip: AppStrings.posCheckoutClearCart,
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onDecrement,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(line.quantity.toExactString()),
                  IconButton(
                    onPressed: onIncrement,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: line.unitPrice == null ? null : onEditDiscount,
                icon: const Icon(Icons.discount_outlined),
                label: Text(
                  line.discountRule == null
                      ? AppStrings.posDiscountAdd
                      : AppStrings.posDiscountEdit,
                ),
              ),
            ),
            if (line.product.currency != currency)
              Padding(
                padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
                child: Text(
                  '${AppStrings.posCheckoutCatalogReference}: '
                  '${formatPosMoney(line.product.salePrice)}',
                ),
              ),
            if (line.rateSnapshot != null)
              Text(
                '${AppStrings.posCheckoutRateSnapshotLabel}: '
                '${_formatStoredRate(line.rateSnapshot!)}'
                '${line.rateSnapshot!.isInverted ? ' · ${AppStrings.posCheckoutRateReverseApplied}' : ''}\n'
                '${line.rateSnapshot!.recordedAt.toLocal()}',
              ),
          ],
        ),
      ),
    );
  }
}

String _formatStoredRate(PosCurrencyRateQuote quote) {
  final scaled = BigInt.from(quote.storedRateScaled);
  final whole = scaled ~/ BigInt.from(100000000);
  final fraction = (scaled % BigInt.from(100000000)).toString().padLeft(8, '0');
  return '1 ${quote.storedFromCurrency.code} = '
      '$whole.$fraction ${quote.storedToCurrency.code}';
}

typedef _DiscountDialogResult = ({bool confirmed, PosDiscountRule? rule});

Future<_DiscountDialogResult> _showDiscountRuleDialog({
  required BuildContext context,
  required String title,
  required PosDiscountRule? existing,
  required int eligibleMinorUnits,
  required CurrencyCode currency,
  required String actorId,
  required int policyMaximumBasisPoints,
}) async {
  var method = existing?.method ?? PosDiscountMethod.fixedAmount;
  final amountController = TextEditingController(
    text: existing == null
        ? ''
        : existing.method == PosDiscountMethod.fixedAmount
        ? _formatMinorUnitsInput(existing.value, currency)
        : _formatBasisPoints(existing.value),
  );
  final reasonController = TextEditingController(text: existing?.reason ?? '');
  String? error;
  final result = await showDialog<_DiscountDialogResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${AppStrings.posDiscountEligibleAmount}: '
                '${formatPosMinor(eligibleMinorUnits, currency)}',
              ),
              const SizedBox(height: SpacingTokens.sm),
              DropdownButtonFormField<PosDiscountMethod>(
                initialValue: method,
                decoration: InputDecoration(
                  labelText: AppStrings.posDiscountMethod,
                ),
                items: [
                  DropdownMenuItem(
                    value: PosDiscountMethod.fixedAmount,
                    child: Text(AppStrings.posDiscountFixed),
                  ),
                  DropdownMenuItem(
                    value: PosDiscountMethod.percentage,
                    child: Text(AppStrings.posDiscountPercent),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() {
                    method = value;
                    amountController.clear();
                    error = null;
                  });
                },
              ),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: false,
                ),
                decoration: InputDecoration(
                  labelText: method == PosDiscountMethod.fixedAmount
                      ? '${AppStrings.posDiscountAmount} (${currency.code})'
                      : AppStrings.posDiscountPercentLimit(
                          _formatBasisPoints(policyMaximumBasisPoints),
                        ),
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              TextField(
                controller: reasonController,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: AppStrings.posDiscountReason,
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop((confirmed: false, rule: null)),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop((confirmed: true, rule: null)),
              child: Text(AppStrings.posDiscountRemove),
            ),
          FilledButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                setDialogState(
                  () => error = AppStrings.posDiscountReasonRequired,
                );
                return;
              }
              try {
                final PosDiscountRule rule;
                if (method == PosDiscountMethod.fixedAmount) {
                  final minorUnits = _parseCurrencyToMinor(
                    amountController.text,
                    currency.fractionalDigits,
                  );
                  if (minorUnits == null) throw const FormatException();
                  rule = PosDiscountRule.fixed(
                    amount: Money.fromMinorUnits(minorUnits, currency),
                    reason: reason,
                    actorId: actorId,
                    policyMaximumBasisPoints: policyMaximumBasisPoints,
                  );
                } else {
                  final basisPoints = _parsePercentageBasisPoints(
                    amountController.text,
                  );
                  if (basisPoints == null) throw const FormatException();
                  rule = PosDiscountRule.percentage(
                    basisPoints: basisPoints,
                    reason: reason,
                    actorId: actorId,
                    policyMaximumBasisPoints: policyMaximumBasisPoints,
                  );
                }
                rule.amountFor(
                  Money.fromMinorUnits(eligibleMinorUnits, currency),
                );
                Navigator.of(dialogContext).pop((confirmed: true, rule: rule));
              } on Exception {
                setDialogState(() => error = AppStrings.posDiscountInvalid);
              }
            },
            child: Text(
              existing == null
                  ? AppStrings.posDiscountAdd
                  : AppStrings.posDiscountEdit,
            ),
          ),
        ],
      ),
    ),
  );
  amountController.dispose();
  reasonController.dispose();
  return result ?? (confirmed: false, rule: null);
}

int? _parseCurrencyToMinor(String raw, int fractionalDigits) {
  final normalized = raw.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final fraction = parts.length == 1 ? '' : parts[1];
  if (fraction.length > fractionalDigits) return null;
  final whole = BigInt.tryParse(parts[0]);
  if (whole == null) return null;
  final scale = BigInt.from(PosMoneyMath.scaleFactor(fractionalDigits));
  final fractionValue = fraction.isEmpty
      ? BigInt.zero
      : BigInt.parse(fraction.padRight(fractionalDigits, '0'));
  final minorUnits = whole * scale + fractionValue;
  if (minorUnits > BigInt.parse('7fffffffffffffff', radix: 16)) return null;
  return minorUnits.toInt();
}

int? _parsePercentageBasisPoints(String raw) {
  final normalized = raw.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,3}(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final whole = int.tryParse(parts[0]);
  if (whole == null || whole > 100) return null;
  final fraction = parts.length == 1 ? '' : parts[1];
  final basisPoints =
      whole * 100 +
      (fraction.isEmpty ? 0 : int.parse(fraction.padRight(2, '0')));
  if (basisPoints <= 0 || basisPoints > PosDiscountRule.maximumBasisPoints) {
    return null;
  }
  return basisPoints;
}

String _formatBasisPoints(int basisPoints) =>
    '${basisPoints ~/ 100}.${(basisPoints % 100).toString().padLeft(2, '0')}';

String _formatMinorUnitsInput(int minorUnits, CurrencyCode currency) {
  final digits = currency.fractionalDigits;
  if (digits == 0) return '$minorUnits';
  final scale = PosMoneyMath.scaleFactor(digits);
  final whole = minorUnits ~/ scale;
  final fraction = (minorUnits % scale).toString().padLeft(digits, '0');
  return '$whole.$fraction';
}
