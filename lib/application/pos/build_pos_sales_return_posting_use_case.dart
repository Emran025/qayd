import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_activation_result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/entities/pos_template_definition.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/pos_invoice_read_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';

final class BuildPosSalesReturnLineInput {
  const BuildPosSalesReturnLineInput({
    required this.sourceLineId,
    required this.quantity,
  });

  final String sourceLineId;
  final PosQuantity quantity;
}

final class BuildPosSalesReturnPostingInput {
  const BuildPosSalesReturnPostingInput({
    required this.returnInvoiceId,
    required this.returnInvoiceNumber,
    required this.sourceInvoiceId,
    required this.idempotencyKey,
    required this.lines,
    required this.invoiceDate,
    required this.createdAt,
    this.reason,
    this.voidSource = false,
  });

  final String returnInvoiceId;
  final String returnInvoiceNumber;
  final String sourceInvoiceId;
  final String idempotencyKey;
  final List<BuildPosSalesReturnLineInput> lines;
  final DateTime invoiceDate;
  final DateTime createdAt;
  final String? reason;
  final bool voidSource;
}

/// Pure builder for a sales return or full void; it does not write to storage.
final class BuildPosSalesReturnPostingUseCase {
  BuildPosSalesReturnPostingUseCase({
    required PosInvoiceReadRepository invoiceRepository,
    required PosTemplateInstallationRepository installationRepository,
    EntryGenerator entryGenerator = const EntryGenerator(),
  })  : _invoices = invoiceRepository,
        _installation = installationRepository,
        _entries = entryGenerator;

  final PosInvoiceReadRepository _invoices;
  final PosTemplateInstallationRepository _installation;
  final EntryGenerator _entries;

