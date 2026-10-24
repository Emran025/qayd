import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/vouchers/create_tripartite_transfer_use_case.dart';
import 'package:qayd/application/vouchers/dtos/create_tripartite_transfer_input.dart';
import 'package:qayd/application/vouchers/dtos/create_tripartite_transfer_output.dart';
import 'package:qayd/application/settings/get_active_transaction_fee_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/fee_calculation_type.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/transaction_fee_setting.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';

import 'package:qayd/domain/services/entry_generator.dart';

class MockVoucherRepository extends Mock implements VoucherRepository {}

class MockCurrencyRepository extends Mock implements CurrencyRepository {}

class MockIdGenerator extends Mock implements IdGenerator {}

class MockGovernanceWriteGuard extends Mock implements GovernanceWriteGuard {}

class MockGetActiveTransactionFeeUseCase extends Mock
    implements GetActiveTransactionFeeUseCase {}

class MockAccountRepository extends Mock implements AccountRepository {}

class MockEntryGenerator extends Mock implements EntryGenerator {}

class FakeVoucher extends Fake implements Voucher {}

class FakeAccount extends Fake implements Account {}

class MockTransactionFeeSetting extends Mock implements TransactionFeeSetting {}

void main() {
  late CreateTripartiteTransferUseCase useCase;
  late MockVoucherRepository mockVoucherRepo;
  late MockCurrencyRepository mockCurrencyRepo;
  late MockIdGenerator mockIdGen;
  late MockGovernanceWriteGuard mockWriteGuard;
  late MockGetActiveTransactionFeeUseCase mockGetFee;
  late MockAccountRepository mockAccountRepo;
  late MockEntryGenerator mockEntryGenerator;

  setUpAll(() {
    registerFallbackValue(VoucherId('id'));
    registerFallbackValue(FakeVoucher());
    registerFallbackValue(FakeAccount());
  });

  setUp(() {
    mockVoucherRepo = MockVoucherRepository();
    mockCurrencyRepo = MockCurrencyRepository();
    mockIdGen = MockIdGenerator();
    mockWriteGuard = MockGovernanceWriteGuard();
    mockGetFee = MockGetActiveTransactionFeeUseCase();
    mockAccountRepo = MockAccountRepository();
    mockEntryGenerator = MockEntryGenerator();

    useCase = CreateTripartiteTransferUseCase(
      mockVoucherRepo,
      mockCurrencyRepo,
      mockIdGen,
      mockWriteGuard,
      mockGetFee,
      mockAccountRepo,
      mockEntryGenerator,
    );
  });

  final currency = CurrencyCode(
    code: 'SAR',
    nameAr: '﷼ودي',
    symbol: 'ر.س',
    fractionalDigits: 2,
  );

  final input = CreateTripartiteTransferInput(
    sourceAccountId: 'source-123',
    destinationAccountId: 'dest-456',
    affectedAccountId: 'me-789',
    amountMinorUnits: 5000,
    currencyCode: 'SAR',
    date: DateTime.now(),
    description: 'تحويل ثلاثي تجريبي',
  );

  group('CreateTripartiteTransferUseCase', () {
    test('should succeed and return output when all validations pass',
        () async {
      // Arrange
      when(() => mockWriteGuard.assertWritesPermitted())
          .thenAnswer((_) async => const Success(null));
      when(() => mockCurrencyRepo.getByCode('SAR'))
          .thenAnswer((_) async => Success(currency));
      when(() => mockIdGen.next()).thenReturn('unique-id');
      when(() => mockGetFee.call())
          .thenAnswer((_) async => const Success(null));
      when(() => mockAccountRepo.getAll())
          .thenAnswer((_) async => const Success([]));
      when(() => mockAccountRepo.getById(AccountId('me-789'))).thenAnswer(
        (_) async => Success(Account.createRoot(
          id: AccountId('me-789'),
          name: 'Mediator',
          classification: AccountClassification.payables,
          createdAt: DateTime.utc(2026, 1, 1),
        )),
      );

      when(() => mockVoucherRepo.saveTripartitePair(
            receiptVoucher: any(named: 'receiptVoucher'),
            paymentVoucher: any(named: 'paymentVoucher'),
          )).thenAnswer((_) async => const Success(null));

      // Act
      final result = await useCase.call(input);

      // Assert
      expect(result.isSuccess, isTrue);
      final output = result.valueOrNull as CreateTripartiteTransferOutput;
      expect(output.transferGroupId, 'unique-id');

      verify(() => mockVoucherRepo.saveTripartitePair(
            receiptVoucher: any(named: 'receiptVoucher'),
            paymentVoucher: any(named: 'paymentVoucher'),
          )).called(1);
    });

    test('should fail when source and destination accounts are identical',
        () async {
      // Arrange
      final invalidInput =
          input.copyWith(destinationAccountId: input.sourceAccountId);
      when(() => mockWriteGuard.assertWritesPermitted())
          .thenAnswer((_) async => const Success(null));
      when(() => mockCurrencyRepo.getByCode('SAR'))
          .thenAnswer((_) async => Success(currency));

      // Act
      final result = await useCase.call(invalidInput);

      // Assert
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull?.messageAr,
          contains('لا يمكن أن يكون المصدر والوجهة نفس الطرف'));
    });

    test('should fail when governance gate blocks writes', () async {
      // Arrange
      when(() => mockWriteGuard.assertWritesPermitted()).thenAnswer((_) async =>
          const FailureResult(UnexpectedFailure(messageAr: 'ممنوع الكتابة')));

      // Act
      final result = await useCase.call(input);

      // Assert
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull?.messageAr, 'ممنوع الكتابة');
    });

    test('should fail when currency is invalid', () async {
      // Arrange
      when(() => mockWriteGuard.assertWritesPermitted())
          .thenAnswer((_) async => const Success(null));
      when(() => mockCurrencyRepo.getByCode('SAR'))
          .thenAnswer((_) async => const Success(null));

      // Act
      final result = await useCase.call(input);

      // Assert
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull?.messageAr,
          contains('العملة المختارة غير صالحة'));
    });

    test('should create fee voucher when transaction fee is active', () async {
      // Arrange
      final feeSetting = MockTransactionFeeSetting();
      when(() => feeSetting.value).thenReturn(100);
      when(() => feeSetting.calculationType)
          .thenReturn(FeeCalculationType.fixed);

      when(() => mockWriteGuard.assertWritesPermitted())
          .thenAnswer((_) async => const Success(null));
      when(() => mockCurrencyRepo.getByCode('SAR'))
          .thenAnswer((_) async => Success(currency));
      when(() => mockIdGen.next()).thenReturn('unique-id');
      when(() => mockGetFee.call())
          .thenAnswer((_) async => Success(feeSetting));
      when(() => mockAccountRepo.getAll(excludeArchived: true))
          .thenAnswer((_) async => const Success([]));
      when(() => mockAccountRepo.getById(AccountId('me-789'))).thenAnswer(
        (_) async => Success(Account.createRoot(
          id: AccountId('me-789'),
          name: 'Mediator',
          classification: AccountClassification.payables,
          createdAt: DateTime.utc(2026, 1, 1),
        )),
      );

      when(() => mockVoucherRepo.saveTripartitePair(
            receiptVoucher: any(named: 'receiptVoucher'),
            paymentVoucher: any(named: 'paymentVoucher'),
          )).thenAnswer((_) async => const Success(null));

      when(() => mockVoucherRepo.save(any()))
          .thenAnswer((_) async => const Success(null));
      when(() => mockAccountRepo.save(any()))
          .thenAnswer((_) async => const Success(null));

      // Act
      final result = await useCase.call(input);

      // Assert
      expect(
        result.isSuccess,
        isTrue,
        reason: result.failureOrNull?.toString(),
      );
      // Verify fee voucher was saved
      verify(() => mockVoucherRepo.save(any())).called(1);
      // The fee income and remittance-clearing accounts are both created.
      verify(() => mockAccountRepo.save(any())).called(2);
    });
  });
}
