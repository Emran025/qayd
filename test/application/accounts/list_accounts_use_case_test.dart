import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/accounts/list_accounts_use_case.dart';
import 'package:qayd/application/accounts/dtos/list_accounts_input.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/ledger_repository.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/services/balance_calculator.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/core/error/failures.dart';

class MockAccountRepository extends Mock implements AccountRepository {}

class MockLedgerRepository extends Mock implements LedgerRepository {}

class MockVoucherRepository extends Mock implements VoucherRepository {}

class MockFiscalPeriodRepository extends Mock
    implements FiscalPeriodRepository {}

class MockBalanceCalculator extends Mock implements BalanceCalculator {}

void main() {
  setUpAll(() {
    registerFallbackValue(AccountId('dummy'));
    registerFallbackValue(AccountNature.debit);
  });

  late ListAccountsUseCase useCase;
  late MockAccountRepository mockAccountRepo;
  late MockLedgerRepository mockLedgerRepo;
  late MockBalanceCalculator mockBalanceCalc;
  late MockVoucherRepository mockVoucherRepo;
  late MockFiscalPeriodRepository mockFiscalRepo;

  setUp(() {
    mockAccountRepo = MockAccountRepository();
    mockLedgerRepo = MockLedgerRepository();
    mockBalanceCalc = MockBalanceCalculator();
    mockVoucherRepo = MockVoucherRepository();
    mockFiscalRepo = MockFiscalPeriodRepository();

    when(() => mockFiscalRepo.findLatestClosed())
        .thenAnswer((_) async => const Success(null));
    when(() => mockFiscalRepo.listAllOrdered())
        .thenAnswer((_) async => const Success([]));

    useCase = ListAccountsUseCase(
      mockAccountRepo,
      mockLedgerRepo,
      mockBalanceCalc,
      mockVoucherRepo,
      mockFiscalRepo,
    );
  });

  test('should fetch accounts successfully', () async {
    final account = Account.createRoot(
      id: AccountId('acc-1'),
      name: 'Test Account',
      classification: AccountClassification.settlements,
      createdAt: DateTime.now(),
    );

    when(() => mockAccountRepo.getAll(
          activeOnly: any(named: 'activeOnly'),
          excludeArchived: any(named: 'excludeArchived'),
        )).thenAnswer((_) async => Success([account]));
    when(() => mockLedgerRepo.getAllEntries())
        .thenAnswer((_) async => const Success([]));
    when(() => mockVoucherRepo.getAll())
        .thenAnswer((_) async => const Success([]));
    when(() => mockBalanceCalc.signedBalanceMinorUnitsPerCurrency(
        entries: any(named: 'entries'),
        accountId: any(named: 'accountId'),
        nature: any(named: 'nature'))).thenReturn({});

    final result = await useCase(const ListAccountsInput());

    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull?.accounts, hasLength(1));
    expect(result.valueOrNull?.accounts.first.id, 'acc-1');
  });

  test('should compute pending voucher impacts correctly', () async {
    final account = Account.createRoot(
      id: AccountId('acc-1'),
      name: 'Test Account',
      classification: AccountClassification.settlements,
      createdAt: DateTime.now(),
    );
    final currency = CurrencyCode(
        code: 'USD',
        nameAr: 'دولار أمريكي',
        symbol: r'$',
        fractionalDigits: 2,
        isActive: true);

    final voucher = Voucher.draft(
      id: VoucherId('v-123'),
      type: VoucherType.receipt,
      date: DateTime.now(),
      amount: Money.positiveAmount(100, currency),
      currency: currency,
      counterpartyId: AccountId('cp-1'),
      affectedAccountId: AccountId('acc-1'), // Account owner is sender
      createdAt: DateTime.now(),
    );

    // Make sender status accepted
    final acceptedVoucher = voucher.attachSignature(
        signatureHex: 'hex',
        publicKeyHex: 'pubhex',
        isSender: true,
        status: AgreementStatus.accepted,
        signerPhone: '123');

    when(() => mockAccountRepo.getAll(
          activeOnly: any(named: 'activeOnly'),
          excludeArchived: any(named: 'excludeArchived'),
        )).thenAnswer((_) async => Success([account]));
    when(() => mockLedgerRepo.getAllEntries())
        .thenAnswer((_) async => const Success([]));
    when(() => mockVoucherRepo.getAll())
        .thenAnswer((_) async => Success([acceptedVoucher]));
    when(() => mockBalanceCalc.signedBalanceMinorUnitsPerCurrency(
        entries: any(named: 'entries'),
        accountId: any(named: 'accountId'),
        nature: any(named: 'nature'))).thenReturn({});

    final result = await useCase(const ListAccountsInput());

    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull?.accounts, hasLength(1));
    final balances = result.valueOrNull?.accounts.first.balancesMinorUnits;
    expect(balances, isNotNull);
    expect(balances!['USD'],
        -100); // Affected account on receipt is debit side, settlements is a liability (credit nature) -> so debit reduces it.
  });

  test('should handle exception gracefully', () async {
    when(() => mockAccountRepo.getAll(activeOnly: any(named: 'activeOnly')))
        .thenThrow(Exception('Unexpected failure'));

    final result = await useCase(const ListAccountsInput());

    expect(result.isFailure, isTrue);
    expect(result.failureOrNull, isA<UnexpectedFailure>());
  });
}
