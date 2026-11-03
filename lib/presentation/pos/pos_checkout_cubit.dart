import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/application/pos/build_pos_sale_posting_use_case.dart';
import 'package:qayd/application/pos/complete_pos_sale_use_case.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/application/pos/resolve_pos_product_for_checkout_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/entities/pos_discount_rule.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/services/pos_currency_converter.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

/// UI state for the fast POS checkout surface.
enum PosCheckoutStatus {
  initial,
  loading,
  ready,
  resolving,
  completing,
  completed,
  failure,
}

final class PosCheckoutLineState {
  const PosCheckoutLineState({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.rateSnapshot,
    this.discountRule,
  });

  final PosProduct product;
  final PosQuantity quantity;
  final Money? unitPrice;
  final PosCurrencyRateQuote? rateSnapshot;
  final PosDiscountRule? discountRule;

  int get grossMinorUnits => unitPrice == null
      ? 0
      : PosMoneyMath.multiply(quantity, unitPrice!).minorUnits;

  int get discountMinorUnits {
    final price = unitPrice;
    final rule = discountRule;
    if (price == null || rule == null) return 0;
    try {
      return rule
          .amountFor(Money.fromMinorUnits(grossMinorUnits, price.currency))
          .minorUnits;
    } on Exception {
      return 0;
    }
  }

  bool get hasValidDiscount {
    final price = unitPrice;
    final rule = discountRule;
    if (price == null || rule == null) return true;
    try {
      rule.amountFor(Money.fromMinorUnits(grossMinorUnits, price.currency));
      return true;
    } on Exception {
      return false;
    }
  }

  int get totalMinorUnits => grossMinorUnits - discountMinorUnits;

  PosCheckoutLineState withQuantity(PosQuantity value) => PosCheckoutLineState(
    product: product,
    quantity: value,
    unitPrice: unitPrice,
    rateSnapshot: rateSnapshot,
    discountRule: discountRule,
  );

  PosCheckoutLineState withConversion(
    Money? value,
    PosCurrencyRateQuote? quote,
  ) => PosCheckoutLineState(
    product: product,
    quantity: quantity,
    unitPrice: value,
    rateSnapshot: quote,
    discountRule: discountRule,
  );

  PosCheckoutLineState withDiscountRule(PosDiscountRule? value) =>
      PosCheckoutLineState(
        product: product,
        quantity: quantity,
        unitPrice: unitPrice,
        rateSnapshot: rateSnapshot,
        discountRule: value,
      );
}

final class PosCheckoutState {
  const PosCheckoutState({
    this.status = PosCheckoutStatus.initial,
    this.currency,
    this.lines = const <PosCheckoutLineState>[],
    this.searchResults = const <PosProduct>[],
    this.searchQuery,
    this.failure,
    this.completedInvoice,
    this.cartDiscountRule,
  });

  final PosCheckoutStatus status;
  final CurrencyCode? currency;
  final List<PosCheckoutLineState> lines;
  final List<PosProduct> searchResults;
  final String? searchQuery;
  final Failure? failure;
  final PosInvoice? completedInvoice;
  final PosDiscountRule? cartDiscountRule;

  int get subtotalMinorUnits =>
      lines.fold<int>(0, (sum, line) => sum + line.grossMinorUnits);

  int get lineDiscountMinorUnits =>
      lines.fold<int>(0, (sum, line) => sum + line.discountMinorUnits);

  int get cartDiscountMinorUnits {
    final rule = cartDiscountRule;
    final selectedCurrency = currency;
    if (rule == null || selectedCurrency == null) return 0;
    try {
      return rule
          .amountFor(
            Money.fromMinorUnits(
              subtotalMinorUnits - lineDiscountMinorUnits,
              selectedCurrency,
            ),
          )
          .minorUnits;
    } on Exception {
      return 0;
    }
  }

  int get totalDiscountMinorUnits =>
      lineDiscountMinorUnits + cartDiscountMinorUnits;

  int get totalMinorUnits => subtotalMinorUnits - totalDiscountMinorUnits;

