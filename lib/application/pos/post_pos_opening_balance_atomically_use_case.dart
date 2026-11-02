import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/pos/build_pos_opening_balance_posting_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_stock_lot.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/pos_accounting_posting_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class PostPosOpeningBalanceInput {
  const PostPosOpeningBalanceInput({
    required this.productId,
    required this.quantityScaled,
    required this.quantityScale,
    required this.unitCostMinor,
    required this.currencyCode,
    required this.idempotencyKey,
    required this.sourceId,
    this.movementId,
    this.voucherId,
    this.transactionId,
    this.debitEntryId,
    this.creditEntryId,
    this.occurredAt,
    this.createdAt,
    this.batches = const [],
  });

  final String productId;
  final int quantityScaled;
  final int quantityScale;
  final int unitCostMinor;
  final String currencyCode;
  final String idempotencyKey;
  final String sourceId;
  final String? movementId;
  final String? voucherId;
  final String? transactionId;
  final String? debitEntryId;
  final String? creditEntryId;
  final DateTime? occurredAt;
  final DateTime? createdAt;
  final List<PostPosOpeningBalanceBatchInput> batches;
}

final class PostPosOpeningBalanceBatchInput {
  const PostPosOpeningBalanceBatchInput({
    required this.id,
    required this.quantity,
    required this.expiryDate,
    this.supplierLotNumber,
  });

  final String id;
  final PosQuantity quantity;
  final PosDate expiryDate;
  final String? supplierLotNumber;
}

/// Governed application orchestration for opening stock plus its bridge entry.
///
/// The use case owns policy and aggregate construction only. It never writes
/// SQL, vouchers, or ledger rows directly; the final write is delegated to the
/// atomic POS accounting repository.
final class PostPosOpeningBalanceAtomicallyUseCase {
  PostPosOpeningBalanceAtomicallyUseCase({
    required GovernanceWriteGuard writeGuard,
    required PosTemplateInstallationRepository installationRepository,
    required PosProductRepository productRepository,
    required AccountRepository accountRepository,
    required FiscalPeriodRepository fiscalPeriodRepository,
    required BuildPosOpeningBalancePostingUseCase buildPosting,
    required PosAccountingPostingRepository postingRepository,
    required IdGenerator idGenerator,
    PosTemplateDefinition? template,
  })  : _writeGuard = writeGuard,
        _installationRepository = installationRepository,
        _productRepository = productRepository,
        _accountRepository = accountRepository,
        _fiscalPeriodRepository = fiscalPeriodRepository,
        _buildPosting = buildPosting,
        _postingRepository = postingRepository,
        _idGenerator = idGenerator,
        _template = template ?? PosTemplateDefinition.current();

  final GovernanceWriteGuard _writeGuard;
  final PosTemplateInstallationRepository _installationRepository;
  final PosProductRepository _productRepository;
  final AccountRepository _accountRepository;
  final FiscalPeriodRepository _fiscalPeriodRepository;
  final BuildPosOpeningBalancePostingUseCase _buildPosting;
  final PosAccountingPostingRepository _postingRepository;
  final IdGenerator _idGenerator;
  final PosTemplateDefinition _template;

