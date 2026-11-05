import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/entities/pos_invoice_line_conversion.dart';
import 'package:qayd/domain/entities/pos_purchase_return_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/pos_invoice_read_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class BuildPosPurchaseReturnLineInput {
  const BuildPosPurchaseReturnLineInput({
    required this.sourceLineId,
    required this.quantity,
  });

  final String sourceLineId;
  final PosQuantity quantity;
}

final class BuildPosPurchaseReturnPostingInput {
  const BuildPosPurchaseReturnPostingInput({
    required this.returnInvoiceId,
    required this.returnInvoiceNumber,
    required this.sourceInvoiceId,
    required this.idempotencyKey,
    required this.lines,
    required this.invoiceDate,
    required this.createdAt,
    this.reason,
  });

  final String returnInvoiceId;
  final String returnInvoiceNumber;
  final String sourceInvoiceId;
  final String idempotencyKey;
  final List<BuildPosPurchaseReturnLineInput> lines;
  final DateTime invoiceDate;
  final DateTime createdAt;
  final String? reason;
}

/// Builds a supplier credit note against a posted purchase without writing.
///
/// Returns use the original invoice's net line amounts for the supplier credit
/// and the current weighted-average cost for stock/Inventory valuation. Any
/// difference is posted to the configured POS purchase-returns variance
/// account. A return always creates supplier credit; it never refunds cash.
final class BuildPosPurchaseReturnPostingUseCase {
  BuildPosPurchaseReturnPostingUseCase({
    required PosInvoiceReadRepository invoiceRepository,
    required PosTemplateInstallationRepository installationRepository,
    required PosStockMovementRepository stockRepository,
    required AccountRepository accountRepository,
    EntryGenerator entryGenerator = const EntryGenerator(),
  }) : _invoices = invoiceRepository,
       _installation = installationRepository,
       _stock = stockRepository,
       _accounts = accountRepository,
       _entries = entryGenerator;

  final PosInvoiceReadRepository _invoices;
  final PosTemplateInstallationRepository _installation;
  final PosStockMovementRepository _stock;
  final AccountRepository _accounts;
  final EntryGenerator _entries;

