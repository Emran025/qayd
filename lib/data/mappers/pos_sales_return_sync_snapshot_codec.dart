import 'package:qayd/data/mappers/ledger_entry_mapper.dart';
import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/data/mappers/voucher_mapper.dart';
import 'package:qayd/data/models/ledger_entry_model.dart';
import 'package:qayd/data/models/voucher_model.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/entities/pos_discount_rule.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_line_conversion.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_invoice_signature.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';
import 'package:qayd/domain/entities/pos_stock_movement.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/pos_stock_disposal_reason.dart';

/// Strict, versioned, JSON-safe representation of a complete POS sale.
final class PosSalesReturnSyncSnapshotCodec {
  static const schema = 'qayd.pos.sales-return-posting.v1';

  static Map<String, Object?> encode(PosSalesReturnPosting posting) {
    return <String, Object?>{
      'schema': schema,
      'invoice': PosInvoiceMapper.toRow(posting.invoice),
      'lines': posting.invoice.lines.map(PosInvoiceMapper.lineToRow).toList(),
      'refund_payments': posting.refundPayments
          .map(
            (p) => PosInvoiceMapper.paymentToRow(p, posting.invoice.createdAt),
          )
          .toList(),
      'movements': posting.movements.map(_movementToRow).toList(),
      'postings': posting.postings
          .map(
            (p) => <String, Object?>{
              'source_id': p.sourceId,
              'voucher': VoucherMapper.toModel(p.voucher).toMap(),
              'entries': p.entries
                  .map((e) => LedgerEntryMapper.toModel(e).toMap())
                  .toList(),
            },
          )
          .toList(),
      'source_invoice_id': posting.sourceInvoiceId,
      'sales_returns_account_id': posting.salesReturnsAccountId.value,
      'inventory_account_id': posting.inventoryAccountId.value,
      'cost_of_goods_sold_account_id': posting.costOfGoodsSoldAccountId.value,
      'void_source': posting.voidSource ? 1 : 0,
      'reason': posting.reason,
    };
  }

  static Map<String, Object?> toJsonSafeMap(PosSalesReturnPosting posting) =>
      encode(posting);

  /// Shared strict decoders used by other versioned POS return snapshots.
  static PosInvoice decodeInvoiceSnapshot(
    Map<String, Object?> invoiceRow,
    List<Map<String, Object?>> lineRows,
  ) => _invoice(invoiceRow, lineRows);

  static PosStockMovement decodeMovementSnapshot(Map<String, Object?> row) =>
      _movement(row);

  static Map<String, Object?> encodeMovementSnapshot(
    PosStockMovement movement,
  ) => _movementToRow(movement);

  static PosAccountingPosting decodeAccountingPostingSnapshot(
    Map<String, Object?> row,
  ) {
    _keys(row, const {'source_id', 'voucher', 'entries'}, 'posting');
    final model = VoucherModel.fromMap(_map(row['voucher'], 'posting.voucher'));
    final voucher = VoucherMapper.toEntity(
      model,
      _currency(model.currencyCode),
    );
    final entries = _listOfMaps(row['entries'], 'posting.entries').map((entry) {
      final mapped = LedgerEntryModel.fromMap(entry);
      return LedgerEntryMapper.toEntity(mapped, _currency(mapped.currencyCode));
    }).toList();
    return PosAccountingPosting(
      sourceId: _string(row['source_id'], 'posting.source_id'),
      voucher: voucher,
      entries: entries,
    );
  }

  static Map<String, Object?> encodeAccountingPostingSnapshot(
    PosAccountingPosting posting,
  ) => <String, Object?>{
    'source_id': posting.sourceId,
    'voucher': VoucherMapper.toModel(posting.voucher).toMap(),
    'entries': posting.entries
        .map((entry) => LedgerEntryMapper.toModel(entry).toMap())
        .toList(),
  };

  static PosSalesReturnPosting decode(Map<String, Object?> raw) {
    try {
      return _decode(raw);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Malformed POS sales return snapshot: $e');
    }
  }

