import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/pos/build_pos_stock_disposal_posting_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_side.dart';
import 'package:qayd/domain/value_objects/pos_stock_disposal_reason.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';

CurrencyCode _currency() => CurrencyCode(
      code: 'SAR',
      nameAr: 'ريال سعودي',
      symbol: 'ر.س',
    );

BuildPosStockDisposalPostingInput _input({
  required CurrencyCode currency,
  required PosStockMovementDirection direction,
  PosStockDisposalReason? reason = PosStockDisposalReason.damage,
  String? reasonDetail,
  String? reversalOfSourceId,
  int amount = 1250,
}) =>
    BuildPosStockDisposalPostingInput(
      sourceId: 'disposal-source-1',
      voucherId: 'disposal-voucher-1',
      transactionId: 'disposal-transaction-1',
      debitEntryId: 'disposal-debit-1',
      creditEntryId: 'disposal-credit-1',
      inventoryAccountId: 'inventory-account',
      lossAccountId: 'loss-account',
      direction: direction,
      amountMinorUnits: amount,
      currency: currency,
      date: DateTime.utc(2026, 1, 1, 12),
      createdAt: DateTime.utc(2026, 1, 1, 12),
      reason: reason,
      reasonDetail: reasonDetail,
      reversalOfSourceId: reversalOfSourceId,
    );

void main() {
  group('BuildPosStockDisposalPostingUseCase', () {
    test('debits dedicated loss and credits inventory for disposal', () async {
      final result = await const BuildPosStockDisposalPostingUseCase()(
        _input(
          currency: _currency(),
          direction: PosStockMovementDirection.outbound,
          reasonDetail: 'Damaged during handling',
        ),
      );

      expect(result.isSuccess, isTrue);
      final posting = result.valueOrNull!;
      expect(posting.voucher.type, VoucherType.payment);
      expect(posting.voucher.counterpartyId.value, 'loss-account');
      expect(posting.voucher.affectedAccountId.value, 'inventory-account');
      expect(posting.entries, hasLength(2));
      expect(
        posting.entries.singleWhere((entry) => entry.side == EntrySide.debit)
            .accountId.value,
        'loss-account',
      );
      expect(
        posting.entries.singleWhere((entry) => entry.side == EntrySide.credit)
            .accountId.value,
        'inventory-account',
      );
      expect(
        posting.entries.map((entry) => entry.amount.minorUnits).toSet(),
        {1250},
      );
    });

    test('debit inventory and credit loss for a linked reversal', () async {
      final result = await const BuildPosStockDisposalPostingUseCase()(
        _input(
          currency: _currency(),
          direction: PosStockMovementDirection.inbound,
          reason: null,
          reversalOfSourceId: 'disposal-source-original',
        ),
      );

      expect(result.isSuccess, isTrue);
      final posting = result.valueOrNull!;
      expect(posting.voucher.type, VoucherType.receipt);
      expect(posting.entries, hasLength(2));
      expect(
        posting.entries.singleWhere((entry) => entry.side == EntrySide.debit)
            .accountId.value,
        'inventory-account',
      );
      expect(
        posting.entries.singleWhere((entry) => entry.side == EntrySide.credit)
            .accountId.value,
        'loss-account',
      );
    });

    test('requires detail for other and prevents using inventory as loss', () async {
      final useCase = const BuildPosStockDisposalPostingUseCase();
      final missingDetail = await useCase(
        _input(
          currency: _currency(),
          direction: PosStockMovementDirection.outbound,
          reason: PosStockDisposalReason.other,
        ),
      );
      final sameAccount = await useCase(
        BuildPosStockDisposalPostingInput(
          sourceId: 'source',
          voucherId: 'voucher',
          transactionId: 'tx',
          debitEntryId: 'debit',
          creditEntryId: 'credit',
          inventoryAccountId: 'inventory-account',
          lossAccountId: 'inventory-account',
          direction: PosStockMovementDirection.outbound,
          amountMinorUnits: 100,
          currency: _currency(),
          date: DateTime.utc(2026, 1, 1),
          createdAt: DateTime.utc(2026, 1, 1),
          reason: PosStockDisposalReason.damage,
        ),
      );

      expect(missingDetail.isFailure, isTrue);
      expect(sameAccount.isFailure, isTrue);
    });
  });
}
