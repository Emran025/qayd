import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/governance/check_governance_status_use_case.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/build_pos_stock_disposal_posting_use_case.dart';
import 'package:qayd/application/pos/post_pos_stock_disposal_atomically_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/fiscal_period.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_stock_lot.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/governance_repository.dart';
import 'package:qayd/domain/repositories/pos_accounting_posting_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/governance_status.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/pos_stock_disposal_reason.dart';
import 'package:qayd/domain/value_objects/submit_activation_request.dart';

final class _GovernanceRepository implements GovernanceRepository {
  @override
  Future<Result<GovernanceStatus>> getStatus({bool forceRefresh = false}) async =>
      const Success(GovernanceStatus(kind: GovernanceStatusKind.activated));

  @override
  Future<Result<void>> submitActivation(SubmitActivationRequest request) async =>
      const Success(null);
}

final class _InstallationRepository implements PosTemplateInstallationRepository {
  @override
  Future<Result<PosActivationResult?>> getEnabledInstallation({
    required PosTemplateDefinition template,
  }) async =>
      Success(
        PosActivationResult(
          templateKey: PosTemplateDefinition.coreTemplateKey,
          templateVersion: PosTemplateDefinition.currentVersion,
          warehouseId: 'warehouse-1',
          accountIdsByKey: {
            PosTemplateAccountKey.inventoryAsset.value: 'inventory-account',
            PosTemplateAccountKey.inventoryLossExpense.value: 'loss-account',
          },
          alreadyInstalled: true,
        ),
      );
}

final class _PostingRepository implements PosAccountingPostingRepository {
  PosStockMovement? movement;
  PosAccountingPosting? posting;
  int disposalCalls = 0;

