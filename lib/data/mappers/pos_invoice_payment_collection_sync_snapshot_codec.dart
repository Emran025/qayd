import 'dart:convert';

import 'package:qayd/data/mappers/pos_invoice_mapper.dart';
import 'package:qayd/domain/entities/ledger_entry.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_discount_rule.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_line_conversion.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
import 'package:qayd/domain/entities/pos_invoice_signature.dart';
import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/domain/value_objects/attachment_id.dart';
import 'package:qayd/domain/value_objects/attachment_ref.dart';
import 'package:qayd/domain/value_objects/attachment_source_type.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/entry_side.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/tripartite_meta.dart';
import 'package:qayd/domain/value_objects/tripartite_role.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_lifecycle.dart';
import 'package:qayd/domain/value_objects/voucher_state.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';

/// Strict, versioned, JSON-safe wire codec for the atomic POS collection event.
abstract final class PosInvoicePaymentCollectionSyncSnapshotCodec {
  static const schema = 'qayd.pos_invoice_payment_collection_sync_snapshot';
  static const version = 1;

  static Map<String, Object?> encode(PosInvoicePaymentCollectionPosting value) {
    final currency = value.invoiceBefore.currency;
    if (value.invoiceAfter.currency != currency ||
        value.payment.currency != currency ||
        value.accountingPosting.voucher.currency != currency ||
        value.accountingPosting.entries.any((e) => e.currency != currency)) {
      throw StateError('Snapshot currencies do not match');
    }
    return {
      'schema': schema,
      'version': version,
      'invoiceBefore': _invoice(value.invoiceBefore),
      'invoiceAfter': _invoice(value.invoiceAfter),
      'payment': {
        'id': value.payment.id,
        'invoiceId': value.payment.invoiceId,
        'accountId': value.payment.accountId.value,
        'method': value.payment.method.name,
        'amountMinor': value.payment.amount.minorUnits,
        'currency': _currency(value.payment.currency),
        'occurredAt': _date(value.payment.occurredAt),
        'idempotencyKey': value.payment.idempotencyKey,
      },
      'accountingPosting': {
        'sourceId': value.accountingPosting.sourceId,
        'voucher': _voucher(value.accountingPosting.voucher),
        'entries': value.accountingPosting.entries.map(_entry).toList(),
      },
      'recordedAt': _date(value.recordedAt),
      'isReplay': value.isReplay,
      'currency': _currency(currency),
    };
  }

