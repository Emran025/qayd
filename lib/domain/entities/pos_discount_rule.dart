import 'package:qayd/domain/exceptions/invalid_pos_invoice_exception.dart';
import 'package:qayd/domain/value_objects/money.dart';

/// The explicit input used to calculate one line or cart discount.
///
/// Percentages use integer basis points; 10% is 1000. The current maximum
/// policy is 100% of the eligible base. There is intentionally no bypass
/// control: a stricter configured policy must be supplied by the caller and
/// is retained with the invoice snapshot.
enum PosDiscountMethod { fixedAmount, percentage }

final class PosDiscountRule {
  const PosDiscountRule._({
    required this.method,
    required this.value,
    required this.reason,
    required this.actorId,
    required this.policyMaximumBasisPoints,
    this.currencyCode,
  });

  static const int maximumBasisPoints = 10000;

  factory PosDiscountRule.fixed({
    required Money amount,
    required String reason,
    required String actorId,
    int policyMaximumBasisPoints = maximumBasisPoints,
  }) {
    _validateMetadata(reason, actorId, policyMaximumBasisPoints);
    if (amount.minorUnits <= 0) {
      throw InvalidPosInvoiceException.invalidLine();
    }
    return PosDiscountRule._(
      method: PosDiscountMethod.fixedAmount,
      value: amount.minorUnits,
      reason: reason.trim(),
      actorId: actorId.trim(),
      policyMaximumBasisPoints: policyMaximumBasisPoints,
      currencyCode: amount.currency.code,
    );
  }

  factory PosDiscountRule.percentage({
    required int basisPoints,
    required String reason,
    required String actorId,
    int policyMaximumBasisPoints = maximumBasisPoints,
  }) {
    _validateMetadata(reason, actorId, policyMaximumBasisPoints);
    if (basisPoints <= 0 || basisPoints > policyMaximumBasisPoints) {
      throw InvalidPosInvoiceException.invalidLine();
    }
    return PosDiscountRule._(
      method: PosDiscountMethod.percentage,
      value: basisPoints,
      reason: reason.trim(),
      actorId: actorId.trim(),
      policyMaximumBasisPoints: policyMaximumBasisPoints,
    );
  }

  final PosDiscountMethod method;

  /// Minor currency units for fixed discounts; basis points for percentages.
  final int value;
  final String reason;

  /// Stable current device identity; the app has no per-employee POS role model.
  final String actorId;
  final int policyMaximumBasisPoints;

  /// Non-null only for fixed-amount rules so currency mismatches fail closed.
  final String? currencyCode;

  Money amountFor(Money eligibleBase) {
    if (eligibleBase.isNegative) {
      throw InvalidPosInvoiceException.invalidTotals();
    }
    if (method == PosDiscountMethod.fixedAmount) {
      if (eligibleBase.currency.code != currencyCode) {
        throw InvalidPosInvoiceException.currencyMismatch();
      }
      if (value > eligibleBase.minorUnits) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
      final policyMaximumMinor =
          (BigInt.from(eligibleBase.minorUnits) *
                  BigInt.from(policyMaximumBasisPoints) +
              BigInt.from(5000)) ~/
          BigInt.from(10000);
      if (BigInt.from(value) > policyMaximumMinor) {
        throw InvalidPosInvoiceException.invalidTotals();
      }
      return Money.fromMinorUnits(value, eligibleBase.currency);
    }
    if (value > policyMaximumBasisPoints || value > maximumBasisPoints) {
      throw InvalidPosInvoiceException.invalidTotals();
    }
    final scaled = BigInt.from(eligibleBase.minorUnits) * BigInt.from(value);
    final rounded = (scaled + BigInt.from(5000)) ~/ BigInt.from(10000);
    return Money.fromMinorUnits(rounded.toInt(), eligibleBase.currency);
  }

  static void _validateMetadata(
    String reason,
    String actorId,
    int policyMaximumBasisPoints,
  ) {
    if (reason.trim().isEmpty ||
        actorId.trim().isEmpty ||
        policyMaximumBasisPoints < 0 ||
        policyMaximumBasisPoints > maximumBasisPoints) {
      throw InvalidPosInvoiceException.invalidLine();
    }
  }
}
