import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';

/// Markup applied to a product's cost when proposing a sale price.
///
/// Percentage margins are stored as basis points (10,000 basis points equals
/// 100 percent). Fixed margins are stored in the product's currency.
final class PosProfitMargin {
  const PosProfitMargin._percentage(this.percentageBasisPoints)
      : fixedAmount = null;

  const PosProfitMargin._fixed(this.fixedAmount) : percentageBasisPoints = null;

  /// A zero percentage markup, compatible with products created before margins
  /// were introduced.
  const PosProfitMargin.zero() : this._percentage(0);

  /// Creates a percentage markup in basis points (10,000 = 100%).
  factory PosProfitMargin.percentage(int basisPoints) {
    if (basisPoints < 0) {
      throw ArgumentError.value(
          basisPoints, 'basisPoints', 'Must be non-negative');
    }
    return PosProfitMargin._percentage(basisPoints);
  }

  /// Creates a fixed markup in the supplied currency.
  factory PosProfitMargin.fixedAmount(Money amount) {
    if (amount.isNegative) {
      throw ArgumentError.value(amount, 'amount', 'Must be non-negative');
    }
    return PosProfitMargin._fixed(amount);
  }

  /// Percentage markup in basis points, or null for a fixed margin.
  final int? percentageBasisPoints;

  /// Fixed markup, or null for a percentage margin.
  final Money? fixedAmount;

  bool get isPercentage => percentageBasisPoints != null;
  bool get isFixedAmount => fixedAmount != null;

  /// Calculates cost plus this margin in integer minor units.
  ///
  /// Percentage markup uses round-half-up without converting to double.
  Money calculateProposedSalePrice(Money cost) {
    final basisPoints = percentageBasisPoints;
    if (basisPoints != null) {
      final markup = (BigInt.from(cost.minorUnits) * BigInt.from(basisPoints) +
              BigInt.from(5000)) ~/
          BigInt.from(10000);
      return Money.fromMinorUnits(
        cost.minorUnits + markup.toInt(),
        cost.currency,
      );
    }

    final fixed = fixedAmount!;
    if (fixed.currency != cost.currency) {
      throw ArgumentError.value(
        cost.currency,
        'cost',
        'Currency must match the fixed margin currency',
      );
    }
    return cost + fixed;
  }

  /// Whether this margin's fixed amount is valid for [currency].
  bool matchesCurrency(CurrencyCode currency) =>
      fixedAmount == null || fixedAmount!.currency == currency;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PosProfitMargin &&
          other.percentageBasisPoints == percentageBasisPoints &&
          other.fixedAmount == fixedAmount;

  @override
  int get hashCode => Object.hash(percentageBasisPoints, fixedAmount);
}
