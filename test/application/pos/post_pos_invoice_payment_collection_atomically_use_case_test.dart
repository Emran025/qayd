import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/governance/check_governance_status_use_case.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/post_pos_invoice_payment_collection_atomically_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/fiscal_period.dart';
import 'package:qayd/domain/entities/ledger_account_snapshot.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/governance_repository.dart';
import 'package:qayd/domain/repositories/pos_invoice_payment_collection_repository.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/governance_status.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/submit_activation_request.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';

final _currency = CurrencyCode(
  code: 'SAR',
  nameAr: 'ريال سعودي',
  symbol: 'ر.س',
);
final _date = DateTime.utc(2026, 2, 2, 11);

final class _Governance implements GovernanceRepository {
  _Governance(this.status);

  final GovernanceStatus status;

  @override
  Future<Result<GovernanceStatus>> getStatus({bool forceRefresh = false}) async =>
      Success(status);

  @override
  Future<Result<void>> submitActivation(SubmitActivationRequest request) async =>
      const Success(null);
}

final class _Periods implements FiscalPeriodRepository {
  _Periods(this.periods);

  final List<FiscalPeriod> periods;

  @override
  Future<Result<List<FiscalPeriod>>> listAllOrdered() async => Success(periods);

  @override
  Future<Result<FiscalPeriod?>> findLatestClosed() async => const Success(null);

  @override
  Future<Result<FiscalPeriod?>> findOpenPeriod() async => const Success(null);

  @override
  Future<Result<void>> insert(FiscalPeriod period) async => const Success(null);

  @override
  Future<Result<List<LedgerAccountSnapshot>>> snapshotsForPeriod(
    String periodId,
  ) async =>
      const Success([]);

  @override
  Future<Result<void>> closePeriodWithSnapshots({
    required FiscalPeriod closed,
    required List<LedgerAccountSnapshot> snapshots,
  }) async =>
      const Success(null);
}

final class _CollectionRepository
    implements PosInvoicePaymentCollectionRepository {
  _CollectionRepository({this.recovered = false});

  final bool recovered;
  int recoverCalls = 0;
  int saveCalls = 0;

  @override
  Future<Result<bool>> recoverCommitted(
    PosInvoicePaymentCollectionPosting posting,
  ) async {
    recoverCalls++;
    return Success(recovered);
  }

  @override
  Future<Result<void>> saveAtomically(
    PosInvoicePaymentCollectionPosting posting,
  ) async {
    saveCalls++;
    return const Success(null);
  }
}

PosInvoicePaymentCollectionPosting _posting() {
  final line = PosInvoiceLine.create(
    id: 'line-1',
    invoiceId: 'invoice-1',
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    quantity: PosQuantity.whole(2),
    unitPrice: Money.fromMinorUnits(500, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    createdAt: _date.subtract(const Duration(days: 1)),
  );
  final before = PosInvoice.draft(
    id: 'invoice-1',
    invoiceNumber: 'S-1',
    type: PosInvoiceType.sale,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [line],
    idempotencyKey: 'sale-key',
    invoiceDate: _date.subtract(const Duration(days: 1)),
    now: _date.subtract(const Duration(days: 1)),
    counterpartyAccountId: AccountId('customer-1'),
  ).post(_date.subtract(const Duration(days: 1)));
  final payment = PosInvoicePayment.create(
    id: 'collection-1',
    invoiceId: before.id,
    accountId: AccountId('cash-1'),
    method: PosPaymentMethod.cash,
    amount: Money.fromMinorUnits(250, _currency),
    currency: _currency,
    occurredAt: _date,
    idempotencyKey: 'collection-key',
  );
  final voucher = Voucher.draft(
    id: VoucherId('collection-1:voucher'),
    type: VoucherType.receipt,
    date: _date,
    amount: payment.amount,
    currency: _currency,
    counterpartyId: AccountId('customer-1'),
    affectedAccountId: AccountId('cash-1'),
    referenceNumber: payment.id,
    description: 'POS collection S-1',
    createdAt: _date,
  ).confirm(_date);
  return PosInvoicePaymentCollectionPosting(
    invoiceBefore: before,
    invoiceAfter: before.applyPayment(payment.amount, _date),
    payment: payment,
    accountingPosting: PosAccountingPosting(
      sourceId: payment.id,
      voucher: voucher,
      entries: const EntryGenerator().generateForConfirmedVoucher(
        voucher: voucher,
        transactionId: TransactionId('collection-1:transaction'),
        debitEntryId: EntryId('collection-1:debit'),
        creditEntryId: EntryId('collection-1:credit'),
        ledgerCreatedAt: _date,
      ),
    ),
    recordedAt: _date,
  );
}

PostPosInvoicePaymentCollectionAtomicallyUseCase _useCase({
  required GovernanceStatus governance,
  required List<FiscalPeriod> periods,
  required _CollectionRepository repository,
}) =>
    PostPosInvoicePaymentCollectionAtomicallyUseCase(
      writeGuard: GovernanceWriteGuard(
        CheckGovernanceStatusUseCase(_Governance(governance)),
      ),
      fiscalPeriodRepository: _Periods(periods),
      postingRepository: repository,
    );

void main() {
  test('rejects collection dated in a closed fiscal period', () async {
    final repository = _CollectionRepository();
    final closed = FiscalPeriod(
      id: 'closed-1',
      name: 'Closed',
      startDate: DateTime.utc(2026, 2, 1),
      endDate: DateTime.utc(2026, 2, 28),
      status: FiscalPeriodStatus.closed,
    );

    final result = await _useCase(
      governance: GovernanceStatus.activated,
      periods: [closed],
      repository: repository,
    )(_posting());

    expect(result.isFailure, isTrue);
    expect(repository.recoverCalls, 1);
    expect(repository.saveCalls, 0);
  });

  test('rejects a new collection when governance is suspended', () async {
    final repository = _CollectionRepository();

    final result = await _useCase(
      governance: const GovernanceStatus(kind: GovernanceStatusKind.suspended),
      periods: const [],
      repository: repository,
    )(_posting());

    expect(result.isFailure, isTrue);
    expect(repository.saveCalls, 0);
  });

  test('returns an exact committed replay before closed-period/governance gates',
      () async {
    final repository = _CollectionRepository(recovered: true);
    final closed = FiscalPeriod(
      id: 'closed-1',
      name: 'Closed',
      startDate: DateTime.utc(2026, 2, 1),
      endDate: DateTime.utc(2026, 2, 28),
      status: FiscalPeriodStatus.closed,
    );

    final result = await _useCase(
      governance: const GovernanceStatus(kind: GovernanceStatusKind.suspended),
      periods: [closed],
      repository: repository,
    )(_posting());

    expect(result.isSuccess, isTrue);
    expect(repository.recoverCalls, 1);
    expect(repository.saveCalls, 0);
  });
}
