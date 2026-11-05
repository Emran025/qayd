import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_signature.dart';
import 'package:qayd/domain/services/pos_money_math.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

/// Immutable, presentation-only invoice data sent to a credit customer.
///
/// This snapshot is deliberately not a [PosInvoice] persistence record. It
/// omits local account, warehouse, inventory-cost, and idempotency identifiers.
/// [toPdfInvoice] creates an in-memory document projection only; it must never
/// be passed to a POS posting repository.
final class PosCreditInvoiceChatSnapshot {
  const PosCreditInvoiceChatSnapshot._({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.counterpartyAccountId,
    required this.creditDueDate,
    required this.creditTerms,
    required this.status,
    required this.currency,
    required this.subtotalMinorUnits,
    required this.discountMinorUnits,
    required this.cartDiscountMinorUnits,
    required this.invoiceLevelTaxMinorUnits,
    required this.taxMinorUnits,
    required this.totalMinorUnits,
    required this.paidMinorUnits,
    required this.dueMinorUnits,
    required this.invoiceDate,
    required this.createdAt,
    required this.updatedAt,
    required this.postedAt,
    required this.lines,
    required this.signature,
  });

  static const schema = 'qayd_pos_credit_invoice_snapshot_v2';
  static const maxLines = 500;
  static const maxSerializedBytes = 240 * 1024;
  static const maxExactInteger = 9007199254740991;
  static const _snapshotFields = <String>{
    'schema',
    'invoice_id',
    'invoice_number',
    'counterparty_account_id',
    'credit_due_date',
    'credit_terms',
    'status',
    'currency',
    'subtotal_minor',
    'discount_minor',
    'cart_discount_minor',
    'invoice_level_tax_minor',
    'tax_minor',
    'total_minor',
    'paid_minor',
    'due_minor',
    'invoice_date',
    'created_at',
    'updated_at',
    'posted_at',
    'lines',
    'signature',
  };

  final String invoiceId;
  final String invoiceNumber;
  final String counterpartyAccountId;
  final DateTime? creditDueDate;
  final String? creditTerms;
  final PosDocumentStatus status;
  final CurrencyCode currency;
  final int subtotalMinorUnits;
  final int discountMinorUnits;
  final int cartDiscountMinorUnits;
  final int invoiceLevelTaxMinorUnits;
  final int taxMinorUnits;
  final int totalMinorUnits;
  final int paidMinorUnits;
  final int dueMinorUnits;
  final DateTime invoiceDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime postedAt;
  final List<PosCreditInvoiceChatLine> lines;
  final PosInvoiceSignature? signature;