  Future<Result<PosSalesReturnPosting>> call(
    BuildPosSalesReturnPostingInput input,
  ) async {
    try {
      if (input.returnInvoiceId.trim().isEmpty ||
          input.returnInvoiceNumber.trim().isEmpty ||
          input.sourceInvoiceId.trim().isEmpty ||
          input.idempotencyKey.trim().isEmpty) {
        return _invalid('pos_sales_return_input_invalid');
      }

      final sourceResult = await _invoices.getById(input.sourceInvoiceId);
      if (sourceResult.isFailure) {
        return FailureResult(sourceResult.failureOrNull!);
      }
      final sourceDetails = sourceResult.valueOrNull;
      if (sourceDetails == null) {
        return _invalid('pos_sales_return_source_not_found');
      }
      final source = sourceDetails.invoice;
      if (source.type != PosInvoiceType.sale ||
          source.status == PosDocumentStatus.voided ||
          source.status == PosDocumentStatus.fullyReturned) {
        return _invalid('pos_sales_return_source_status_invalid');
      }
      if (source.due.minorUnits != 0 ||
          source.paid.minorUnits != source.total.minorUnits ||
          source.total.minorUnits <= 0 ||
          sourceDetails.payments.isEmpty ||
          sourceDetails.payments.any(
            (payment) => payment.method == PosPaymentMethod.credit,
          ) ||
          sourceDetails.payments.fold<int>(
                0,
                (sum, payment) => sum + payment.amount.minorUnits,
              ) !=
              source.total.minorUnits) {
        return _invalid('pos_sales_return_source_must_be_fully_paid');
      }

      final priorResult = await _invoices.getReturnsForSource(source.id);
      if (priorResult.isFailure) {
        return FailureResult(priorResult.failureOrNull!);
      }
      final priorReturns = priorResult.valueOrNull!;
      if (input.voidSource && priorReturns.isNotEmpty) {
        return _invalid('pos_sales_return_void_after_return_forbidden');
      }
      if (input.voidSource && input.lines.isNotEmpty) {
        return _invalid('pos_sales_return_void_lines_forbidden');
      }
      if (!input.voidSource && input.lines.isEmpty) {
        return _invalid('pos_sales_return_lines_required');
      }

      final installationResult = await _installation.getEnabledInstallation(
        template: PosTemplateDefinition.current(),
      );
      if (installationResult.isFailure) {
        return FailureResult(installationResult.failureOrNull!);
      }
      final installation = installationResult.valueOrNull;
      if (installation == null || installation.warehouseId != source.warehouseId) {
        return _invalid('pos_sales_return_not_enabled');
      }
      final salesReturnsAccount = _account(
        installation,
        PosTemplateAccountKey.salesReturns,
      );
      final inventoryAccount = _account(
        installation,
        PosTemplateAccountKey.inventoryAsset,
      );
      final cogsAccount = _account(
        installation,
        PosTemplateAccountKey.costOfGoodsSold,
      );
      if (salesReturnsAccount == null ||
          inventoryAccount == null ||
          cogsAccount == null) {
        return _invalid('pos_sales_return_accounts_missing');
      }

      final sourceById = {for (final line in source.lines) line.id: line};
      final requested = <String, PosQuantity>{};
      if (input.voidSource) {
        for (final line in source.lines) {
          requested[line.id] = line.quantity;
        }
      } else {
        for (final request in input.lines) {
          if (request.sourceLineId.trim().isEmpty ||
              request.quantity.scaledUnits <= 0 ||
              requested.containsKey(request.sourceLineId)) {
            return _invalid('pos_sales_return_line_invalid');
          }
          requested[request.sourceLineId] = request.quantity;
        }
      }

      final priorQuantity = <String, int>{};
      final priorLineDiscount = <String, int>{};
      final priorLineTax = <String, int>{};
      var priorGross = 0;
      var priorDocumentDiscount = 0;
      var priorDocumentTax = 0;
      var priorLineDiscountTotal = 0;
      var priorLineTaxTotal = 0;
      for (final details in priorReturns) {
        if (details.invoice.type != PosInvoiceType.salesReturn ||
            details.invoice.sourceInvoiceId != source.id ||
            details.invoice.currency != source.currency) {
          return _invalid('pos_sales_return_history_invalid');
        }
        priorDocumentDiscount += details.invoice.discount.minorUnits;
        priorDocumentTax += details.invoice.tax.minorUnits;
        for (final line in details.invoice.lines) {
          final sourceLineId = line.sourceLineId;
          if (sourceLineId == null || !sourceById.containsKey(sourceLineId)) {
            return _invalid('pos_sales_return_history_invalid');
          }
          priorQuantity[sourceLineId] =
              (priorQuantity[sourceLineId] ?? 0) + line.quantity.scaledUnits;
          priorLineDiscount[sourceLineId] =
              (priorLineDiscount[sourceLineId] ?? 0) + line.discount.minorUnits;
          priorLineTax[sourceLineId] =
              (priorLineTax[sourceLineId] ?? 0) + line.tax.minorUnits;
          priorGross += PosMoneyMath.multiply(line.quantity, line.unitPrice).minorUnits;
          priorLineDiscountTotal += line.discount.minorUnits;
          priorLineTaxTotal += line.tax.minorUnits;
        }
      }
      final priorGlobalDiscount = priorDocumentDiscount - priorLineDiscountTotal;
      final priorGlobalTax = priorDocumentTax - priorLineTaxTotal;
      final sourceLineDiscount = source.lines.fold<int>(
        0,
        (sum, line) => sum + line.discount.minorUnits,
      );
      final sourceLineTax = source.lines.fold<int>(
        0,
        (sum, line) => sum + line.tax.minorUnits,
      );
      final sourceGlobalDiscount = source.discount.minorUnits - sourceLineDiscount;
      final sourceGlobalTax = source.tax.minorUnits - sourceLineTax;
      if (sourceGlobalDiscount < 0 ||
          sourceGlobalTax < 0 ||
          priorGlobalDiscount < 0 ||
          priorGlobalTax < 0 ||
          priorGlobalDiscount > sourceGlobalDiscount ||
          priorGlobalTax > sourceGlobalTax ||
          priorGross > source.subtotal.minorUnits ||
          priorQuantity.entries.any((entry) =>
              entry.value > (sourceById[entry.key]?.quantity.scaledUnits ?? 0))) {
        return _invalid('pos_sales_return_history_invalid');
      }

      final returnLines = <PosInvoiceLine>[];
      final movements = <PosStockMovement>[];
      var lineIndex = 0;
      for (final entry in requested.entries) {
        final sourceLine = sourceById[entry.key];
        if (sourceLine == null ||
            entry.value.scale != sourceLine.quantity.scale ||
            entry.value.scaledUnits + (priorQuantity[entry.key] ?? 0) >
                sourceLine.quantity.scaledUnits) {
          return _invalid('pos_sales_return_quantity_exceeds_source');
        }
        final cumulativeQuantity =
            entry.value.scaledUnits + (priorQuantity[entry.key] ?? 0);
        final discount = _cumulativeAllocation(
              sourceLine.discount.minorUnits,
              cumulativeQuantity,
              sourceLine.quantity.scaledUnits,
            ) -
            (priorLineDiscount[entry.key] ?? 0);
        final tax = _cumulativeAllocation(
              sourceLine.tax.minorUnits,
              cumulativeQuantity,
              sourceLine.quantity.scaledUnits,
            ) -
            (priorLineTax[entry.key] ?? 0);
        if (discount < 0 || tax < 0) {
          return _invalid('pos_sales_return_history_invalid');
        }

        final lineId = '${input.returnInvoiceId}:line:$lineIndex';
        final line = PosInvoiceLine.create(
          id: lineId,
          invoiceId: input.returnInvoiceId,
          productId: sourceLine.productId,
          productNameSnapshot: sourceLine.productNameSnapshot,
          barcodeSnapshot: sourceLine.barcodeSnapshot,
          quantity: entry.value,
          unitPrice: sourceLine.unitPrice,
          unitCost: sourceLine.unitCost,
          discount: Money.fromMinorUnits(discount, source.currency),
          tax: Money.fromMinorUnits(tax, source.currency),
          sourceLineId: sourceLine.id,
          createdAt: input.createdAt,
        );
        returnLines.add(line);
        movements.add(
          PosStockMovement.create(
            id: '${input.returnInvoiceId}:movement:$lineIndex',
            productId: sourceLine.productId,
            warehouseId: source.warehouseId,
            type: PosStockMovementType.salesReturn,
            direction: PosStockMovementDirection.inbound,
            quantity: entry.value,
            unitCost: sourceLine.unitCost,
            sourceType: 'pos_invoice',
            sourceId: input.returnInvoiceId,
            sourceLineId: lineId,
            occurredAt: input.invoiceDate,
            createdAt: input.createdAt,
            idempotencyKey: '${input.idempotencyKey}:movement:$lineIndex',
          ),
        );
        lineIndex++;
      }
      if (returnLines.isEmpty) {
        return _invalid('pos_sales_return_lines_required');
      }

      final returnGross = returnLines.fold<int>(
        0,
        (sum, line) =>
            sum + PosMoneyMath.multiply(line.quantity, line.unitPrice).minorUnits,
      );
      final cumulativeGross = priorGross + returnGross;
      if (cumulativeGross > source.subtotal.minorUnits) {
        return _invalid('pos_sales_return_quantity_exceeds_source');
      }
      final globalDiscount = _cumulativeAllocation(
            sourceGlobalDiscount,
            cumulativeGross,
            source.subtotal.minorUnits,
          ) -
          priorGlobalDiscount;
      final globalTax = _cumulativeAllocation(
            sourceGlobalTax,
            cumulativeGross,
            source.subtotal.minorUnits,
          ) -
          priorGlobalTax;
      if (globalDiscount < 0 || globalTax < 0) {
        return _invalid('pos_sales_return_history_invalid');
      }

      var invoice = PosInvoice.draft(
        id: input.returnInvoiceId,
        invoiceNumber: input.returnInvoiceNumber,
        type: PosInvoiceType.salesReturn,
        warehouseId: source.warehouseId,
        currency: source.currency,
        lines: returnLines,
        counterpartyAccountId: source.counterpartyAccountId,
        sourceInvoiceId: source.id,
        idempotencyKey: input.idempotencyKey,
        invoiceDate: input.invoiceDate,
        now: input.createdAt,
        discount: Money.fromMinorUnits(globalDiscount, source.currency),
        tax: Money.fromMinorUnits(globalTax, source.currency),
      ).post(input.createdAt);
      invoice = invoice.applyPayment(invoice.total, input.createdAt);
      final refundPayments = _splitRefunds(
        sourceDetails.payments,
        invoice.total,
        invoice.id,
        input,
      );
      final postings = <PosAccountingPosting>[];
      for (final refund in refundPayments) {
        postings.add(
          _posting(
            invoice: invoice,
            amount: refund.amount,
            affectedAccount: salesReturnsAccount,
            counterpartyAccount: refund.accountId,
            description: 'POS sales return ${source.invoiceNumber}',
            createdAt: input.createdAt,
            postingKey: 'refund:${refund.id}',
          ),
        );
      }
      final cogsAmount = returnLines.fold<int>(
        0,
        (sum, line) =>
            sum + PosMoneyMath.multiply(line.quantity, line.unitCost).minorUnits,
      );
      if (cogsAmount > 0) {
        postings.add(
          _posting(
            invoice: invoice,
            amount: Money.fromMinorUnits(cogsAmount, source.currency),
            affectedAccount: inventoryAccount,
            counterpartyAccount: cogsAccount,
            description: 'POS COGS reversal ${source.invoiceNumber}',
            createdAt: input.createdAt,
            postingKey: 'cogs-reversal',
          ),
        );
      }

      return Success(
        PosSalesReturnPosting(
          invoice: invoice,
          sourceInvoiceId: source.id,
          salesReturnsAccountId: salesReturnsAccount,
          inventoryAccountId: inventoryAccount,
          costOfGoodsSoldAccountId: cogsAccount,
          movements: movements,
          postings: postings,
          refundPayments: refundPayments,
          voidSource: input.voidSource,
          reason: input.reason,
        ),
      );
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  AccountId? _account(PosActivationResult context, PosTemplateAccountKey key) {
    final raw = context.accountIdsByKey[key.value];
    return raw == null || raw.isEmpty ? null : AccountId(raw);
  }

  int _cumulativeAllocation(int total, int part, int whole) =>
      (total * part + whole ~/ 2) ~/ whole;

  List<PosInvoicePayment> _splitRefunds(
    List<PosInvoicePayment> originals,
    Money total,
    String invoiceId,
    BuildPosSalesReturnPostingInput input,
  ) {
    if (total.isZero) return const [];
    final denominator = originals.fold<int>(
      0,
      (sum, payment) => sum + payment.amount.minorUnits,
    );
    if (denominator <= 0) return const [];
    var allocated = 0;
    final refunds = <PosInvoicePayment>[];
    for (var index = 0; index < originals.length; index++) {
      final original = originals[index];
      final amount = index == originals.length - 1
          ? total.minorUnits - allocated
          : (original.amount.minorUnits * total.minorUnits + denominator ~/ 2) ~/
              denominator;
      if (amount <= 0) continue;
      allocated += amount;
      refunds.add(
        PosInvoicePayment.create(
          id: '$invoiceId:refund:$index',
          invoiceId: invoiceId,
          accountId: original.accountId,
          method: original.method,
          amount: Money.fromMinorUnits(amount, total.currency),
          currency: total.currency,
          occurredAt: input.createdAt,
          idempotencyKey: '${input.idempotencyKey}:refund:$index',
        ),
      );
    }
    return refunds;
  }

  PosAccountingPosting _posting({
    required PosInvoice invoice,
    required Money amount,
    required AccountId affectedAccount,
    required AccountId counterpartyAccount,
    required String description,
    required DateTime createdAt,
    required String postingKey,
  }) {
    final voucher = Voucher.draft(
      id: VoucherId('${invoice.id}:voucher:$postingKey'),
      type: VoucherType.receipt,
      date: invoice.invoiceDate,
      amount: amount,
      currency: invoice.currency,
      counterpartyId: counterpartyAccount,
      affectedAccountId: affectedAccount,
      referenceNumber: invoice.id,
      description: description,
      createdAt: createdAt,
    ).confirm(createdAt);
    return PosAccountingPosting(
      sourceId: invoice.id,
      voucher: voucher,
      entries: _entries.generateForConfirmedVoucher(
        voucher: voucher,
        transactionId: TransactionId('${voucher.id.value}:transaction'),
        debitEntryId: EntryId('${voucher.id.value}:debit'),
        creditEntryId: EntryId('${voucher.id.value}:credit'),
        ledgerCreatedAt: createdAt,
      ),
    );
  }

  FailureResult<PosSalesReturnPosting> _invalid(String code) =>
      FailureResult(ValidationFailure(messageAr: code, code: code));
}
