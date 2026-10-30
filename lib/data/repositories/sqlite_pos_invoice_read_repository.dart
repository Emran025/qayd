import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_details.dart';
import 'package:qayd/domain/entities/pos_invoice_line_conversion.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_invoice_signature.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/pos_invoice_read_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final class SqlitePosInvoiceReadRepository implements PosInvoiceReadRepository {
  const SqlitePosInvoiceReadRepository(this._db, this._currencyRepository);

  final Database _db;
  final CurrencyRepository _currencyRepository;

  @override
  Future<Result<PosInvoiceDetails?>> getById(String invoiceId) async {
    try {
      final rows = await _db.query(
        'pos_invoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      if (rows.isEmpty) return const Success(null);
      return Success(await _mapDetails(rows.single));
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  @override
  Future<Result<List<PosInvoiceDetails>>> getReturnsForSource(
    String sourceInvoiceId,
  ) async {
    try {
      final rows = await _db.query(
        'pos_invoices',
        where: 'source_invoice_id = ? AND document_type = ?',
        whereArgs: [sourceInvoiceId, 'sales_return'],
        orderBy: 'invoice_date ASC, created_at ASC',
      );
      final result = <PosInvoiceDetails>[];
      for (final row in rows) result.add(await _mapDetails(row));
      return Success(List.unmodifiable(result));
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  @override
  Future<Result<List<PosInvoice>>> list({
    DateTime? from,
    DateTime? to,
    PosInvoiceType? type,
    int? limit,
  }) async {
    try {
      final where = <String>[];
      final args = <Object?>[];
      if (from != null) {
        where.add('invoice_date >= ?');
        args.add(from.toUtc().toIso8601String());
      }
      if (to != null) {
        where.add('invoice_date <= ?');
        args.add(to.toUtc().toIso8601String());
      }
      if (type != null) {
        where.add('document_type = ?');
        args.add(_typeToStorage(type));
      }
      final rows = await _db.query(
        'pos_invoices',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'invoice_date DESC, created_at DESC',
        limit: limit,
      );
      final invoices = <PosInvoice>[];
      for (final row in rows) {
        invoices.add((await _mapDetails(row)).invoice);
      }
      return Success(List.unmodifiable(invoices));
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  Future<PosInvoiceDetails> _mapDetails(Map<String, Object?> row) async {
    final currencyResult = await _currencyRepository.getByCode(
      _string(row, 'currency_code'),
    );
    if (currencyResult.isFailure) throw currencyResult.failureOrNull!;
    final currency = currencyResult.valueOrNull;
    if (currency == null) {
      throw FormatException('Missing currency for POS invoice');
    }
    final invoiceId = _string(row, 'id');
    final lineRows = await _db.query(
      'pos_invoice_lines',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'created_at ASC, id ASC',
    );
    final paymentRows = await _db.query(
      'pos_payments',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'occurred_at ASC, id ASC',
    );
    final lines = (await Future.wait(
      lineRows.map((line) => _lineFromRow(line, currency)),
    ))
        .toList(growable: false);
    final invoice = PosInvoice.fromPersistence(
      id: invoiceId,
      invoiceNumber: _string(row, 'invoice_number'),
      type: _typeFromStorage(_string(row, 'document_type')),
      status: _statusFromStorage(_string(row, 'status')),
      counterpartyAccountId: _nullableAccount(row['counterparty_account_id']),
      warehouseId: _string(row, 'warehouse_id'),
      sourceInvoiceId: row['source_invoice_id'] as String?,
      currency: currency,
      lines: lines,
      subtotal: _money(row, 'subtotal_minor', currency),
      discount: _money(row, 'discount_minor', currency),
      tax: _money(row, 'tax_minor', currency),
      total: _money(row, 'total_minor', currency),
      paid: _money(row, 'paid_minor', currency),
      due: _money(row, 'due_minor', currency),
      idempotencyKey: _string(row, 'idempotency_key'),
      invoiceDate: DateTime.parse(_string(row, 'invoice_date')),
      createdAt: DateTime.parse(_string(row, 'created_at')),
      updatedAt: DateTime.parse(_string(row, 'updated_at')),
      postedAt: _nullableDate(row['posted_at']),
      signature: _signatureFromRow(row),
    );
    final payments = paymentRows
        .map((payment) => _paymentFromRow(payment, currency))
        .toList(growable: false);
    return PosInvoiceDetails(invoice: invoice, payments: payments);
  }

  Future<PosInvoiceLine> _lineFromRow(
    Map<String, Object?> row,
    CurrencyCode currency,
  ) async {
    final costCode = row['unit_cost_currency_code'] as String?;
    final costCurrency = costCode == null || costCode.isEmpty
        ? currency
        : (await _currencyRepository.getByCode(costCode)).valueOrNull;
    if (costCurrency == null) {
      throw FormatException('Missing currency for POS invoice line cost');
    }
    final conversion = await _conversionFromRow(row);
    final proposedMinor = row['proposed_sale_price_minor'];
    final proposedSalePrice = proposedMinor == null
        ? null
        : Money.fromMinorUnits(_asInt(proposedMinor), costCurrency);
    return PosInvoiceLine.fromPersistence(
      id: _string(row, 'id'),
      invoiceId: _string(row, 'invoice_id'),
      productId: _string(row, 'product_id'),
      productNameSnapshot: _string(row, 'product_name_snapshot'),
      barcodeSnapshot: row['barcode_snapshot'] as String?,
      quantity: PosQuantity.fromScaled(
        _int(row, 'quantity_scaled'),
        scale: _int(row, 'quantity_scale'),
      ),
      unitPrice: _money(row, 'unit_price_minor', currency),
      unitCost: _money(
        row,
        'unit_cost_minor',
        costCurrency,
      ),
      discount: _money(row, 'discount_minor', currency),
      tax: _money(row, 'tax_minor', currency),
      lineTotal: _money(row, 'line_total_minor', currency),
      sourceLineId: row['source_line_id'] as String?,
      createdAt: DateTime.parse(_string(row, 'created_at')),
      currencyConversion: conversion,
      proposedSalePrice: proposedSalePrice,
      proposedSalePriceApplied:
          _asInt(row['proposed_sale_price_applied'] ?? 0) == 1,
      productUpdatedAtSnapshot:
          _nullableDate(row['product_updated_at_snapshot']),
    );
  }

  Future<PosInvoiceLineConversion?> _conversionFromRow(
    Map<String, Object?> row,
  ) async {
    final purposeValue = row['conversion_purpose'] as String?;
    if (purposeValue == null) return null;
    final purpose = PosInvoiceLineConversionPurpose.values.firstWhere(
      (value) => value.name == purposeValue,
      orElse: () => throw FormatException('Unknown POS line conversion'),
    );
    final sourceCurrency = await _getCurrency(
      _string(row, 'conversion_source_currency_code'),
    );
    final targetCurrency = await _getCurrency(
      _string(row, 'conversion_target_currency_code'),
    );
    final rateId = row['fx_rate_id'] as String?;
    PosCurrencyRateQuote? rate;
    if (rateId != null) {
      rate = PosCurrencyRateQuote(
        rateId: rateId,
        storedFromCurrency: await _getCurrency(
          _string(row, 'fx_stored_from_code'),
        ),
        storedToCurrency: await _getCurrency(
          _string(row, 'fx_stored_to_code'),
        ),
        storedRateScaled: _int(row, 'fx_rate_scaled'),
        requestedFromCurrency: await _getCurrency(
          _string(row, 'fx_requested_from_code'),
        ),
        requestedToCurrency: await _getCurrency(
          _string(row, 'fx_requested_to_code'),
        ),
        effectiveAt: DateTime.parse(_string(row, 'fx_effective_at')),
        recordedAt: DateTime.parse(_string(row, 'fx_recorded_at')),
        createdAt: DateTime.parse(_string(row, 'fx_created_at')),
        isInverted: _asInt(row['fx_is_inverted']) == 1,
        note: row['fx_note'] as String?,
      );
    }
    return PosInvoiceLineConversion(
      purpose: purpose,
      sourceAmount: Money.fromMinorUnits(
        _int(row, 'conversion_source_minor'),
        sourceCurrency,
      ),
      targetAmount: Money.fromMinorUnits(
        _int(row, 'conversion_target_minor'),
        targetCurrency,
      ),
      rateSnapshot: rate,
    );
  }

  Future<CurrencyCode> _getCurrency(String code) async {
    final result = await _currencyRepository.getByCode(code);
    if (result.isFailure) throw result.failureOrNull!;
    final currency = result.valueOrNull;
    if (currency == null) throw FormatException('Missing currency $code');
    return currency;
  }

  PosInvoicePayment _paymentFromRow(
    Map<String, Object?> row,
    CurrencyCode currency,
  ) {
    return PosInvoicePayment(
      id: _string(row, 'id'),
      invoiceId: _string(row, 'invoice_id'),
      accountId: AccountId(_string(row, 'account_id')),
      method: PosPaymentMethod.values.firstWhere(
        (method) => method.name == _string(row, 'payment_method'),
      ),
      amount: _money(row, 'amount_minor', currency),
      currency: currency,
      occurredAt: DateTime.parse(_string(row, 'occurred_at')),
      idempotencyKey: _string(row, 'idempotency_key'),
    );
  }

  PosInvoiceSignature? _signatureFromRow(Map<String, Object?> row) {
    final signature = row['signature_hex'] as String?;
    final publicKey = row['signer_public_key_hex'] as String?;
    final hash = row['signature_payload_hash'] as String?;
    final signedAt = row['signed_at'] as String?;
    if ([signature, publicKey, hash, signedAt].any((value) => value == null)) {
      return null;
    }
    return PosInvoiceSignature(
      invoiceId: _string(row, 'id'),
      signatureHex: signature!,
      signerPublicKeyHex: publicKey!,
      payloadHashHex: hash!,
      signedAt: DateTime.parse(signedAt!),
    );
  }

  static Money _money(
    Map<String, Object?> row,
    String key,
    CurrencyCode currency,
  ) =>
      Money.fromMinorUnits(_int(row, key), currency);

  static int _int(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw FormatException('Expected integer column $key');
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw FormatException('Expected numeric POS invoice value');
  }

  static String _string(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Expected non-empty text column $key');
  }

  static DateTime? _nullableDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  static AccountId? _nullableAccount(Object? value) =>
      value == null ? null : AccountId(value as String);

  static PosDocumentStatus _statusFromStorage(String value) =>
      PosDocumentStatus.values.firstWhere((status) => status.name == value);

  static PosInvoiceType _typeFromStorage(String value) => switch (value) {
        'sale' => PosInvoiceType.sale,
        'purchase' => PosInvoiceType.purchase,
        'sales_return' => PosInvoiceType.salesReturn,
        'purchase_return' => PosInvoiceType.purchaseReturn,
        _ => throw FormatException('Unknown POS document type $value'),
      };

  static String _typeToStorage(PosInvoiceType type) => switch (type) {
        PosInvoiceType.sale => 'sale',
        PosInvoiceType.purchase => 'purchase',
        PosInvoiceType.salesReturn => 'sales_return',
        PosInvoiceType.purchaseReturn => 'purchase_return',
      };
}
