import 'dart:collection';

import 'package:qayd/domain/entities/pos_invoice_signature.dart';
import 'package:qayd/domain/exceptions/invalid_pos_invoice_exception.dart';
import 'package:qayd/domain/entities/pos_invoice_line_conversion.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

/// POS document direction. Returns are separate documents linked to a source.
enum PosInvoiceType { sale, purchase, salesReturn, purchaseReturn }

/// One immutable invoice line with snapshots for historical rendering.
final class PosInvoiceLine {
  const PosInvoiceLine._({
    required this.id,
    required this.invoiceId,
    required this.productId,
    required this.productNameSnapshot,
    required this.barcodeSnapshot,
    required this.quantity,
    required this.unitPrice,
    required this.unitCost,
    required this.discount,
    required this.tax,
    required this.lineTotal,
    required this.sourceLineId,
    required this.createdAt,
    this.currencyConversion,
    this.proposedSalePrice,
    this.proposedSalePriceApplied = false,
    this.productUpdatedAtSnapshot,
  });

  factory PosInvoiceLine.create({
    required String id,
    required String invoiceId,
    required String productId,
    required String productNameSnapshot,
    required PosQuantity quantity,
    required Money unitPrice,
    required Money unitCost,
    required Money discount,
    required Money tax,
    required DateTime createdAt,
    String? barcodeSnapshot,
    String? sourceLineId,
    PosInvoiceLineConversion? currencyConversion,
    Money? proposedSalePrice,
    bool proposedSalePriceApplied = false,
    DateTime? productUpdatedAtSnapshot,
  }) {
    if (id.trim().isEmpty ||
        invoiceId.trim().isEmpty ||
        productId.trim().isEmpty) {
      throw InvalidPosInvoiceException.invalidLine();
    }
    if (productNameSnapshot.trim().isEmpty || quantity.isZero) {
      throw InvalidPosInvoiceException.invalidLine();
    }
    _assertCurrency(unitPrice, discount, tax);
    if (unitPrice.isNegative ||
        unitCost.isNegative ||
        discount.isNegative ||
        tax.isNegative) {
      throw InvalidPosInvoiceException.invalidLine();
    }
    if (currencyConversion != null) {
      final conversionMatches = switch (currencyConversion.purpose) {
        PosInvoiceLineConversionPurpose.catalogSalePrice =>
          currencyConversion.targetAmount == unitPrice,
        PosInvoiceLineConversionPurpose.purchaseCost =>
          currencyConversion.sourceAmount == unitPrice &&
              currencyConversion.targetAmount == unitCost,
      };
      if (!conversionMatches) {
        throw InvalidPosInvoiceException.invalidLine();
      }
    }
    if (proposedSalePrice != null &&
        proposedSalePrice.currency != unitCost.currency) {
      throw InvalidPosInvoiceException.currencyMismatch();
    }
    if (proposedSalePriceApplied &&
        (proposedSalePrice == null || productUpdatedAtSnapshot == null)) {
      throw InvalidPosInvoiceException.invalidLine();
    }
    final gross = PosMoneyMath.multiply(quantity, unitPrice);
    if (discount.minorUnits > gross.minorUnits) {
      throw InvalidPosInvoiceException.invalidLine();
    }
    final net = gross.minorUnits - discount.minorUnits + tax.minorUnits;
    if (net < 0) throw InvalidPosInvoiceException.invalidLine();
    return PosInvoiceLine._(
      id: id.trim(),
      invoiceId: invoiceId.trim(),
      productId: productId.trim(),
      productNameSnapshot: productNameSnapshot.trim(),
      barcodeSnapshot: barcodeSnapshot?.trim(),
      quantity: quantity,
      unitPrice: unitPrice,
      unitCost: unitCost,
      discount: discount,
      tax: tax,
      lineTotal: Money.fromMinorUnits(net, unitPrice.currency),
      sourceLineId: sourceLineId?.trim(),
      createdAt: createdAt.toUtc(),
      currencyConversion: currencyConversion,
      proposedSalePrice: proposedSalePrice,
      proposedSalePriceApplied: proposedSalePriceApplied,
      productUpdatedAtSnapshot: productUpdatedAtSnapshot?.toUtc(),
    );
  }

  factory PosInvoiceLine.fromPersistence({
    required String id,
    required String invoiceId,
    required String productId,
    required String productNameSnapshot,
    required PosQuantity quantity,
    required Money unitPrice,
    required Money unitCost,
    required Money discount,
    required Money tax,
    required Money lineTotal,
    required DateTime createdAt,
    String? barcodeSnapshot,
    String? sourceLineId,
    PosInvoiceLineConversion? currencyConversion,
    Money? proposedSalePrice,
    bool proposedSalePriceApplied = false,
    DateTime? productUpdatedAtSnapshot,
  }) {
    final line = PosInvoiceLine.create(
      id: id,
      invoiceId: invoiceId,
      productId: productId,
      productNameSnapshot: productNameSnapshot,
      quantity: quantity,
      unitPrice: unitPrice,
      unitCost: unitCost,
      discount: discount,
      tax: tax,
      createdAt: createdAt,
      barcodeSnapshot: barcodeSnapshot,
      sourceLineId: sourceLineId,
      currencyConversion: currencyConversion,
      proposedSalePrice: proposedSalePrice,
      proposedSalePriceApplied: proposedSalePriceApplied,
      productUpdatedAtSnapshot: productUpdatedAtSnapshot,
    );
    if (line.lineTotal != lineTotal) {
      throw InvalidPosInvoiceException.invalidTotals();
    }
    return line;
  }

