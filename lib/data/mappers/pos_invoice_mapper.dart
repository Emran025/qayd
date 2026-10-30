import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';

abstract final class PosInvoiceMapper {
  static Map<String, Object?> toRow(PosInvoice invoice) {
    return <String, Object?>{
      'id': invoice.id,
      'invoice_number': invoice.invoiceNumber,
      'document_type': _typeToStorage(invoice.type),
      'status': invoice.status.name,
      'counterparty_account_id': invoice.counterpartyAccountId?.value,
      'warehouse_id': invoice.warehouseId,
      'source_invoice_id': invoice.sourceInvoiceId,
      'currency_code': invoice.currency.code,
      'subtotal_minor': invoice.subtotal.minorUnits,
      'discount_minor': invoice.discount.minorUnits,
      'tax_minor': invoice.tax.minorUnits,
      'total_minor': invoice.total.minorUnits,
      'paid_minor': invoice.paid.minorUnits,
      'due_minor': invoice.due.minorUnits,
      'idempotency_key': invoice.idempotencyKey,
      'created_at': invoice.createdAt.toUtc().toIso8601String(),
      'updated_at': invoice.updatedAt.toUtc().toIso8601String(),
      'posted_at': invoice.postedAt?.toUtc().toIso8601String(),
      'invoice_date': invoice.invoiceDate.toUtc().toIso8601String(),
      'signature_hex': invoice.signature?.signatureHex,
      'signer_public_key_hex': invoice.signature?.signerPublicKeyHex,
      'signature_payload_hash': invoice.signature?.payloadHashHex,
      'signed_at': invoice.signature?.signedAt.toUtc().toIso8601String(),
    };
  }

  static Map<String, Object?> lineToRow(PosInvoiceLine line) {
    final conversion = line.currencyConversion;
    final rate = conversion?.rateSnapshot;
    return <String, Object?>{
      'id': line.id,
      'invoice_id': line.invoiceId,
      'product_id': line.productId,
      'product_name_snapshot': line.productNameSnapshot,
      'barcode_snapshot': line.barcodeSnapshot,
      'quantity_scaled': line.quantity.scaledUnits,
      'quantity_scale': line.quantity.scale,
      'unit_price_minor': line.unitPrice.minorUnits,
      'unit_cost_minor': line.unitCost.minorUnits,
      'unit_cost_currency_code': line.unitCost.currency.code,
      'discount_minor': line.discount.minorUnits,
      'tax_minor': line.tax.minorUnits,
      'line_total_minor': line.lineTotal.minorUnits,
      'source_line_id': line.sourceLineId,
      'created_at': line.createdAt.toUtc().toIso8601String(),
      'conversion_purpose': conversion?.purpose.name,
      'conversion_source_minor': conversion?.sourceAmount.minorUnits,
      'conversion_source_currency_code': conversion?.sourceAmount.currency.code,
      'conversion_target_minor': conversion?.targetAmount.minorUnits,
      'conversion_target_currency_code': conversion?.targetAmount.currency.code,
      'fx_rate_id': rate?.rateId,
      'fx_requested_from_code': rate?.requestedFromCurrency.code,
      'fx_requested_to_code': rate?.requestedToCurrency.code,
      'fx_stored_from_code': rate?.storedFromCurrency.code,
      'fx_stored_to_code': rate?.storedToCurrency.code,
      'fx_rate_scaled': rate?.storedRateScaled,
      'fx_effective_at': rate?.effectiveAt.toUtc().toIso8601String(),
      'fx_recorded_at': rate?.recordedAt.toUtc().toIso8601String(),
      'fx_created_at': rate?.createdAt.toUtc().toIso8601String(),
      'fx_is_inverted': rate == null ? null : (rate.isInverted ? 1 : 0),
      'fx_note': rate?.note,
      'proposed_sale_price_minor': line.proposedSalePrice?.minorUnits,
      'proposed_sale_price_applied': line.proposedSalePriceApplied ? 1 : 0,
      'product_updated_at_snapshot':
          line.productUpdatedAtSnapshot?.toUtc().toIso8601String(),
    };
  }

  static Map<String, Object?> paymentToRow(
    PosInvoicePayment payment,
    DateTime createdAt,
  ) {
    return <String, Object?>{
      'id': payment.id,
      'invoice_id': payment.invoiceId,
      'account_id': payment.accountId.value,
      'payment_method': payment.method.name,
      'amount_minor': payment.amount.minorUnits,
      'currency_code': payment.currency.code,
      'occurred_at': payment.occurredAt.toUtc().toIso8601String(),
      'idempotency_key': payment.idempotencyKey,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  static String _typeToStorage(PosInvoiceType type) {
    return switch (type) {
      PosInvoiceType.sale => 'sale',
      PosInvoiceType.purchase => 'purchase',
      PosInvoiceType.salesReturn => 'sales_return',
      PosInvoiceType.purchaseReturn => 'purchase_return',
    };
  }
}