  Future<Result<PosPurchaseReturnPosting>> call(
    BuildPosPurchaseReturnPostingInput input,
  ) async {
    try {
      if (input.returnInvoiceId.trim().isEmpty ||
          input.returnInvoiceNumber.trim().isEmpty ||
          input.sourceInvoiceId.trim().isEmpty ||
          input.idempotencyKey.trim().isEmpty ||
          input.lines.isEmpty) {
        return _invalid('pos_purchase_return_input_invalid');
      }
      final requested = <String, PosQuantity>{};
      for (final line in input.lines) {
        final key = line.sourceLineId.trim();
        if (key.isEmpty ||
            !line.quantity.isPositive ||
            requested.containsKey(key)) {
          return _invalid('pos_purchase_return_lines_invalid');
        }
        requested[key] = line.quantity;
      }

      final sourceResult = await _invoices.getById(input.sourceInvoiceId);
      if (sourceResult.isFailure) {
        return FailureResult(sourceResult.failureOrNull!);
      }
      final sourceDetails = sourceResult.valueOrNull;
      if (sourceDetails == null) {
        return _invalid('pos_purchase_return_source_not_found');
      }
      final source = sourceDetails.invoice;
      if (source.type != PosInvoiceType.purchase ||
          source.status == PosDocumentStatus.voided ||
          source.status == PosDocumentStatus.fullyReturned ||
          source.postedAt == null) {
        return _invalid('pos_purchase_return_source_status_invalid');
      }
      if (!source.tax.isZero) {
        return _invalid('pos_purchase_return_tax_account_required');
      }
      final supplierId = source.counterpartyAccountId;
      if (supplierId == null) {
        return _invalid('pos_purchase_return_supplier_required');
      }
      final supplierResult = await _requireActiveAccount(supplierId);
      if (supplierResult.isFailure) {
        return FailureResult(supplierResult.failureOrNull!);
      }

      final priorResult = await _invoices.getReturnsForSource(source.id);
      if (priorResult.isFailure) {
        return FailureResult(priorResult.failureOrNull!);
      }
      final priorReturns = priorResult.valueOrNull!;
      final priorQuantity = <String, int>{};
      final priorLineDiscount = <String, int>{};
      final priorLineTax = <String, int>{};
      var priorGross = 0;
      var priorGlobalDiscount = 0;
      var priorGlobalTax = 0;
      final sourceById = <String, PosInvoiceLine>{
        for (final line in source.lines) line.id: line,
      };
      for (final details in priorReturns) {
        final prior = details.invoice;
        if (prior.type != PosInvoiceType.purchaseReturn ||
            prior.sourceInvoiceId != source.id ||
            prior.status != PosDocumentStatus.posted ||
            prior.currency != source.currency ||
            prior.warehouseId != source.warehouseId ||
            prior.counterpartyAccountId != supplierId ||
            prior.paid.minorUnits != 0 ||
            prior.due.minorUnits != prior.total.minorUnits) {
          return _invalid('pos_purchase_return_history_invalid');
        }
        priorGross += prior.subtotal.minorUnits;
        priorGlobalDiscount += prior.cartDiscount.minorUnits;
        priorGlobalTax +=
            prior.tax.minorUnits -
            prior.lines.fold<int>(0, (sum, line) => sum + line.tax.minorUnits);
        for (final line in prior.lines) {
          final sourceLineId = line.sourceLineId;
          final original = sourceLineId == null
              ? null
              : sourceById[sourceLineId];
          if (original == null ||
              line.productId != original.productId ||
              line.quantity.scale != original.quantity.scale ||
              line.unitPrice != original.unitPrice ||
              line.unitCost != original.unitCost) {
            return _invalid('pos_purchase_return_history_invalid');
          }
          priorQuantity.update(
            sourceLineId!,
            (value) => value + line.quantity.scaledUnits,
            ifAbsent: () => line.quantity.scaledUnits,
          );
          priorLineDiscount.update(
            sourceLineId,
            (value) => value + line.discount.minorUnits,
            ifAbsent: () => line.discount.minorUnits,
          );
          priorLineTax.update(
            sourceLineId,
            (value) => value + line.tax.minorUnits,
            ifAbsent: () => line.tax.minorUnits,
          );
        }
      }

      final installationResult = await _installation.getEnabledInstallation(
        template: PosTemplateDefinition.current(),
      );
      if (installationResult.isFailure) {
        return FailureResult(installationResult.failureOrNull!);
      }
      final installation = installationResult.valueOrNull;
      if (installation == null ||
          installation.warehouseId != source.warehouseId) {
        return _invalid('pos_purchase_return_not_enabled');
      }
      final inventoryAccount = _account(
        installation,
        PosTemplateAccountKey.inventoryAsset,
      );
      final supplierPayablesAccount = _account(
        installation,
        PosTemplateAccountKey.supplierPayables,
      );
      final purchaseReturnsAccount = _account(
        installation,
        PosTemplateAccountKey.purchaseReturns,
      );
      if (inventoryAccount == null ||
          supplierPayablesAccount == null ||
          purchaseReturnsAccount == null ||
          inventoryAccount == supplierPayablesAccount ||
          inventoryAccount == purchaseReturnsAccount ||
          supplierPayablesAccount == purchaseReturnsAccount) {
        return _invalid('pos_purchase_return_accounts_missing');
      }
      for (final account in <AccountId>[
        inventoryAccount,
        supplierPayablesAccount,
        purchaseReturnsAccount,
      ]) {
        final result = await _requireActiveAccount(account);
        if (result.isFailure) return FailureResult(result.failureOrNull!);
      }

      final sourceMovementsResult = await _stock.listMovementsForSource(
        sourceType: 'pos_invoice',
        sourceId: source.id,
        type: PosStockMovementType.purchase,
      );
      if (sourceMovementsResult.isFailure) {
        return FailureResult(sourceMovementsResult.failureOrNull!);
      }
      final sourceMovements = sourceMovementsResult.valueOrNull!;
      final sourceMovementsByLine = <String, List<PosStockMovement>>{};
      for (final movement in sourceMovements) {
        final lineId = movement.sourceLineId;
        if (lineId == null ||
            movement.sourceType != 'pos_invoice' ||
            movement.sourceId != source.id ||
            movement.type != PosStockMovementType.purchase ||
            movement.direction != PosStockMovementDirection.inbound) {
          return _invalid('pos_purchase_return_history_invalid');
        }
        sourceMovementsByLine.putIfAbsent(lineId, () => []).add(movement);
      }

      final movementsByReturnLineId = <String, List<PosStockMovement>>{};
      for (final details in priorReturns) {
        final priorMovementsResult = await _stock.listMovementsForSource(
          sourceType: 'pos_invoice',
          sourceId: details.invoice.id,
          type: PosStockMovementType.purchaseReturn,
        );
        if (priorMovementsResult.isFailure) {
          return FailureResult(priorMovementsResult.failureOrNull!);
        }
        final priorLines = <String, PosInvoiceLine>{
          for (final line in details.invoice.lines) line.id: line,
        };
        for (final movement in priorMovementsResult.valueOrNull!) {
          final returnLineId = movement.sourceLineId;
          final returnLine = returnLineId == null
              ? null
              : priorLines[returnLineId];
          if (returnLineId == null ||
              returnLine == null ||
              movement.sourceType != 'pos_invoice' ||
              movement.sourceId != details.invoice.id ||
              movement.type != PosStockMovementType.purchaseReturn ||
              movement.direction != PosStockMovementDirection.outbound ||
              movement.productId != returnLine.productId ||
              movement.quantity.scale != returnLine.quantity.scale) {
            return _invalid('pos_purchase_return_history_invalid');
          }
          movementsByReturnLineId
              .putIfAbsent(returnLineId, () => [])
              .add(movement);
        }
      }

      final returnLines = <PosInvoiceLine>[];
      final newMovements = <PosStockMovement>[];
      final simulatedBalances = <String, PosStockBalance>{};
      var lineIndex = 0;
      for (final entry in requested.entries) {
        final sourceLine = sourceById[entry.key];
        final quantity = entry.value;
        if (sourceLine == null || quantity.scale != sourceLine.quantity.scale) {
          return _invalid('pos_purchase_return_line_invalid');
        }
        final previouslyReturned = priorQuantity[sourceLine.id] ?? 0;
        final cumulativeQuantity = previouslyReturned + quantity.scaledUnits;
        if (cumulativeQuantity > sourceLine.quantity.scaledUnits) {
          return _invalid('pos_purchase_return_quantity_exceeds_source');
        }
        final discount =
            _cumulativeAllocation(
              sourceLine.discount.minorUnits,
              cumulativeQuantity,
              sourceLine.quantity.scaledUnits,
            ) -
            (priorLineDiscount[sourceLine.id] ?? 0);
        final tax =
            _cumulativeAllocation(
              sourceLine.tax.minorUnits,
              cumulativeQuantity,
              sourceLine.quantity.scaledUnits,
            ) -
            (priorLineTax[sourceLine.id] ?? 0);
        if (discount < 0 || tax < 0) {
          return _invalid('pos_purchase_return_history_invalid');
        }

        final returnLineId = '${input.returnInvoiceId}:line:$lineIndex';
        final returnLine = PosInvoiceLine.create(
          id: returnLineId,
          invoiceId: input.returnInvoiceId,
          productId: sourceLine.productId,
          productNameSnapshot: sourceLine.productNameSnapshot,
          barcodeSnapshot: sourceLine.barcodeSnapshot,
          quantity: quantity,
          unitPrice: sourceLine.unitPrice,
          unitCost: sourceLine.unitCost,
          discount: Money.fromMinorUnits(discount, source.currency),
          tax: Money.fromMinorUnits(tax, source.currency),
          sourceLineId: sourceLine.id,
          createdAt: input.createdAt,
          currencyConversion: sourceLine.currencyConversion,
          expiryTrackingSnapshot: sourceLine.expiryTrackingSnapshot,
        );
        returnLines.add(returnLine);

        final sourceAllocations =
            sourceMovementsByLine[sourceLine.id] ?? const [];
        final sourceQuantity = sourceAllocations.fold<int>(
          0,
          (sum, movement) => sum + movement.quantity.scaledUnits,
        );
        if (sourceQuantity != sourceLine.quantity.scaledUnits ||
            sourceAllocations.any(
              (movement) =>
                  movement.quantity.scale != sourceLine.quantity.scale,
            )) {
          return _invalid('pos_purchase_return_history_invalid');
        }

        final allocations = <({PosQuantity quantity, String? lotId})>[];
        if (sourceLine.expiryTrackingSnapshot == true) {
          var remaining = quantity.scaledUnits;
          for (final sourceAllocation in sourceAllocations) {
            final lotId = sourceAllocation.lotId;
            if (lotId == null) {
              return _invalid('pos_purchase_return_history_invalid');
            }
            var alreadyReturned = 0;
            for (final prior in priorReturns) {
              for (final priorLine in prior.invoice.lines.where(
                (line) => line.sourceLineId == sourceLine.id,
              )) {
                for (final movement
                    in movementsByReturnLineId[priorLine.id] ?? const []) {
                  if (movement.lotId == lotId) {
                    alreadyReturned =
                        (alreadyReturned + movement.quantity.scaledUnits)
                            .toInt();
                  }
                }
              }
            }
            final available =
                sourceAllocation.quantity.scaledUnits - alreadyReturned;
            if (available <= 0 || remaining == 0) continue;
            final take = remaining < available ? remaining : available;
            allocations.add((
              quantity: PosQuantity.fromScaled(take, scale: quantity.scale),
              lotId: lotId,
            ));
            remaining -= take;
          }
          if (remaining != 0) {
            return _invalid('pos_purchase_return_history_invalid');
          }
        } else {
          if (sourceAllocations.any((movement) => movement.lotId != null)) {
            return _invalid('pos_purchase_return_history_invalid');
          }
          allocations.add((quantity: quantity, lotId: null));
        }

        for (
          var allocationIndex = 0;
          allocationIndex < allocations.length;
          allocationIndex++
        ) {
          final allocation = allocations[allocationIndex];
          var balance = simulatedBalances[sourceLine.productId];
          if (balance == null) {
            final balanceResult = await _stock.getBalance(
              productId: sourceLine.productId,
              warehouseId: source.warehouseId,
            );
            if (balanceResult.isFailure) {
              return FailureResult(balanceResult.failureOrNull!);
            }
            balance = balanceResult.valueOrNull;
          }
          if (balance == null || balance.quantity.scale != quantity.scale) {
            return _invalid('pos_purchase_return_stock_unavailable');
          }
          final unitCost = balance.averageUnitCost;
          if (unitCost.currency != sourceLine.unitCost.currency) {
            return _invalid('pos_purchase_return_currency_mismatch');
          }
          final ordinal = allocationIndex.toString().padLeft(6, '0');
          final movement = PosStockMovement.create(
            id: '${input.returnInvoiceId}:movement:$lineIndex:$ordinal',
            productId: sourceLine.productId,
            warehouseId: source.warehouseId,
            type: PosStockMovementType.purchaseReturn,
            direction: PosStockMovementDirection.outbound,
            quantity: allocation.quantity,
            unitCost: unitCost,
            sourceType: 'pos_invoice',
            sourceId: input.returnInvoiceId,
            sourceLineId: returnLineId,
            lotId: allocation.lotId,
            reversesSourceId: source.id,
            occurredAt: input.invoiceDate,
            createdAt: input.createdAt,
            idempotencyKey:
                '${input.idempotencyKey}:movement:$lineIndex:$ordinal',
          );
          try {
            simulatedBalances[sourceLine.productId] = balance.apply(movement);
          } on Exception {
            return _invalid('pos_purchase_return_stock_unavailable');
          }
          newMovements.add(movement);
        }
        lineIndex++;
      }

      final requestedGross = returnLines.fold<int>(
        0,
        (sum, line) =>
            sum +
            PosMoneyMath.multiply(line.quantity, line.unitPrice).minorUnits,
      );
      final cumulativeGross = priorGross + requestedGross;
      if (source.subtotal.minorUnits > 0 &&
          cumulativeGross > source.subtotal.minorUnits) {
        return _invalid('pos_purchase_return_value_exceeds_source');
      }
      final globalDiscount = source.subtotal.minorUnits == 0
          ? 0
          : _cumulativeAllocation(
                  source.cartDiscount.minorUnits,
                  cumulativeGross,
                  source.subtotal.minorUnits,
                ) -
                priorGlobalDiscount;
      final sourceGlobalTax =
          source.tax.minorUnits -
          source.lines.fold<int>(0, (sum, line) => sum + line.tax.minorUnits);
      final globalTax = source.subtotal.minorUnits == 0
          ? 0
          : _cumulativeAllocation(
                  sourceGlobalTax,
                  cumulativeGross,
                  source.subtotal.minorUnits,
                ) -
                priorGlobalTax;
      if (globalDiscount < 0 || globalTax < 0) {
        return _invalid('pos_purchase_return_history_invalid');
      }

      final invoice = PosInvoice.draft(
        id: input.returnInvoiceId,
        invoiceNumber: input.returnInvoiceNumber,
        type: PosInvoiceType.purchaseReturn,
        warehouseId: source.warehouseId,
        currency: source.currency,
        lines: returnLines,
        counterpartyAccountId: supplierId,
        sourceInvoiceId: source.id,
        idempotencyKey: input.idempotencyKey,
        invoiceDate: input.invoiceDate,
        now: input.createdAt,
        discount: Money.fromMinorUnits(globalDiscount, source.currency),
        tax: Money.fromMinorUnits(globalTax, source.currency),
      ).post(input.createdAt);
      final postings = _buildBalancedPostings(
        invoice: invoice,
        movements: newMovements,
        linesById: {for (final line in returnLines) line.id: line},
        supplierPayablesAccount: supplierPayablesAccount,
        inventoryAccount: inventoryAccount,
        purchaseReturnsAccount: purchaseReturnsAccount,
        createdAt: input.createdAt,
      );
      return Success(
        PosPurchaseReturnPosting(
          invoice: invoice,
          sourceInvoiceId: source.id,
          supplierPayablesAccountId: supplierPayablesAccount,
          inventoryAccountId: inventoryAccount,
          purchaseReturnsAccountId: purchaseReturnsAccount,
          movements: newMovements,
          postings: postings,
          reason: input.reason,
        ),
      );
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  List<PosAccountingPosting> _buildBalancedPostings({
    required PosInvoice invoice,
    required List<PosStockMovement> movements,
    required Map<String, PosInvoiceLine> linesById,
    required AccountId supplierPayablesAccount,
    required AccountId inventoryAccount,
    required AccountId purchaseReturnsAccount,
    required DateTime createdAt,
  }) {
    var carryingValue = 0;
    for (final movement in movements) {
      final line = linesById[movement.sourceLineId]!;
      final value = PosMoneyMath.multiply(movement.quantity, movement.unitCost);
      final converted = _convertInventoryValue(
        value,
        invoice.currency,
        line.currencyConversion,
      );
      carryingValue += converted.minorUnits;
    }
    final supplierCredit = invoice.total.minorUnits;
    final postings = <PosAccountingPosting>[];
    final directInventoryAmount = supplierCredit < carryingValue
        ? supplierCredit
        : carryingValue;
    if (directInventoryAmount > 0) {
      postings.add(
        _posting(
          invoice: invoice,
          amount: Money.fromMinorUnits(directInventoryAmount, invoice.currency),
          debitAccount: supplierPayablesAccount,
          creditAccount: inventoryAccount,
          createdAt: createdAt,
          postingKey: 'inventory',
        ),
      );
    }
    if (supplierCredit > carryingValue) {
      postings.add(
        _posting(
          invoice: invoice,
          amount: Money.fromMinorUnits(
            supplierCredit - carryingValue,
            invoice.currency,
          ),
          debitAccount: supplierPayablesAccount,
          creditAccount: purchaseReturnsAccount,
          createdAt: createdAt,
          postingKey: 'variance-credit',
        ),
      );
    } else if (carryingValue > supplierCredit) {
      postings.add(
        _posting(
          invoice: invoice,
          amount: Money.fromMinorUnits(
            carryingValue - supplierCredit,
            invoice.currency,
          ),
          debitAccount: purchaseReturnsAccount,
          creditAccount: inventoryAccount,
          createdAt: createdAt,
          postingKey: 'variance-debit',
        ),
      );
    }
    return postings;
  }

  Money _convertInventoryValue(
    Money value,
    CurrencyCode invoiceCurrency,
    PosInvoiceLineConversion? conversion,
  ) {
    if (value.currency == invoiceCurrency) return value;
    final quote = conversion?.rateSnapshot;
    if (conversion == null || quote == null) {
      throw StateError(
        'Missing immutable purchase FX rate for return valuation.',
      );
    }
    return PosCurrencyRateQuote(
      rateId: quote.rateId,
      storedFromCurrency: quote.storedFromCurrency,
      storedToCurrency: quote.storedToCurrency,
      storedRateScaled: quote.storedRateScaled,
      requestedFromCurrency: quote.requestedToCurrency,
      requestedToCurrency: quote.requestedFromCurrency,
      effectiveAt: quote.effectiveAt,
      recordedAt: quote.recordedAt,
      createdAt: quote.createdAt,
      isInverted: !quote.isInverted,
      note: quote.note,
    ).convert(value);
  }

  PosAccountingPosting _posting({
    required PosInvoice invoice,
    required Money amount,
    required AccountId debitAccount,
    required AccountId creditAccount,
    required DateTime createdAt,
    required String postingKey,
  }) {
    final voucher = Voucher.draft(
      id: VoucherId('${invoice.id}:voucher:$postingKey'),
      type: VoucherType.payment,
      date: invoice.invoiceDate,
      amount: amount,
      currency: amount.currency,
      counterpartyId: debitAccount,
      affectedAccountId: creditAccount,
      referenceNumber: invoice.id,
      description: 'POS purchase return ${invoice.invoiceNumber}',
      createdAt: createdAt,
    ).confirm(createdAt);
    return PosAccountingPosting(
      sourceId: invoice.id,
      voucher: voucher,
      entries: _entries.generateForConfirmedVoucher(
        voucher: voucher,
        transactionId: TransactionId('${invoice.id}:transaction:$postingKey'),
        debitEntryId: EntryId('${invoice.id}:entry:$postingKey:debit'),
        creditEntryId: EntryId('${invoice.id}:entry:$postingKey:credit'),
        ledgerCreatedAt: createdAt,
      ),
    );
  }

  AccountId? _account(
    PosActivationResult installation,
    PosTemplateAccountKey key,
  ) {
    final raw = installation.accountIdsByKey[key.value]?.trim();
    return raw == null || raw.isEmpty ? null : AccountId(raw);
  }

  Future<Result<void>> _requireActiveAccount(AccountId id) async {
    final result = await _accounts.getById(id);
    if (result.isFailure) return FailureResult(result.failureOrNull!);
    final account = result.valueOrNull;
    if (account == null || !account.isActive || account.isArchived) {
      return FailureResult(
        ValidationFailure(
          messageAr: AppStrings.posInvoiceInvalid,
          code: 'pos_purchase_return_account_invalid',
        ),
      );
    }
    return const Success(null);
  }

  int _cumulativeAllocation(int total, int part, int whole) =>
      whole == 0 ? 0 : (total * part + whole ~/ 2) ~/ whole;

  FailureResult<PosPurchaseReturnPosting> _invalid(String code) =>
      FailureResult(
        ValidationFailure(messageAr: AppStrings.posInvoiceInvalid, code: code),
      );
}
