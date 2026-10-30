import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/governance/check_governance_status_use_case.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/build_pos_opening_balance_posting_use_case.dart';
import 'package:qayd/application/pos/post_pos_opening_balance_atomically_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/fiscal_period.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/governance_repository.dart';
import 'package:qayd/domain/repositories/pos_accounting_posting_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/governance_status.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/submit_activation_request.dart';

final class _GovernanceRepository implements GovernanceRepository {
  GovernanceStatus status = GovernanceStatus.activated;

  @override
  Future<Result<GovernanceStatus>> getStatus(
          {bool forceRefresh = false}) async =>
      Success(status);

  @override
  Future<Result<void>> submitActivation(
          SubmitActivationRequest request) async =>
      const Success(null);
}

final class _InstallationRepository
    implements PosTemplateInstallationRepository {
  _InstallationRepository(this.installation);

  final PosActivationResult? installation;
  int calls = 0;

  @override
  Future<Result<PosActivationResult?>> getEnabledInstallation({
    required PosTemplateDefinition template,
  }) async {
    calls++;
    return Success(installation);
  }
}

final class _ProductRepository implements PosProductRepository {
  _ProductRepository(this.product);

  final PosProduct product;

  @override
  Future<Result<PosProduct>> getById(String id) async => Success(product);

  @override
  Future<Result<PosProduct?>> getByBarcode(dynamic barcode) async =>
      const Success(null);

  @override
  Future<Result<List<PosProduct>>> list({
    bool activeOnly = true,
    String? search,
  }) async =>
      Success([product]);

  @override
  Future<Result<void>> save(PosProduct product) async => const Success(null);

  @override
  Future<Result<void>> deactivate(String id) async => const Success(null);
}

final class _PostingRepository implements PosAccountingPostingRepository {
  PosStockMovement? movement;
  PosAccountingPosting? posting;
  Result<void> result = const Success(null);

  @override
  Future<Result<void>> saveOpeningBalance({
    required PosStockMovement movement,
    required PosAccountingPosting posting,
  }) async {
    this.movement = movement;
    this.posting = posting;
    return result;
  }

  @override
  Future<Result<void>> saveStockAdjustmentAtomically({
    required PosStockMovement movement,
    required PosAccountingPosting posting,
  }) async {
    this.movement = movement;
    this.posting = posting;
    return result;
  }
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String next() => 'generated-${value++}';
}

final class _MockAccountRepository extends Mock implements AccountRepository {}

final class _MockFiscalPeriodRepository extends Mock
    implements FiscalPeriodRepository {}

CurrencyCode _currency() => CurrencyCode(
      code: 'SAR',
      nameAr: 'ريال سعودي',
      symbol: 'ر.س',
    );

PosProduct _product(CurrencyCode currency) => PosProduct.create(
      id: 'product-1',
      sku: 'SKU-1',
      name: 'Coffee',
      currency: currency,
      salePrice: Money.fromMinorUnits(300, currency),
      purchasePrice: Money.fromMinorUnits(100, currency),
      quantityScale: 1,
      reorderLevel: PosQuantity.fromScaled(0, scale: 1),
      now: DateTime.utc(2026, 1, 1),
    );

PosActivationResult _installation() => PosActivationResult(
      templateKey: PosTemplateDefinition.coreTemplateKey,
      templateVersion: PosTemplateDefinition.currentVersion,
      warehouseId: 'warehouse-real-id',
      accountIdsByKey: {
        PosTemplateAccountKey.inventoryAsset.value: 'inventory-account',
        PosTemplateAccountKey.openingBalanceClearing.value: 'clearing-account',
      },
      alreadyInstalled: true,
    );

Account _account(String id, AccountNature nature) => Account.createRoot(
      id: AccountId(id),
      name: id,
      classification: nature == AccountNature.debit
          ? AccountClassification.custom(
              name: 'POS',
              nature: AccountNature.debit,
            )
          : AccountClassification.custom(
              name: 'POS',
              nature: AccountNature.credit,
            ),
      createdAt: DateTime.utc(2026, 1, 1),
    );

PostPosOpeningBalanceAtomicallyUseCase _useCase({
  required _GovernanceRepository governance,
  required _InstallationRepository installation,
  required PosProduct product,
  required AccountRepository accounts,
  required FiscalPeriodRepository periods,
  required _PostingRepository posting,
}) {
  return PostPosOpeningBalanceAtomicallyUseCase(
    writeGuard: GovernanceWriteGuard(CheckGovernanceStatusUseCase(governance)),
    installationRepository: installation,
    productRepository: _ProductRepository(product),
    accountRepository: accounts,
    fiscalPeriodRepository: periods,
    buildPosting: BuildPosOpeningBalancePostingUseCase(),
    postingRepository: posting,
    idGenerator: _Ids(),
  );
}