  @override
  Future<Result<void>> saveOpeningBalance({
    required PosStockMovement movement,
    List<PosStockMovement> additionalMovements = const [],
    List<PosStockLot> lots = const [],
    required PosAccountingPosting posting,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> saveStockAdjustmentAtomically({
    required PosStockMovement movement,
    required PosAccountingPosting posting,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> saveStockDisposalAtomically({
    required PosStockMovement movement,
    required PosAccountingPosting posting,
  }) async {
    this.movement = movement;
    this.posting = posting;
    disposalCalls++;
    return const Success(null);
  }
}

final class _MockAccountRepository extends Mock implements AccountRepository {}
final class _MockFiscalPeriodRepository extends Mock
    implements FiscalPeriodRepository {}
final class _MockProductRepository extends Mock implements PosProductRepository {}
final class _MockStockRepository extends Mock
    implements PosStockMovementRepository {}

CurrencyCode _currency() =>
    CurrencyCode(code: 'SAR', nameAr: 'ريال سعودي', symbol: 'ر.س');

PosProduct _product(CurrencyCode currency, {bool expiryTracking = false}) =>
    PosProduct.create(
      id: 'product-1',
      sku: 'SKU-1',
      name: 'Coffee',
      currency: currency,
      salePrice: Money.fromMinorUnits(300, currency),
      purchasePrice: Money.fromMinorUnits(100, currency),
      quantityScale: 0,
      expiryTracking: expiryTracking,
      reorderLevel: PosQuantity.whole(0),
      now: DateTime.utc(2026, 1, 1),
    );

Account _account(String id, {bool active = true}) => Account.createRoot(
      id: AccountId(id),
      name: id,
      classification: AccountClassification.custom(
        name: 'POS',
        nature: AccountNature.debit,
      ),
      createdAt: DateTime.utc(2026, 1, 1),
      isActive: active,
    );

PosStockMovement _receipt(
  CurrencyCode currency, {
  required String id,
  required int quantity,
  required int unitCost,
  String? lotId,
}) =>
    PosStockMovement.create(
      id: id,
      productId: 'product-1',
      warehouseId: 'warehouse-1',
      type: PosStockMovementType.opening,
      direction: PosStockMovementDirection.inbound,
      quantity: PosQuantity.whole(quantity),
      unitCost: Money.fromMinorUnits(unitCost, currency),
      sourceType: 'test',
      sourceId: id,
      lotId: lotId,
      occurredAt: DateTime.utc(2026, 1, 1),
      idempotencyKey: 'key-$id',
      createdAt: DateTime.utc(2026, 1, 1),
    );

PosStockBalance _balance(CurrencyCode currency) =>
    emptyPosStockBalance(currency: currency, quantityScale: 0).apply(
      _receipt(currency, id: 'opening-stock', quantity: 5, unitCost: 100),
    );

PostPosStockDisposalInput _input({
  String key = 'disposal-key-1',
  String sourceId = 'disposal-source-1',
  int quantity = 2,
  String? lotId,
  DateTime? occurredAt,
}) =>
    PostPosStockDisposalInput(
      productId: 'product-1',
      warehouseId: 'warehouse-1',
      reason: PosStockDisposalReason.damage,
      quantityScaled: quantity,
      quantityScale: 0,
      currencyCode: 'SAR',
      sourceId: sourceId,
      idempotencyKey: key,
      lotId: lotId,
      occurredAt: occurredAt ?? DateTime.utc(2026, 1, 2, 10),
      createdAt: DateTime.utc(2026, 1, 2, 10),
    );

void main() {
  late CurrencyCode currency;
  late _MockAccountRepository accounts;
  late _MockFiscalPeriodRepository periods;
  late _MockProductRepository products;
  late _MockStockRepository stock;
  late _PostingRepository posting;
  late Account inventoryAccount;
  late Account lossAccount;

  setUp(() {
    currency = _currency();
    accounts = _MockAccountRepository();
    periods = _MockFiscalPeriodRepository();
    products = _MockProductRepository();
    stock = _MockStockRepository();
    posting = _PostingRepository();
    inventoryAccount = _account('inventory-account');
    lossAccount = _account('loss-account');

    when(() => accounts.getById(AccountId('inventory-account')))
        .thenAnswer((_) async => Success(inventoryAccount));
    when(() => accounts.getById(AccountId('loss-account')))
        .thenAnswer((_) async => Success(lossAccount));
    when(() => periods.listAllOrdered())
        .thenAnswer((_) async => const Success(<FiscalPeriod>[]));
    when(() => products.getById('product-1'))
        .thenAnswer((_) async => Success(_product(currency)));
    when(() => stock.getByIdempotencyKey('disposal-key-1')).thenAnswer(
      (_) async => Success(posting.movement),
    );
    when(() => stock.getByIdempotencyKey('inactive-account-key'))
        .thenAnswer((_) async => const Success(null));
    when(() => stock.getByIdempotencyKey('closed-period-key'))
        .thenAnswer((_) async => const Success(null));
    when(() => stock.getBalance(
          productId: 'product-1',
          warehouseId: 'warehouse-1',
        )).thenAnswer((_) async => Success(_balance(currency)));
  });

  PostPosStockDisposalAtomicallyUseCase useCase() =>
      PostPosStockDisposalAtomicallyUseCase(
        writeGuard: GovernanceWriteGuard(
          CheckGovernanceStatusUseCase(_GovernanceRepository()),
        ),
        installationRepository: _InstallationRepository(),
        productRepository: products,
        stockRepository: stock,
        accountRepository: accounts,
        fiscalPeriodRepository: periods,
        buildPosting: const BuildPosStockDisposalPostingUseCase(),
        postingRepository: posting,
      );

  test('replays the same request after stock has already been deducted', () async {
    final useCaseUnderTest = useCase();
    final first = await useCaseUnderTest(_input());
    lossAccount = _account('loss-account', active: false);
    final replay = await useCaseUnderTest(_input());

    expect(first.isSuccess, isTrue, reason: first.failureOrNull?.messageAr);
    expect(replay.isSuccess, isTrue, reason: replay.failureOrNull?.messageAr);
    expect(posting.disposalCalls, 2);
    expect(posting.movement?.quantity.scaledUnits, 2);
    verify(() => products.getById('product-1')).called(1);
    verify(() => stock.getBalance(
          productId: 'product-1',
          warehouseId: 'warehouse-1',
        )).called(1);
    verify(() => periods.listAllOrdered()).called(1);
  });

  test('fails before any write when mapped loss account is inactive', () async {
    lossAccount = _account('loss-account', active: false);

    final result = await useCase()(_input(key: 'inactive-account-key'));

    expect(result.isFailure, isTrue);
    expect(posting.disposalCalls, 0);
    verifyNever(() => products.getById('product-1'));
    verifyNever(() => stock.getBalance(
          productId: 'product-1',
          warehouseId: 'warehouse-1',
        ));
  });

  test('rejects a closed fiscal period before the atomic writer is called',
      () async {
    when(() => periods.listAllOrdered()).thenAnswer(
      (_) async => Success([
        FiscalPeriod(
          id: 'closed-2026-01',
          name: 'Closed January',
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 31),
          status: FiscalPeriodStatus.closed,
        ),
      ]),
    );

    final result = await useCase()(_input(key: 'closed-period-key'));

    expect(result.isFailure, isTrue);
    expect(posting.disposalCalls, 0);
    verifyNever(() => stock.getBalance(
          productId: 'product-1',
          warehouseId: 'warehouse-1',
        ));
  });

  test('values a selected batch using the weighted-average cost policy',
      () async {
    final product = _product(currency, expiryTracking: true);
    when(() => products.getById('product-1'))
        .thenAnswer((_) async => Success(product));
    when(() => stock.getByIdempotencyKey('weighted-average-key'))
        .thenAnswer((_) async => const Success(null));
    final weightedBalance = emptyPosStockBalance(
      currency: currency,
      quantityScale: 0,
    )
        .apply(_receipt(
          currency,
          id: 'lower-cost-stock',
          quantity: 2,
          unitCost: 100,
          lotId: 'lot-selected',
        ))
        .apply(_receipt(
          currency,
          id: 'higher-cost-stock',
          quantity: 2,
          unitCost: 200,
          lotId: 'lot-high-cost',
        ));
    when(() => stock.getBalance(
          productId: 'product-1',
          warehouseId: 'warehouse-1',
        )).thenAnswer((_) async => Success(weightedBalance));
    final selectedLot = PosStockLot.restore(
      id: 'lot-selected',
      productId: 'product-1',
      warehouseId: 'warehouse-1',
      supplierLotNumber: 'LOT-100',
      expiryDate: PosDate.fromParts(2026, 12, 31),
      receivedQuantity: PosQuantity.whole(2),
      remainingQuantity: PosQuantity.whole(2),
      unitCost: Money.fromMinorUnits(100, currency),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    when(() => stock.getDisposalLots(
          productId: 'product-1',
          warehouseId: 'warehouse-1',
        )).thenAnswer((_) async => Success([selectedLot]));

    final result = await useCase()(
      _input(key: 'weighted-average-key', quantity: 1, lotId: 'lot-selected'),
    );

    expect(result.isSuccess, isTrue, reason: result.failureOrNull?.messageAr);
    expect(posting.movement?.unitCost.minorUnits, 150);
    expect(posting.posting?.voucher.amount.minorUnits, 150);
  });
}
