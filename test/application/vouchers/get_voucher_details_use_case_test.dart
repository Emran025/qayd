import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/vouchers/get_voucher_details_use_case.dart';
import 'package:qayd/application/vouchers/dtos/get_voucher_details_input.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/attachment_repository.dart';
import 'package:qayd/domain/repositories/collateral_repository.dart';
import 'package:qayd/domain/repositories/cost_center_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/repositories/ledger_repository.dart';
import 'package:qayd/domain/services/voucher_qr_service.dart';
import 'package:qayd/data/security/license_vault.dart';
import 'package:qayd/domain/services/signature_verification_engine.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/core/result/result.dart';

class MockVoucherRepository extends Mock implements VoucherRepository {}

class MockAccountRepository extends Mock implements AccountRepository {}

class MockVoucherQrService extends Mock implements VoucherQrService {}

class MockLicenseVault extends Mock implements LicenseVault {}

class MockAttachmentRepository extends Mock implements AttachmentRepository {}

class MockCollateralRepository extends Mock implements CollateralRepository {}

class MockCostCenterRepository extends Mock implements CostCenterRepository {}

class MockLedgerRepository extends Mock implements LedgerRepository {}

class MockSignatureVerificationEngine extends Mock
    implements SignatureVerificationEngine {}

class FakeVoucher extends Fake implements Voucher {}

void main() {
  setUpAll(() {
    registerFallbackValue(VoucherId('dummy'));
    registerFallbackValue(AccountId('dummy'));
    registerFallbackValue(FakeVoucher());
  });
  late GetVoucherDetailsUseCase useCase;
  late MockVoucherRepository mockVoucherRepo;
  late MockAccountRepository mockAccountRepo;
  late MockVoucherQrService mockQrService;
  late MockLicenseVault mockLicenseVault;
  late MockAttachmentRepository mockAttachmentRepo;
  late MockCollateralRepository mockCollateralRepo;
  late MockCostCenterRepository mockCostCenterRepo;
  late MockLedgerRepository mockLedgerRepo;
  late MockSignatureVerificationEngine mockVerificationEngine;

  setUp(() {
    mockVoucherRepo = MockVoucherRepository();
    mockAccountRepo = MockAccountRepository();
    mockQrService = MockVoucherQrService();
    mockLicenseVault = MockLicenseVault();
    mockAttachmentRepo = MockAttachmentRepository();
    mockCollateralRepo = MockCollateralRepository();
    mockCostCenterRepo = MockCostCenterRepository();
    mockLedgerRepo = MockLedgerRepository();
    mockVerificationEngine = MockSignatureVerificationEngine();

    useCase = GetVoucherDetailsUseCase(
      mockVoucherRepo,
      mockAccountRepo,
      mockQrService,
      mockLicenseVault,
      mockAttachmentRepo,
      mockCollateralRepo,
      mockCostCenterRepo,
      mockLedgerRepo,
      mockVerificationEngine,
    );

    // Default stub for ledger entries to avoid breaking existing tests
    when(() => mockLedgerRepo.getEntriesForAccount(any()))
        .thenAnswer((_) async => const Success([]));
  });

  test('should return voucher details successfully', () async {
    final currency = CurrencyCode(
        code: 'USD', nameAr: 'USD', symbol: '\$', fractionalDigits: 2);
    final voucher = Voucher.draft(
      id: VoucherId('v-1'),
      type: VoucherType.receipt,
      date: DateTime(2023, 1, 1),
      amount: Money.positiveAmount(100, currency),
      currency: currency,
      counterpartyId: AccountId('cp-1'),
      affectedAccountId: AccountId('aff-1'),
      createdAt: DateTime(2023, 1, 1),
    );

    final cpAccount = Account.createRoot(
        id: AccountId('cp-1'),
        name: 'CP Name',
        classification: AccountClassification.payables,
        createdAt: DateTime.now());
    final affAccount = Account.createRoot(
        id: AccountId('aff-1'),
        name: 'Aff Name',
        classification: AccountClassification.liquidAssets,
        createdAt: DateTime.now());

    when(() => mockVoucherRepo.getById(VoucherId('v-1')))
        .thenAnswer((_) async => Success(voucher));
    when(() => mockAccountRepo.getById(AccountId('cp-1')))
        .thenAnswer((_) async => Success(cpAccount));
    when(() => mockAccountRepo.getById(AccountId('aff-1')))
        .thenAnswer((_) async => Success(affAccount));

    when(() => mockLicenseVault.readLicenseData())
        .thenAnswer((_) async => {'phone': '12345', 'public_key': 'pub1'});

    when(() => mockAttachmentRepo.getByVoucherId(VoucherId('v-1')))
        .thenAnswer((_) async => const Success([]));
    when(() => mockCollateralRepo.getByVoucherId(VoucherId('v-1')))
        .thenAnswer((_) async => const Success(null));
    when(() => mockVoucherRepo.getByOriginVoucherId(VoucherId('v-1')))
        .thenAnswer((_) async => const Success([]));

    when(() => mockQrService.generateQrData(voucher, ownerPhone: '12345'))
        .thenReturn('qr-data');

    when(() => mockCostCenterRepo.getCostCenterIdsForVoucher('v-1'))
        .thenAnswer((_) async => const Success([]));

    final result =
        await useCase(const GetVoucherDetailsInput(voucherId: 'v-1'));

    if (result.isFailure) {}

    expect(result.isSuccess, isTrue);
    final out = result.valueOrNull!;
    expect(out.id, 'v-1');
    expect(out.counterpartyName, 'CP Name');
    expect(out.affectedName, 'Aff Name');
    expect(out.qrData, 'qr-data');
    expect(out.canApprove, isTrue); // The local creator can confirm their draft.
  });
}
