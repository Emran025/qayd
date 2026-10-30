import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_line_conversion.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/services/pos_currency_converter.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class BuildPosSalePostingInput {
  const BuildPosSalePostingInput({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.warehouseId,
    required this.currency,
    required this.lines,
    required this.idempotencyKey,
    required this.invoiceDate,
    required this.createdAt,
    this.customerAccountId,
    this.cashSale = true,
    this.settlement,
  });

  final String invoiceId;
  final String invoiceNumber;
  final String warehouseId;
  final CurrencyCode currency;
  final List<BuildPosSaleLineInput> lines;
  final String idempotencyKey;
  final DateTime invoiceDate;
  final DateTime createdAt;
  final AccountId? customerAccountId;

  /// When present, this is the explicit final settlement chosen by checkout.
  /// [advanceMinorUnits] is exact minor currency units and may be zero for credit.
  final PosSaleSettlementInput? settlement;

  /// Legacy full-cash/full-credit switch. New checkout should use [settlement].
  final bool cashSale;
}

final class PosSaleSettlementInput {
  const PosSaleSettlementInput({
    required this.advanceMinorUnits,
    required this.paymentMethod,
    this.paymentAccountId,
  });

  final int advanceMinorUnits;
  final PosPaymentMethod paymentMethod;
  final AccountId? paymentAccountId;
}

final class BuildPosSaleLineInput {
  const BuildPosSaleLineInput({
    required this.productId,
    required this.quantity,
    this.unitPrice,
    this.rateSnapshot,
  });

  final String productId;
  final PosQuantity quantity;
  final Money? unitPrice;
  final PosCurrencyRateQuote? rateSnapshot;
}

/// Builds a sale payload without writing anything to SQLite.
final class BuildPosSalePostingUseCase {
  BuildPosSalePostingUseCase({
    required PosProductRepository productRepository,
    required PosStockMovementRepository stockRepository,
    required PosTemplateInstallationRepository installationRepository,
    required AccountRepository accountRepository,
    required IdGenerator idGenerator,
    required PosCurrencyConverter currencyConverter,
    EntryGenerator entryGenerator = const EntryGenerator(),
  })  : _productRepository = productRepository,
        _stockRepository = stockRepository,
        _installationRepository = installationRepository,
        _accountRepository = accountRepository,
        _idGenerator = idGenerator,
        _currencyConverter = currencyConverter,
        _entryGenerator = entryGenerator;

  final PosProductRepository _productRepository;
  final PosStockMovementRepository _stockRepository;
  final PosTemplateInstallationRepository _installationRepository;
  final AccountRepository _accountRepository;
  final IdGenerator _idGenerator;
  final PosCurrencyConverter _currencyConverter;
  final EntryGenerator _entryGenerator;

