import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/pos/build_pos_stock_adjustment_posting_use_case.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_side.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';

CurrencyCode _currency() => CurrencyCode(
      code: 'SAR',
      nameAr: 'ريال سعودي',
      symbol: 'ر.س',
    );

BuildPosStockAdjustmentPostingInput _input(
  CurrencyCode currency, {
  required PosStockMovementDirection direction,
}) =>
    BuildPosStockAdjustmentPostingInput(
      sourceId: 'count-source-1',
      voucherId: 'voucher-1',
      transactionId: 'transaction-1',
      debitEntryId: 'debit-1',
      creditEntryId: 'credit-1',
      inventoryAccountId: 'inventory',
      counterAccountId: 'variance',
      direction: direction,
      amountMinorUnits: 750,
      currency: currency,
      reason: 'Physical count variance',
      date: DateTime.utc(2026, 1, 1),
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('BuildPosStockAdjustmentPostingUseCase', () {
    test('increase debits inventory and credits variance account', () async {
      final result = await const BuildPosStockAdjustmentPostingUseCase()(
        _input(
          _currency(),
          direction: PosStockMovementDirection.inbound,
        ),
      );

      expect(result.isSuccess, isTrue);
      final posting = result.valueOrNull!;
      expect(posting.voucher.type, VoucherType.receipt);
      expect(posting.voucher.affectedAccountId.value, 'inventory');
      expect(posting.voucher.counterpartyId.value, 'variance');
      expect(posting.entries, hasLength(2));
      expect(
        posting.entries.singleWhere((entry) => entry.side == EntrySide.debit)
            .accountId.value,
        'inventory',
      );
      expect(
        posting.entries.singleWhere((entry) => entry.side == EntrySide.credit)
            .accountId.value,
        'variance',
      );
    });

    test('decrease debits variance and credits inventory', () async {
      final result = await const BuildPosStockAdjustmentPostingUseCase()(
        _input(
          _currency(),
          direction: PosStockMovementDirection.outbound,
        ),
      );

      expect(result.isSuccess, isTrue);
      final posting = result.valueOrNull!;
      expect(posting.voucher.type, VoucherType.payment);
      expect(
        posting.entries.singleWhere((entry) => entry.side == EntrySide.debit)
            .accountId.value,
        'variance',
      );
      expect(
        posting.entries.singleWhere((entry) => entry.side == EntrySide.credit)
            .accountId.value,
        'inventory',
      );
      expect(
        posting.entries.map((entry) => entry.amount.minorUnits).toSet(),
        {750},
      );
    });

    test('rejects the inventory account as its own counter account', () async {
      final valid = _input(
        _currency(),
        direction: PosStockMovementDirection.inbound,
      );
      final result = await const BuildPosStockAdjustmentPostingUseCase()(
        BuildPosStockAdjustmentPostingInput(
          sourceId: valid.sourceId,
          voucherId: valid.voucherId,
          transactionId: valid.transactionId,
          debitEntryId: valid.debitEntryId,
          creditEntryId: valid.creditEntryId,
          inventoryAccountId: 'inventory',
          counterAccountId: 'inventory',
          direction: valid.direction,
          amountMinorUnits: valid.amountMinorUnits,
          currency: valid.currency,
          reason: valid.reason,
          date: valid.date,
          createdAt: valid.createdAt,
        ),
      );

      expect(result.isFailure, isTrue);
    });
  });
}
