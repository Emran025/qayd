import 'package:qayd/presentation/l10n/app_strings.dart';

final class InvalidPosProductException implements Exception {
  InvalidPosProductException._(this.messageAr);

  final String messageAr;

  factory InvalidPosProductException.idRequired() =>
      InvalidPosProductException._(AppStrings.posProductIdRequired);

  factory InvalidPosProductException.nameRequired() =>
      InvalidPosProductException._(AppStrings.posProductNameRequired);

  factory InvalidPosProductException.unitRequired() =>
      InvalidPosProductException._(AppStrings.posProductUnitRequired);

  factory InvalidPosProductException.skuRequired() =>
      InvalidPosProductException._(AppStrings.posProductSkuRequired);

  factory InvalidPosProductException.priceNegative() =>
      InvalidPosProductException._(AppStrings.posProductPriceInvalid);

  factory InvalidPosProductException.currencyMismatch() =>
      InvalidPosProductException._(AppStrings.posProductCurrencyMismatch);

  factory InvalidPosProductException.quantityScaleInvalid() =>
      InvalidPosProductException._(AppStrings.posProductScaleInvalid);

  factory InvalidPosProductException.quantityScaleImmutable() =>
      InvalidPosProductException._(AppStrings.posProductScaleImmutable);

  factory InvalidPosProductException.thresholdScaleMismatch() =>
      InvalidPosProductException._(AppStrings.posProductThresholdInvalid);

  factory InvalidPosProductException.duplicateBarcode() =>
      InvalidPosProductException._(AppStrings.posBarcodeInvalid);

  @override
  String toString() => messageAr;
}
