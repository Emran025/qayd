import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/governance/check_governance_status_use_case.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/post_pos_sale_atomically_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/fiscal_period.dart';
import 'package:qayd/domain/entities/ledger_account_snapshot.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/governance_repository.dart';
import 'package:qayd/domain/repositories/pos_sale_posting_repository.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/domain/value_objects/governance_status.dart';
import 'package:qayd/domain/value_objects/submit_activation_request.dart';

final _currency = CurrencyCode(
  code: 'SAR',
  nameAr: 'ريال سعودي',
  symbol: 'ر.س',
);

final class _GovernanceRepository implements GovernanceRepository {
  _GovernanceRepository(this.status);

  GovernanceStatus status;

  @override
  Future<Result<GovernanceStatus>> getStatus(
          {bool forceRefresh = false}) async =>
      Success(status);

  @override
  Future<Result<void>> submitActivation(
          SubmitActivationRequest request) async =>
      const Success(null);
}

final class _FiscalPeriods implements FiscalPeriodRepository {
  _FiscalPeriods(this.periods);

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

final class _SaleRepository implements PosSalePostingRepository {
  int calls = 0;
  PosSalePosting? received;

  @override
  Future<Result<void>> saveAtomically(PosSalePosting posting) async {
    calls++;
    received = posting;
    return const Success(null);
  }
}

PosAccountingPosting _posting({required String id, required String sourceId}) {
  final date = DateTime.utc(2026, 1, 10, 10);
  final voucher = Voucher.draft(
    id: VoucherId(id),
    type: VoucherType.receipt,
    date: date,
    amount: Money.fromMinorUnits(500, _currency),
    currency: _currency,
    counterpartyId: AccountId('revenue'),
    affectedAccountId: AccountId('cash'),
    referenceNumber: sourceId,
    createdAt: date,
  ).confirm(date);
  return PosAccountingPosting(
    sourceId: sourceId,
    voucher: voucher,
    entries: EntryGenerator().generateForConfirmedVoucher(
      voucher: voucher,
      transactionId: TransactionId('$id-tx'),
      debitEntryId: EntryId('$id-debit'),
      creditEntryId: EntryId('$id-credit'),
      ledgerCreatedAt: date,
    ),
  );
}

PosSalePosting _sale({bool posted = true}) {
  final date = DateTime.utc(2026, 1, 10, 10);
  const invoiceId = 'sale-1';
  final line = PosInvoiceLine.create(
    id: 'line-1',
    invoiceId: invoiceId,
    productId: 'product-1',
    productNameSnapshot: 'Coffee',
    quantity: PosQuantity.whole(1),
    unitPrice: Money.fromMinorUnits(500, _currency),
    unitCost: Money.fromMinorUnits(100, _currency),
    discount: Money.zero(_currency),
    tax: Money.zero(_currency),
    createdAt: date,
  );
  final draft = PosInvoice.draft(
    id: invoiceId,
    invoiceNumber: 'S-1',
    type: PosInvoiceType.sale,
    warehouseId: 'warehouse-1',
    currency: _currency,
    lines: [line],
    idempotencyKey: 'sale-key-1',
    invoiceDate: date,
    now: date,
  );
  final invoice = posted ? draft.post(date) : draft;
  return PosSalePosting(
    invoice: invoice,
    movements: [
      PosStockMovement.create(
        id: 'movement-1',
        productId: 'product-1',
        warehouseId: 'warehouse-1',
        type: PosStockMovementType.sale,
        direction: PosStockMovementDirection.outbound,
        quantity: PosQuantity.whole(1),
        unitCost: Money.fromMinorUnits(100, _currency),
        sourceType: 'pos_invoice',
        sourceId: invoiceId,
        sourceLineId: 'line-1',
        occurredAt: date,
        idempotencyKey: 'stock-key-1',
        createdAt: date,
      ),
    ],
    postings: [
      _posting(id: 'voucher-1', sourceId: invoiceId),
      _posting(id: 'voucher-2', sourceId: invoiceId),
    ],
    payments: const [],
  );
}

void main() {
  test('rejects suspended governance before fiscal or coordinator writes',
      () async {
    final saleRepository = _SaleRepository();
    final fiscalPeriods = _FiscalPeriods(const []);
    final useCase = PostPosSaleAtomicallyUseCase(
      writeGuard: GovernanceWriteGuard(
        CheckGovernanceStatusUseCase(
          _GovernanceRepository(
            const GovernanceStatus(kind: GovernanceStatusKind.suspended),
          ),
        ),
      ),
      fiscalPeriodRepository: fiscalPeriods,
      postingRepository: saleRepository,
    );

    final result = await useCase(_sale());

    expect(result.isFailure, isTrue);
    expect(saleRepository.calls, 0);
  });

  test('rejects a closed fiscal period before coordinator write', () async {
    final saleRepository = _SaleRepository();
    final period = FiscalPeriod(
      id: 'period-1',
      name: 'Closed',
      startDate: DateTime.utc(2026, 1, 1),
      endDate: DateTime.utc(2026, 1, 31),
      status: FiscalPeriodStatus.closed,
    );
    final useCase = PostPosSaleAtomicallyUseCase(
      writeGuard: GovernanceWriteGuard(
        CheckGovernanceStatusUseCase(
          _GovernanceRepository(GovernanceStatus.activated),
        ),
      ),
      fiscalPeriodRepository: _FiscalPeriods([period]),
      postingRepository: saleRepository,
    );

    final result = await useCase(_sale());

    expect(result.isFailure, isTrue);
    expect(saleRepository.calls, 0);
  });

  test('rejects an unposted invoice before coordinator write', () async {
    final saleRepository = _SaleRepository();
    final useCase = PostPosSaleAtomicallyUseCase(
      writeGuard: GovernanceWriteGuard(
        CheckGovernanceStatusUseCase(
          _GovernanceRepository(GovernanceStatus.activated),
        ),
      ),
      fiscalPeriodRepository: _FiscalPeriods(const []),
      postingRepository: saleRepository,
    );

    final result = await useCase(_sale(posted: false));

    expect(result.isFailure, isTrue);
    expect(saleRepository.calls, 0);
  });

  test('delegates a governed posted sale exactly once', () async {
    final saleRepository = _SaleRepository();
    final useCase = PostPosSaleAtomicallyUseCase(
      writeGuard: GovernanceWriteGuard(
        CheckGovernanceStatusUseCase(
          _GovernanceRepository(GovernanceStatus.activated),
        ),
      ),
      fiscalPeriodRepository: _FiscalPeriods(const []),
      postingRepository: saleRepository,
    );
    final sale = _sale();

    final result = await useCase(sale);

    expect(result.isSuccess, isTrue);
    expect(saleRepository.calls, 1);
    expect(saleRepository.received?.invoice.id, sale.invoice.id);
  });
}
