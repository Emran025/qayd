import 'dart:collection';

import 'package:qayd/domain/exceptions/invalid_pos_product_exception.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_barcode.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

/// Product aggregate used by POS catalog and inventory flows.
final class PosProduct {
  PosProduct._({
    required this.id,
    required this.sku,
    required this.name,
    required this.categoryId,
    required this.description,
    required this.unitName,
    required this.currency,
    required this.salePrice,
    required this.purchasePrice,
    required this.quantityScale,
    required this.reorderLevel,
    required this.expiryTracking,
    required this.isActive,
    required List<PosBarcode> barcodes,
    required this.createdAt,
    required this.updatedAt,
  }) : barcodes = UnmodifiableListView(barcodes);

  factory PosProduct.create({
    required String id,
    required String sku,
    required String name,
    required CurrencyCode currency,
    required Money salePrice,
    required Money purchasePrice,
    int quantityScale = 0,
    PosQuantity? reorderLevel,
    bool expiryTracking = false,
    List<PosBarcode> barcodes = const <PosBarcode>[],
    String? categoryId,
    String? description,
    String unitName = 'unit',
    DateTime? now,
  }) {
    final trimmedId = id.trim();
    final trimmedSku = sku.trim();
    final trimmedName = name.trim();
    final trimmedUnit = unitName.trim();
    if (trimmedId.isEmpty) throw InvalidPosProductException.idRequired();
    if (trimmedSku.isEmpty) throw InvalidPosProductException.skuRequired();
    if (trimmedName.isEmpty) throw InvalidPosProductException.nameRequired();
    if (trimmedUnit.isEmpty) throw InvalidPosProductException.unitRequired();
    if (salePrice.currency != currency || purchasePrice.currency != currency) {
      throw InvalidPosProductException.currencyMismatch();
    }
    if (salePrice.isNegative || purchasePrice.isNegative) {
      throw InvalidPosProductException.priceNegative();
    }
    if (quantityScale < PosQuantity.minScale ||
        quantityScale > PosQuantity.maxScale) {
      throw InvalidPosProductException.quantityScaleInvalid();
    }
    final threshold = reorderLevel ?? PosQuantity.fromScaled(
      0,
      scale: quantityScale,
    );
    if (threshold.scale != quantityScale) {
      throw InvalidPosProductException.thresholdScaleMismatch();
    }
    final uniqueBarcodes = <String>{};
    for (final barcode in barcodes) {
      if (!uniqueBarcodes.add(barcode.value)) {
        throw InvalidPosProductException.duplicateBarcode();
      }
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    return PosProduct._(
      id: trimmedId,
      sku: trimmedSku,
      name: trimmedName,
      categoryId: categoryId?.trim().isEmpty == true ? null : categoryId?.trim(),
      description: description?.trim(),
      unitName: trimmedUnit,
      currency: currency,
      salePrice: salePrice,
      purchasePrice: purchasePrice,
      quantityScale: quantityScale,
      reorderLevel: threshold,
      expiryTracking: expiryTracking,
      isActive: true,
      barcodes: barcodes,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  /// Rehydrates a product from persistence without changing its timestamps.
  factory PosProduct.restore({
    required String id,
    required String sku,
    required String name,
    required CurrencyCode currency,
    required Money salePrice,
    required Money purchasePrice,
    required int quantityScale,
    required PosQuantity reorderLevel,
    required bool expiryTracking,
    required bool isActive,
    required List<PosBarcode> barcodes,
    String? categoryId,
    String? description,
    String unitName = 'unit',
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    final created = PosProduct.create(
      id: id,
      sku: sku,
      name: name,
      currency: currency,
      salePrice: salePrice,
      purchasePrice: purchasePrice,
      quantityScale: quantityScale,
      reorderLevel: reorderLevel,
      expiryTracking: expiryTracking,
      barcodes: barcodes,
      categoryId: categoryId,
      description: description,
      unitName: unitName,
      now: createdAt,
    );
    return PosProduct._(
      id: created.id,
      sku: created.sku,
      name: created.name,
      categoryId: created.categoryId,
      description: created.description,
      unitName: created.unitName,
      currency: created.currency,
      salePrice: created.salePrice,
      purchasePrice: created.purchasePrice,
      quantityScale: created.quantityScale,
      reorderLevel: created.reorderLevel,
      expiryTracking: created.expiryTracking,
      isActive: isActive,
      barcodes: created.barcodes,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
  }

  final String id;
  final String sku;
  final String name;
  final String? categoryId;
  final String? description;
  final String unitName;
  final CurrencyCode currency;
  final Money salePrice;
  final Money purchasePrice;
  final int quantityScale;
  final PosQuantity reorderLevel;
  final bool expiryTracking;
  final bool isActive;
  final List<PosBarcode> barcodes;
  final DateTime createdAt;
  final DateTime updatedAt;

  PosBarcode? get primaryBarcode => barcodes.isEmpty ? null : barcodes.first;

  PosProduct addBarcode(PosBarcode barcode) {
    if (barcodes.any((item) => item == barcode)) {
      throw InvalidPosProductException.duplicateBarcode();
    }
    return _copyWith(
      barcodes: [...barcodes, barcode],
      updatedAt: DateTime.now().toUtc(),
    );
  }

  PosProduct updateDetails({
    String? sku,
    String? name,
    String? categoryId,
    String? description,
    bool clearCategory = false,
    bool clearDescription = false,
    String? unitName,
    Money? salePrice,
    Money? purchasePrice,
    int? quantityScale,
    PosQuantity? reorderLevel,
    bool? expiryTracking,
    List<PosBarcode>? barcodes,
  }) {
    if (quantityScale != null && quantityScale != this.quantityScale) {
      throw InvalidPosProductException.quantityScaleImmutable();
    }
    final draft = PosProduct.create(
      id: id,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
      description: clearDescription ? null : description ?? this.description,
      unitName: unitName ?? this.unitName,
      currency: currency,
      salePrice: salePrice ?? this.salePrice,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      quantityScale: quantityScale ?? this.quantityScale,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      expiryTracking: expiryTracking ?? this.expiryTracking,
      barcodes: barcodes ?? this.barcodes,
      now: DateTime.now().toUtc(),
    );
    return PosProduct._(
      id: draft.id,
      sku: draft.sku,
      name: draft.name,
      categoryId: draft.categoryId,
      description: draft.description,
      unitName: draft.unitName,
      currency: draft.currency,
      salePrice: draft.salePrice,
      purchasePrice: draft.purchasePrice,
      quantityScale: draft.quantityScale,
      reorderLevel: draft.reorderLevel,
      expiryTracking: draft.expiryTracking,
      isActive: isActive,
      barcodes: draft.barcodes,
      createdAt: createdAt,
      updatedAt: draft.updatedAt,
    );
  }

  PosProduct deactivate() {
    if (!isActive) return this;
    return _copyWith(isActive: false, updatedAt: DateTime.now().toUtc());
  }

  PosProduct activate() {
    if (isActive) return this;
    return _copyWith(isActive: true, updatedAt: DateTime.now().toUtc());
  }

  PosProduct _copyWith({
    List<PosBarcode>? barcodes,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return PosProduct._(
      id: id,
      sku: sku,
      name: name,
      categoryId: categoryId,
      description: description,
      unitName: unitName,
      currency: currency,
      salePrice: salePrice,
      purchasePrice: purchasePrice,
      quantityScale: quantityScale,
      reorderLevel: reorderLevel,
      expiryTracking: expiryTracking,
      isActive: isActive ?? this.isActive,
      barcodes: barcodes ?? this.barcodes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