  final String id;
  final String invoiceId;
  final String productId;
  final String productNameSnapshot;
  final String? barcodeSnapshot;
  final PosQuantity quantity;
  final Money unitPrice;
  final Money unitCost;
  final Money discount;
  final Money tax;
  final Money lineTotal;
  final String? sourceLineId;
  final DateTime createdAt;
  final PosInvoiceLineConversion? currencyConversion;
  final Money? proposedSalePrice;
  final bool proposedSalePriceApplied;
  final DateTime? productUpdatedAtSnapshot;

  static void _assertCurrency(
    Money unitPrice,
    Money discount,
    Money tax,
  ) {
    final currency = unitPrice.currency;
    if (discount.currency != currency || tax.currency != currency) {
      throw InvalidPosInvoiceException.currencyMismatch();
    }
  }
}

/// Immutable POS invoice aggregate. Posted documents are never edited in place.
final class PosInvoice {
  const PosInvoice._({
    required this.id,
    required this.invoiceNumber,
    required this.type,
    required this.status,
    required this.counterpartyAccountId,
    required this.warehouseId,
    required this.sourceInvoiceId,
    required this.currency,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paid,
    required this.due,
    required this.idempotencyKey,
    required this.invoiceDate,
    required this.createdAt,
    required this.updatedAt,
    required this.postedAt,
    required this.signature,
  });

  factory PosInvoice.draft({
    required String id,
    required String invoiceNumber,
    required PosInvoiceType type,
    required String warehouseId,
    required CurrencyCode currency,
    required List<PosInvoiceLine> lines,
    required String idempotencyKey,
    required DateTime invoiceDate,
    required DateTime now,
    AccountId? counterpartyAccountId,
    String? sourceInvoiceId,
    Money? discount,
    Money? tax,
  }) {
    if (id.trim().isEmpty ||
        invoiceNumber.trim().isEmpty ||
        warehouseId.trim().isEmpty) {
      throw InvalidPosInvoiceException.requiredField();
    }
    if (lines.isEmpty) throw InvalidPosInvoiceException.linesRequired();
    if (idempotencyKey.trim().isEmpty) {
      throw InvalidPosInvoiceException.requiredField();
    }
    final immutableLines = List<PosInvoiceLine>.unmodifiable(lines);
    for (final line in immutableLines) {
      if (line.invoiceId != id.trim() || line.unitPrice.currency != currency) {
        throw InvalidPosInvoiceException.invalidLine();
      }
    }
    final zero = Money.zero(currency);
    final appliedDiscount = discount ?? zero;
    final appliedTax = tax ?? zero;
    if (appliedDiscount.currency != currency ||
        appliedTax.currency != currency) {
      throw InvalidPosInvoiceException.currencyMismatch();
    }
    final subtotalMinor = immutableLines.fold<int>(
      0,
      (sum, line) =>
          sum + PosMoneyMath.multiply(line.quantity, line.unitPrice).minorUnits,
    );
    final lineDiscountMinor = immutableLines.fold<int>(
      0,
      (sum, line) => sum + line.discount.minorUnits,
    );
    final totalMinor = subtotalMinor -
        lineDiscountMinor -
        appliedDiscount.minorUnits +
        immutableLines.fold<int>(0, (sum, line) => sum + line.tax.minorUnits) +
        appliedTax.minorUnits;
    if (totalMinor < 0) throw InvalidPosInvoiceException.invalidTotals();
    final timestamp = now.toUtc();
    return PosInvoice._(
      id: id.trim(),
      invoiceNumber: invoiceNumber.trim(),
      type: type,
      status: PosDocumentStatus.draft,
      counterpartyAccountId: counterpartyAccountId,
      warehouseId: warehouseId.trim(),
      sourceInvoiceId: sourceInvoiceId?.trim(),
      currency: currency,
      lines: UnmodifiableListView(immutableLines),
      subtotal: Money.fromMinorUnits(subtotalMinor, currency),
      discount: Money.fromMinorUnits(
          lineDiscountMinor + appliedDiscount.minorUnits, currency),
      tax: Money.fromMinorUnits(
        immutableLines.fold<int>(0, (sum, line) => sum + line.tax.minorUnits) +
            appliedTax.minorUnits,
        currency,
      ),
      total: Money.fromMinorUnits(totalMinor, currency),
      paid: zero,
      due: Money.fromMinorUnits(totalMinor, currency),
      idempotencyKey: idempotencyKey.trim(),
      invoiceDate: invoiceDate.toUtc(),
      createdAt: timestamp,
      updatedAt: timestamp,
      postedAt: null,
      signature: null,
    );
  }

