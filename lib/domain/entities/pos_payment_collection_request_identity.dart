/// Opaque identity for one later POS invoice collection attempt.
///
/// The identity is kept in encrypted app settings until the committed result is
/// acknowledged, so retrying after a restart reuses the same payment key.
final class PosPaymentCollectionRequestIdentity {
  const PosPaymentCollectionRequestIdentity({
    required this.paymentId,
    required this.idempotencyKey,
    required this.createdAt,
    required this.occurredAt,
  });

  final String paymentId;
  final String idempotencyKey;
  final DateTime createdAt;
  final DateTime occurredAt;
}
