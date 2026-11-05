import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_invoice_signature.dart';
import 'package:qayd/domain/entities/pos_discount_rule.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';

/// Canonical invoice signing boundary. The payload is intentionally versioned.
final class PosInvoiceSigningService {
  const PosInvoiceSigningService({
    required ReceiptSigningService receiptSigningService,
  }) : _receiptSigningService = receiptSigningService;

  final ReceiptSigningService _receiptSigningService;

  String canonicalPayload(
    PosInvoice invoice,
    List<PosInvoicePayment> payments,
  ) {
    final includesDiscountAudit =
        invoice.cartDiscountRule != null ||
        invoice.lines.any((line) => line.discountRule != null);
    final includesCreditTerms =
        invoice.creditDueDate != null || invoice.creditTerms != null;
    final lines = invoice.lines
        .map(
          (line) => <Object?>[
            line.id,
            line.productId,
            line.productNameSnapshot,
            line.barcodeSnapshot ?? '',
            line.quantity.scaledUnits,
            line.quantity.scale,
            line.unitPrice.minorUnits,
            line.unitCost.minorUnits,
            line.discount.minorUnits,
            line.tax.minorUnits,
            line.lineTotal.minorUnits,
            if (includesDiscountAudit) _discountRulePayload(line.discountRule),
          ].join(','),
        )
        .join(';');
    final paymentPayload = payments
        .map(
          (payment) => [
            payment.id,
            payment.accountId.value,
            payment.method.name,
            payment.amount.minorUnits,
            payment.currency.code,
            payment.occurredAt.toUtc().toIso8601String(),
            payment.idempotencyKey,
          ].join(','),
        )
        .join(';');
    return [
      includesCreditTerms
          ? 'QAYD_POS_INVOICE_V3'
          : includesDiscountAudit
          ? 'QAYD_POS_INVOICE_V2'
          : 'QAYD_POS_INVOICE_V1',
      invoice.id,
      invoice.invoiceNumber,
      invoice.type.name,
      invoice.invoiceDate.toUtc().toIso8601String(),
      invoice.warehouseId,
      invoice.counterpartyAccountId?.value ?? '',
      invoice.currency.code,
      invoice.currency.fractionalDigits,
      invoice.subtotal.minorUnits,
      invoice.discount.minorUnits,
      invoice.tax.minorUnits,
      invoice.total.minorUnits,
      invoice.paid.minorUnits,
      invoice.due.minorUnits,
      if (includesCreditTerms)
        invoice.creditDueDate?.toUtc().toIso8601String() ?? '',
      if (includesCreditTerms) invoice.creditTerms ?? '',
      invoice.status.name,
      if (includesDiscountAudit)
        '${invoice.cartDiscount.minorUnits}:${_discountRulePayload(invoice.cartDiscountRule)}',
      lines,
      paymentPayload,
    ].join('|');
  }

  String _discountRulePayload(PosDiscountRule? rule) {
    if (rule == null) return '-';
    return [
      rule.method.name,
      rule.value,
      rule.currencyCode ?? '',
      rule.reason,
      rule.actorId,
      rule.policyMaximumBasisPoints,
    ].join('~');
  }

  PosInvoiceSignature sign({
    required PosInvoice invoice,
    required List<PosInvoicePayment> payments,
    required CryptoKeyPair keyPair,
    required DateTime signedAt,
  }) {
    final signature = _receiptSigningService.signCanonicalString(
      canonicalPayload(invoice, payments),
      keyPair,
    );
    return PosInvoiceSignature(
      invoiceId: invoice.id,
      signatureHex: signature.signatureHex,
      signerPublicKeyHex: signature.signerPublicKeyHex,
      payloadHashHex: signature.payloadHashHex,
      signedAt: signedAt.toUtc(),
    );
  }
}