  Future<Result<void>> call(PostPosOpeningBalanceInput input) async {
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

      final inventoryId = installation
          .accountIdsByKey[PosTemplateAccountKey.inventoryAsset.value];
      final clearingId = installation
          .accountIdsByKey[PosTemplateAccountKey.openingBalanceClearing.value];
      if (inventoryId == null ||
          inventoryId.trim().isEmpty ||
          clearingId == null ||
          clearingId.trim().isEmpty) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.posAccountingAccountsRequired,
          ),
        );
      }
      final accountCheck = await _verifyAccounts(inventoryId, clearingId);
      if (accountCheck.isFailure) {
        return FailureResult(accountCheck.failureOrNull!);
      }

      final productResult = await _productRepository.getById(
        input.productId.trim(),
      );
      if (productResult.isFailure) {
        return FailureResult(productResult.failureOrNull!);
      }
      final product = productResult.valueOrNull!;
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
      if (product.expiryTracking) {
        final batchIds = <String>{};
        var allocated = 0;
        for (final batch in input.batches) {
          if (batch.id.trim().isEmpty ||
              !batchIds.add(batch.id.trim()) ||
              !batch.quantity.isPositive ||
              batch.quantity.scale != product.quantityScale) {
            return FailureResult(
              ValidationFailure(
                messageAr: AppStrings.posPurchaseBatchSumInvalid,
                code: 'pos_opening_balance_batches_invalid',
              ),
            );
          }
          allocated += batch.quantity.scaledUnits;
        }
        if (input.batches.isEmpty || allocated != input.quantityScaled) {
          return FailureResult(
            ValidationFailure(
              messageAr: input.batches.isEmpty
                  ? AppStrings.posPurchaseBatchExpiryRequired
                  : AppStrings.posPurchaseBatchSumInvalid,
              code: 'pos_opening_balance_batches_quantity_mismatch',
            ),
          );
        }
      } else if (input.batches.isNotEmpty) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.posInvoiceInvalid),
        );
      }

      final periodsResult = await _fiscalPeriodRepository.listAllOrdered();
      if (periodsResult.isFailure) {
        return FailureResult(periodsResult.failureOrNull!);
      }
      final date = (input.occurredAt ?? DateTime.now().toUtc()).toUtc();
      if (FiscalPeriodPolicy.voucherDateInClosedPeriod(
        periodsResult.valueOrNull!,
        date,
      )) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.voucherDateInClosedPeriod,
            code: 'pos_opening_balance_closed_period',
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
      final createdAt = (input.createdAt ?? date).toUtc();
      final unitCost = Money.nonNegative(input.unitCostMinor, product.currency);
      final movements = <PosStockMovement>[];
      final lots = <PosStockLot>[];
      if (product.expiryTracking) {
        for (var index = 0; index < input.batches.length; index++) {
          final batch = input.batches[index];
          final ordinal = (index + 1).toString().padLeft(6, '0');
          final lot = PosStockLot.create(
            id: batch.id,
            productId: product.id,
            warehouseId: installation.warehouseId,
            supplierLotNumber: batch.supplierLotNumber,
            expiryDate: batch.expiryDate,
            receivedQuantity: batch.quantity,
            unitCost: unitCost,
            createdAt: createdAt,
          );
          lots.add(lot);
          movements.add(
            PosStockMovement.create(
              id: '$sourceId:movement:$ordinal',
              productId: product.id,
              warehouseId: installation.warehouseId,
              type: PosStockMovementType.opening,
              direction: PosStockMovementDirection.inbound,
              quantity: batch.quantity,
              unitCost: unitCost,
              sourceType: 'opening_balance',
              sourceId: sourceId,
              lotId: lot.id,
              occurredAt: date,
              idempotencyKey: '$idempotencyKey:stock:$ordinal',
              createdAt: createdAt,
            ),
          );
        }
      } else {
        movements.add(
          PosStockMovement.create(
            id: input.movementId?.trim().isNotEmpty == true
                ? input.movementId!.trim()
                : _idGenerator.next(),
            productId: product.id,
            warehouseId: installation.warehouseId,
            type: PosStockMovementType.opening,
            direction: PosStockMovementDirection.inbound,
            quantity: PosQuantity.positive(
              input.quantityScaled,
              scale: product.quantityScale,
            ),
            unitCost: unitCost,
            sourceType: 'opening_balance',
            sourceId: sourceId,
            occurredAt: date,
            idempotencyKey: idempotencyKey,
            createdAt: createdAt,
          ),
        );
      }

      final postingResult = await _buildPosting(
        BuildPosOpeningBalancePostingInput(
          sourceId: sourceId,
          voucherId: input.voucherId?.trim().isNotEmpty == true
              ? input.voucherId!.trim()
              : _idGenerator.next(),
          transactionId: input.transactionId?.trim().isNotEmpty == true
              ? input.transactionId!.trim()
              : _idGenerator.next(),
          debitEntryId: input.debitEntryId?.trim().isNotEmpty == true
              ? input.debitEntryId!.trim()
              : _idGenerator.next(),
          creditEntryId: input.creditEntryId?.trim().isNotEmpty == true
              ? input.creditEntryId!.trim()
              : _idGenerator.next(),
          inventoryAccountId: inventoryId,
          clearingAccountId: clearingId,
          amountMinorUnits: _totalMinorUnits(
            input.quantityScaled,
            input.unitCostMinor,
            product.quantityScale,
          ),
          currency: product.currency,
          date: date,
          createdAt: createdAt,
        ),
      );
      if (postingResult.isFailure) {
        return FailureResult(postingResult.failureOrNull!);
      }
      final posting = postingResult.valueOrNull!;
      return await _postingRepository.saveOpeningBalance(
        movement: movements.first,
        additionalMovements: movements.skip(1).toList(growable: false),
        lots: lots,
        posting: posting,
      );
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  Future<Result<void>> _verifyAccounts(
    String inventoryId,
    String clearingId,
  ) async {
    for (final id in [inventoryId, clearingId]) {
      final result = await _accountRepository.getById(AccountId(id));
      if (result.isFailure) return FailureResult(result.failureOrNull!);
      final account = result.valueOrNull!;
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

  static int _totalMinorUnits(
    int quantityScaled,
    int unitCostMinor,
    int scale,
  ) {
    var divisor = 1;
    for (var index = 0; index < scale; index++) {
      divisor *= 10;
    }
    final product = quantityScaled * unitCostMinor;
    final quotient = product ~/ divisor;
    final remainder = product % divisor;
    return quotient + (remainder * 2 >= divisor ? 1 : 0);
  }
}