  Future<Result<PosSalePosting>> call(BuildPosSalePostingInput input) async {
    try {
      if (input.lines.isEmpty || input.invoiceId.trim().isEmpty) {
        return _invalid('pos_sale_input_invalid');
      }
      final installation = await _installationRepository.getEnabledInstallation(
        template: PosTemplateDefinition.current(),
      );
      if (installation.isFailure) {
        return FailureResult(installation.failureOrNull!);
      }
      final context = installation.valueOrNull;
      if (context == null || context.warehouseId != input.warehouseId) {
        return _invalid('pos_sale_not_enabled');
      }
      final accountIds = await _resolveAccounts(context.accountIdsByKey, input);
      if (accountIds.isFailure) return FailureResult(accountIds.failureOrNull!);
      final accounts = accountIds.valueOrNull!;

      final invoiceLines = <PosInvoiceLine>[];
      final movements = <PosStockMovement>[];
      final cogsByCurrency = <CurrencyCode, int>{};
      for (final request in input.lines) {
        final productResult =
            await _productRepository.getById(request.productId);
        if (productResult.isFailure) {
          return FailureResult(productResult.failureOrNull!);
        }
        final product = productResult.valueOrNull!;
        if (!product.isActive ||
            request.quantity.scale != product.quantityScale ||
            request.quantity.isZero) {
          return _invalid('pos_sale_product_invalid');
        }
        final balanceResult = await _stockRepository.getBalance(
          productId: product.id,
          warehouseId: input.warehouseId,
        );
        if (balanceResult.isFailure) {
          return FailureResult(balanceResult.failureOrNull!);
        }
        final balance = balanceResult.valueOrNull!;
        if (balance.quantity.scale != product.quantityScale ||
            balance.quantity.scaledUnits < request.quantity.scaledUnits) {
          return _invalid('pos_sale_insufficient_stock');
        }
        final lineId = _idGenerator.next();
        final unitCost = balance.averageUnitCost;
        PosCurrencyConversion conversion;
        final suppliedRate = request.rateSnapshot;
        if (suppliedRate != null) {
          if (suppliedRate.requestedFromCurrency !=
                  product.salePrice.currency ||
              suppliedRate.requestedToCurrency != input.currency) {
            return _invalid('pos_sale_rate_currency_mismatch');
          }
          try {
            conversion = PosCurrencyConversion(
              sourceAmount: product.salePrice,
              targetAmount: suppliedRate.convert(product.salePrice),
              rateSnapshot: suppliedRate,
            );
          } on ArgumentError {
            return _invalid('pos_sale_rate_invalid');
          }
        } else {
          final conversionResult = await _currencyConverter.convertWithSnapshot(
            product.salePrice,
            toCurrency: input.currency,
          );
          if (conversionResult.isFailure) {
            return FailureResult(conversionResult.failureOrNull!);
          }
          conversion = conversionResult.valueOrNull!;
        }
        final unitPrice = conversion.targetAmount;
        if (request.unitPrice != null && request.unitPrice != unitPrice) {
          return _invalid('pos_sale_price_rate_changed');
        }
        final line = PosInvoiceLine.create(
          id: lineId,
          invoiceId: input.invoiceId,
          productId: product.id,
          productNameSnapshot: product.name,
          barcodeSnapshot: product.primaryBarcode?.value,
          quantity: request.quantity,
          unitPrice: unitPrice,
          unitCost: unitCost,
          discount: Money.zero(input.currency),
          tax: Money.zero(input.currency),
          createdAt: input.createdAt,
          currencyConversion: PosInvoiceLineConversion(
            purpose: PosInvoiceLineConversionPurpose.catalogSalePrice,
            sourceAmount: conversion.sourceAmount,
            targetAmount: conversion.targetAmount,
            rateSnapshot: conversion.rateSnapshot,
          ),
        );
        invoiceLines.add(line);
        final cogs = PosMoneyMath.multiply(request.quantity, unitCost);
        cogsByCurrency[cogs.currency] =
            (cogsByCurrency[cogs.currency] ?? 0) + cogs.minorUnits;
        movements.add(
          PosStockMovement.create(
            id: _idGenerator.next(),
            productId: product.id,
            warehouseId: input.warehouseId,
            type: PosStockMovementType.sale,
            direction: PosStockMovementDirection.outbound,
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
        type: PosInvoiceType.sale,
        warehouseId: input.warehouseId,
        currency: input.currency,
        lines: invoiceLines,
        idempotencyKey: input.idempotencyKey,
        invoiceDate: input.invoiceDate,
        now: input.createdAt,
        counterpartyAccountId: input.customerAccountId,
      ).post(input.createdAt);
      final payments = <PosInvoicePayment>[];
      final commercialPostings = <PosAccountingPosting>[];
      if (input.settlement == null) {
        if (input.cashSale) {
          invoice = invoice.applyPayment(invoice.total, input.createdAt);
          payments.add(
            PosInvoicePayment.create(
              id: _idGenerator.next(),
              invoiceId: invoice.id,
              accountId: accounts.cash,
              method: PosPaymentMethod.cash,
              amount: invoice.total,
              currency: invoice.currency,
              occurredAt: input.createdAt,
              idempotencyKey: '${input.idempotencyKey}:payment:cash',
            ),
          );
        }
        commercialPostings.add(
          _commercialPosting(
            invoice: invoice,
            amount: invoice.total,
            counterpartyAccountId: accounts.revenue,
            affectedAccountId:
                input.cashSale ? accounts.cash : accounts.receivable,
            description: 'POS sale ${invoice.invoiceNumber}',
            createdAt: input.createdAt,
          ),
        );
      } else {
        final settlement = input.settlement!;
        if (settlement.advanceMinorUnits < 0 ||
            settlement.advanceMinorUnits > invoice.total.minorUnits ||
            (settlement.paymentMethod == PosPaymentMethod.credit &&
                settlement.advanceMinorUnits != 0) ||
            (settlement.advanceMinorUnits == 0 &&
                settlement.paymentMethod != PosPaymentMethod.credit)) {
          return _invalid('pos_sale_payment_invalid');
        }
        final advance = Money.fromMinorUnits(
          settlement.advanceMinorUnits,
          invoice.currency,
        );
        final dueMinor = invoice.total.minorUnits - advance.minorUnits;
        if (dueMinor > 0 && input.customerAccountId == null) {
          return _invalid('pos_sale_customer_required');
        }
        if (dueMinor > 0) {
          final customer = await _accountRepository.getById(
            input.customerAccountId!,
          );
          if (customer.isFailure ||
              customer.valueOrNull == null ||
              !customer.valueOrNull!.isActive ||
              customer.valueOrNull!.isArchived) {
            return customer.isFailure
                ? FailureResult(customer.failureOrNull!)
                : _invalid('pos_sale_customer_invalid');
          }
        }
        if (advance.minorUnits > 0) {
          final paymentAccountId = settlement.paymentAccountId;
          if (paymentAccountId == null) {
            return _invalid('pos_sale_payment_account_required');
          }
          final paymentAccount =
              await _accountRepository.getById(paymentAccountId);
          if (paymentAccount.isFailure ||
              paymentAccount.valueOrNull == null ||
              !paymentAccount.valueOrNull!.isActive ||
              paymentAccount.valueOrNull!.isArchived) {
            return paymentAccount.isFailure
                ? FailureResult(paymentAccount.failureOrNull!)
                : _invalid('pos_sale_payment_account_invalid');
          }
          invoice = invoice.applyPayment(advance, input.createdAt);
          final payment = PosInvoicePayment.create(
            id: _idGenerator.next(),
            invoiceId: invoice.id,
            accountId: paymentAccountId,
            method: settlement.paymentMethod,
            amount: advance,
            currency: invoice.currency,
            occurredAt: input.createdAt,
            idempotencyKey: '${input.idempotencyKey}:payment:advance',
          );
          payments.add(payment);
          commercialPostings.add(
            _commercialPosting(
              invoice: invoice,
              amount: advance,
              counterpartyAccountId: accounts.revenue,
              affectedAccountId: paymentAccountId,
              description: 'POS sale advance ${invoice.invoiceNumber}',
              createdAt: input.createdAt,
            ),
          );
        }
        if (dueMinor > 0) {
          commercialPostings.add(
            _commercialPosting(
              invoice: invoice,
              amount: Money.fromMinorUnits(dueMinor, invoice.currency),
              counterpartyAccountId: accounts.revenue,
              affectedAccountId: input.customerAccountId!,
              description: 'POS sale receivable ${invoice.invoiceNumber}',
              createdAt: input.createdAt,
            ),
          );
        }
      }

      final cogsPostings = <PosAccountingPosting>[];
      for (final cost in cogsByCurrency.entries) {
        if (cost.value <= 0) continue;
        final cogsVoucher = Voucher.draft(
          id: VoucherId(_idGenerator.next()),
          type: VoucherType.payment,
          date: input.invoiceDate,
          amount: Money.fromMinorUnits(cost.value, cost.key),
          currency: cost.key,
          counterpartyId: accounts.cogs,
          affectedAccountId: accounts.inventory,
          referenceNumber: invoice.id,
          description: 'POS COGS ${invoice.invoiceNumber}',
          createdAt: input.createdAt,
        ).confirm(input.createdAt);
        cogsPostings.add(
          PosAccountingPosting(
            sourceId: invoice.id,
            voucher: cogsVoucher,
            entries: _entryGenerator.generateForConfirmedVoucher(
              voucher: cogsVoucher,
              transactionId: TransactionId(_idGenerator.next()),
              debitEntryId: EntryId(_idGenerator.next()),
              creditEntryId: EntryId(_idGenerator.next()),
              ledgerCreatedAt: input.createdAt,
            ),
          ),
        );
      }
      return Success(
        PosSalePosting(
          invoice: invoice,
          movements: movements,
          postings: [
            ...commercialPostings,
            ...cogsPostings,
          ],
          payments: payments,
        ),
      );
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  PosAccountingPosting _commercialPosting({
    required PosInvoice invoice,
    required Money amount,
    required AccountId counterpartyAccountId,
    required AccountId affectedAccountId,
    required String description,
    required DateTime createdAt,
  }) {
    final voucher = Voucher.draft(
      id: VoucherId(_idGenerator.next()),
      type: VoucherType.receipt,
      date: invoice.invoiceDate,
      amount: amount,
      currency: invoice.currency,
      counterpartyId: counterpartyAccountId,
      affectedAccountId: affectedAccountId,
      referenceNumber: invoice.id,
      description: description,
      createdAt: createdAt,
    ).confirm(createdAt);
    final entries = _entryGenerator.generateForConfirmedVoucher(
      voucher: voucher,
      transactionId: TransactionId(_idGenerator.next()),
      debitEntryId: EntryId(_idGenerator.next()),
      creditEntryId: EntryId(_idGenerator.next()),
      ledgerCreatedAt: createdAt,
    );
    return PosAccountingPosting(
      sourceId: invoice.id,
      voucher: voucher,
      entries: entries,
    );
  }

  Future<Result<_SaleAccounts>> _resolveAccounts(
    Map<String, String> ids,
    BuildPosSalePostingInput input,
  ) async {
    final required = <PosTemplateAccountKey>[
      PosTemplateAccountKey.inventoryAsset,
      PosTemplateAccountKey.salesRevenue,
      PosTemplateAccountKey.costOfGoodsSold,
      if (input.cashSale)
        PosTemplateAccountKey.posCash
      else
        PosTemplateAccountKey.customerReceivables,
    ];
    final resolved = <PosTemplateAccountKey, AccountId>{};
    for (final key in required) {
      final raw = ids[key.value]?.trim();
      if (raw == null || raw.isEmpty) {
        return _invalid('pos_sale_accounts_missing');
      }
      final accountResult = await _accountRepository.getById(AccountId(raw));
      if (accountResult.isFailure) {
        return FailureResult(accountResult.failureOrNull!);
      }
      final account = accountResult.valueOrNull;
      if (account == null || !account.isActive || account.isArchived) {
        return _invalid('pos_sale_accounts_invalid');
      }
      resolved[key] = account.id;
    }
    if (!input.cashSale && input.customerAccountId == null) {
      return _invalid('pos_sale_customer_required');
    }
    return Success(
      _SaleAccounts(
        inventory: resolved[PosTemplateAccountKey.inventoryAsset]!,
        revenue: resolved[PosTemplateAccountKey.salesRevenue]!,
        cogs: resolved[PosTemplateAccountKey.costOfGoodsSold]!,
        cash:
            resolved[PosTemplateAccountKey.posCash] ?? AccountId('unused-cash'),
        receivable: resolved[PosTemplateAccountKey.customerReceivables] ??
            AccountId('unused-receivable'),
      ),
    );
  }

  FailureResult<T> _invalid<T>(String code) => FailureResult(
        ValidationFailure(messageAr: AppStrings.posInvoiceInvalid, code: code),
      );
}

final class _SaleAccounts {
  const _SaleAccounts({
    required this.inventory,
    required this.revenue,
    required this.cogs,
    required this.cash,
    required this.receivable,
  });

  final AccountId inventory;
  final AccountId revenue;
  final AccountId cogs;
  final AccountId cash;
  final AccountId receivable;
}
