import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/build_pos_stock_disposal_posting_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/pos_accounting_posting_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/pos_stock_disposal_reason.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class PostPosStockDisposalInput {
  const PostPosStockDisposalInput({
    required this.productId,
    required this.warehouseId,
    required this.reason,
    required this.quantityScaled,
    required this.quantityScale,
    required this.currencyCode,
    required this.sourceId,
    required this.idempotencyKey,
    this.reasonDetail,
    this.lotId,
    this.movementId,
    this.voucherId,
    this.transactionId,
    this.debitEntryId,
    this.creditEntryId,
    this.occurredAt,
    this.createdAt,
  });

  final String productId;
  final String warehouseId;
  final PosStockDisposalReason reason;
  final int quantityScaled;
  final int quantityScale;
  final String currencyCode;
  final String sourceId;
  final String idempotencyKey;
  final String? reasonDetail;
  final String? lotId;
  final String? movementId;
  final String? voucherId;
  final String? transactionId;
  final String? debitEntryId;
  final String? creditEntryId;
  final DateTime? occurredAt;
  final DateTime? createdAt;
}

final class ReversePosStockDisposalInput {
  const ReversePosStockDisposalInput({
    required this.originalSourceId,
    required this.sourceId,
    required this.idempotencyKey,
    required this.reasonDetail,
    this.movementId,
    this.voucherId,
    this.transactionId,
    this.debitEntryId,
    this.creditEntryId,
    this.occurredAt,
    this.createdAt,
  });

  final String originalSourceId;
  final String sourceId;
  final String idempotencyKey;
  final String reasonDetail;
  final String? movementId;
  final String? voucherId;
  final String? transactionId;
  final String? debitEntryId;
  final String? creditEntryId;
  final DateTime? occurredAt;
  final DateTime? createdAt;
}

/// Posts damaged, expired, or authorized inventory loss as an immutable stock
/// movement, its lot projection, and a balanced loss voucher in one transaction.
final class PostPosStockDisposalAtomicallyUseCase {
  PostPosStockDisposalAtomicallyUseCase({
    required GovernanceWriteGuard writeGuard,
    required PosTemplateInstallationRepository installationRepository,
    required PosProductRepository productRepository,
    required PosStockMovementRepository stockRepository,
    required AccountRepository accountRepository,
    required FiscalPeriodRepository fiscalPeriodRepository,
    required BuildPosStockDisposalPostingUseCase buildPosting,
    required PosAccountingPostingRepository postingRepository,
    PosTemplateDefinition? template,
  })  : _writeGuard = writeGuard,
        _installationRepository = installationRepository,
        _productRepository = productRepository,
        _stockRepository = stockRepository,
        _accountRepository = accountRepository,
        _fiscalPeriodRepository = fiscalPeriodRepository,
        _buildPosting = buildPosting,
        _postingRepository = postingRepository,
        _template = template ?? PosTemplateDefinition.current();

  final GovernanceWriteGuard _writeGuard;
  final PosTemplateInstallationRepository _installationRepository;
  final PosProductRepository _productRepository;
  final PosStockMovementRepository _stockRepository;
  final AccountRepository _accountRepository;
  final FiscalPeriodRepository _fiscalPeriodRepository;
  final BuildPosStockDisposalPostingUseCase _buildPosting;
  final PosAccountingPostingRepository _postingRepository;
  final PosTemplateDefinition _template;

