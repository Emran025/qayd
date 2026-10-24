import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/vouchers/delete_draft_voucher_use_case.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';

class MockVoucherRepository extends Mock implements VoucherRepository {}

class MockGovernanceWriteGuard extends Mock implements GovernanceWriteGuard {}

void main() {
  setUpAll(() {
    registerFallbackValue(VoucherId('dummy'));
  });

  late DeleteDraftVoucherUseCase useCase;
  late MockVoucherRepository mockVoucherRepo;
  late MockGovernanceWriteGuard mockWriteGuard;

  setUp(() {
    mockVoucherRepo = MockVoucherRepository();
    mockWriteGuard = MockGovernanceWriteGuard();
    final currency = CurrencyCode(
      code: 'SAR',
      nameAr: 'ريال سعودي',
      symbol: 'ر.س',
    );
    final draft = Voucher.draft(
      id: VoucherId('v-1'),
      type: VoucherType.receipt,
      date: DateTime.utc(2026, 1, 1),
      amount: Money.fromMinorUnits(100, currency),
      currency: currency,
      counterpartyId: AccountId('counterparty'),
      affectedAccountId: AccountId('cash'),
      createdAt: DateTime.utc(2026, 1, 1),
    );
    when(() => mockVoucherRepo.getById(any()))
        .thenAnswer((_) async => Success(draft));

    useCase = DeleteDraftVoucherUseCase(
      mockVoucherRepo,
      mockWriteGuard,
    );
  });

  test('should return failure when write guard denies access', () async {
    when(() => mockWriteGuard.assertWritesPermitted()).thenAnswer(
        (_) async => FailureResult(ValidationFailure(messageAr: 'Denied')));

    final result = await useCase(voucherId: 'v-1');

    expect(result.isFailure, isTrue);
    verifyZeroInteractions(mockVoucherRepo);
  });

  test('should delete draft voucher successfully', () async {
    when(() => mockWriteGuard.assertWritesPermitted())
        .thenAnswer((_) async => const Success(null));
    when(() => mockVoucherRepo.deleteDraft(any()))
        .thenAnswer((_) async => const Success(null));

    final result = await useCase(voucherId: 'v-1');

    expect(result.isSuccess, isTrue);
    verify(() => mockVoucherRepo.deleteDraft(any())).called(1);
  });

  test('should handle exception gracefully', () async {
    when(() => mockWriteGuard.assertWritesPermitted())
        .thenAnswer((_) async => const Success(null));
    when(() => mockVoucherRepo.deleteDraft(any()))
        .thenThrow(Exception('Unexpected error'));

    final result = await useCase(voucherId: 'v-1');

    expect(result.isFailure, isTrue);
    expect(result.failureOrNull, isA<UnexpectedFailure>());
  });
}
