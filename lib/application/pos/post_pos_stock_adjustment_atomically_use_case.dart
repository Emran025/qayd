import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/build_pos_stock_adjustment_posting_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
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
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class PostPosStockAdjustmentInput {
  const PostPosStockAdjustmentInput({
    required this.productId,
    required this.direction,
    required this.quantityScaled,
    required this.quantityScale,
    required this.currencyCode,
    required this.counterAccountId,
    required this.reason,
    required this.idempotencyKey,
    required this.sourceId,
    this.inboundUnitCostMinor,
    this.movementId,
    this.voucherId,
    this.transactionId,
    this.debitEntryId,
    this.creditEntryId,
    this.occurredAt,
    this.createdAt,
  });

  final String productId;
  final PosStockMovementDirection direction;
  final int quantityScaled;
  final int quantityScale;
  final String currencyCode;
  final String counterAccountId;
  final String reason;
  final String idempotencyKey;
  final String sourceId;
  /// Required only for inbound adjustments. Outbound adjustments use current
  /// weighted-average cost, revalidated inside the atomic transaction.
  final int? inboundUnitCostMinor;
  final String? movementId;
  final String? voucherId;
  final String? transactionId;
  final String? debitEntryId;
  final String? creditEntryId;
  final DateTime? occurredAt;
  final DateTime? createdAt;
}

/// Posts an append-only manual count variance with its accounting voucher.
///
/// No direct stock-only adjustment is made: stock movement, voucher and ledger
/// rows must all commit or all roll back through [PosAccountingPostingRepository].
final class PostPosStockAdjustmentAtomicallyUseCase {
  PostPosStockAdjustmentAtomicallyUseCase({
    required GovernanceWriteGuard writeGuard,
    required PosTemplateInstallationRepository installationRepository,
    required PosProductRepository productRepository,
    required PosStockMovementRepository stockRepository,
    required AccountRepository accountRepository,
    required FiscalPeriodRepository fiscalPeriodRepository,
    required BuildPosStockAdjustmentPostingUseCase buildPosting,
    required PosAccountingPostingRepository postingRepository,
    required IdGenerator idGenerator,
    PosTemplateDefinition? template,
  })  : _writeGuard = writeGuard,
        _installationRepository = installationRepository,
        _productRepository = productRepository,
        _stockRepository = stockRepository,
        _accountRepository = accountRepository,
        _fiscalPeriodRepository = fiscalPeriodRepository,
        _buildPosting = buildPosting,
        _postingRepository = postingRepository,
        _idGenerator = idGenerator,
        _template = template ?? PosTemplateDefinition.current();

  final GovernanceWriteGuard _writeGuard;
  final PosTemplateInstallationRepository _installationRepository;
  final PosProductRepository _productRepository;
  final PosStockMovementRepository _stockRepository;
  final AccountRepository _accountRepository;
  final FiscalPeriodRepository _fiscalPeriodRepository;
  final BuildPosStockAdjustmentPostingUseCase _buildPosting;
  final PosAccountingPostingRepository _postingRepository;
  final IdGenerator _idGenerator;
  final PosTemplateDefinition _template;

  Future<Result<void>> call(PostPosStockAdjustmentInput input) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) return FailureResult(gate.failureOrNull!);

      final installationResult =
          await _installationRepository.getEnabledInstallation(
        template: _template,
      );
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
      if (inventoryAccountId == null || inventoryAccountId.trim().isEmpty) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posAccountingAccountsRequired,
          ),
        );
      }
      final counterAccountId = input.counterAccountId.trim();
      if (counterAccountId.isEmpty || counterAccountId == inventoryAccountId) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posAccountingAccountsDistinct,
          ),
        );
      }
      final accounts = await _verifyAccounts(
        inventoryAccountId,
        counterAccountId,
      );
      if (accounts.isFailure) return FailureResult(accounts.failureOrNull!);

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
      if (!product.isActive) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posStockProductInactive),
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
      final reason = input.reason.trim();
      if (reason.isEmpty) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posStockAdjustmentReasonRequired,
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

      final date = (input.occurredAt ?? DateTime.now().toUtc()).toUtc();
      final periodsResult = await _fiscalPeriodRepository.listAllOrdered();
      if (periodsResult.isFailure) {
        return FailureResult(periodsResult.failureOrNull!);
      }
      if (FiscalPeriodPolicy.voucherDateInClosedPeriod(
        periodsResult.valueOrNull!,
        date,
      )) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.voucherDateInClosedPeriod,
            code: 'pos_stock_adjustment_closed_period',
          ),
        );
      }

      final balanceResult = await _stockRepository.getBalance(
        productId: product.id,
        warehouseId: installation.warehouseId,
      );
      if (balanceResult.isFailure) {
        return FailureResult(balanceResult.failureOrNull!);
      }
      final balance = balanceResult.valueOrNull!;
      final quantity = PosQuantity.positive(
        input.quantityScaled,
        scale: product.quantityScale,
      );
      final inbound = input.direction == PosStockMovementDirection.inbound;
      final unitCostMinor = inbound
          ? input.inboundUnitCostMinor
          : balance.averageUnitCost.minorUnits;
      if (unitCostMinor == null || unitCostMinor <= 0) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posStockAdjustmentValueRequired,
          ),
        );
      }
      final unitCost = Money.positiveAmount(unitCostMinor, product.currency);
      final movement = PosStockMovement.create(
        id: _resolveId(input.movementId),
        productId: product.id,
        warehouseId: installation.warehouseId,
        type: PosStockMovementType.adjustment,
        direction: input.direction,
        quantity: quantity,
        unitCost: unitCost,
        sourceType: 'manual_adjustment',
        sourceId: sourceId,
        occurredAt: date,
        idempotencyKey: idempotencyKey,
        createdAt: (input.createdAt ?? date).toUtc(),
      );
      // Preflight for helpful errors; the repository repeats this check inside
      // its write transaction to protect against concurrent stock changes.
      balance.apply(movement);
      final amount = PosMoneyMath.multiply(quantity, unitCost);
      if (amount.minorUnits <= 0) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posStockAdjustmentValueRequired,
          ),
        );
      }
      final createdAt = (input.createdAt ?? date).toUtc();
      final postingResult = await _buildPosting(
        BuildPosStockAdjustmentPostingInput(
          sourceId: sourceId,
          voucherId: _resolveId(input.voucherId),
          transactionId: _resolveId(input.transactionId),
          debitEntryId: _resolveId(input.debitEntryId),
          creditEntryId: _resolveId(input.creditEntryId),
          inventoryAccountId: inventoryAccountId,
          counterAccountId: counterAccountId,
          direction: input.direction,
          amountMinorUnits: amount.minorUnits,
          currency: product.currency,
          reason: reason,
          date: date,
          createdAt: createdAt,
        ),
      );
      if (postingResult.isFailure) {
        return FailureResult(postingResult.failureOrNull!);
      }
      return await _postingRepository.saveStockAdjustmentAtomically(
        movement: movement,
        posting: postingResult.valueOrNull!,
      );
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  String _resolveId(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim() : _idGenerator.next();

  Future<Result<void>> _verifyAccounts(
    String inventoryId,
    String counterId,
  ) async {
    for (final id in [inventoryId, counterId]) {
      final result = await _accountRepository.getById(AccountId(id));
      if (result.isFailure) return FailureResult(result.failureOrNull!);
      final account = result.valueOrNull;
      if (account == null) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posAccountingAccountsRequired,
          ),
        );
      }
      if (!account.isActive || account.isArchived) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posAccountingAccountsRequired,
          ),
        );
      }
    }
    return const Success(null);
  }
}