  factory PosCreditInvoiceChatSnapshot.fromInvoice(PosInvoice invoice) {
    if (invoice.type != PosInvoiceType.sale ||
        invoice.due.minorUnits <= 0 ||
        (invoice.status != PosDocumentStatus.posted &&
            invoice.status != PosDocumentStatus.partiallyPaid) ||
        invoice.postedAt == null) {
      throw const FormatException('Only posted credit sales can be shared.');
    }
    final counterpartyAccountId = invoice.counterpartyAccountId?.value;
    if (counterpartyAccountId == null ||
        counterpartyAccountId.isEmpty ||
        counterpartyAccountId.length > 128) {
      throw const FormatException('A valid invoice counterparty is required.');
    }
    if (invoice.lines.length > maxLines ||
        invoice.id.length > 128 ||
        invoice.invoiceNumber.length > 128) {
      throw const FormatException('POS credit invoice is too large.');
    }
    for (final line in invoice.lines) {
      if (line.productNameSnapshot.length > 240 ||
          (line.barcodeSnapshot?.length ?? 0) > 128) {
        throw const FormatException('POS credit invoice line is too large.');
      }
    }
    final lineTaxMinorUnits = invoice.lines.fold<BigInt>(
      BigInt.zero,
      (sum, line) => sum + BigInt.from(line.tax.minorUnits),
    );
    final invoiceLevelTax =
        BigInt.from(invoice.tax.minorUnits) - lineTaxMinorUnits;
    if (invoiceLevelTax < BigInt.zero ||
        invoiceLevelTax > BigInt.from(maxExactInteger)) {
      throw const FormatException('Invalid invoice tax total.');
    }
    final map = <String, dynamic>{
      'schema': schema,
      'invoice_id': invoice.id,
      'invoice_number': invoice.invoiceNumber,
      'counterparty_account_id': counterpartyAccountId,
      'credit_due_date': invoice.creditDueDate == null
          ? null
          : _dateOnlyJson(invoice.creditDueDate!),
      'credit_terms': invoice.creditTerms,
      'status': invoice.status.name,
      'currency': <String, dynamic>{
        'code': invoice.currency.code,
        'name_ar': invoice.currency.nameAr,
        'symbol': invoice.currency.symbol,
        'fractional_digits': invoice.currency.fractionalDigits,
      },
      'subtotal_minor': invoice.subtotal.minorUnits,
      'discount_minor': invoice.discount.minorUnits,
      'cart_discount_minor': invoice.cartDiscount.minorUnits,
      'invoice_level_tax_minor': invoiceLevelTax.toInt(),
      'tax_minor': invoice.tax.minorUnits,
      'total_minor': invoice.total.minorUnits,
      'paid_minor': invoice.paid.minorUnits,
      'due_minor': invoice.due.minorUnits,
      'invoice_date': invoice.invoiceDate.toUtc().toIso8601String(),
      'created_at': invoice.createdAt.toUtc().toIso8601String(),
      'updated_at': invoice.updatedAt.toUtc().toIso8601String(),
      'posted_at': invoice.postedAt!.toUtc().toIso8601String(),
      'lines': invoice.lines
          .map(
            (line) => <String, dynamic>{
              'name': line.productNameSnapshot,
              'barcode': line.barcodeSnapshot,
              'quantity_scaled': line.quantity.scaledUnits,
              'quantity_scale': line.quantity.scale,
              'unit_price_minor': line.unitPrice.minorUnits,
              'discount_minor': line.discount.minorUnits,
              'tax_minor': line.tax.minorUnits,
              'line_total_minor': line.lineTotal.minorUnits,
            },
          )
          .toList(growable: false),
      'signature': invoice.signature == null
          ? null
          : <String, dynamic>{
              'signature_hex': invoice.signature!.signatureHex,
              'signer_public_key_hex': invoice.signature!.signerPublicKeyHex,
              'payload_hash_hex': invoice.signature!.payloadHashHex,
              'signed_at': invoice.signature!.signedAt
                  .toUtc()
                  .toIso8601String(),
            },
    };
    return PosCreditInvoiceChatSnapshot.fromJson(map);
  }

  factory PosCreditInvoiceChatSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != schema ||
        json.length != _snapshotFields.length ||
        json.keys.any((key) => !_snapshotFields.contains(key))) {
      throw const FormatException('Unsupported POS credit invoice snapshot.');
    }
    if (utf8.encode(jsonEncode(json)).length > maxSerializedBytes) {
      throw const FormatException('POS credit invoice snapshot is too large.');
    }
    final invoiceId = _readString(json['invoice_id'], 'invoice_id', max: 128);
    final invoiceNumber = _readString(
      json['invoice_number'],
      'invoice_number',
      max: 128,
    );
    final counterpartyAccountId = _readString(
      json['counterparty_account_id'],
      'counterparty_account_id',
      max: 128,
    );
    final creditDueDateValue = json['credit_due_date'];
    final creditDueDate = creditDueDateValue == null
        ? null
        : _readDateOnly(creditDueDateValue, 'credit_due_date');
    final creditTermsValue = json['credit_terms'];
    final creditTerms = creditTermsValue == null
        ? null
        : _readString(creditTermsValue, 'credit_terms', max: 240);
    if (creditTerms != null && creditTerms != creditTerms.trim()) {
      throw const FormatException('Invalid credit terms.');
    }
    final statusName = _readString(json['status'], 'status', max: 32);
    final status = PosDocumentStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => throw const FormatException('Invalid invoice status.'),
    );
    if (status != PosDocumentStatus.posted &&
        status != PosDocumentStatus.partiallyPaid) {
      throw const FormatException('Invoice is not an open posted credit sale.');
    }

    final currencyMap = _readMap(json['currency'], 'currency');
    final code = _readString(currencyMap['code'], 'currency.code', max: 12);
    final nameAr = _readString(
      currencyMap['name_ar'],
      'currency.name_ar',
      max: 80,
    );
    final symbol = _readString(
      currencyMap['symbol'],
      'currency.symbol',
      max: 20,
    );
    final digits = _readInt(
      currencyMap['fractional_digits'],
      'currency.digits',
    );
    if (digits < 0 || digits > PosQuantity.maxScale) {
      throw const FormatException('Invalid currency precision.');
    }
    final currency = CurrencyCode(
      code: code,
      nameAr: nameAr,
      symbol: symbol,
      fractionalDigits: digits,
    );

    final lineJson = json['lines'];
    if (lineJson is! List || lineJson.isEmpty || lineJson.length > maxLines) {
      throw const FormatException('Invalid invoice lines.');
    }
    final lines = <PosCreditInvoiceChatLine>[];
    var calculatedSubtotal = 0;
    var lineDiscount = 0;
    var lineTax = 0;
    for (final value in lineJson) {
      final lineMap = _readMap(value, 'line');
      final name = _readString(lineMap['name'], 'line.name', max: 240);
      final barcodeValue = lineMap['barcode'];
      final barcode = barcodeValue == null
          ? null
          : _readString(barcodeValue, 'line.barcode', max: 128);
      final quantityScaled = _readInt(
        lineMap['quantity_scaled'],
        'line.quantity_scaled',
      );
      final quantity = PosQuantity.fromScaled(
        quantityScaled,
        scale: _readInt(lineMap['quantity_scale'], 'line.quantity_scale'),
        allowZero: false,
      );
      final unitPrice = _readInt(
        lineMap['unit_price_minor'],
        'line.unit_price_minor',
      );
      final discount = _readInt(
        lineMap['discount_minor'],
        'line.discount_minor',
      );
      final tax = _readInt(lineMap['tax_minor'], 'line.tax_minor');
      final lineTotal = _readInt(
        lineMap['line_total_minor'],
        'line.line_total_minor',
      );
      if (unitPrice < 0 || discount < 0 || tax < 0 || lineTotal < 0) {
        throw const FormatException('Invalid invoice line amount.');
      }
      final unscaledProduct =
          BigInt.from(quantity.scaledUnits) * BigInt.from(unitPrice);
      if (unscaledProduct > BigInt.from(maxExactInteger)) {
        throw const FormatException('Invoice line amount is too large.');
      }
      final price = Money.fromMinorUnits(unitPrice, currency);
      final quantityGross = PosMoneyMath.multiply(quantity, price).minorUnits;
      final expectedLineTotal =
          BigInt.from(quantityGross) - BigInt.from(discount) + BigInt.from(tax);
      if (discount > quantityGross ||
          expectedLineTotal < BigInt.zero ||
          expectedLineTotal > BigInt.from(maxExactInteger) ||
          lineTotal != expectedLineTotal.toInt()) {
        throw const FormatException('Invoice line totals do not match.');
      }
      calculatedSubtotal = _checkedAdd(calculatedSubtotal, quantityGross);
      lineDiscount = _checkedAdd(lineDiscount, discount);
      lineTax = _checkedAdd(lineTax, tax);
      lines.add(
        PosCreditInvoiceChatLine(
          productName: name,
          barcode: barcode,
          quantity: quantity,
          unitPriceMinorUnits: unitPrice,
          discountMinorUnits: discount,
          taxMinorUnits: tax,
          lineTotalMinorUnits: lineTotal,
        ),
      );
    }

    final subtotal = _readInt(json['subtotal_minor'], 'subtotal_minor');
    final discount = _readInt(json['discount_minor'], 'discount_minor');
    final cartDiscount = _readInt(
      json['cart_discount_minor'],
      'cart_discount_minor',
    );
    final invoiceLevelTax = _readInt(
      json['invoice_level_tax_minor'],
      'invoice_level_tax_minor',
    );
    final tax = _readInt(json['tax_minor'], 'tax_minor');
    final total = _readInt(json['total_minor'], 'total_minor');
    final paid = _readInt(json['paid_minor'], 'paid_minor');
    final due = _readInt(json['due_minor'], 'due_minor');
    final expectedDiscount =
        BigInt.from(lineDiscount) + BigInt.from(cartDiscount);
    final expectedTax = BigInt.from(lineTax) + BigInt.from(invoiceLevelTax);
    final expectedTotal =
        BigInt.from(subtotal) - BigInt.from(discount) + BigInt.from(tax);
    final paidAndDue = BigInt.from(paid) + BigInt.from(due);
    if (subtotal < 0 ||
        discount < 0 ||
        cartDiscount < 0 ||
        invoiceLevelTax < 0 ||
        tax < 0 ||
        total < 0 ||
        subtotal != calculatedSubtotal ||
        lineDiscount > subtotal ||
        cartDiscount > subtotal - lineDiscount ||
        expectedDiscount != BigInt.from(discount) ||
        expectedTax != BigInt.from(tax) ||
        expectedTotal != BigInt.from(total) ||
        paid < 0 ||
        due <= 0 ||
        paidAndDue != BigInt.from(total)) {
      throw const FormatException('Invoice totals do not match.');
    }

    final signatureValue = json['signature'];
    PosInvoiceSignature? signature;
    if (signatureValue != null) {
      final signatureMap = _readMap(signatureValue, 'signature');
      final signatureHex = _readHex(
        signatureMap['signature_hex'],
        'signature.signature_hex',
        128,
      );
      final publicKeyHex = _readHex(
        signatureMap['signer_public_key_hex'],
        'signature.signer_public_key_hex',
        64,
      );
      final payloadHashHex = _readHex(
        signatureMap['payload_hash_hex'],
        'signature.payload_hash_hex',
        64,
      );
      signature = PosInvoiceSignature(
        invoiceId: invoiceId,
        signatureHex: signatureHex,
        signerPublicKeyHex: publicKeyHex,
        payloadHashHex: payloadHashHex,
        signedAt: _readDate(signatureMap['signed_at'], 'signature.signed_at'),
      );
    }

    return PosCreditInvoiceChatSnapshot._(
      invoiceId: invoiceId,
      invoiceNumber: invoiceNumber,
      counterpartyAccountId: counterpartyAccountId,
      creditDueDate: creditDueDate,
      creditTerms: creditTerms,
      status: status,
      currency: currency,
      subtotalMinorUnits: subtotal,
      discountMinorUnits: discount,
      cartDiscountMinorUnits: cartDiscount,
      invoiceLevelTaxMinorUnits: invoiceLevelTax,
      taxMinorUnits: tax,
      totalMinorUnits: total,
      paidMinorUnits: paid,
      dueMinorUnits: due,
      invoiceDate: _readDate(json['invoice_date'], 'invoice_date'),
      createdAt: _readDate(json['created_at'], 'created_at'),
      updatedAt: _readDate(json['updated_at'], 'updated_at'),
      postedAt: _readDate(json['posted_at'], 'posted_at'),
      lines: List.unmodifiable(lines),
      signature: signature,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema': schema,
    'invoice_id': invoiceId,
    'invoice_number': invoiceNumber,
    'counterparty_account_id': counterpartyAccountId,
    'credit_due_date': creditDueDate == null
        ? null
        : _dateOnlyJson(creditDueDate!),
    'credit_terms': creditTerms,
    'status': status.name,
    'currency': <String, dynamic>{
      'code': currency.code,
      'name_ar': currency.nameAr,
      'symbol': currency.symbol,
      'fractional_digits': currency.fractionalDigits,
    },
    'subtotal_minor': subtotalMinorUnits,
    'discount_minor': discountMinorUnits,
    'cart_discount_minor': cartDiscountMinorUnits,
    'invoice_level_tax_minor': invoiceLevelTaxMinorUnits,
    'tax_minor': taxMinorUnits,
    'total_minor': totalMinorUnits,
    'paid_minor': paidMinorUnits,
    'due_minor': dueMinorUnits,
    'invoice_date': invoiceDate.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'posted_at': postedAt.toUtc().toIso8601String(),
    'lines': lines.map((line) => line.toJson()).toList(growable: false),
    'signature': signature == null
        ? null
        : <String, dynamic>{
            'signature_hex': signature!.signatureHex,
            'signer_public_key_hex': signature!.signerPublicKeyHex,
            'payload_hash_hex': signature!.payloadHashHex,
            'signed_at': signature!.signedAt.toUtc().toIso8601String(),
          },
  };

  String get fingerprint =>
      crypto.sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();

  /// Creates an in-memory document projection for the existing PDF renderer.
  /// This value is not persisted and is never suitable for POS posting.
  PosInvoice toPdfInvoice() {
    final invoiceLines = <PosInvoiceLine>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      invoiceLines.add(
        PosInvoiceLine.fromPersistence(
          id: 'shared-line-$index',
          invoiceId: invoiceId,
          productId: 'shared-product-$index',
          productNameSnapshot: line.productName,
          barcodeSnapshot: line.barcode,
          quantity: line.quantity,
          unitPrice: Money.fromMinorUnits(line.unitPriceMinorUnits, currency),
          unitCost: Money.zero(currency),
          discount: Money.fromMinorUnits(line.discountMinorUnits, currency),
          tax: Money.fromMinorUnits(line.taxMinorUnits, currency),
          lineTotal: Money.fromMinorUnits(line.lineTotalMinorUnits, currency),
          createdAt: createdAt,
        ),
      );
    }
    return PosInvoice.fromPersistence(
      id: invoiceId,
      invoiceNumber: invoiceNumber,
      type: PosInvoiceType.sale,
      status: status,
      counterpartyAccountId: null,
      warehouseId: 'shared-document',
      sourceInvoiceId: null,
      currency: currency,
      lines: invoiceLines,
      subtotal: Money.fromMinorUnits(subtotalMinorUnits, currency),
      discount: Money.fromMinorUnits(discountMinorUnits, currency),
      cartDiscount: Money.fromMinorUnits(cartDiscountMinorUnits, currency),
      tax: Money.fromMinorUnits(taxMinorUnits, currency),
      total: Money.fromMinorUnits(totalMinorUnits, currency),
      paid: Money.fromMinorUnits(paidMinorUnits, currency),
      due: Money.fromMinorUnits(dueMinorUnits, currency),
      creditDueDate: creditDueDate,
      creditTerms: creditTerms,
      idempotencyKey: 'shared:$invoiceId',
      invoiceDate: invoiceDate,
      createdAt: createdAt,
      updatedAt: updatedAt,
      postedAt: postedAt,
      // The current PDF renderer labels every non-null signature as verified
      // without verifying it; never imply verification for a received snapshot.
      signature: null,
    );
  }
}