  static PosSalesReturnPosting _decode(Map<String, Object?> raw) {
    _keys(raw, const {
      'schema',
      'invoice',
      'lines',
      'refund_payments',
      'movements',
      'postings',
      'source_invoice_id',
      'sales_returns_account_id',
      'inventory_account_id',
      'cost_of_goods_sold_account_id',
      'void_source',
      'reason',
    }, 'root');
    if (raw['schema'] != schema) {
      throw FormatException('Unsupported sales return snapshot schema');
    }
    final invoiceRow = _map(raw['invoice'], 'invoice');
    final invoice = _invoice(invoiceRow, _listOfMaps(raw['lines'], 'lines'));
    final refunds = _listOfMaps(
      raw['refund_payments'],
      'refund_payments',
    ).map(_payment).toList();
    final movements = _listOfMaps(
      raw['movements'],
      'movements',
    ).map(_movement).toList();
    final postings = _listOfMaps(raw['postings'], 'postings').map((r) {
      _keys(r, const {'source_id', 'voucher', 'entries'}, 'posting');
      final model = VoucherModel.fromMap(_map(r['voucher'], 'posting.voucher'));
      final voucher = VoucherMapper.toEntity(
        model,
        _currency(model.currencyCode),
      );
      final entries = _listOfMaps(r['entries'], 'posting.entries').map((e) {
        final em = LedgerEntryModel.fromMap(e);
        return LedgerEntryMapper.toEntity(em, _currency(em.currencyCode));
      }).toList();
      return PosAccountingPosting(
        sourceId: _string(r['source_id'], 'posting.source_id'),
        voucher: voucher,
        entries: entries,
      );
    }).toList();
    try {
      return PosSalesReturnPosting(
        invoice: invoice,
        sourceInvoiceId: _string(raw['source_invoice_id'], 'source_invoice_id'),
        salesReturnsAccountId: AccountId(
          _string(raw['sales_returns_account_id'], 'sales_returns_account_id'),
        ),
        inventoryAccountId: AccountId(
          _string(raw['inventory_account_id'], 'inventory_account_id'),
        ),
        costOfGoodsSoldAccountId: AccountId(
          _string(
            raw['cost_of_goods_sold_account_id'],
            'cost_of_goods_sold_account_id',
          ),
        ),
        movements: movements,
        postings: postings,
        refundPayments: refunds,
        voidSource: _flag(raw['void_source'], 'void_source'),
        reason: _nullableString(raw['reason'], 'reason'),
      );
    } catch (e) {
      throw FormatException('Invalid POS sales return posting invariant: $e');
    }
  }

  static PosSalesReturnPosting fromJsonSafeMap(Map<String, Object?> raw) =>
      decode(raw);