  Future<Result<void>> call(PostPosStockDisposalInput input) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) return FailureResult(gate.failureOrNull!);

      final installationResult = await _installationRepository
          .getEnabledInstallation(template: _template);
      if (installationResult.isFailure) {
        return FailureResult(installationResult.failureOrNull!);
      }
      final installation = installationResult.valueOrNull;
      if (installation == null) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posWarehouseUnavailable),
        );
      }
      final warehouseId = input.warehouseId.trim();
      if (warehouseId.isEmpty || warehouseId != installation.warehouseId) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posStockDisposalWarehouseMismatch,
          ),
        );
      }
      final sourceId = input.sourceId.trim();
      final idempotencyKey = input.idempotencyKey.trim();
      if (sourceId.isEmpty || idempotencyKey.isEmpty) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posAccountingSourceRequired),
        );
      }
      final existingResult = await _stockRepository.getByIdempotencyKey(
        idempotencyKey,
      );
      if (existingResult.isFailure) {
        return FailureResult(existingResult.failureOrNull!);
      }
      final existingMovement = existingResult.valueOrNull;
      final reasonDetail = input.reasonDetail?.trim();
      if ((reasonDetail?.length ?? 0) > 500) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockDisposalInvalid),
        );
      }
      if (input.reason == PosStockDisposalReason.other &&
          (reasonDetail == null || reasonDetail.isEmpty)) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posStockDisposalOtherDetailRequired,
          ),
        );
      }

      final inventoryAccountId = installation
          .accountIdsByKey[PosTemplateAccountKey.inventoryAsset.value];
      final lossAccountId = installation.accountIdsByKey[
          PosTemplateAccountKey.inventoryLossExpense.value];
      if (inventoryAccountId == null || inventoryAccountId.trim().isEmpty ||
          lossAccountId == null || lossAccountId.trim().isEmpty) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posStockDisposalLossAccountRequired,
          ),
        );
      }
      if (existingMovement != null) {
        return _replayExistingDisposal(
          input: input,
          existing: existingMovement,
          inventoryAccountId: inventoryAccountId,
          lossAccountId: lossAccountId,
          sourceId: sourceId,
          idempotencyKey: idempotencyKey,
          reasonDetail: reasonDetail,
          warehouseId: warehouseId,
        );
      }
      final accountResult = await _verifyAccounts(
        inventoryAccountId,
        lossAccountId,
      );
      if (accountResult.isFailure) {
        return FailureResult(accountResult.failureOrNull!);
      }
      final productResult =
          await _productRepository.getById(input.productId.trim());
      if (productResult.isFailure) {
        return FailureResult(productResult.failureOrNull!);
      }
      final product = productResult.valueOrNull;
      if (product == null) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posProductNotFound),
        );
      }
      if (input.currencyCode.trim() != product.currency.code) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockCurrencyMismatch),
        );
      }
      if (input.quantityScale != product.quantityScale) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockScaleMismatch),
        );
      }
      final date = (input.occurredAt ?? DateTime.now()).toUtc();
      final periodResult = await _validateOpenPeriod(date);
      if (periodResult.isFailure) {
        return FailureResult(periodResult.failureOrNull!);
      }

      final quantity = PosQuantity.positive(
        input.quantityScaled,
        scale: product.quantityScale,
      );
      final balanceResult = await _stockRepository.getBalance(
        productId: product.id,
        warehouseId: warehouseId,
      );
      if (balanceResult.isFailure) {
        return FailureResult(balanceResult.failureOrNull!);
      }
      final balance = balanceResult.valueOrNull!;
      final selectedLotId = input.lotId?.trim().isNotEmpty == true
          ? input.lotId!.trim()
          : null;
      if (product.expiryTracking ||
          input.reason == PosStockDisposalReason.expiry) {
        if (selectedLotId == null) {
          return FailureResult(
            ValidationFailure(
              messageAr: AppStrings.posStockDisposalExpiryLotRequired,
            ),
          );
        }
      }
      if (input.reason == PosStockDisposalReason.expiry &&
          !product.expiryTracking) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posStockDisposalExpiryLotRequired,
          ),
        );
      }
      if (selectedLotId != null) {
        final lotsResult = await _stockRepository.getDisposalLots(
          productId: product.id,
          warehouseId: warehouseId,
        );
        if (lotsResult.isFailure) {
          return FailureResult(lotsResult.failureOrNull!);
        }
        final selectedLot = lotsResult.valueOrNull!
            .where((lot) => lot.id == selectedLotId)
            .firstOrNull;
        if (selectedLot == null ||
            selectedLot.productId != product.id ||
            selectedLot.warehouseId != warehouseId ||
            selectedLot.remainingQuantity.scale != product.quantityScale) {
          return FailureResult(
            ValidationFailure(messageAr: AppStrings.posStockLotProjectionMismatch),
          );
        }
        if (quantity.scaledUnits >
            selectedLot.remainingQuantity.scaledUnits) {
          return FailureResult(
            ValidationFailure(messageAr: AppStrings.posStockLotsInsufficient),
          );
        }
        final expiry = selectedLot.expiryDate;
        final businessDate = PosDate.fromDateTime(date.toLocal());
        if (input.reason == PosStockDisposalReason.expiry &&
            (expiry == null || !expiry.isBefore(businessDate))) {
          return FailureResult(
            ValidationFailure(messageAr: AppStrings.posStockDisposalNotExpired),
          );
        }
        if (input.reason == PosStockDisposalReason.damage &&
            expiry != null &&
            expiry.isBefore(businessDate)) {
          return FailureResult(
            ValidationFailure(messageAr: AppStrings.posStockDisposalBatchExpired),
          );
        }
      }

      // Lot selection validates eligibility and quantity; POS valuation remains
      // weighted-average, matching the inventory cost policy.
      final unitCost = balance.averageUnitCost;
      if (unitCost.minorUnits <= 0) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockAdjustmentValueRequired),
        );
      }
      final amount = PosMoneyMath.multiply(quantity, unitCost);
      if (amount.minorUnits <= 0) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockAdjustmentValueRequired),
        );
      }
      final createdAt = (input.createdAt ?? date).toUtc();
      final voucherId = _resolveId(input.voucherId, idempotencyKey, 'voucher');
      final movement = PosStockMovement.create(
        id: _resolveId(input.movementId, idempotencyKey, 'movement'),
        productId: product.id,
        warehouseId: warehouseId,
        type: _movementType(input.reason),
        direction: PosStockMovementDirection.outbound,
        quantity: quantity,
        unitCost: unitCost,
        sourceType: 'stock_disposal',
        sourceId: sourceId,
        lotId: selectedLotId,
        disposalReason: input.reason,
        reasonDetail: reasonDetail,
        voucherId: voucherId,
        occurredAt: date,
        idempotencyKey: idempotencyKey,
        createdAt: createdAt,
      );
      balance.apply(movement);
      final postingResult = await _buildPosting(
        BuildPosStockDisposalPostingInput(
          sourceId: sourceId,
          voucherId: voucherId,
          transactionId: _resolveId(
            input.transactionId,
            idempotencyKey,
            'transaction',
          ),
          debitEntryId: _resolveId(
            input.debitEntryId,
            idempotencyKey,
            'debit',
          ),
          creditEntryId: _resolveId(
            input.creditEntryId,
            idempotencyKey,
            'credit',
          ),
          inventoryAccountId: inventoryAccountId,
          lossAccountId: lossAccountId,
          direction: PosStockMovementDirection.outbound,
          amountMinorUnits: amount.minorUnits,
          currency: product.currency,
          date: date,
          createdAt: createdAt,
          reason: input.reason,
          reasonDetail: reasonDetail,
        ),
      );
      if (postingResult.isFailure) {
        return FailureResult(postingResult.failureOrNull!);
      }
      return await _postingRepository.saveStockDisposalAtomically(
        movement: movement,
        posting: postingResult.valueOrNull!,
      );
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  /// Reverses one full disposal with an inbound adjustment and a balanced
  /// inventory-debit/loss-credit voucher linked to the original source.
  Future<Result<void>> reverse(ReversePosStockDisposalInput input) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) return FailureResult(gate.failureOrNull!);
      final installationResult = await _installationRepository
          .getEnabledInstallation(template: _template);
      if (installationResult.isFailure) {
        return FailureResult(installationResult.failureOrNull!);
      }
      final installation = installationResult.valueOrNull;
      if (installation == null) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posWarehouseUnavailable),
        );
      }
      final inventoryAccountId = installation
          .accountIdsByKey[PosTemplateAccountKey.inventoryAsset.value];
      final lossAccountId = installation.accountIdsByKey[
          PosTemplateAccountKey.inventoryLossExpense.value];
      if (inventoryAccountId == null || inventoryAccountId.trim().isEmpty ||
          lossAccountId == null || lossAccountId.trim().isEmpty) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posStockDisposalLossAccountRequired,
          ),
        );
      }
      final originalSourceId = input.originalSourceId.trim();
      final sourceId = input.sourceId.trim();
      final idempotencyKey = input.idempotencyKey.trim();
      final note = input.reasonDetail.trim();
      if (originalSourceId.isEmpty || sourceId.isEmpty ||
          sourceId == originalSourceId || idempotencyKey.isEmpty || note.isEmpty) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockDisposalReverseNoteRequired),
        );
      }
      if (note.length > 500) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockDisposalInvalid),
        );
      }
      final existingResult = await _stockRepository.getByIdempotencyKey(
        idempotencyKey,
      );
      if (existingResult.isFailure) {
        return FailureResult(existingResult.failureOrNull!);
      }
      final existingMovement = existingResult.valueOrNull;
      if (existingMovement != null) {
        return _replayExistingReversal(
          input: input,
          existing: existingMovement,
          originalSourceId: originalSourceId,
          sourceId: sourceId,
          idempotencyKey: idempotencyKey,
          note: note,
          inventoryAccountId: inventoryAccountId,
          lossAccountId: lossAccountId,
        );
      }
      final accountResult = await _verifyAccounts(
        inventoryAccountId,
        lossAccountId,
      );
      if (accountResult.isFailure) {
        return FailureResult(accountResult.failureOrNull!);
      }
      final date = (input.occurredAt ?? DateTime.now()).toUtc();
      final periodResult = await _validateOpenPeriod(date);
      if (periodResult.isFailure) {
        return FailureResult(periodResult.failureOrNull!);
      }
      final originals = await _stockRepository.listMovementsForSource(
        sourceType: 'stock_disposal',
        sourceId: originalSourceId,
      );
      if (originals.isFailure) {
        return FailureResult(originals.failureOrNull!);
      }
      final originalMovements = originals.valueOrNull!;
      if (originalMovements.length != 1) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockDisposalInvalid),
        );
      }
      final original = originalMovements.single;
      if (original.direction != PosStockMovementDirection.outbound ||
          original.disposalReason == null ||
          original.voucherId == null) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockDisposalInvalid),
        );
      }
      final amount = PosMoneyMath.multiply(original.quantity, original.unitCost);
      if (amount.minorUnits <= 0) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockDisposalInvalid),
        );
      }
      final createdAt = (input.createdAt ?? date).toUtc();
      final voucherId = _resolveId(input.voucherId, idempotencyKey, 'voucher');
      final movement = PosStockMovement.create(
        id: _resolveId(input.movementId, idempotencyKey, 'movement'),
        productId: original.productId,
        warehouseId: original.warehouseId,
        type: PosStockMovementType.adjustment,
        direction: PosStockMovementDirection.inbound,
        quantity: original.quantity,
        unitCost: original.unitCost,
        sourceType: 'stock_disposal_reversal',
        sourceId: sourceId,
        lotId: original.lotId,
        reasonDetail: note,
        voucherId: voucherId,
        reversesSourceId: originalSourceId,
        occurredAt: date,
        idempotencyKey: idempotencyKey,
        createdAt: createdAt,
      );
      final postingResult = await _buildPosting(
        BuildPosStockDisposalPostingInput(
          sourceId: sourceId,
          voucherId: voucherId,
          transactionId: _resolveId(
            input.transactionId,
            idempotencyKey,
            'transaction',
          ),
          debitEntryId: _resolveId(input.debitEntryId, idempotencyKey, 'debit'),
          creditEntryId:
              _resolveId(input.creditEntryId, idempotencyKey, 'credit'),
          inventoryAccountId: inventoryAccountId,
          lossAccountId: lossAccountId,
          direction: PosStockMovementDirection.inbound,
          amountMinorUnits: amount.minorUnits,
          currency: original.unitCost.currency,
          date: date,
          createdAt: createdAt,
          reversalOfSourceId: originalSourceId,
        ),
      );
      if (postingResult.isFailure) {
        return FailureResult(postingResult.failureOrNull!);
      }
      return await _postingRepository.saveStockDisposalAtomically(
        movement: movement,
        posting: postingResult.valueOrNull!,
      );
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
      }
  }

  Future<Result<void>> _replayExistingReversal({
    required ReversePosStockDisposalInput input,
    required PosStockMovement existing,
    required String originalSourceId,
    required String sourceId,
    required String idempotencyKey,
    required String note,
    required String inventoryAccountId,
    required String lossAccountId,
  }) async {
    try {
      final date = (input.occurredAt ?? existing.occurredAt).toUtc();
      final createdAt = (input.createdAt ?? existing.createdAt).toUtc();
      final voucherId = _resolveId(input.voucherId, idempotencyKey, 'voucher');
      final movement = PosStockMovement.create(
        id: _resolveId(input.movementId, idempotencyKey, 'movement'),
        productId: existing.productId,
        warehouseId: existing.warehouseId,
        type: PosStockMovementType.adjustment,
        direction: PosStockMovementDirection.inbound,
        quantity: existing.quantity,
        unitCost: existing.unitCost,
        sourceType: 'stock_disposal_reversal',
        sourceId: sourceId,
        lotId: existing.lotId,
        reasonDetail: note,
        voucherId: voucherId,
        reversesSourceId: originalSourceId,
        occurredAt: date,
        idempotencyKey: idempotencyKey,
        createdAt: createdAt,
      );
      final amount = PosMoneyMath.multiply(existing.quantity, existing.unitCost);
      if (amount.minorUnits <= 0) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockDisposalInvalid),
        );
      }
      final postingResult = await _buildPosting(
        BuildPosStockDisposalPostingInput(
          sourceId: sourceId,
          voucherId: voucherId,
          transactionId: _resolveId(
            input.transactionId,
            idempotencyKey,
            'transaction',
          ),
          debitEntryId: _resolveId(input.debitEntryId, idempotencyKey, 'debit'),
          creditEntryId:
              _resolveId(input.creditEntryId, idempotencyKey, 'credit'),
          inventoryAccountId: inventoryAccountId,
          lossAccountId: lossAccountId,
          direction: PosStockMovementDirection.inbound,
          amountMinorUnits: amount.minorUnits,
          currency: existing.unitCost.currency,
          date: date,
          createdAt: createdAt,
          reversalOfSourceId: originalSourceId,
        ),
      );
      if (postingResult.isFailure) {
        return FailureResult(postingResult.failureOrNull!);
      }
      return await _postingRepository.saveStockDisposalAtomically(
        movement: movement,
        posting: postingResult.valueOrNull!,
      );
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  Future<Result<void>> _replayExistingDisposal({
    required PostPosStockDisposalInput input,
    required PosStockMovement existing,
    required String inventoryAccountId,
    required String lossAccountId,
    required String sourceId,
    required String idempotencyKey,
    required String? reasonDetail,
    required String warehouseId,
  }) async {
    try {
      if (input.currencyCode.trim() != existing.unitCost.currency.code) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockCurrencyMismatch),
        );
      }
      final quantity = PosQuantity.positive(
        input.quantityScaled,
        scale: input.quantityScale,
      );
      final date = (input.occurredAt ?? existing.occurredAt).toUtc();
      final createdAt = (input.createdAt ?? existing.createdAt).toUtc();
      final voucherId = _resolveId(input.voucherId, idempotencyKey, 'voucher');
      final movement = PosStockMovement.create(
        id: _resolveId(input.movementId, idempotencyKey, 'movement'),
        productId: input.productId.trim(),
        warehouseId: warehouseId,
        type: _movementType(input.reason),
        direction: PosStockMovementDirection.outbound,
        quantity: quantity,
        unitCost: existing.unitCost,
        sourceType: 'stock_disposal',
        sourceId: sourceId,
        lotId: input.lotId?.trim().isNotEmpty == true
            ? input.lotId!.trim()
            : null,
        disposalReason: input.reason,
        reasonDetail: reasonDetail,
        voucherId: voucherId,
        occurredAt: date,
        idempotencyKey: idempotencyKey,
        createdAt: createdAt,
      );
      final amount = PosMoneyMath.multiply(quantity, existing.unitCost);
      if (amount.minorUnits <= 0) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockAdjustmentValueRequired),
        );
      }
      final postingResult = await _buildPosting(
        BuildPosStockDisposalPostingInput(
          sourceId: sourceId,
          voucherId: voucherId,
          transactionId: _resolveId(
            input.transactionId,
            idempotencyKey,
            'transaction',
          ),
          debitEntryId: _resolveId(input.debitEntryId, idempotencyKey, 'debit'),
          creditEntryId:
              _resolveId(input.creditEntryId, idempotencyKey, 'credit'),
          inventoryAccountId: inventoryAccountId,
          lossAccountId: lossAccountId,
          direction: PosStockMovementDirection.outbound,
          amountMinorUnits: amount.minorUnits,
          currency: existing.unitCost.currency,
          date: date,
          createdAt: createdAt,
          reason: input.reason,
          reasonDetail: reasonDetail,
        ),
      );
      if (postingResult.isFailure) {
        return FailureResult(postingResult.failureOrNull!);
      }
      return await _postingRepository.saveStockDisposalAtomically(
        movement: movement,
        posting: postingResult.valueOrNull!,
      );
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  Future<Result<void>> _validateOpenPeriod(DateTime date) async {
    final result = await _fiscalPeriodRepository.listAllOrdered();
    if (result.isFailure) return FailureResult(result.failureOrNull!);
    if (FiscalPeriodPolicy.voucherDateInClosedPeriod(result.valueOrNull!, date)) {
      return FailureResult(
        ValidationFailure(
          messageAr: AppStrings.voucherDateInClosedPeriod,
          code: 'pos_stock_disposal_closed_period',
        ),
      );
    }
    return const Success(null);
  }

  Future<Result<void>> _verifyAccounts(
    String inventoryId,
    String lossId,
  ) async {
    if (inventoryId.trim() == lossId.trim()) {
      return FailureResult(
        ValidationFailure(messageAr: AppStrings.posAccountingAccountsDistinct),
      );
    }
    for (final id in [inventoryId, lossId]) {
      final result = await _accountRepository.getById(AccountId(id));
      if (result.isFailure) return FailureResult(result.failureOrNull!);
      final account = result.valueOrNull;
      if (account == null ||
          !account.isActive ||
          account.isArchived ||
          account.nature != AccountNature.debit) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posStockDisposalLossAccountRequired,
          ),
        );
      }
    }
    return const Success(null);
  }

  static PosStockMovementType _movementType(PosStockDisposalReason reason) {
    return switch (reason) {
      PosStockDisposalReason.damage => PosStockMovementType.damage,
      PosStockDisposalReason.expiry => PosStockMovementType.expiry,
      PosStockDisposalReason.authorizedLoss => PosStockMovementType.adjustment,
      PosStockDisposalReason.other => PosStockMovementType.adjustment,
    };
  }

  static String _resolveId(String? value, String key, String suffix) {
    final normalized = value?.trim();
    return normalized != null && normalized.isNotEmpty
        ? normalized
        : '$key:$suffix';
  }
}