  bool get hasValidDiscounts {
    if (!lines.every((line) => line.hasValidDiscount)) return false;
    final rule = cartDiscountRule;
    if (rule == null) return true;
    final selectedCurrency = currency;
    if (selectedCurrency == null) return false;
    try {
      rule.amountFor(
        Money.fromMinorUnits(
          subtotalMinorUnits - lineDiscountMinorUnits,
          selectedCurrency,
        ),
      );
      return true;
    } on Exception {
      return false;
    }
  }

  bool get isBusy =>
      status == PosCheckoutStatus.loading ||
      status == PosCheckoutStatus.resolving ||
      status == PosCheckoutStatus.completing;

  PosCheckoutState copyWith({
    PosCheckoutStatus? status,
    CurrencyCode? currency,
    List<PosCheckoutLineState>? lines,
    List<PosProduct>? searchResults,
    String? searchQuery,
    Failure? failure,
    bool clearFailure = false,
    bool clearSearch = false,
    PosInvoice? completedInvoice,
    PosDiscountRule? cartDiscountRule,
    bool clearCartDiscount = false,
  }) {
    return PosCheckoutState(
      status: status ?? this.status,
      currency: currency ?? this.currency,
      lines: lines ?? this.lines,
      searchResults: searchResults ?? this.searchResults,
      searchQuery: clearSearch ? null : searchQuery ?? this.searchQuery,
      failure: clearFailure ? null : failure ?? this.failure,
      completedInvoice: completedInvoice ?? this.completedInvoice,
      cartDiscountRule: clearCartDiscount
          ? null
          : cartDiscountRule ?? this.cartDiscountRule,
    );
  }
}

/// Presentation coordinator for keyboard/camera/search checkout input.
final class PosCheckoutCubit extends Cubit<PosCheckoutState> {
  PosCheckoutCubit({
    required ResolvePosProductForCheckoutUseCase resolveProduct,
    required ListPosProductsUseCase listProducts,
    this.currencyConverter,
    this.completeSale,
    this.idGenerator,
    this.discountActorId = 'device:unknown',
    this.discountPolicyMaximumBasisPoints = PosDiscountRule.maximumBasisPoints,
  }) : _resolveProduct = resolveProduct,
       _listProducts = listProducts,
       super(const PosCheckoutState());

  final ResolvePosProductForCheckoutUseCase _resolveProduct;
  final ListPosProductsUseCase _listProducts;
  final PosCurrencyConverter? currencyConverter;
  final CompletePosSaleUseCase? completeSale;
  final IdGenerator? idGenerator;
  final String discountActorId;
  final int discountPolicyMaximumBasisPoints;
  String? _pendingInvoiceId;
  String? _pendingInvoiceNumber;
  String? _pendingIdempotencyKey;