  static PosInvoice _invoice(
    Map<String, Object?> row,
    List<Map<String, Object?>> lineRows,
  ) {
    _keys(row, const {
      'id',
      'invoice_number',
      'document_type',
      'status',
      'counterparty_account_id',
      'warehouse_id',
      'source_invoice_id',
      'currency_code',
      'subtotal_minor',
      'discount_minor',
      'cart_discount_minor',
      'cart_discount_method',
      'cart_discount_value',
      'cart_discount_reason',
      'cart_discount_actor_id',
      'cart_discount_policy_max_bps',
      'tax_minor',
      'total_minor',
      'paid_minor',
      'due_minor',
      'credit_due_date',
      'credit_terms',
      'idempotency_key',
      'created_at',
      'updated_at',
      'posted_at',
      'invoice_date',
      'signature_hex',
      'signer_public_key_hex',
      'signature_payload_hash',
      'signed_at',
    }, 'invoice');
    final currency = _currency(
      _string(row['currency_code'], 'invoice.currency_code'),
    );
    final lines = lineRows.map((r) => _line(r, currency)).toList();
    final cartMethod = _nullableString(
      row['cart_discount_method'],
      'invoice.cart_discount_method',
    );
    final cartRule = cartMethod == null
        ? null
        : _discountRule(row, 'cart', currency, cartMethod);
    if (cartMethod == null &&
        [
          row['cart_discount_value'],
          row['cart_discount_reason'],
          row['cart_discount_actor_id'],
          row['cart_discount_policy_max_bps'],
        ].any((v) => v != null)) {
      throw FormatException('Partial cart discount rule');
    }
    final signatureFields = [
      row['signature_hex'],
      row['signer_public_key_hex'],
      row['signature_payload_hash'],
      row['signed_at'],
    ];
    final signature = signatureFields.every((v) => v == null)
        ? null
        : PosInvoiceSignature(
            invoiceId: _string(row['id'], 'invoice.id'),
            signatureHex: _string(
              row['signature_hex'],
              'invoice.signature_hex',
            ),
            signerPublicKeyHex: _string(
              row['signer_public_key_hex'],
              'invoice.signer_public_key_hex',
            ),
            payloadHashHex: _string(
              row['signature_payload_hash'],
              'invoice.signature_payload_hash',
            ),
            signedAt: _date(row['signed_at'], 'invoice.signed_at'),
          );
    try {
      return PosInvoice.fromPersistence(
        id: _string(row['id'], 'invoice.id'),
        invoiceNumber: _string(row['invoice_number'], 'invoice.invoice_number'),
        type: _invoiceType(row['document_type']),
        status: _enum(
          row['status'],
          PosDocumentStatus.values,
          'invoice.status',
        ),
        counterpartyAccountId:
            _nullableString(
                  row['counterparty_account_id'],
                  'invoice.counterparty_account_id',
                ) ==
                null
            ? null
            : AccountId(row['counterparty_account_id'] as String),
        warehouseId: _string(row['warehouse_id'], 'invoice.warehouse_id'),
        sourceInvoiceId: _nullableString(
          row['source_invoice_id'],
          'invoice.source_invoice_id',
        ),
        currency: currency,
        lines: lines,
        subtotal: _money(
          row['subtotal_minor'],
          currency,
          'invoice.subtotal_minor',
        ),
        discount: _money(
          row['discount_minor'],
          currency,
          'invoice.discount_minor',
        ),
        cartDiscount: _money(
          row['cart_discount_minor'],
          currency,
          'invoice.cart_discount_minor',
        ),
        cartDiscountRule: cartRule,
        tax: _money(row['tax_minor'], currency, 'invoice.tax_minor'),
        total: _money(row['total_minor'], currency, 'invoice.total_minor'),
        paid: _money(row['paid_minor'], currency, 'invoice.paid_minor'),
        due: _money(row['due_minor'], currency, 'invoice.due_minor'),
        creditDueDate: _nullableDate(
          row['credit_due_date'],
          'invoice.credit_due_date',
        ),
        creditTerms: _nullableString(
          row['credit_terms'],
          'invoice.credit_terms',
        ),
        idempotencyKey: _string(
          row['idempotency_key'],
          'invoice.idempotency_key',
        ),
        invoiceDate: _date(row['invoice_date'], 'invoice.invoice_date'),
        createdAt: _date(row['created_at'], 'invoice.created_at'),
        updatedAt: _date(row['updated_at'], 'invoice.updated_at'),
        postedAt: _nullableDate(row['posted_at'], 'invoice.posted_at'),
        signature: signature,
      );
    } catch (e) {
      throw FormatException('Invalid invoice: $e');
    }
  }

