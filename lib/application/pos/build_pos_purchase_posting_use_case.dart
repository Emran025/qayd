import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_line_conversion.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_purchase_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/services/pos_currency_converter.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class BuildPosPurchasePostingInput {
  const BuildPosPurchasePostingInput({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.warehouseId,
    required this.currency,
    required this.lines,
    required this.idempotencyKey,
    required this.invoiceDate,
    required this.createdAt,
    this.supplierAccountId,
    this.advanceMinorUnits = 0,
    this.paymentMethod = PosPaymentMethod.credit,
    this.paymentAccountId,
  });

  final String invoiceId;
  final String invoiceNumber;
  final String warehouseId;
  final String idempotencyKey;
  final CurrencyCode currency;
  final List<BuildPosPurchaseLineInput> lines;
  final DateTime invoiceDate;
  final DateTime createdAt;
  final AccountId? supplierAccountId;
  final int advanceMinorUnits;
  final PosPaymentMethod paymentMethod;
  final AccountId? paymentAccountId;
}

final class BuildPosPurchaseLineInput {
  const BuildPosPurchaseLineInput({
    required this.productId,
    required this.quantity,
    this.unitCostMinor,
    this.applyProposedSalePrice = false,
    this.rateSnapshot,
    this.productUpdatedAtSnapshot,
  });

  final String productId;
  final PosQuantity quantity;

  /// Supplier unit price in the purchase invoice currency, not catalog cost.
  final int? unitCostMinor;
  final bool applyProposedSalePrice;
  final PosCurrencyRateQuote? rateSnapshot;
  final DateTime? productUpdatedAtSnapshot;
}

/// Builds the complete immutable purchase payload without writing to SQLite.
final class BuildPosPurchasePostingUseCase {
  BuildPosPurchasePostingUseCase({
    required PosProductRepository productRepository,
    required PosTemplateInstallationRepository installationRepository,
    required AccountRepository accountRepository,
    required PosCurrencyConverter currencyConverter,
    EntryGenerator entryGenerator = const EntryGenerator(),
  })  : _products = productRepository,
        _installations = installationRepository,
        _accounts = accountRepository,
        _currencyConverter = currencyConverter,
        _entries = entryGenerator;

  final PosProductRepository _products;
  final PosTemplateInstallationRepository _installations;
  final AccountRepository _accounts;
  final PosCurrencyConverter _currencyConverter;
  final EntryGenerator _entries;