  static PosInvoicePaymentCollectionPosting decode(Object input) {
    try {
      final root = _map(input, 'root');
      _keys(root, const {
        'schema',
        'version',
        'invoiceBefore',
        'invoiceAfter',
        'payment',
        'accountingPosting',
        'recordedAt',
        'isReplay',
        'currency',
      });
      if (root['schema'] != schema || root['version'] != version) {
        throw const FormatException('Unsupported snapshot schema or version');
      }
      final currency = _readCurrency(root['currency'], 'currency');
      final before = _readInvoice(root['invoiceBefore'], currency);
      final after = _readInvoice(root['invoiceAfter'], currency);
      final p = _map(root['payment'], 'payment');
      _keys(p, const {
        'id',
        'invoiceId',
        'accountId',
        'method',
        'amountMinor',
        'currency',
        'occurredAt',
        'idempotencyKey',
      });
      final paymentCurrency = _readCurrency(p['currency'], 'payment.currency');
      final payment = PosInvoicePayment.create(
        id: _string(p['id'], 'payment.id'),
        invoiceId: _string(p['invoiceId'], 'payment.invoiceId'),
        accountId: AccountId(_string(p['accountId'], 'payment.accountId')),
        method: _enum(p['method'], PosPaymentMethod.values, 'payment.method'),
        amount: Money.fromMinorUnits(
          _int(p['amountMinor'], 'payment.amountMinor'),
          paymentCurrency,
        ),
        currency: paymentCurrency,
        occurredAt: _dateRead(p['occurredAt'], 'payment.occurredAt'),
        idempotencyKey: _string(p['idempotencyKey'], 'payment.idempotencyKey'),
      );
      if (payment.currency != currency ||
          payment.invoiceId != before.id ||
          after.id != before.id ||
          after.paid.minorUnits < before.paid.minorUnits ||
          jsonEncode(_invoice(after)) !=
              jsonEncode(
                _invoice(
                  before.applyPayment(payment.amount, payment.occurredAt),
                ),
              )) {
        throw const FormatException(
          'Snapshot invoice transition invariant failed',
        );
      }
      final a = _map(root['accountingPosting'], 'accountingPosting');
      _keys(a, const {'sourceId', 'voucher', 'entries'});
      final entries = _list(
        a['entries'],
        'accountingPosting.entries',
      ).map((e) => _readEntry(e, currency)).toList(growable: false);
      final posting = PosAccountingPosting(
        sourceId: _string(a['sourceId'], 'accountingPosting.sourceId'),
        voucher: _readVoucher(a['voucher'], currency),
        entries: entries,
      );
      if (posting.sourceId != payment.id ||
          posting.voucher.amount != payment.amount ||
          posting.voucher.currency != currency ||
          entries.isEmpty ||
          entries.any((e) => e.voucherId != posting.voucher.id) ||
          entries.any((e) => e.amount.currency != currency)) {
        throw const FormatException('Accounting posting invariant failed');
      }
      return PosInvoicePaymentCollectionPosting(
        invoiceBefore: before,
        invoiceAfter: after,
        payment: payment,
        accountingPosting: posting,
        recordedAt: _dateRead(root['recordedAt'], 'recordedAt'),
        isReplay: _bool(root['isReplay'], 'isReplay'),
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Malformed snapshot: $error');
    }
  }

  static String encodeJson(PosInvoicePaymentCollectionPosting value) =>
      jsonEncode(encode(value));
  static Map<String, Object?> toJsonSafeMap(
    PosInvoicePaymentCollectionPosting value,
  ) => encode(value);
  static PosInvoicePaymentCollectionPosting fromJsonSafeMap(
    Map<String, Object?> value,
  ) => decode(value);

  static Map<String, Object?> _invoice(PosInvoice x) => {
    'row': PosInvoiceMapper.toRow(x),
    'lines': x.lines.map(PosInvoiceMapper.lineToRow).toList(),
    'currency': _currency(x.currency),
  };

  static PosInvoice _readInvoice(Object? raw, CurrencyCode currency) {
    final x = _map(raw, 'invoice');
    _keys(x, const {'row', 'lines', 'currency'});
    final row = _map(x['row'], 'invoice.row');
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
    });
    if (_string(row['currency_code'], 'invoice.row.currency_code') !=
        currency.code) {
      throw const FormatException('Invoice currency mismatch');
    }
    final lines = _list(
      x['lines'],
      'invoice.lines',
    ).map((v) => _readLine(v, currency)).toList(growable: false);
    final money = (String key) =>
        Money.fromMinorUnits(_int(row[key], 'invoice.row.$key'), currency);
    final rule = _readDiscountRule(
      method: row['cart_discount_method'],
      value: row['cart_discount_value'],
      reason: row['cart_discount_reason'],
      actor: row['cart_discount_actor_id'],
      maximum: row['cart_discount_policy_max_bps'],
      currency: currency,
      path: 'invoice.cartDiscountRule',
    );
    final signature =
        row['signature_hex'] == null &&
            row['signer_public_key_hex'] == null &&
            row['signature_payload_hash'] == null &&
            row['signed_at'] == null
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
            signedAt: _dateRead(row['signed_at'], 'invoice.signed_at'),
          );
    return PosInvoice.fromPersistence(
      id: _string(row['id'], 'invoice.id'),
      invoiceNumber: _string(row['invoice_number'], 'invoice.invoice_number'),
      type: _invoiceType(row['document_type']),
      status: _enum(row['status'], PosDocumentStatus.values, 'invoice.status'),
      counterpartyAccountId: row['counterparty_account_id'] == null
          ? null
          : AccountId(
              _string(
                row['counterparty_account_id'],
                'invoice.counterparty_account_id',
              ),
            ),
      warehouseId: _string(row['warehouse_id'], 'invoice.warehouse_id'),
      sourceInvoiceId: _nullableString(
        row['source_invoice_id'],
        'invoice.source_invoice_id',
      ),
      currency: currency,
      lines: lines,
      subtotal: money('subtotal_minor'),
      discount: money('discount_minor'),
      cartDiscount: money('cart_discount_minor'),
      cartDiscountRule: rule,
      tax: money('tax_minor'),
      total: money('total_minor'),
      paid: money('paid_minor'),
      due: money('due_minor'),
      creditDueDate: _nullableDate(
        row['credit_due_date'],
        'invoice.credit_due_date',
      ),
      creditTerms: _nullableString(row['credit_terms'], 'invoice.credit_terms'),
      idempotencyKey: _string(
        row['idempotency_key'],
        'invoice.idempotency_key',
      ),
      invoiceDate: _dateRead(row['invoice_date'], 'invoice.invoice_date'),
      createdAt: _dateRead(row['created_at'], 'invoice.created_at'),
      updatedAt: _dateRead(row['updated_at'], 'invoice.updated_at'),
      postedAt: _nullableDate(row['posted_at'], 'invoice.posted_at'),
      signature: signature,
    );
  }

  static PosInvoiceLine _readLine(Object? raw, CurrencyCode currency) {
    final r = _map(raw, 'invoice.line');
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
    });
    CurrencyCode code(String key) =>
        _currencyWithCode(_string(r[key], 'line.$key'), currency);
    Money money(String key, String currencyKey) =>
        Money.fromMinorUnits(_int(r[key], 'line.$key'), code(currencyKey));
    final unitPrice = Money.fromMinorUnits(
      _int(r['unit_price_minor'], 'line.unit_price_minor'),
      currency,
    );
    final unitCost = money('unit_cost_minor', 'unit_cost_currency_code');
    final rule = _readDiscountRule(
      method: r['discount_rule_method'],
      value: r['discount_rule_value'],
      reason: r['discount_reason'],
      actor: r['discount_actor_id'],
      maximum: r['discount_policy_max_bps'],
      currency: currency,
      path: 'line.discountRule',
    );
    final hasConversion = r['conversion_purpose'] != null;
    PosInvoiceLineConversion? conversion;
    if (hasConversion) {
      final source = money(
        'conversion_source_minor',
        'conversion_source_currency_code',
      );
      final target = money(
        'conversion_target_minor',
        'conversion_target_currency_code',
      );
      final hasRate = r['fx_rate_id'] != null;
      PosCurrencyRateQuote? rate;
      if (hasRate) {
        rate = PosCurrencyRateQuote(
          rateId: _string(r['fx_rate_id'], 'line.fx_rate_id'),
          requestedFromCurrency: code('fx_requested_from_code'),
          requestedToCurrency: code('fx_requested_to_code'),
          storedFromCurrency: code('fx_stored_from_code'),
          storedToCurrency: code('fx_stored_to_code'),
          storedRateScaled: _int(r['fx_rate_scaled'], 'line.fx_rate_scaled'),
          effectiveAt: _dateRead(r['fx_effective_at'], 'line.fx_effective_at'),
          recordedAt: _dateRead(r['fx_recorded_at'], 'line.fx_recorded_at'),
          createdAt: _dateRead(r['fx_created_at'], 'line.fx_created_at'),
          isInverted: _int(r['fx_is_inverted'], 'line.fx_is_inverted') == 1,
          note: _nullableString(r['fx_note'], 'line.fx_note'),
        );
      }
      conversion = PosInvoiceLineConversion(
        purpose: _enum(
          r['conversion_purpose'],
          PosInvoiceLineConversionPurpose.values,
          'line.conversion_purpose',
        ),
        sourceAmount: source,
        targetAmount: target,
        rateSnapshot: rate,
      );
    }
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
      unitPrice: unitPrice,
      unitCost: unitCost,
      discount: Money.fromMinorUnits(
        _int(r['discount_minor'], 'line.discount_minor'),
        currency,
      ),
      discountRule: rule,
      tax: Money.fromMinorUnits(
        _int(r['tax_minor'], 'line.tax_minor'),
        currency,
      ),
      lineTotal: Money.fromMinorUnits(
        _int(r['line_total_minor'], 'line.line_total_minor'),
        currency,
      ),
      sourceLineId: _nullableString(r['source_line_id'], 'line.source_line_id'),
      createdAt: _dateRead(r['created_at'], 'line.created_at'),
      currencyConversion: conversion,
      proposedSalePrice: r['proposed_sale_price_minor'] == null
          ? null
          : money('proposed_sale_price_minor', 'unit_cost_currency_code'),
      proposedSalePriceApplied:
          _int(
            r['proposed_sale_price_applied'],
            'line.proposed_sale_price_applied',
          ) ==
          1,
      expiryTrackingSnapshot: r['expiry_tracking_snapshot'] == null
          ? null
          : _int(
                  r['expiry_tracking_snapshot'],
                  'line.expiry_tracking_snapshot',
                ) ==
                1,
      productUpdatedAtSnapshot: _nullableDate(
        r['product_updated_at_snapshot'],
        'line.product_updated_at_snapshot',
      ),
    );
  }

  static Map<String, Object?> _currency(CurrencyCode c) => {
    'code': c.code,
    'nameAr': c.nameAr,
    'symbol': c.symbol,
    'fractionalDigits': c.fractionalDigits,
    'isActive': c.isActive,
  };

  static CurrencyCode _readCurrency(Object? raw, String path) {
    final m = _map(raw, path);
    _keys(m, const {
      'code',
      'nameAr',
      'symbol',
      'fractionalDigits',
      'isActive',
    });
    return CurrencyCode(
      code: _string(m['code'], '$path.code'),
      nameAr: _string(m['nameAr'], '$path.nameAr'),
      symbol: _string(m['symbol'], '$path.symbol'),
      fractionalDigits: _int(m['fractionalDigits'], '$path.fractionalDigits'),
      isActive: _bool(m['isActive'], '$path.isActive'),
    );
  }

  static CurrencyCode _currencyWithCode(String code, CurrencyCode fallback) =>
      code == fallback.code
      ? fallback
      : CurrencyCode(code: code, nameAr: code, symbol: code);

  static Map<String, Object?> _voucher(Voucher v) => {
    'id': v.id.value,
    'type': v.type.name,
    'referenceNumber': v.referenceNumber,
    'date': _date(v.date),
    'amountMinor': v.amount.minorUnits,
    'currency': _currency(v.currency),
    'counterpartyId': v.counterpartyId.value,
    'affectedAccountId': v.affectedAccountId.value,
    'state': v.state.name,
    'description': v.description,
    'attachmentRefs': v.attachmentRefs.map(_attachment).toList(),
    'notes': v.notes,
    'tags': v.tags,
    'createdAt': _date(v.createdAt),
    'confirmedAt': v.confirmedAt == null ? null : _date(v.confirmedAt!),
    'settledAt': v.settledAt == null ? null : _date(v.settledAt!),
    'senderStatus': v.senderStatus.name,
    'receiverStatus': v.receiverStatus.name,
    'lifecycleStatus': v.lifecycleStatus.name,
    'signerPhone': v.signerPhone,
    'canonicalSenderPhone': v.canonicalSenderPhone,
    'canonicalReceiverPhone': v.canonicalReceiverPhone,
    'originVoucherId': v.originVoucherId?.value,
    'rejectionReason': v.rejectionReason,
    'withdrawnAt': v.withdrawnAt == null ? null : _date(v.withdrawnAt!),
    'reversalCount': v.reversalCount,
    'firstChildId': v.firstChildId?.value,
    'isInbound': v.isInbound,
    'senderSignatureHex': v.senderSignatureHex,
    'receiverSignatureHex': v.receiverSignatureHex,
    'senderPublicKeyHex': v.senderPublicKeyHex,
    'receiverPublicKeyHex': v.receiverPublicKeyHex,
    'tripartiteMeta': v.tripartiteMeta == null
        ? null
        : _tripartite(v.tripartiteMeta!),
  };

  static Map<String, Object?> _attachment(AttachmentRef a) => {
    'id': a.id.value,
    'path': a.storagePath,
    'mimeType': a.mimeType,
    'byteSize': a.byteSize,
    'blobHash': a.encryptedBlobHash,
    'thumbPath': a.thumbnailPath,
    'source': a.sourceType.name,
  };

  static Map<String, Object?> _tripartite(TripartiteMeta t) => {
    'transferGroupId': t.transferGroupId,
    'role': t.role.columnValue,
    'linkedPartyId': t.linkedPartyId.value,
    'mediatorAccountId': t.mediatorAccountId?.value,
    'feeAmountMinor': t.feeAmount?.minorUnits,
    'isContingent': t.isContingent,
  };

  static Voucher _readVoucher(Object? raw, CurrencyCode currency) {
    final m = _map(raw, 'voucher');
    _keys(m, const {
      'id',
      'type',
      'referenceNumber',
      'date',
      'amountMinor',
      'currency',
      'counterpartyId',
      'affectedAccountId',
      'state',
      'description',
      'attachmentRefs',
      'notes',
      'tags',
      'createdAt',
      'confirmedAt',
      'settledAt',
      'senderStatus',
      'receiverStatus',
      'lifecycleStatus',
      'signerPhone',
      'canonicalSenderPhone',
      'canonicalReceiverPhone',
      'originVoucherId',
      'rejectionReason',
      'withdrawnAt',
      'reversalCount',
      'firstChildId',
      'isInbound',
      'senderSignatureHex',
      'receiverSignatureHex',
      'senderPublicKeyHex',
      'receiverPublicKeyHex',
      'tripartiteMeta',
    });
    final vc = _readCurrency(m['currency'], 'voucher.currency');
    if (vc != currency)
      throw const FormatException('Voucher currency mismatch');
    final attachments = _list(
      m['attachmentRefs'],
      'voucher.attachmentRefs',
    ).map(_readAttachment).toList(growable: false);
    final t = m['tripartiteMeta'] == null
        ? null
        : _readTripartite(m['tripartiteMeta'], currency);
    return Voucher.restore(
      id: VoucherId(_string(m['id'], 'voucher.id')),
      type: _enum(m['type'], VoucherType.values, 'voucher.type'),
      referenceNumber: _nullableString(
        m['referenceNumber'],
        'voucher.referenceNumber',
      ),
      date: _dateRead(m['date'], 'voucher.date'),
      amount: Money.fromMinorUnits(
        _int(m['amountMinor'], 'voucher.amountMinor'),
        vc,
      ),
      currency: vc,
      counterpartyId: AccountId(
        _string(m['counterpartyId'], 'voucher.counterpartyId'),
      ),
      affectedAccountId: AccountId(
        _string(m['affectedAccountId'], 'voucher.affectedAccountId'),
      ),
      state: _enum(m['state'], VoucherState.values, 'voucher.state'),
      description: _nullableString(m['description'], 'voucher.description'),
      attachmentRefs: attachments,
      notes: _nullableString(m['notes'], 'voucher.notes'),
      tags: _list(
        m['tags'],
        'voucher.tags',
      ).map((e) => _string(e, 'voucher.tag')).toList(),
      createdAt: _dateRead(m['createdAt'], 'voucher.createdAt'),
      confirmedAt: _nullableDate(m['confirmedAt'], 'voucher.confirmedAt'),
      settledAt: _nullableDate(m['settledAt'], 'voucher.settledAt'),
      senderStatus: _enum(
        m['senderStatus'],
        AgreementStatus.values,
        'voucher.senderStatus',
      ),
      receiverStatus: _enum(
        m['receiverStatus'],
        AgreementStatus.values,
        'voucher.receiverStatus',
      ),
      lifecycleStatus: _enum(
        m['lifecycleStatus'],
        VoucherLifecycle.values,
        'voucher.lifecycleStatus',
      ),
      signerPhone: _nullableString(m['signerPhone'], 'voucher.signerPhone'),
      canonicalSenderPhone: _nullableString(
        m['canonicalSenderPhone'],
        'voucher.canonicalSenderPhone',
      ),
      canonicalReceiverPhone: _nullableString(
        m['canonicalReceiverPhone'],
        'voucher.canonicalReceiverPhone',
      ),
      originVoucherId: m['originVoucherId'] == null
          ? null
          : VoucherId(_string(m['originVoucherId'], 'voucher.originVoucherId')),
      rejectionReason: _nullableString(
        m['rejectionReason'],
        'voucher.rejectionReason',
      ),
      withdrawnAt: _nullableDate(m['withdrawnAt'], 'voucher.withdrawnAt'),
      reversalCount: _int(m['reversalCount'], 'voucher.reversalCount'),
      firstChildId: m['firstChildId'] == null
          ? null
          : VoucherId(_string(m['firstChildId'], 'voucher.firstChildId')),
      isInbound: _bool(m['isInbound'], 'voucher.isInbound'),
      senderSignatureHex: _nullableString(
        m['senderSignatureHex'],
        'voucher.senderSignatureHex',
      ),
      receiverSignatureHex: _nullableString(
        m['receiverSignatureHex'],
        'voucher.receiverSignatureHex',
      ),
      senderPublicKeyHex: _nullableString(
        m['senderPublicKeyHex'],
        'voucher.senderPublicKeyHex',
      ),
      receiverPublicKeyHex: _nullableString(
        m['receiverPublicKeyHex'],
        'voucher.receiverPublicKeyHex',
      ),
      tripartiteMeta: t,
    );
  }

  static AttachmentRef _readAttachment(Object? raw) {
    final m = _map(raw, 'voucher.attachment');
    _keys(m, const {
      'id',
      'path',
      'mimeType',
      'byteSize',
      'blobHash',
      'thumbPath',
      'source',
    });
    return AttachmentRef(
      id: AttachmentId(_string(m['id'], 'attachment.id')),
      storagePath: _string(m['path'], 'attachment.path'),
      mimeType: _nullableString(m['mimeType'], 'attachment.mimeType'),
      byteSize: m['byteSize'] == null
          ? null
          : _int(m['byteSize'], 'attachment.byteSize'),
      encryptedBlobHash: _nullableString(m['blobHash'], 'attachment.blobHash'),
      thumbnailPath: _nullableString(m['thumbPath'], 'attachment.thumbPath'),
      sourceType: _enum(
        m['source'],
        AttachmentSourceType.values,
        'attachment.source',
      ),
    );
  }

  static TripartiteMeta _readTripartite(Object? raw, CurrencyCode currency) {
    final m = _map(raw, 'voucher.tripartiteMeta');
    _keys(m, const {
      'transferGroupId',
      'role',
      'linkedPartyId',
      'mediatorAccountId',
      'feeAmountMinor',
      'isContingent',
    });
    return TripartiteMeta(
      transferGroupId: _string(
        m['transferGroupId'],
        'tripartite.transferGroupId',
      ),
      role: TripartiteRole.values.firstWhere(
        (r) => r.columnValue == _string(m['role'], 'tripartite.role'),
        orElse: () => throw const FormatException('Invalid tripartite role'),
      ),
      linkedPartyId: AccountId(
        _string(m['linkedPartyId'], 'tripartite.linkedPartyId'),
      ),
      mediatorAccountId: m['mediatorAccountId'] == null
          ? null
          : AccountId(
              _string(m['mediatorAccountId'], 'tripartite.mediatorAccountId'),
            ),
      feeAmount: m['feeAmountMinor'] == null
          ? null
          : Money.fromMinorUnits(
              _int(m['feeAmountMinor'], 'tripartite.feeAmountMinor'),
              currency,
            ),
      isContingent: _bool(m['isContingent'], 'tripartite.isContingent'),
    );
  }

  static Map<String, Object?> _entry(LedgerEntry e) => {
    'id': e.id.value,
    'transactionId': e.transactionId.value,
    'accountId': e.accountId.value,
    'side': e.side.name,
    'amountMinor': e.amount.minorUnits,
    'currency': _currency(e.currency),
    'voucherId': e.voucherId.value,
    'date': _date(e.date),
    'createdAt': _date(e.createdAt),
  };
  static LedgerEntry _readEntry(Object? raw, CurrencyCode currency) {
    final m = _map(raw, 'entry');
    _keys(m, const {
      'id',
      'transactionId',
      'accountId',
      'side',
      'amountMinor',
      'currency',
      'voucherId',
      'date',
      'createdAt',
    });
    final c = _readCurrency(m['currency'], 'entry.currency');
    if (c != currency) throw const FormatException('Entry currency mismatch');
    return LedgerEntry.create(
      id: EntryId(_string(m['id'], 'entry.id')),
      transactionId: TransactionId(
        _string(m['transactionId'], 'entry.transactionId'),
      ),
      accountId: AccountId(_string(m['accountId'], 'entry.accountId')),
      side: _enum(m['side'], EntrySide.values, 'entry.side'),
      amount: Money.fromMinorUnits(
        _int(m['amountMinor'], 'entry.amountMinor'),
        c,
      ),
      currency: c,
      voucherId: VoucherId(_string(m['voucherId'], 'entry.voucherId')),
      date: _dateRead(m['date'], 'entry.date'),
      createdAt: _dateRead(m['createdAt'], 'entry.createdAt'),
    );
  }

  static PosDiscountRule? _readDiscountRule({
    required Object? method,
    required Object? value,
    required Object? reason,
    required Object? actor,
    required Object? maximum,
    required CurrencyCode currency,
    required String path,
  }) {
    final any =
        method != null ||
        value != null ||
        reason != null ||
        actor != null ||
        maximum != null;
    if (!any) return null;
    final m = _string(method, '$path.method');
    final v = _int(value, '$path.value');
    final r = _string(reason, '$path.reason');
    final a = _string(actor, '$path.actorId');
    final max = _int(maximum, '$path.policyMaximumBasisPoints');
    return switch (m) {
      'fixedAmount' => PosDiscountRule.fixed(
        amount: Money.fromMinorUnits(v, currency),
        reason: r,
        actorId: a,
        policyMaximumBasisPoints: max,
      ),
      'percentage' => PosDiscountRule.percentage(
        basisPoints: v,
        reason: r,
        actorId: a,
        policyMaximumBasisPoints: max,
      ),
      _ => throw FormatException('Invalid $path.method'),
    };
  }

  static String _date(DateTime d) => d.toUtc().toIso8601String();
  static DateTime _dateRead(Object? v, String p) {
    final s = _string(v, p);
    final d = DateTime.tryParse(s);
    if (d == null || !s.endsWith('Z'))
      throw FormatException('Invalid UTC date: $p');
    return d.toUtc();
  }

  static DateTime? _nullableDate(Object? v, String p) =>
      v == null ? null : _dateRead(v, p);
  static Map<String, Object?> _map(Object? v, String p) {
    if (v is! Map) throw FormatException('Invalid object at $p');
    final result = <String, Object?>{};
    for (final entry in v.entries) {
      if (entry.key is! String) throw FormatException('Non-string key at $p');
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static List<Object?> _list(Object? v, String p) =>
      v is List ? List<Object?>.from(v) : _bad(p);
  static Never _bad(String p) => throw FormatException('Invalid value at $p');
  static void _keys(Map<String, Object?> m, Set<String> expected) {
    if (m.length != expected.length || !m.keys.toSet().containsAll(expected))
      throw const FormatException('Unexpected or missing keys');
  }

  static String _string(Object? v, String p) => v is String ? v : _bad(p);
  static String? _nullableString(Object? v, String p) =>
      v == null ? null : _string(v, p);
  static int _int(Object? v, String p) => v is int ? v : _bad(p);
  static bool _bool(Object? v, String p) => v is bool ? v : _bad(p);
  static T _enum<T extends Enum>(Object? v, List<T> values, String p) =>
      values.firstWhere((e) => e.name == _string(v, p), orElse: () => _bad(p));
  static PosInvoiceType _invoiceType(Object? v) =>
      switch (_string(v, 'invoice.document_type')) {
        'sale' => PosInvoiceType.sale,
        'purchase' => PosInvoiceType.purchase,
        'sales_return' => PosInvoiceType.salesReturn,
        'purchase_return' => PosInvoiceType.purchaseReturn,
        _ => throw const FormatException('Invalid invoice.document_type'),
      };
}