  Future<void> completeCheckout({
    required String warehouseId,
    required CurrencyCode currency,
    required int advanceMinorUnits,
    required PosPaymentMethod paymentMethod,
    AccountId? customerAccountId,
    AccountId? paymentAccountId,
  }) async {
    if (isClosed ||
        state.isBusy ||
        state.lines.isEmpty ||
        !state.hasValidDiscounts ||
        state.lines.any((line) => line.unitPrice == null)) {
      return;
    }
    final action = completeSale;
    if (action == null) {
      emit(state.copyWith(status: PosCheckoutStatus.failure));
      return;
    }
    emit(
      state.copyWith(status: PosCheckoutStatus.completing, clearFailure: true),
    );
    final id =
        _pendingInvoiceId ??
        (idGenerator?.next() ??
            'pos-${DateTime.now().toUtc().microsecondsSinceEpoch}');
    final invoiceNumber =
        _pendingInvoiceNumber ??
        'POS-${DateTime.now().toUtc().millisecondsSinceEpoch}';
    final idempotencyKey = _pendingIdempotencyKey ?? 'pos-sale:$id';
    final now = DateTime.now().toUtc();
    _pendingInvoiceId = id;
    _pendingInvoiceNumber = invoiceNumber;
    _pendingIdempotencyKey = idempotencyKey;
    final result = await action(
      invoiceId: id,
      invoiceNumber: invoiceNumber,
      warehouseId: warehouseId,
      currency: currency,
      lines: state.lines
          .map(
            (line) => BuildPosSaleLineInput(
              productId: line.product.id,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
              rateSnapshot: line.rateSnapshot,
              discountRule: line.discountRule,
            ),
          )
          .toList(growable: false),
      idempotencyKey: idempotencyKey,
      invoiceDate: now,
      createdAt: now,
      customerAccountId: customerAccountId,
      cartDiscountRule: state.cartDiscountRule,
      settlement: PosSaleSettlementInput(
        advanceMinorUnits: advanceMinorUnits,
        paymentMethod: paymentMethod,
        paymentAccountId: paymentAccountId,
      ),
    );
    if (isClosed) return;
    result.fold(
      (failure) => emit(
        state.copyWith(status: PosCheckoutStatus.failure, failure: failure),
      ),
      (invoice) => emit(
        state.copyWith(
          status: PosCheckoutStatus.completed,
          lines: const [],
          clearCartDiscount: true,
          completedInvoice: invoice,
          clearFailure: true,
          clearSearch: true,
        ),
      ),
    );
    if (state.status == PosCheckoutStatus.completed) {
      _clearPendingSale();
    }
  }

  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      emit(state.copyWith(searchResults: const [], clearSearch: true));
      return;
    }
    emit(
      state.copyWith(
        status: PosCheckoutStatus.loading,
        searchQuery: query,
        clearFailure: true,
      ),
    );
    final result = await _listProducts(activeOnly: true, search: query);
    if (isClosed) return;
    result.fold(
      (failure) => emit(
        state.copyWith(status: PosCheckoutStatus.failure, failure: failure),
      ),
      (products) => emit(
        state.copyWith(
          status: PosCheckoutStatus.ready,
          searchResults: List.unmodifiable(products),
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> resolveAndAdd(String rawQuery) async {
    if (isClosed || state.isBusy) return;
    emit(
      state.copyWith(status: PosCheckoutStatus.resolving, clearFailure: true),
    );
    final result = await _resolveProduct(rawQuery);
    if (isClosed) return;
    if (result.isFailure) {
      emit(
        state.copyWith(
          status: PosCheckoutStatus.failure,
          failure: result.failureOrNull,
        ),
      );
      return;
    }
    final product = result.valueOrNull;
    if (product != null) await addProduct(product);
  }

  Future<void> addProduct(PosProduct product, {int units = 1}) async {
    if (isClosed || units <= 0) return;
    _clearPendingSale();
    final quantity = PosQuantity.fromScaled(
      PosMoneyMath.scaleFactor(product.quantityScale) * units,
      scale: product.quantityScale,
    );
    final saleCurrency = state.currency ?? product.currency;
    final index = state.lines.indexWhere(
      (line) => line.product.id == product.id,
    );
    final next = [...state.lines];
    if (index >= 0) {
      final existing = next[index];
      next[index] = existing.withQuantity(existing.quantity + quantity);
      emit(
        state.copyWith(
          status: PosCheckoutStatus.ready,
          currency: saleCurrency,
          lines: List.unmodifiable(next),
          searchResults: const [],
          clearSearch: true,
          clearFailure: true,
        ),
      );
      return;
    }
    next.add(
      PosCheckoutLineState(
        product: product,
        quantity: quantity,
        unitPrice: null,
      ),
    );
    emit(
      state.copyWith(
        status: PosCheckoutStatus.resolving,
        currency: saleCurrency,
        lines: List.unmodifiable(next),
        searchResults: const [],
        clearSearch: true,
        clearFailure: true,
      ),
    );
    await _populateLinePrice(product.id, saleCurrency);
  }

  void setQuantity(String productId, PosQuantity quantity) {
    _clearPendingSale();
    if (quantity.isZero) {
      removeProduct(productId);
      return;
    }
    final index = state.lines.indexWhere(
      (line) => line.product.id == productId,
    );
    if (index < 0 || state.lines[index].quantity.scale != quantity.scale)
      return;
    final next = [...state.lines];
    next[index] = next[index].withQuantity(quantity);
    emit(state.copyWith(lines: List.unmodifiable(next)));
  }

  bool setLineDiscountRule(String productId, PosDiscountRule? rule) {
    final index = state.lines.indexWhere(
      (line) => line.product.id == productId,
    );
    if (index < 0) return false;
    final line = state.lines[index];
    if (rule != null) {
      final price = line.unitPrice;
      if (price == null) return false;
      try {
        rule.amountFor(
          Money.fromMinorUnits(line.grossMinorUnits, price.currency),
        );
      } on Exception {
        return false;
      }
    }
    _clearPendingSale();
    final next = [...state.lines];
    next[index] = line.withDiscountRule(rule);
    emit(state.copyWith(lines: List.unmodifiable(next), clearFailure: true));
    return true;
  }

  bool setCartDiscountRule(PosDiscountRule? rule) {
    if (rule != null) {
      final selectedCurrency = state.currency;
      if (selectedCurrency == null) return false;
      try {
        rule.amountFor(
          Money.fromMinorUnits(
            state.subtotalMinorUnits - state.lineDiscountMinorUnits,
            selectedCurrency,
          ),
        );
      } on Exception {
        return false;
      }
    }
    _clearPendingSale();
    emit(
      state.copyWith(
        cartDiscountRule: rule,
        clearCartDiscount: rule == null,
        clearFailure: true,
      ),
    );
    return true;
  }

  Future<void> setSaleCurrency(CurrencyCode currency) async {
    if (state.currency == currency) return;
    _clearPendingSale();
    final productIds = state.lines.map((line) => line.product.id).toList();
    emit(
      state.copyWith(
        currency: currency,
        status: productIds.isEmpty
            ? PosCheckoutStatus.ready
            : PosCheckoutStatus.resolving,
        lines: List.unmodifiable(
          state.lines.map((line) => line.withConversion(null, null)),
        ),
        clearFailure: true,
      ),
    );
    for (final productId in productIds) {
      await _populateLinePrice(productId, currency);
      if (state.status == PosCheckoutStatus.failure) return;
    }
  }

  Future<void> _populateLinePrice(
    String productId,
    CurrencyCode currency,
  ) async {
    final index = state.lines.indexWhere(
      (line) => line.product.id == productId,
    );
    if (index < 0 || state.currency != currency) return;
    final line = state.lines[index];
    Money? unitPrice;
    PosCurrencyRateQuote? quote;
    if (line.product.salePrice.currency == currency) {
      unitPrice = line.product.salePrice;
    } else {
      final converter = currencyConverter;
      if (converter == null) {
        emit(
          state.copyWith(
            status: PosCheckoutStatus.failure,
            failure: const ValidationFailure(
              messageAr: 'لا يتوفر محول العملة في نقطة البيع.',
              code: 'pos_currency_converter_unavailable',
            ),
          ),
        );
        return;
      }
      final result = await converter.convertWithSnapshot(
        line.product.salePrice,
        toCurrency: currency,
      );
      if (isClosed || state.currency != currency) return;
      if (result.isFailure) {
        emit(
          state.copyWith(
            status: PosCheckoutStatus.failure,
            failure: result.failureOrNull,
          ),
        );
        return;
      }
      final conversion = result.valueOrNull!;
      unitPrice = conversion.targetAmount;
      quote = conversion.rateSnapshot;
    }
    final currentIndex = state.lines.indexWhere(
      (item) => item.product.id == productId,
    );
    if (currentIndex < 0 || state.currency != currency) return;
    final next = [...state.lines];
    next[currentIndex] = next[currentIndex].withConversion(unitPrice, quote);
    final ready = next.every((item) => item.unitPrice != null);
    emit(
      state.copyWith(
        status: ready ? PosCheckoutStatus.ready : PosCheckoutStatus.resolving,
        lines: List.unmodifiable(next),
        clearFailure: true,
      ),
    );
  }

  void removeProduct(String productId) {
    _clearPendingSale();
    final remaining = state.lines
        .where((line) => line.product.id != productId)
        .toList();
    emit(
      state.copyWith(
        lines: List.unmodifiable(remaining),
        clearCartDiscount: remaining.isEmpty,
      ),
    );
  }

  void clearCart() {
    _clearPendingSale();
    emit(
      state.copyWith(
        lines: const [],
        clearCartDiscount: true,
        searchResults: const [],
        clearSearch: true,
        clearFailure: true,
        status: PosCheckoutStatus.ready,
      ),
    );
  }

  void _clearPendingSale() {
    _pendingInvoiceId = null;
    _pendingInvoiceNumber = null;
    _pendingIdempotencyKey = null;
  }
}