  static PosInvoiceLine _line(Map<String, Object?> r, CurrencyCode currency) {
    _keys(r, const {
      'id',
      'invoice_id',
      'product_id',
      'product_name_snapshot',
      'barcode_snapshot',
      'quantity_scaled',
      'quantity_scale',
      'unit_price_minor',
      'unit_cost_minor',
      'unit_cost_currency_code',
      'discount_minor',
      'discount_rule_method',
      'discount_rule_value',
      'discount_reason',
      'discount_actor_id',
      'discount_policy_max_bps',
      'tax_minor',
      'line_total_minor',
      'source_line_id',
      'created_at',
      'conversion_purpose',
      'conversion_source_minor',
      'conversion_source_currency_code',
      'conversion_target_minor',
      'conversion_target_currency_code',
      'fx_rate_id',
      'fx_requested_from_code',
      'fx_requested_to_code',
      'fx_stored_from_code',
      'fx_stored_to_code',
      'fx_rate_scaled',
      'fx_effective_at',
      'fx_recorded_at',
      'fx_created_at',
      'fx_is_inverted',
      'fx_note',
      'proposed_sale_price_minor',
      'proposed_sale_price_applied',
      'expiry_tracking_snapshot',
      'product_updated_at_snapshot',
    }, 'line');
    final ruleName = _nullableString(
      r['discount_rule_method'],
      'line.discount_rule_method',
    );
    final rule = ruleName == null
        ? null
        : _discountRule(r, 'line', currency, ruleName);
    PosInvoiceLineConversion? conversion;
    final purpose = _nullableString(
      r['conversion_purpose'],
      'line.conversion_purpose',
    );
    if (purpose != null) {
      final source = _money(
        r['conversion_source_minor'],
        _currency(
          _string(
            r['conversion_source_currency_code'],
            'conversion.source_currency',
          ),
        ),
        'conversion.source_minor',
      );
      final target = _money(
        r['conversion_target_minor'],
        _currency(
          _string(
            r['conversion_target_currency_code'],
            'conversion.target_currency',
          ),
        ),
        'conversion.target_minor',
      );
      PosCurrencyRateQuote? rate;
      if (r['fx_rate_id'] != null) {
        rate = PosCurrencyRateQuote(
          rateId: _string(r['fx_rate_id'], 'fx.rate_id'),
          storedFromCurrency: _currency(
            _string(r['fx_stored_from_code'], 'fx.stored_from'),
          ),
          storedToCurrency: _currency(
            _string(r['fx_stored_to_code'], 'fx.stored_to'),
          ),
          storedRateScaled: _int(r['fx_rate_scaled'], 'fx.rate_scaled'),
          requestedFromCurrency: _currency(
            _string(r['fx_requested_from_code'], 'fx.requested_from'),
          ),
          requestedToCurrency: _currency(
            _string(r['fx_requested_to_code'], 'fx.requested_to'),
          ),
          effectiveAt: _date(r['fx_effective_at'], 'fx.effective_at'),
          recordedAt: _date(r['fx_recorded_at'], 'fx.recorded_at'),
          createdAt: _date(r['fx_created_at'], 'fx.created_at'),
          isInverted: _flag(r['fx_is_inverted'], 'fx.is_inverted'),
          note: _nullableString(r['fx_note'], 'fx.note'),
        );
      } else if ([
        r['fx_requested_from_code'],
        r['fx_requested_to_code'],
        r['fx_stored_from_code'],
        r['fx_stored_to_code'],
        r['fx_rate_scaled'],
        r['fx_effective_at'],
        r['fx_recorded_at'],
        r['fx_created_at'],
        r['fx_is_inverted'],
        r['fx_note'],
      ].any((v) => v != null)) {
        throw FormatException('Partial FX snapshot');
      }
      conversion = PosInvoiceLineConversion(
        purpose: _enum(
          purpose,
          PosInvoiceLineConversionPurpose.values,
          'conversion.purpose',
        ),
        sourceAmount: source,
        targetAmount: target,
        rateSnapshot: rate,
      );
    } else if ([
      r['conversion_source_minor'],
      r['conversion_source_currency_code'],
      r['conversion_target_minor'],
      r['conversion_target_currency_code'],
    ].any((v) => v != null))
      throw FormatException('Partial conversion');
    return PosInvoiceLine.fromPersistence(
      id: _string(r['id'], 'line.id'),
      invoiceId: _string(r['invoice_id'], 'line.invoice_id'),
      productId: _string(r['product_id'], 'line.product_id'),
      productNameSnapshot: _string(
        r['product_name_snapshot'],
        'line.product_name_snapshot',
      ),
      barcodeSnapshot: _nullableString(
        r['barcode_snapshot'],
        'line.barcode_snapshot',
      ),
      quantity: PosQuantity.fromScaled(
        _int(r['quantity_scaled'], 'line.quantity_scaled'),
        scale: _int(r['quantity_scale'], 'line.quantity_scale'),
      ),
      unitPrice: _money(
        r['unit_price_minor'],
        currency,
        'line.unit_price_minor',
      ),
      unitCost: _money(
        r['unit_cost_minor'],
        _currency(
          _string(r['unit_cost_currency_code'], 'line.unit_cost_currency_code'),
        ),
        'line.unit_cost_minor',
      ),
      discount: _money(r['discount_minor'], currency, 'line.discount_minor'),
      tax: _money(r['tax_minor'], currency, 'line.tax_minor'),
      lineTotal: _money(
        r['line_total_minor'],
        currency,
        'line.line_total_minor',
      ),
      sourceLineId: _nullableString(r['source_line_id'], 'line.source_line_id'),
      createdAt: _date(r['created_at'], 'line.created_at'),
      currencyConversion: conversion,
      discountRule: rule,
      proposedSalePrice: r['proposed_sale_price_minor'] == null
          ? null
          : _money(
              r['proposed_sale_price_minor'],
              _currency(
                _string(
                  r['unit_cost_currency_code'],
                  'line.unit_cost_currency_code',
                ),
              ),
              'line.proposed_sale_price_minor',
            ),
      proposedSalePriceApplied: _flag(
        r['proposed_sale_price_applied'],
        'line.proposed_sale_price_applied',
      ),
      productUpdatedAtSnapshot: _nullableDate(
        r['product_updated_at_snapshot'],
        'line.product_updated_at_snapshot',
      ),
      expiryTrackingSnapshot: r['expiry_tracking_snapshot'] == null
          ? null
          : _flag(
              r['expiry_tracking_snapshot'],
              'line.expiry_tracking_snapshot',
            ),
    );
  }

