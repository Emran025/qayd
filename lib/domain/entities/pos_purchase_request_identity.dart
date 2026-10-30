/// Opaque identifiers allocated before a POS purchase is posted.
///
/// The identity is retained in the encrypted local database until the atomic
/// invoice/stock/ledger transaction commits. Re-entering the same request after
/// an app restart therefore reuses the same invoice and idempotency IDs.
final class PosPurchaseRequestIdentity {
  const PosPurchaseRequestIdentity({
    required this.invoiceId,
    required this.idempotencyKey,
    required this.createdAt,
    this.requestSnapshotJson,
  });

  final String invoiceId;
  final String idempotencyKey;
  final DateTime createdAt;
  final String? requestSnapshotJson;
}
