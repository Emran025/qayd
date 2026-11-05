import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/application/accounts/dtos/list_accounts_input.dart';
import 'package:qayd/application/accounts/dtos/statement_chat_filter_input.dart';
import 'package:qayd/application/accounts/list_account_statement_chat_use_case.dart';
import 'package:qayd/application/accounts/list_accounts_use_case.dart';
import 'package:qayd/application/cost_centers/get_cost_center_details_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/application/sync/sync_coordinator_service.dart';
import 'package:qayd/domain/value_objects/standard_account_classification_kind.dart';
import 'package:qayd/presentation/pages/accounts/statement_chat_state.dart';

class StatementChatCubit extends Cubit<StatementChatState> {
  StatementChatCubit({
    required ListAccountStatementChatUseCase listStatement,
    required ListAccountsUseCase listAccounts,
    required GetCostCenterDetailsUseCase getCostCenterDetails,
    required String counterpartyAccountId,
    required SyncCoordinatorService syncCoordinatorService,
    StatementChatFilterInput? initialFilter,
    String? initialCounterpartyName,
    String? myAccountId,
  })  : _listStatement = listStatement,
        _listAccounts = listAccounts,
        _getCostCenterDetails = getCostCenterDetails,
        _counterpartyAccountId = counterpartyAccountId,
        _syncCoordinatorService = syncCoordinatorService,
        _initialMyAccountId = myAccountId,
        _initialCounterpartyName = initialCounterpartyName,
        _filter = initialFilter ?? StatementChatFilterInput.empty,
        super(const StatementChatInitial()) {
    _syncSubscription = _syncCoordinatorService.onSyncUpdate.listen((_) {
      if (!isClosed) reload();
    });
  }

  final ListAccountStatementChatUseCase _listStatement;
  final ListAccountsUseCase _listAccounts;
  final GetCostCenterDetailsUseCase _getCostCenterDetails;
  final String _counterpartyAccountId;
  final SyncCoordinatorService _syncCoordinatorService;
  final String? _initialMyAccountId;
  final String? _initialCounterpartyName;

  String _myAccountId = '';
  String _counterpartyName = '';
  String _searchQuery = '';
  bool _isFund = false;
  StatementChatFilterInput _filter;
  Timer? _searchDebounce;
  StreamSubscription<void>? _syncSubscription;

  String get searchQuery => _searchQuery;
  StatementChatFilterInput get filter => _filter;

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    _syncSubscription?.cancel();
    return super.close();
  }

  Future<void> load() async {
    emit(const StatementChatLoading());

    // Resolve accounts to find "my" account and counterparty name.
    final accountsR = await _listAccounts.call(
      const ListAccountsInput(activeOnly: false),
    );
    if (isClosed) return;
    if (accountsR.isFailure) {
      emit(StatementChatFailure(accountsR.failureOrNull!));
      return;
    }

    final accounts = accountsR.valueOrNull!.accounts;
    final cpIndex = accounts.indexWhere((a) => a.id == _counterpartyAccountId);
    if (cpIndex != -1) {
      final cp = accounts[cpIndex];
      _counterpartyName = cp.name;
      _isFund = cp.standardClassificationKind ==
          StandardAccountClassificationKind.liquidAssets.name;
    } else {
      // It's likely a cost center or just another entity
      _counterpartyName = _initialCounterpartyName ?? 'Entity';
      _isFund = true; // Use unified mode for non-account entities
    }

    // Pick the "my" account.
    // If provided initially, use it.
    // Otherwise, prioritize the "Fund" account (liquidAssets).
    if (_initialMyAccountId != null) {
      _myAccountId = _initialMyAccountId;
    } else {
      // Find the first liquidAssets account that isn't the counterparty
      final fundAccount = accounts.firstWhere(
        (a) =>
            a.standardClassificationKind ==
                StandardAccountClassificationKind.liquidAssets.name &&
            a.id != _counterpartyAccountId,
        orElse: () => accounts.firstWhere(
          (a) => a.id != _counterpartyAccountId,
          orElse: () => accounts.first,
        ),
      );
      _myAccountId = fundAccount.id;
    }

    await _fetch();
  }

  void setSearchText(String text) {
    _searchQuery = text;
    final s = state;
    if (s is StatementChatReady) {
      emit(s.copyWith(searchQuery: text));
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), _fetch);
  }

  void setFilter(StatementChatFilterInput filter) {
    _filter = filter;
    _fetch();
  }

  void setViewMode(StatementChatViewMode mode) {
    _filter = _filter.copyWith(viewMode: mode);
    _fetch();
  }

  void clearSearch() {
    _searchQuery = '';
    _searchDebounce?.cancel();
    _fetch();
  }

  void clearAllFiltersAndSearch() {
    _searchQuery = '';
    _filter = StatementChatFilterInput.empty;
    _searchDebounce?.cancel();
    _fetch();
  }

  Future<void> reload() => _fetch();

  Future<void> _fetch() async {
    final activeFilter = _filter.copyWith(
      searchQuery: _searchQuery.trim().isEmpty ? null : _searchQuery,
      clearSearchQuery: _searchQuery.trim().isEmpty,
    );

    final result = await _listStatement.call(
      myAccountId: _myAccountId,
      counterpartyAccountId: _counterpartyAccountId,
      filter: activeFilter,
      isUnified: _isFund,
    );
    if (isClosed) return;

    result.fold(
      (f) => emit(StatementChatFailure(f)),
      (out) async {
        // Infer currency from first message if available.
        String currSymbol = '';
        int currDigits = 0;
        if (out.messages.isNotEmpty) {
          currSymbol = out.messages.first.currencySymbol;
          currDigits = out.messages.first.currencyDigits;
        }

        final Map<String, String> costCenterNames = {};
        final ccId = _filter.costCenterId;
        if (ccId != null && ccId.isNotEmpty) {
          final ccR = await _getCostCenterDetails.call(ccId);
          if (isClosed) return;
          if (ccR.isSuccess) {
            costCenterNames[ccId] = ccR.valueOrNull!.center.name;
          }
        }

        emit(StatementChatReady(
          myAccountId: _myAccountId,
          counterpartyAccountId: _counterpartyAccountId,
          counterpartyName: _counterpartyName,
          messages: out.messages,
          broughtForwardByCurrency: out.broughtForwardByCurrency,
          finalBalanceByCurrency: out.finalBalanceByCurrency,
          filter: _filter,
          searchQuery: _searchQuery,
          isUnified: _isFund,
          currencySymbol: currSymbol,
          currencyDigits: currDigits,
          costCenterNamesById: costCenterNames,
        ));
      },
    );
  }
}