  static PosInvoicePayment _payment(Map<String, Object?> r) {
    _keys(r, const {
      'id',
      'invoice_id',
      'account_id',
      'payment_method',
      'amount_minor',
      'currency_code',
      'occurred_at',
      'idempotency_key',
      'created_at',
    }, 'payment');
    final c = _currency(_string(r['currency_code'], 'payment.currency_code'));
    _date(r['created_at'], 'payment.created_at');
    return PosInvoicePayment.create(
      id: _string(r['id'], 'payment.id'),
      invoiceId: _string(r['invoice_id'], 'payment.invoice_id'),
      accountId: AccountId(_string(r['account_id'], 'payment.account_id')),
      method: _enum(
        r['payment_method'],
        PosPaymentMethod.values,
        'payment.payment_method',
      ),
      amount: _money(r['amount_minor'], c, 'payment.amount_minor'),
      currency: c,
      occurredAt: _date(r['occurred_at'], 'payment.occurred_at'),
      idempotencyKey: _string(r['idempotency_key'], 'payment.idempotency_key'),
    );
  }

  static PosStockMovement _movement(Map<String, Object?> r) {
    _keys(r, const {
      'id',
      'product_id',
      'warehouse_id',
      'type',
      'direction',
      'quantity_scaled',
      'quantity_scale',
      'unit_cost_minor',
      'unit_cost_currency_code',
      'source_type',
      'source_id',
      'source_line_id',
      'lot_id',
      'disposal_reason',
      'reason_detail',
      'voucher_id',
      'reverses_source_id',
      'occurred_at',
      'idempotency_key',
      'created_at',
    }, 'movement');
    final c = _currency(
      _string(r['unit_cost_currency_code'], 'movement.unit_cost_currency_code'),
    );
    final disposalCode = _nullableString(
      r['disposal_reason'],
      'movement.disposal_reason',
    );
    final disposal = disposalCode == null
        ? null
        : parsePosStockDisposalReason(disposalCode);
    if (disposalCode != null && disposal == null)
      throw FormatException('Unknown movement disposal reason');
    return PosStockMovement.create(
      id: _string(r['id'], 'movement.id'),
      productId: _string(r['product_id'], 'movement.product_id'),
      warehouseId: _string(r['warehouse_id'], 'movement.warehouse_id'),
      type: _enum(r['type'], PosStockMovementType.values, 'movement.type'),
      direction: _enum(
        r['direction'],
        PosStockMovementDirection.values,
        'movement.direction',
      ),
      quantity: PosQuantity.fromScaled(
        _int(r['quantity_scaled'], 'movement.quantity_scaled'),
        scale: _int(r['quantity_scale'], 'movement.quantity_scale'),
      ),
      unitCost: _money(r['unit_cost_minor'], c, 'movement.unit_cost_minor'),
      sourceType: _nullableString(r['source_type'], 'movement.source_type'),
      sourceId: _nullableString(r['source_id'], 'movement.source_id'),
      sourceLineId: _nullableString(
        r['source_line_id'],
        'movement.source_line_id',
      ),
      lotId: _nullableString(r['lot_id'], 'movement.lot_id'),
      disposalReason: disposal,
      reasonDetail: _nullableString(
        r['reason_detail'],
        'movement.reason_detail',
      ),
      voucherId: _nullableString(r['voucher_id'], 'movement.voucher_id'),
      reversesSourceId: _nullableString(
        r['reverses_source_id'],
        'movement.reverses_source_id',
      ),
      occurredAt: _date(r['occurred_at'], 'movement.occurred_at'),
      idempotencyKey: _string(r['idempotency_key'], 'movement.idempotency_key'),
      createdAt: _date(r['created_at'], 'movement.created_at'),
    );
  }

