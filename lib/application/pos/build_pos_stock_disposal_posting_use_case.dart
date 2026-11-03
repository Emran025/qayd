import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_stock_disposal_reason.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class BuildPosStockDisposalPostingInput {
  const BuildPosStockDisposalPostingInput({
    required this.sourceId,
    required this.voucherId,
    required this.transactionId,
    required this.debitEntryId,
    required this.creditEntryId,
    required this.inventoryAccountId,
    required this.lossAccountId,
    required this.direction,
    required this.amountMinorUnits,
    required this.currency,
    required this.date,
    required this.createdAt,
    this.reason,
    this.reasonDetail,
    this.reversalOfSourceId,
  });

  final String sourceId;
  final String voucherId;
  final String transactionId;
  final String debitEntryId;
  final String creditEntryId;
  final String inventoryAccountId;
  final String lossAccountId;
  final PosStockMovementDirection direction;
  final int amountMinorUnits;
  final CurrencyCode currency;
  final DateTime date;
  final DateTime createdAt;
  final PosStockDisposalReason? reason;
  final String? reasonDetail;
  final String? reversalOfSourceId;
}

/// Builds balanced, non-cash accounting lines strictly between inventory and
/// the dedicated inventory-loss account. It never posts revenue or COGS.
final class BuildPosStockDisposalPostingUseCase {
  const BuildPosStockDisposalPostingUseCase({
    EntryGenerator entryGenerator = const EntryGenerator(),
  }) : _entryGenerator = entryGenerator;

  final EntryGenerator _entryGenerator;

  Future<Result<PosAccountingPosting>> call(
    BuildPosStockDisposalPostingInput input,
  ) async {
    try {
      final sourceId = input.sourceId.trim();
      final inventoryId = input.inventoryAccountId.trim();
      final lossId = input.lossAccountId.trim();
      final reasonDetail = input.reasonDetail?.trim();
      final isReversal = input.direction == PosStockMovementDirection.inbound;
      if (sourceId.isEmpty || inventoryId.isEmpty || lossId.isEmpty) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posAccountingSourceRequired),
        );
      }
      if (inventoryId == lossId) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posAccountingAccountsDistinct),
        );
      }
      if (input.amountMinorUnits <= 0) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockAdjustmentValueRequired),
        );
      }
      if (isReversal) {
        if (input.reversalOfSourceId?.trim().isNotEmpty != true ||
            input.reason != null) {
          return FailureResult(
            ValidationFailure(messageAr: AppStrings.posStockDisposalInvalid),
          );
        }
      } else if (input.reason == null ||
          (input.reason == PosStockDisposalReason.other &&
              reasonDetail?.isNotEmpty != true)) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockDisposalInvalid),
        );
      }

      final description = isReversal
          ? AppStrings.posStockDisposalReversalVoucherDescription(
              input.reversalOfSourceId!.trim(),
            )
          : AppStrings.posStockDisposalVoucherDescription(
              AppStrings.posStockDisposalReasonLabel(input.reason!.code),
              reasonDetail,
            );
      final voucher = Voucher.draft(
        id: VoucherId(input.voucherId),
        type: isReversal ? VoucherType.receipt : VoucherType.payment,
        date: input.date,
        amount: Money.positiveAmount(input.amountMinorUnits, input.currency),
        currency: input.currency,
        counterpartyId: AccountId(lossId),
        affectedAccountId: AccountId(inventoryId),
        createdAt: input.createdAt,
        referenceNumber: sourceId,
        description: description,
      ).confirm(input.createdAt);
      final entries = _entryGenerator.generateForConfirmedVoucher(
        voucher: voucher,
        transactionId: TransactionId(input.transactionId),
        debitEntryId: EntryId(input.debitEntryId),
        creditEntryId: EntryId(input.creditEntryId),
        ledgerCreatedAt: input.createdAt,
      );
      return Success(
        PosAccountingPosting(
          sourceId: sourceId,
          voucher: voucher,
          entries: List.unmodifiable(entries),
        ),
      );
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }
}
