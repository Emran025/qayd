import 'package:flutter/material.dart';
import 'package:qayd/application/accounts/list_accounts_use_case.dart';
import 'package:qayd/application/pos/get_pos_stock_balance_use_case.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/application/pos/list_pos_stock_movements_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/components/atomic/qayd_empty_state.dart';
import 'package:qayd/presentation/components/atomic/qayd_floating_action_button.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/navigation/qayd_page_route.dart';
import 'package:qayd/presentation/pages/pos/pos_stock_adjustment_page.dart';
import 'package:qayd/presentation/pos/pos_money_display.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/widgets/qayd_scaffold.dart';

/// Read-only movement history with filters and pagination. Stock changes are
/// delegated to the separately governed adjustment page.
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
  int _loadGeneration = 0;
  List<PosProduct> _products = const [];
  List<PosStockMovement> _movements = const [];
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = true}) async {
    final generation = ++_loadGeneration;
    if (reset) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _failure = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    final offset = reset ? 0 : _movements.length;
    var products = _products;
    if (reset) {
      final productResult = await widget.listProducts(activeOnly: false);
      if (!mounted || generation != _loadGeneration) return;
      if (productResult.isFailure) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _failure = productResult.failureOrNull?.messageAr ??
              AppStrings.posProductReadFailed;
        });
        return;
      }
      products = productResult.valueOrNull ?? const <PosProduct>[];
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
    if (!mounted || generation != _loadGeneration) return;
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
      _products = products;
      _movements = reset ? page : [..._movements, ...page];
      _hasMore = page.length == _pageSize;
      _loading = false;
      _loadingMore = false;
      _failure = null;
    });
  }

  Future<void> _openAdjustment() async {
    final saved = await Navigator.of(context).push<bool>(
      QaydPageRoute.slideFromStart<bool>(
        builder: (_) => PosStockAdjustmentPage(
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
    return QaydScaffold(
      appBar: QaydAppBar(title: AppStrings.posStockMovementsTitle),
      floatingActionButton: QaydFloatingActionButton.extended(
        onPressed: _openAdjustment,
        icon: const Icon(Icons.tune_rounded),
        label: Text(AppStrings.posStockAdjustmentTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failure != null
              ? QaydEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: _failure!,
                  action: FilledButton.tonal(
                    onPressed: _load,
                    child: Text(AppStrings.retryAction),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      SpacingTokens.md,
                      SpacingTokens.md,
                      SpacingTokens.md,
                      SpacingTokens.xxl * 2,
                    ),
                    children: [
                      Text(AppStrings.posStockMovementsDescription),
                      const SizedBox(height: SpacingTokens.md),
                      DropdownButtonFormField<String?>(
                        initialValue: _productId,
                        decoration: InputDecoration(
                          labelText: AppStrings.posOpeningBalanceProduct,
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(AppStrings.posStockMovementAllProducts),
                          ),
                          ...activeProducts.map(
                            (product) => DropdownMenuItem<String?>(
                              value: product.id,
                              child: Text(
                                product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                        initialValue: _type,
                        decoration: InputDecoration(
                          labelText: AppStrings.posStockMovementAllTypes,
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
                          child: SizedBox(
                            height: 200,
                            child: QaydEmptyState(
                              icon: Icons.inventory_2_outlined,
                              title: AppStrings.posStockMovementsEmpty,
                            ),
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