  static Map<String, Object?> _movementToRow(PosStockMovement m) => {
    'id': m.id,
    'product_id': m.productId,
    'warehouse_id': m.warehouseId,
    'type': m.type.name,
    'direction': m.direction.name,
    'quantity_scaled': m.quantity.scaledUnits,
    'quantity_scale': m.quantity.scale,
    'unit_cost_minor': m.unitCost.minorUnits,
    'unit_cost_currency_code': m.unitCost.currency.code,
    'source_type': m.sourceType,
    'source_id': m.sourceId,
    'source_line_id': m.sourceLineId,
    'lot_id': m.lotId,
    'disposal_reason': m.disposalReason?.code,
    'reason_detail': m.reasonDetail,
    'voucher_id': m.voucherId,
    'reverses_source_id': m.reversesSourceId,
    'occurred_at': m.occurredAt.toUtc().toIso8601String(),
    'idempotency_key': m.idempotencyKey,
    'created_at': m.createdAt.toUtc().toIso8601String(),
  };
  static PosDiscountRule _discountRule(
    Map<String, Object?> r,
    String p,
    CurrencyCode c,
    String method,
  ) {
    final reason = _string(
      r['${p == 'cart' ? 'cart_discount_reason' : 'discount_reason'}'],
      '$p.discount.reason',
    );
    final actor = _string(
      r['${p == 'cart' ? 'cart_discount_actor_id' : 'discount_actor_id'}'],
      '$p.discount.actor',
    );
    final value = _int(
      r['${p == 'cart' ? 'cart_discount_value' : 'discount_rule_value'}'],
      '$p.discount.value',
    );
    final max = _int(
      r['${p == 'cart' ? 'cart_discount_policy_max_bps' : 'discount_policy_max_bps'}'],
      '$p.discount.max',
    );
    return method == 'fixedAmount'
        ? PosDiscountRule.fixed(
            amount: Money.fromMinorUnits(value, c),
            reason: reason,
            actorId: actor,
            policyMaximumBasisPoints: max,
          )
        : method == 'percentage'
        ? PosDiscountRule.percentage(
            basisPoints: value,
            reason: reason,
            actorId: actor,
            policyMaximumBasisPoints: max,
          )
        : throw FormatException('Unknown discount method');
  }

  static PosInvoiceType _invoiceType(Object? v) => switch (v) {
    'sale' => PosInvoiceType.sale,
    'purchase' => PosInvoiceType.purchase,
    'sales_return' => PosInvoiceType.salesReturn,
    'purchase_return' => PosInvoiceType.purchaseReturn,
    _ => throw FormatException('Unknown invoice type'),
  };
  static CurrencyCode _currency(String code) =>
      CurrencyCode(code: code, nameAr: code, symbol: code);
  static Money _money(Object? v, CurrencyCode c, String p) =>
      Money.fromMinorUnits(_int(v, p), c);
  static String _string(Object? v, String p) {
    if (v is! String || v.isEmpty)
      throw FormatException('Expected non-empty string: $p');
    return v;
  }

  static String? _nullableString(Object? v, String p) {
    if (v == null) return null;
    if (v is String) return v;
    throw FormatException('Expected nullable string: $p');
  }

  static int _int(Object? v, String p) {
    if (v is int) return v;
    throw FormatException('Expected int: $p');
  }

  static bool _flag(Object? v, String p) {
    final i = _int(v, p);
    if (i == 0) return false;
    if (i == 1) return true;
    throw FormatException('Expected 0/1 flag: $p');
  }

  static DateTime _date(Object? v, String p) {
    final s = _string(v, p);
    try {
      return DateTime.parse(s).toUtc();
    } catch (_) {
      throw FormatException('Invalid date: $p');
    }
  }

  static DateTime? _nullableDate(Object? v, String p) =>
      v == null ? null : _date(v, p);
  static T _enum<T extends Enum>(Object? v, List<T> values, String p) {
    final s = _string(v, p);
    for (final x in values) {
      if (x.name == s) return x;
    }
    throw FormatException('Unknown enum: $p');
  }

  static Map<String, Object?> _map(Object? v, String p) {
    if (v is Map<String, Object?>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    throw FormatException('Expected map: $p');
  }

  static List<Map<String, Object?>> _listOfMaps(Object? v, String p) {
    if (v is! List) throw FormatException('Expected list: $p');
    return v.map((x) => _map(x, p)).toList();
  }

  static void _keys(Map<String, Object?> m, Set<String> expected, String p) {
    if (m.length != expected.length || !m.keys.toSet().containsAll(expected))
      throw FormatException('Missing or unexpected fields: $p');
  }
}
