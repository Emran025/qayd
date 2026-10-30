import 'package:qayd/domain/entities/pos_currency_rate.dart';
import 'package:qayd/domain/value_objects/money.dart';

/// Which price is being converted for a POS invoice line.
enum PosInvoiceLineConversionPurpose { catalogSalePrice, purchaseCost }

/// Immutable, auditable conversion attached to a POS invoice line.
///
/// For a sale, the source is the catalog price and the target is the invoice
/// unit price. For a purchase, the source is the supplier's unit price and the
/// target is the inventory unit cost in the product's catalog currency.
final class PosInvoiceLineConversion {
  factory PosInvoiceLineConversion({
    required PosInvoiceLineConversionPurpose purpose,
    required Money sourceAmount,
    required Money targetAmount,
    PosCurrencyRateQuote? rateSnapshot,
  }) {
    if (sourceAmount.isNegative || targetAmount.isNegative) {
      throw ArgumentError('Converted POS prices must be non-negative');
    }
    if (sourceAmount.currency == targetAmount.currency) {
      if (sourceAmount != targetAmount || rateSnapshot != null) {
        throw ArgumentError('Identity conversion must preserve the amount');
      }
    } else {
      if (rateSnapshot == null ||
          rateSnapshot.requestedFromCurrency != sourceAmount.currency ||
          rateSnapshot.requestedToCurrency != targetAmount.currency ||
          rateSnapshot.convert(sourceAmount) != targetAmount) {
        throw ArgumentError('Rate snapshot does not reproduce the conversion');
      }
    }
    return PosInvoiceLineConversion._(
      purpose: purpose,
      sourceAmount: sourceAmount,
      targetAmount: targetAmount,
      rateSnapshot: rateSnapshot,
    );
  }

  const PosInvoiceLineConversion._({
    required this.purpose,
    required this.sourceAmount,
    required this.targetAmount,
    required this.rateSnapshot,
  });

  final PosInvoiceLineConversionPurpose purpose;
  final Money sourceAmount;
  final Money targetAmount;
  final PosCurrencyRateQuote? rateSnapshot;
}
