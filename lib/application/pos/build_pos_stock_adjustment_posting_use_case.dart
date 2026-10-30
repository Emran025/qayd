import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class BuildPosStockAdjustmentPostingInput {
  const BuildPosStockAdjustmentPostingInput({
    required this.sourceId,
    required this.voucherId,
    required this.transactionId,
    required this.debitEntryId,
    required this.creditEntryId,
    required this.inventoryAccountId,
    required this.counterAccountId,
    required this.direction,
    required this.amountMinorUnits,
    required this.currency,
    required this.reason,
    required this.date,
    required this.createdAt,
  });

  final String sourceId;
  final String voucherId;
  final String transactionId;
  final String debitEntryId;
  final String creditEntryId;
  final String inventoryAccountId;
  final String counterAccountId;
  final PosStockMovementDirection direction;
  final int amountMinorUnits;
  final CurrencyCode currency;
  final String reason;
  final DateTime date;
  final DateTime createdAt;
}

/// Builds a balanced voucher without performing any persistence.
///
/// For an increase, inventory is debited and the selected variance account is
/// credited. For a decrease, the selected variance account is debited and
/// inventory is credited.
final class BuildPosStockAdjustmentPostingUseCase {
  const BuildPosStockAdjustmentPostingUseCase({
    EntryGenerator entryGenerator = const EntryGenerator(),
  }) : _entryGenerator = entryGenerator;

  final EntryGenerator _entryGenerator;

  Future<Result<PosAccountingPosting>> call(
    BuildPosStockAdjustmentPostingInput input,
  ) async {
    try {
      final sourceId = input.sourceId.trim();
      final inventoryId = input.inventoryAccountId.trim();
      final counterId = input.counterAccountId.trim();
      final reason = input.reason.trim();
      if (sourceId.isEmpty) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posAccountingSourceRequired),
        );
      }
      if (inventoryId.isEmpty || counterId.isEmpty) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posAccountingAccountsRequired,
          ),
        );
      }
      if (inventoryId == counterId) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posAccountingAccountsDistinct,
          ),
        );
      }
      if (reason.isEmpty) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockAdjustmentReasonRequired),
        );
      }

      final inbound = input.direction == PosStockMovementDirection.inbound;
      final voucher = Voucher.draft(
        id: VoucherId(input.voucherId),
        type: inbound ? VoucherType.receipt : VoucherType.payment,
        date: input.date,
        amount: Money.positiveAmount(input.amountMinorUnits, input.currency),
        currency: input.currency,
        counterpartyId: AccountId(counterId),
        affectedAccountId: AccountId(inventoryId),
        createdAt: input.createdAt,
        referenceNumber: sourceId,
        description: AppStrings.posStockAdjustmentVoucherDescription(reason),
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
