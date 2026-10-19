import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/application/pos/build_pos_sale_posting_use_case.dart';
import 'package:qayd/application/pos/complete_pos_sale_use_case.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/application/pos/resolve_pos_product_for_checkout_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
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
  const PosCheckoutLineState({required this.product, required this.quantity});

  final PosProduct product;
  final PosQuantity quantity;

  int get totalMinorUnits =>
      PosMoneyMath.multiply(quantity, product.salePrice).minorUnits;

  PosCheckoutLineState withQuantity(PosQuantity value) =>
      PosCheckoutLineState(product: product, quantity: value);
}

final class PosCheckoutState {
  const PosCheckoutState({
    this.status = PosCheckoutStatus.initial,
    this.lines = const <PosCheckoutLineState>[],
    this.searchResults = const <PosProduct>[],
    this.searchQuery,
    this.failure,
    this.completedInvoice,
  });

  final PosCheckoutStatus status;
  final List<PosCheckoutLineState> lines;
  final List<PosProduct> searchResults;
  final String? searchQuery;
  final Failure? failure;
  final PosInvoice? completedInvoice;

  int get subtotalMinorUnits => lines.fold<int>(
        0,
        (sum, line) => sum + line.totalMinorUnits,
      );

  bool get isBusy =>
      status == PosCheckoutStatus.loading ||
      status == PosCheckoutStatus.resolving ||
      status == PosCheckoutStatus.completing;

  PosCheckoutState copyWith({
    PosCheckoutStatus? status,
    List<PosCheckoutLineState>? lines,
    List<PosProduct>? searchResults,
    String? searchQuery,
    Failure? failure,
    bool clearFailure = false,
    bool clearSearch = false,
    PosInvoice? completedInvoice,
  }) {
    return PosCheckoutState(
      status: status ?? this.status,
      lines: lines ?? this.lines,
      searchResults: searchResults ?? this.searchResults,
      searchQuery: clearSearch ? null : searchQuery ?? this.searchQuery,
      failure: clearFailure ? null : failure ?? this.failure,
      completedInvoice: completedInvoice ?? this.completedInvoice,
    );
  }
}

/// Presentation coordinator for keyboard/camera/search checkout input.
final class PosCheckoutCubit extends Cubit<PosCheckoutState> {
  PosCheckoutCubit({
    required ResolvePosProductForCheckoutUseCase resolveProduct,
    required ListPosProductsUseCase listProducts,
    this.completeSale,
    this.idGenerator,
  })  : _resolveProduct = resolveProduct,
        _listProducts = listProducts,
        super(const PosCheckoutState());

  final ResolvePosProductForCheckoutUseCase _resolveProduct;
  final ListPosProductsUseCase _listProducts;
  final CompletePosSaleUseCase? completeSale;
  final IdGenerator? idGenerator;
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
    if (isClosed || state.isBusy || state.lines.isEmpty) return;
    final action = completeSale;
    if (action == null) {
      emit(state.copyWith(status: PosCheckoutStatus.failure));
      return;
    }
    emit(state.copyWith(
        status: PosCheckoutStatus.completing, clearFailure: true));
    final id = _pendingInvoiceId ??
        (idGenerator?.next() ??
            'pos-${DateTime.now().toUtc().microsecondsSinceEpoch}');
    final invoiceNumber = _pendingInvoiceNumber ??
        'POS-${DateTime.now().toUtc().millisecondsSinceEpoch}';
    final idempotencyKey = _pendingIdempotencyKey ?? 'pos-sale:$id';
    _pendingInvoiceId = id;
    _pendingInvoiceNumber = invoiceNumber;
    _pendingIdempotencyKey = idempotencyKey;
    final result = await action(
      invoiceId: id,
      invoiceNumber: invoiceNumber,
      warehouseId: warehouseId,
      currency: currency,
      lines: state.lines
          .map((line) => BuildPosSaleLineInput(
                productId: line.product.id,
                quantity: line.quantity,
              ))
          .toList(growable: false),
      idempotencyKey: idempotencyKey,
      invoiceDate: DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
      customerAccountId: customerAccountId,
      settlement: PosSaleSettlementInput(
        advanceMinorUnits: advanceMinorUnits,
        paymentMethod: paymentMethod,
        paymentAccountId: paymentAccountId,
      ),
    );
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(
        status: PosCheckoutStatus.failure,
        failure: failure,
      )),
      (invoice) => emit(state.copyWith(
        status: PosCheckoutStatus.completed,
        lines: const [],
        completedInvoice: invoice,
        clearFailure: true,
        clearSearch: true,
      )),
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
    emit(state.copyWith(
        status: PosCheckoutStatus.resolving, clearFailure: true));
    final result = await _resolveProduct(rawQuery);
    if (isClosed) return;
    result.fold(
      (failure) => emit(
        state.copyWith(status: PosCheckoutStatus.failure, failure: failure),
      ),
      (product) => addProduct(product),
    );
  }

  void addProduct(PosProduct product, {int units = 1}) {
    if (units <= 0) return;
    _clearPendingSale();
    final quantity = PosQuantity.fromScaled(
      PosMoneyMath.scaleFactor(product.quantityScale) * units,
      scale: product.quantityScale,
    );

    final index =
        state.lines.indexWhere((line) => line.product.id == product.id);
    final next = [...state.lines];
    if (index < 0) {
      next.add(PosCheckoutLineState(product: product, quantity: quantity));
    } else {
      final existing = next[index];
      next[index] = existing.withQuantity(existing.quantity + quantity);
    }
    emit(
      state.copyWith(
        status: PosCheckoutStatus.ready,
        lines: List.unmodifiable(next),
        searchResults: const [],
        clearSearch: true,
        clearFailure: true,
      ),
    );
  }

  void setQuantity(String productId, PosQuantity quantity) {
    _clearPendingSale();
    if (quantity.isZero) {
      removeProduct(productId);
      return;
    }
    final index =
        state.lines.indexWhere((line) => line.product.id == productId);
    if (index < 0 || state.lines[index].quantity.scale != quantity.scale) {
      return;
    }
    final next = [...state.lines];
    next[index] = next[index].withQuantity(quantity);
    emit(state.copyWith(lines: List.unmodifiable(next)));
  }

  void removeProduct(String productId) {
    _clearPendingSale();
    emit(
      state.copyWith(
        lines: List.unmodifiable(
          state.lines.where((line) => line.product.id != productId),
        ),
      ),
    );
  }

  void clearCart() {
    _clearPendingSale();
    emit(
      state.copyWith(
        lines: const [],
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
