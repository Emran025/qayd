/// Opaque identifiers allocated before a POS sales return is posted.
///
/// Only the invoice ID, idempotency key, and allocation timestamp are retained.
/// The request fingerprint itself is used only as the encrypted settings key.
final class PosSalesReturnRequestIdentity {
  const PosSalesReturnRequestIdentity({
    required this.invoiceId,
    required this.idempotencyKey,
    required this.createdAt,
  });

  final String invoiceId;
  final String idempotencyKey;
  final DateTime createdAt;
}