  Future<Result<PosPurchasePosting>> call(
    BuildPosPurchasePostingInput input,
  ) async {
    try {
      if (input.lines.isEmpty ||
          input.invoiceId.trim().isEmpty ||
          input.invoiceNumber.trim().isEmpty ||
          input.warehouseId.trim().isEmpty ||
          input.idempotencyKey.trim().isEmpty ||
          input.advanceMinorUnits < 0) {
        return _invalid('pos_purchase_input_invalid');
      }

      final installationResult = await _installations.getEnabledInstallation(
        template: PosTemplateDefinition.current(),
      );
      if (installationResult.isFailure) {
        return FailureResult(installationResult.failureOrNull!);
      }
      final installation = installationResult.valueOrNull;
      if (installation == null ||
          installation.warehouseId != input.warehouseId) {
        return _invalid('pos_purchase_not_enabled');
      }

      final accountIds = installation.accountIdsByKey;
      final inventoryId = _mappedAccount(
        accountIds,
        PosTemplateAccountKey.inventoryAsset,
      );
      final payablesId = _mappedAccount(
        accountIds,
        PosTemplateAccountKey.supplierPayables,
      );
      final posCashId = _mappedAccount(
        accountIds,
        PosTemplateAccountKey.posCash,
      );
      if (inventoryId == null || payablesId == null) {
        return _invalid('pos_purchase_accounts_missing');
      }
      final inventoryCheck = await _requireActiveAccount(inventoryId);
      if (inventoryCheck.isFailure) {
        return FailureResult(inventoryCheck.failureOrNull!);
      }

      final lines = <PosInvoiceLine>[];
      final movements = <PosStockMovement>[];
      for (var index = 0; index < input.lines.length; index++) {
        final request = input.lines[index];
        if (!request.quantity.isPositive) {
          return _invalid('pos_purchase_quantity_invalid');
        }
        final productResult = await _products.getById(request.productId);
        if (productResult.isFailure) {
          return FailureResult(productResult.failureOrNull!);
        }
        final product = productResult.valueOrNull;
        if (product == null ||
            !product.isActive ||
            request.quantity.scale != product.quantityScale) {
          return _invalid('pos_purchase_product_invalid');
        }
        if (request.productUpdatedAtSnapshot != null &&
            request.productUpdatedAtSnapshot!.toUtc() !=
                product.updatedAt.toUtc()) {
          return _invalid('pos_purchase_product_changed');
        }
        if (product.expiryTracking) {
          return _invalid('pos_purchase_expiry_lot_required');
        }

        final costMinor = request.unitCostMinor ??
            (product.currency == input.currency
                ? product.purchasePrice.minorUnits
                : null);
        if (costMinor == null) {
          return _invalid('pos_purchase_cost_required_for_currency');
        }
        if (costMinor < 0) return _invalid('pos_purchase_cost_invalid');
        final sourceUnitPrice = Money.fromMinorUnits(costMinor, input.currency);
        PosCurrencyConversion costConversion;
        final suppliedRate = request.rateSnapshot;
        if (suppliedRate != null) {
          if (suppliedRate.requestedFromCurrency != input.currency ||
              suppliedRate.requestedToCurrency != product.currency) {
            return _invalid('pos_purchase_rate_currency_mismatch');
          }
          try {
            costConversion = PosCurrencyConversion(
              sourceAmount: sourceUnitPrice,
              targetAmount: suppliedRate.convert(sourceUnitPrice),
              rateSnapshot: suppliedRate,
            );
          } on RangeError {
            return _invalid('pos_purchase_rate_invalid');
          } on ArgumentError {
            return _invalid('pos_purchase_rate_invalid');
          }
        } else {
          final costConversionResult =
              await _currencyConverter.convertWithSnapshot(
            sourceUnitPrice,
            toCurrency: product.currency,
          );
          if (costConversionResult.isFailure) {
            return FailureResult(costConversionResult.failureOrNull!);
          }
          costConversion = costConversionResult.valueOrNull!;
        }
        final unitCost = costConversion.targetAmount;
        final proposedSalePrice =
            product.profitMargin.calculateProposedSalePrice(unitCost);
        final lineId = '${input.invoiceId}:line:${index + 1}';
        final line = PosInvoiceLine.create(
          id: lineId,
          invoiceId: input.invoiceId,
          productId: product.id,
          productNameSnapshot: product.name,
          barcodeSnapshot: product.primaryBarcode?.value,
          quantity: request.quantity,
          unitPrice: sourceUnitPrice,
          unitCost: unitCost,
          discount: Money.zero(input.currency),
          tax: Money.zero(input.currency),
          createdAt: input.createdAt,
          currencyConversion: PosInvoiceLineConversion(
            purpose: PosInvoiceLineConversionPurpose.purchaseCost,
            sourceAmount: costConversion.sourceAmount,
            targetAmount: costConversion.targetAmount,
            rateSnapshot: costConversion.rateSnapshot,
          ),
          proposedSalePrice: proposedSalePrice,
          proposedSalePriceApplied: request.applyProposedSalePrice,
          productUpdatedAtSnapshot: product.updatedAt,
        );
        lines.add(line);
        movements.add(
          PosStockMovement.create(
            id: '${input.invoiceId}:movement:${index + 1}',
            productId: product.id,
            warehouseId: input.warehouseId,
            type: PosStockMovementType.purchase,
            direction: PosStockMovementDirection.inbound,
            quantity: request.quantity,
            unitCost: unitCost,
            sourceType: 'pos_invoice',
            sourceId: input.invoiceId,
            sourceLineId: lineId,
            occurredAt: input.invoiceDate,
            idempotencyKey: '${input.idempotencyKey}:stock:$lineId',
            createdAt: input.createdAt,
          ),
        );
      }

      var invoice = PosInvoice.draft(
        id: input.invoiceId,
        invoiceNumber: input.invoiceNumber,
        type: PosInvoiceType.purchase,
        warehouseId: input.warehouseId,
        currency: input.currency,
        lines: lines,
        idempotencyKey: input.idempotencyKey,
        invoiceDate: input.invoiceDate,
        now: input.createdAt,
        counterpartyAccountId: input.supplierAccountId,
      ).post(input.createdAt);
      final totalMinor = invoice.total.minorUnits;
      if (totalMinor <= 0 || input.advanceMinorUnits > totalMinor) {
        return _invalid('pos_purchase_total_invalid');
      }
      if ((input.advanceMinorUnits > 0 &&
              input.paymentMethod == PosPaymentMethod.credit) ||
          (input.advanceMinorUnits == 0 &&
              input.paymentMethod != PosPaymentMethod.credit)) {
        return _invalid('pos_purchase_payment_invalid');
      }

      final dueMinor = totalMinor - input.advanceMinorUnits;
      final supplierId = input.supplierAccountId;
      if (supplierId != null) {
        final supplierCheck = await _requireActiveAccount(supplierId);
        if (supplierCheck.isFailure) {
          return FailureResult(supplierCheck.failureOrNull!);
        }
      }
      if (dueMinor > 0) {
        if (supplierId == null) {
          return _invalid('pos_purchase_supplier_required');
        }
        final payablesCheck = await _requireActiveAccount(payablesId);
        if (payablesCheck.isFailure) {
          return FailureResult(payablesCheck.failureOrNull!);
        }
      }

      final payments = <PosInvoicePayment>[];
      final postings = <PosAccountingPosting>[];
      if (input.advanceMinorUnits > 0) {
        final paymentAccountId = switch (input.paymentMethod) {
          PosPaymentMethod.cash => posCashId,
          PosPaymentMethod.bank ||
          PosPaymentMethod.other =>
            input.paymentAccountId,
          PosPaymentMethod.credit => null,
        };
        if (paymentAccountId == null ||
            (input.paymentMethod == PosPaymentMethod.cash &&
                input.paymentAccountId != null &&
                input.paymentAccountId != posCashId)) {
          return _invalid('pos_purchase_payment_account_required');
        }
        final paymentAccountCheck =
            await _requireActiveAccount(paymentAccountId);
        if (paymentAccountCheck.isFailure) {
          return FailureResult(paymentAccountCheck.failureOrNull!);
        }
        final amount = Money.fromMinorUnits(
          input.advanceMinorUnits,
          input.currency,
        );
        invoice = invoice.applyPayment(amount, input.createdAt);
        payments.add(
          PosInvoicePayment.create(
            id: '${invoice.id}:payment:1',
            invoiceId: invoice.id,
            accountId: paymentAccountId,
            method: input.paymentMethod,
            amount: amount,
            currency: input.currency,
            occurredAt: input.createdAt,
            idempotencyKey: '${input.idempotencyKey}:payment',
          ),
        );
        postings.add(
          _inventoryReceiptPosting(
            invoice: invoice,
            amount: amount,
            inventoryAccountId: inventoryId,
            creditedAccountId: paymentAccountId,
            description: 'POS purchase payment ${invoice.invoiceNumber}',
            input: input,
            postingKey: 'payment',
          ),
        );
      }
      if (dueMinor > 0) {
        postings.add(
          _inventoryReceiptPosting(
            invoice: invoice,
            amount: Money.fromMinorUnits(dueMinor, input.currency),
            inventoryAccountId: inventoryId,
            creditedAccountId: payablesId,
            description: 'POS purchase payable ${invoice.invoiceNumber}',
            input: input,
            postingKey: 'payable',
          ),
        );
      }

      return Success(
        PosPurchasePosting(
          invoice: invoice,
          movements: movements,
          postings: postings,
          payments: payments,
        ),
      );
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  AccountId? _mappedAccount(
    Map<String, String> ids,
    PosTemplateAccountKey key,
  ) {
    final value = ids[key.value]?.trim();
    return value == null || value.isEmpty ? null : AccountId(value);
  }

  Future<Result<void>> _requireActiveAccount(AccountId id) async {
    final result = await _accounts.getById(id);
    if (result.isFailure) return FailureResult(result.failureOrNull!);
    final account = result.valueOrNull;
    if (account == null || !account.isActive || account.isArchived) {
      return FailureResult(
        ValidationFailure(
          messageAr: AppStrings.posInvoiceInvalid,
          code: 'pos_purchase_account_invalid',
        ),
      );
    }
    return const Success(null);
  }

  PosAccountingPosting _inventoryReceiptPosting({
    required PosInvoice invoice,
    required Money amount,
    required AccountId inventoryAccountId,
    required AccountId creditedAccountId,
    required String description,
    required BuildPosPurchasePostingInput input,
    required String postingKey,
  }) {
    final voucher = Voucher.draft(
      id: VoucherId('${invoice.id}:voucher:$postingKey'),
      type: VoucherType.receipt,
      date: input.invoiceDate,
      amount: amount,
      currency: input.currency,
      counterpartyId: creditedAccountId,
      affectedAccountId: inventoryAccountId,
      referenceNumber: invoice.id,
      description: description,
      createdAt: input.createdAt,
    ).confirm(input.createdAt);
    return PosAccountingPosting(
      sourceId: invoice.id,
      voucher: voucher,
      entries: _entries.generateForConfirmedVoucher(
        voucher: voucher,
        transactionId: TransactionId('${invoice.id}:transaction:$postingKey'),
        debitEntryId: EntryId('${invoice.id}:entry:$postingKey:debit'),
        creditEntryId: EntryId('${invoice.id}:entry:$postingKey:credit'),
        ledgerCreatedAt: input.createdAt,
      ),
    );
  }

  FailureResult<PosPurchasePosting> _invalid(String code) => FailureResult(
        ValidationFailure(
          messageAr: AppStrings.posInvoiceInvalid,
          code: code,
        ),
      );
}
