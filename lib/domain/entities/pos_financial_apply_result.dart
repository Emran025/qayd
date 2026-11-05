/// Outcome of applying a POS financial event inside the local SQL transaction.
enum PosFinancialApplyResult {
  /// The event was newly applied and committed with its inbox/journal markers.
  applied,

  /// This exact immutable event had already committed; no business rows changed.
  exactReplay,

  /// Event ID or idempotency key was reused with different immutable content.
  conflictingReplay,
}