final class PosCreditInvoiceChatLine {
  const PosCreditInvoiceChatLine({
    required this.productName,
    required this.barcode,
    required this.quantity,
    required this.unitPriceMinorUnits,
    required this.discountMinorUnits,
    required this.taxMinorUnits,
    required this.lineTotalMinorUnits,
  });

  final String productName;
  final String? barcode;
  final PosQuantity quantity;
  final int unitPriceMinorUnits;
  final int discountMinorUnits;
  final int taxMinorUnits;
  final int lineTotalMinorUnits;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': productName,
    'barcode': barcode,
    'quantity_scaled': quantity.scaledUnits,
    'quantity_scale': quantity.scale,
    'unit_price_minor': unitPriceMinorUnits,
    'discount_minor': discountMinorUnits,
    'tax_minor': taxMinorUnits,
    'line_total_minor': lineTotalMinorUnits,
  };
}

Map<String, dynamic> _readMap(Object? value, String field) {
  if (value is! Map) throw FormatException('Invalid $field.');
  return Map<String, dynamic>.from(value);
}

String _readString(Object? value, String field, {required int max}) {
  if (value is! String || value.trim().isEmpty || value.length > max) {
    throw FormatException('Invalid $field.');
  }
  return value.trim();
}

int _readInt(Object? value, String field) {
  if (value is! num || !value.isFinite || value.toInt() != value) {
    throw FormatException('Invalid $field.');
  }
  final parsed = value.toInt();
  if (parsed < -PosCreditInvoiceChatSnapshot.maxExactInteger ||
      parsed > PosCreditInvoiceChatSnapshot.maxExactInteger) {
    throw FormatException('Invalid $field.');
  }
  return parsed;
}

int _checkedAdd(int left, int right) {
  if (right < 0 ||
      left < 0 ||
      left > PosCreditInvoiceChatSnapshot.maxExactInteger - right) {
    throw const FormatException('POS invoice amount is too large.');
  }
  return left + right;
}

DateTime _readDate(Object? value, String field) {
  if (value is! String) throw FormatException('Invalid $field.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid $field.');
  return parsed.toUtc();
}

DateTime _readDateOnly(Object? value, String field) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw FormatException('Invalid $field.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || _dateOnlyJson(parsed) != value) {
    throw FormatException('Invalid $field.');
  }
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

String _dateOnlyJson(DateTime value) =>
    '${value.toUtc().year.toString().padLeft(4, '0')}-'
    '${value.toUtc().month.toString().padLeft(2, '0')}-'
    '${value.toUtc().day.toString().padLeft(2, '0')}';

String _readHex(Object? value, String field, int length) {
  if (value is! String ||
      value.length != length ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw FormatException('Invalid $field.');
  }
  return value.toLowerCase();
}