PostPosOpeningBalanceInput _input() => PostPosOpeningBalanceInput(
      productId: 'product-1',
      quantityScaled: 15,
      quantityScale: 1,
      unitCostMinor: 100,
      currencyCode: 'SAR',
      idempotencyKey: 'opening-key',
      sourceId: 'opening-source-1',
      occurredAt: DateTime.utc(2026, 1, 2, 10),
      createdAt: DateTime.utc(2026, 1, 2, 10),
    );

void main() {
  late CurrencyCode currency;
  late PosProduct product;
  late _GovernanceRepository governance;
  late _InstallationRepository installation;
  late _MockAccountRepository accounts;
  late _MockFiscalPeriodRepository periods;
  late _PostingRepository posting;

  setUp(() {
    currency = _currency();
    product = _product(currency);
    governance = _GovernanceRepository();
    installation = _InstallationRepository(_installation());
    accounts = _MockAccountRepository();
    periods = _MockFiscalPeriodRepository();
    posting = _PostingRepository();
    when(() => accounts.getById(AccountId('inventory-account'))).thenAnswer(
      (_) async => Success(_account('inventory-account', AccountNature.debit)),
    );
    when(() => accounts.getById(AccountId('clearing-account'))).thenAnswer(
      (_) async => Success(_account('clearing-account', AccountNature.credit)),
    );
    when(() => periods.listAllOrdered()).thenAnswer(
      (_) async => const Success(<FiscalPeriod>[]),
    );
  });

  test('blocks suspended governance before reading or writing POS data',
      () async {
    governance.status = const GovernanceStatus(
      kind: GovernanceStatusKind.suspended,
    );
    final useCase = _useCase(
      governance: governance,
      installation: installation,
      product: product,
      accounts: accounts,
      periods: periods,
      posting: posting,
    );

    final result = await useCase(_input());

    expect(result.isFailure, isTrue);
    expect(installation.calls, 0);
    expect(posting.posting, isNull);
    verifyNever(() => accounts.getById(AccountId('inventory-account')));
    verifyNever(() => accounts.getById(AccountId('clearing-account')));
  });

  test('rejects a closed fiscal date before coordinator invocation', () async {
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
    final useCase = _useCase(
      governance: governance,
      installation: installation,
      product: product,
      accounts: accounts,
      periods: periods,
      posting: posting,
    );

    final result = await useCase(_input());

    expect(result.isFailure, isTrue);
    expect(posting.posting, isNull);
  });

  test('rejects a missing template account mapping before writes', () async {
    installation = _InstallationRepository(
      PosActivationResult(
        templateKey: PosTemplateDefinition.coreTemplateKey,
        templateVersion: PosTemplateDefinition.currentVersion,
        warehouseId: 'warehouse-real-id',
        accountIdsByKey: {
          PosTemplateAccountKey.inventoryAsset.value: 'inventory-account',
        },
        alreadyInstalled: true,
      ),
    );
    final useCase = _useCase(
      governance: governance,
      installation: installation,
      product: product,
      accounts: accounts,
      periods: periods,
      posting: posting,
    );

    final result = await useCase(_input());

    expect(result.isFailure, isTrue);
    expect(posting.posting, isNull);
  });

  test('builds a governed posting using real warehouse and exact total amount',
      () async {
    final useCase = _useCase(
      governance: governance,
      installation: installation,
      product: product,
      accounts: accounts,
      periods: periods,
      posting: posting,
    );

    final result = await useCase(_input());

    expect(result.isSuccess, isTrue);
    expect(posting.movement?.warehouseId, 'warehouse-real-id');
    expect(posting.movement?.sourceId, 'opening-source-1');
    expect(posting.posting?.sourceId, 'opening-source-1');
    expect(posting.posting?.voucher.amount.minorUnits, 150);
    expect(posting.posting?.entries, hasLength(2));
    expect(posting.posting?.voucher.referenceNumber, 'opening-source-1');
    verify(() => accounts.getById(AccountId('inventory-account'))).called(1);
    verify(() => accounts.getById(AccountId('clearing-account'))).called(1);
  });
}