  final String id;
  final String invoiceNumber;
  final PosInvoiceType type;
  final PosDocumentStatus status;
  final AccountId? counterpartyAccountId;
  final String warehouseId;
  final String? sourceInvoiceId;
  final CurrencyCode currency;
  final UnmodifiableListView<PosInvoiceLine> lines;
  final Money subtotal;
  final Money discount;
  final Money tax;
  final Money total;
  final Money paid;
  final Money due;
  final String idempotencyKey;
  final DateTime invoiceDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? postedAt;
  final PosInvoiceSignature? signature;

  factory PosInvoice.fromPersistence({
    required String id,
    required String invoiceNumber,
    required PosInvoiceType type,
    required PosDocumentStatus status,
    required AccountId? counterpartyAccountId,
    required String warehouseId,
    required String? sourceInvoiceId,
    required CurrencyCode currency,
    required List<PosInvoiceLine> lines,
    required Money subtotal,
    required Money discount,
    required Money tax,
    required Money total,
    required Money paid,
    required Money due,
    required String idempotencyKey,
    required DateTime invoiceDate,
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime? postedAt,
    required PosInvoiceSignature? signature,
  }) {
    if (lines.isEmpty ||
        subtotal.currency != currency ||
        discount.currency != currency ||
        tax.currency != currency ||
        total.currency != currency ||
        paid.currency != currency ||
        due.currency != currency ||
        paid.minorUnits < 0 ||
        due.minorUnits < 0 ||
        paid.minorUnits + due.minorUnits != total.minorUnits) {
      throw InvalidPosInvoiceException.invalidTotals();
    }
    for (final line in lines) {
      if (line.invoiceId != id || line.unitPrice.currency != currency) {
        throw InvalidPosInvoiceException.invalidLine();
      }
    }
    return PosInvoice._(
      id: id,
      invoiceNumber: invoiceNumber,
      type: type,
      status: status,
      counterpartyAccountId: counterpartyAccountId,
      warehouseId: warehouseId,
      sourceInvoiceId: sourceInvoiceId,
      currency: currency,
      lines: UnmodifiableListView(lines),
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      paid: paid,
      due: due,
      idempotencyKey: idempotencyKey,
      invoiceDate: invoiceDate.toUtc(),
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      postedAt: postedAt?.toUtc(),
      signature: signature,
    );
  }

  PosInvoice post(DateTime at) {
    if (!status.isDraft || !status.canTransitionTo(PosDocumentStatus.posted)) {
      throw InvalidPosInvoiceException.invalidTransition();
    }
    return _copy(status: PosDocumentStatus.posted, postedAt: at, updatedAt: at);
  }

  PosInvoice applyPayment(Money amount, DateTime at) {
    if (amount.currency != currency ||
        amount.isNegative ||
        (amount.isZero && total.minorUnits != 0)) {
      throw InvalidPosInvoiceException.invalidPayment();
    }
    final newPaid = paid.minorUnits + amount.minorUnits;
    if (newPaid > total.minorUnits) {
      throw InvalidPosInvoiceException.invalidPayment();
    }
    final newDue = total.minorUnits - newPaid;
    final newStatus =
        newDue == 0 ? PosDocumentStatus.paid : PosDocumentStatus.partiallyPaid;
    if (!status.canTransitionTo(newStatus)) {
      throw InvalidPosInvoiceException.invalidTransition();
    }
    return _copy(
      status: newStatus,
      paid: Money.fromMinorUnits(newPaid, currency),
      due: Money.fromMinorUnits(newDue, currency),
      updatedAt: at,
    );
  }

  PosInvoice attachSignature(PosInvoiceSignature value, DateTime at) {
    if (value.invoiceId != id) {
      throw InvalidPosInvoiceException.signatureMismatch();
    }
    return _copy(signature: value, updatedAt: at);
  }

  PosInvoice _copy({
    PosDocumentStatus? status,
    Money? paid,
    Money? due,
    DateTime? postedAt,
    DateTime? updatedAt,
    PosInvoiceSignature? signature,
  }) =>
      PosInvoice._(
        id: id,
        invoiceNumber: invoiceNumber,
        type: type,
        status: status ?? this.status,
        counterpartyAccountId: counterpartyAccountId,
        warehouseId: warehouseId,
        sourceInvoiceId: sourceInvoiceId,
        currency: currency,
        lines: lines,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        total: total,
        paid: paid ?? this.paid,
        due: due ?? this.due,
        idempotencyKey: idempotencyKey,
        invoiceDate: invoiceDate,
        createdAt: createdAt,
        updatedAt: (updatedAt ?? this.updatedAt).toUtc(),
        postedAt: postedAt ?? this.postedAt,
        signature: signature ?? this.signature,
      );
}
