/// Single chat "message" line in the Statement of Account conversation UI.
class AccountStatementChatMessageDto {
  const AccountStatementChatMessageDto({
    required this.voucherId,
    required this.dateIso,
    required this.direction,
    required this.typeCode,
    required this.voucherStateCode,
    required this.signatureStatusCode,
    required this.amountMinorUnits,
    required this.currencyCode,
    required this.currencySymbol,
    required this.currencyDigits,
    required this.description,
    required this.otherPartyId,
    required this.otherPartyName,
    this.runningBalanceMinorUnits = 0,
    this.referenceNumber,
    this.mediatorAccountId,
    this.mediatorName,
    this.feeAmountMinorUnits,
    required this.isCreator,
    this.originVoucherId,
    this.reversalCount = 0,
    this.isSettlementMilestone = false,
    this.settlementLabel,
    this.settlementBalanceMinorUnits,
    this.isTransferRequest = false,
    this.isPosCreditInvoice = false,
    this.posInvoiceMessageId,
    this.posInvoiceNumber,
    this.posInvoiceTotalMinorUnits,
    this.posInvoiceDueMinorUnits,
    this.posInvoiceAcknowledgmentStatus,
    this.posInvoiceDeliveryStatus,
    this.posInvoicePayloadJson,
  });

  final String voucherId;
  final String dateIso;

  /// `incoming` or `outgoing` relative to the selected "my account".
  final String direction;

  /// `receipt` or `payment`.
  final String typeCode;

  /// `draft` | `confirmed` | `settled`
  final String voucherStateCode;

  /// `underRequest` | `accepted` | `rejected` | `unverified`
  final String signatureStatusCode;

  final int amountMinorUnits;
  final String currencyCode;
  final String currencySymbol;
  final int currencyDigits;

  /// Voucher "description/notes" merged for chat display.
  final String description;

  final String otherPartyId;
  final String otherPartyName;

  /// Cumulative running balance (minor units) up to and including this message.
  /// Positive = counterparty owes user; Negative = user owes counterparty.
  final int runningBalanceMinorUnits;

  /// Voucher reference number if present.
  final String? referenceNumber;

  /// (Remittance) The third-party mediator if this voucher was created via remittance clearing.
  final String? mediatorAccountId;

  /// (Remittance) The name of the mediator.
  final String? mediatorName;

  /// (Remittance) Minor units of the fee amount if any.
  final int? feeAmountMinorUnits;

  /// Indicates if the current user (perspective) is the creator of this voucher.
  final bool isCreator;

  /// The ID of the original voucher if this is a correction or reply.
  final String? originVoucherId;

  /// How many reversal (corrective) entries have been created against this voucher.
  final int reversalCount;

  /// Non-voucher milestone row: indicates account settlement checkpoint.
  final bool isSettlementMilestone;

  /// Display text for settlement milestone row.
  final String? settlementLabel;

  /// Balance that becomes the new opening balance at milestone point.
  final int? settlementBalanceMinorUnits;

  /// Whether this message is a tripartite transfer request rather than a real voucher.
  final bool isTransferRequest;

  /// A POS credit invoice message; its [amountMinorUnits] is always zero so
  /// this acknowledgment-only document cannot alter statement balances.
  final bool isPosCreditInvoice;
  final String? posInvoiceMessageId;
  final String? posInvoiceNumber;
  final int? posInvoiceTotalMinorUnits;
  final int? posInvoiceDueMinorUnits;
  final String? posInvoiceAcknowledgmentStatus;
  final String? posInvoiceDeliveryStatus;
  final String? posInvoicePayloadJson;
}
