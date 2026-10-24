import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/vouchers/withdraw_voucher_use_case.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/error/failures.dart';

class MockVoucherRepository extends Mock implements VoucherRepository {}

class MockGovernanceWriteGuard extends Mock implements GovernanceWriteGuard {}

class MockSyncEventDispatcher extends Mock implements SyncEventDispatcher {}

class FakeVoucher extends Fake implements Voucher {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeVoucher());
    registerFallbackValue(VoucherId('dummy'));
  });

  late WithdrawVoucherUseCase useCase;
  late MockVoucherRepository mockVoucherRepo;
  late MockGovernanceWriteGuard mockWriteGuard;
  late MockSyncEventDispatcher mockSyncEventDispatcher;

  setUp(() {
    mockVoucherRepo = MockVoucherRepository();
    mockWriteGuard = MockGovernanceWriteGuard();
    mockSyncEventDispatcher = MockSyncEventDispatcher();

    useCase = WithdrawVoucherUseCase(
      mockVoucherRepo,
      mockWriteGuard,
      syncEventDispatcher: mockSyncEventDispatcher,
    );
  });

  test('should return failure when write guard denies access', () async {
    when(() => mockWriteGuard.assertWritesPermitted()).thenAnswer(
        (_) async => FailureResult(ValidationFailure(messageAr: 'Denied')));

    final result = await useCase(voucherId: 'v-1');

    expect(result.isFailure, isTrue);
    verifyZeroInteractions(mockVoucherRepo);
  });

  test('should return failure if voucher not found', () async {
    when(() => mockWriteGuard.assertWritesPermitted())
        .thenAnswer((_) async => const Success(null));
    when(() => mockVoucherRepo.getById(any())).thenAnswer(
        (_) async => FailureResult(ValidationFailure(messageAr: 'Not found')));

    final result = await useCase(voucherId: 'v-1');

    expect(result.isFailure, isTrue);
  });

  test('should withdraw voucher and dispatch sync event successfully',
      () async {
    when(() => mockWriteGuard.assertWritesPermitted())
        .thenAnswer((_) async => const Success(null));

    final currency = CurrencyCode(
        code: 'USD', nameAr: 'USD', symbol: '\$', fractionalDigits: 2);
    final voucher = Voucher.draft(
      id: VoucherId('v-1'),
      type: VoucherType.receipt,
      date: DateTime.now(),
      amount: Money.positiveAmount(100, currency),
      currency: currency,
      counterpartyId: AccountId('cp-1'),
      affectedAccountId: AccountId('aff-1'),
      createdAt: DateTime.now(),
    );

    when(() => mockVoucherRepo.getById(any()))
        .thenAnswer((_) async => Success(voucher));
    when(() => mockVoucherRepo.save(any()))
        .thenAnswer((_) async => const Success(null));
    when(() => mockVoucherRepo.getByOriginVoucherId(any()))
        .thenAnswer((_) async => const Success([]));
    when(() => mockSyncEventDispatcher.dispatchVoucherWithdrawal(any()))
        .thenAnswer((_) async {});

    final result = await useCase(voucherId: 'v-1');

    expect(result.isSuccess, isTrue);
    verify(() => mockVoucherRepo.save(any())).called(1);
    verify(() => mockSyncEventDispatcher.dispatchVoucherWithdrawal(any()))
        .called(1);
  });
}
