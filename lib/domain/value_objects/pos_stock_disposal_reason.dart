/// Stable, non-localized reason codes for POS inventory write-offs.
enum PosStockDisposalReason { damage, expiry, authorizedLoss, other }

extension PosStockDisposalReasonX on PosStockDisposalReason {
  String get code => switch (this) {
        PosStockDisposalReason.damage => 'damage',
        PosStockDisposalReason.expiry => 'expiry',
        PosStockDisposalReason.authorizedLoss => 'authorized_loss',
        PosStockDisposalReason.other => 'other',
      };
}

PosStockDisposalReason? parsePosStockDisposalReason(String? code) {
  return switch (code) {
    'damage' => PosStockDisposalReason.damage,
    'expiry' => PosStockDisposalReason.expiry,
    'authorized_loss' => PosStockDisposalReason.authorizedLoss,
    'other' => PosStockDisposalReason.other,
    _ => null,
  };
}
