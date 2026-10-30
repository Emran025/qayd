import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/application/pos/create_pos_product_use_case.dart';
import 'package:qayd/application/pos/deactivate_pos_product_use_case.dart';
import 'package:qayd/application/pos/reactivate_pos_product_use_case.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/application/pos/save_pos_product_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_product.dart';

/// Stable UI states for POS catalog operations.
enum PosCatalogStatus { initial, loading, ready, saving, failure }

final class PosCatalogState {
  const PosCatalogState({
    this.status = PosCatalogStatus.initial,
    this.products = const <PosProduct>[],
    this.search,
    this.includeInactive = false,
    this.failure,
  });

  final PosCatalogStatus status;
  final List<PosProduct> products;
  final String? search;
  final bool includeInactive;
  final Failure? failure;

  bool get isBusy =>
      status == PosCatalogStatus.loading || status == PosCatalogStatus.saving;

  PosCatalogState copyWith({
    PosCatalogStatus? status,
    List<PosProduct>? products,
    String? search,
    bool? includeInactive,
    Failure? failure,
    bool clearFailure = false,
    bool clearSearch = false,
  }) {
    return PosCatalogState(
      status: status ?? this.status,
      products: products ?? this.products,
      search: clearSearch ? null : search ?? this.search,
      failure: clearFailure ? null : failure ?? this.failure,
      includeInactive: includeInactive ?? this.includeInactive,
    );
  }
}

/// Presentation coordinator for product catalog reads and writes.
final class PosCatalogCubit extends Cubit<PosCatalogState> {
  PosCatalogCubit({
    required ListPosProductsUseCase listUseCase,
    required SavePosProductUseCase saveUseCase,
    required CreatePosProductUseCase createUseCase,
    required DeactivatePosProductUseCase deactivateUseCase,
    ReactivatePosProductUseCase? reactivateUseCase,
  })  : _listUseCase = listUseCase,
        _saveUseCase = saveUseCase,
        _createUseCase = createUseCase,
        _deactivateUseCase = deactivateUseCase,
        _reactivateUseCase = reactivateUseCase,
        super(const PosCatalogState());

  final ListPosProductsUseCase _listUseCase;
  final SavePosProductUseCase _saveUseCase;
  final CreatePosProductUseCase _createUseCase;
  final DeactivatePosProductUseCase _deactivateUseCase;
  final ReactivatePosProductUseCase? _reactivateUseCase;

  Future<void> load({String? search, bool? includeInactive}) async {
    if (isClosed || state.status == PosCatalogStatus.saving) return;
    await _load(search: search, includeInactive: includeInactive);
  }

  Future<void> _load({String? search, bool? includeInactive}) async {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: PosCatalogStatus.loading,
        search: search,
        includeInactive: includeInactive,
        clearSearch: search == null,
        clearFailure: true,
      ),
    );

    final result = await _listUseCase(
      activeOnly: !(includeInactive ?? state.includeInactive),
      search: search,
    );
    if (isClosed) return;
    result.fold(
      (failure) => emit(
        state.copyWith(
          status: PosCatalogStatus.failure,
          failure: failure,
        ),
      ),
      (products) => emit(
        state.copyWith(
          status: PosCatalogStatus.ready,
          products: List.unmodifiable(products),
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> create(CreatePosProductInput input) async {
    if (isClosed || state.isBusy) return;
    emit(
      state.copyWith(
        status: PosCatalogStatus.saving,
        clearFailure: true,
      ),
    );

    final result = await _createUseCase(input);
    if (isClosed) return;
    if (result.isFailure) {
      emit(
        state.copyWith(
          status: PosCatalogStatus.failure,
          failure: result.failureOrNull,
        ),
      );
      return;
    }
    await _load(search: state.search);
  }

  Future<void> save(PosProduct product) async {
    if (isClosed || state.isBusy) return;
    emit(
      state.copyWith(
        status: PosCatalogStatus.saving,
        clearFailure: true,
      ),
    );

    final result = await _saveUseCase(product);
    if (isClosed) return;
    if (result.isFailure) {
      emit(
        state.copyWith(
          status: PosCatalogStatus.failure,
          failure: result.failureOrNull,
        ),
      );
      return;
    }
    await _load(search: state.search);
  }

  Future<void> deactivate(String productId) async {
    if (isClosed || state.isBusy) return;
    emit(
      state.copyWith(
        status: PosCatalogStatus.saving,
        clearFailure: true,
      ),
    );

    final result = await _deactivateUseCase(productId);
    if (isClosed) return;
    if (result.isFailure) {
      emit(
        state.copyWith(
          status: PosCatalogStatus.failure,
          failure: result.failureOrNull,
        ),
      );
      return;
    }
    await _load(search: state.search);
  }

  Future<void> reactivate(String productId) async {
    if (isClosed || state.isBusy || _reactivateUseCase == null) return;
    emit(state.copyWith(status: PosCatalogStatus.saving, clearFailure: true));
    final result = await _reactivateUseCase!(productId);
    if (isClosed) return;
    if (result.isFailure) {
      emit(state.copyWith(
        status: PosCatalogStatus.failure,
        failure: result.failureOrNull,
      ));
      return;
    }
    await _load(search: state.search, includeInactive: state.includeInactive);
  }
}
