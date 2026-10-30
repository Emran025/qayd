import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/exceptions/invalid_pos_barcode_exception.dart';
import 'package:qayd/domain/exceptions/invalid_pos_product_exception.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_barcode.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

void main() {
  final currency = CurrencyCode(
    code: 'SAR',
    nameAr: 'ريال سعودي',
    symbol: 'ر.س',
  );

  Money amount(int minorUnits) => Money.fromMinorUnits(minorUnits, currency);

  PosProduct validProduct({
    List<PosBarcode> barcodes = const <PosBarcode>[],
    int quantityScale = 0,
    PosQuantity? reorderLevel,
  }) {
    return PosProduct.create(
      id: 'product-1',
      sku: 'SKU-1',
      name: 'Coffee',
      currency: currency,
      salePrice: amount(1500),
      purchasePrice: amount(900),
      quantityScale: quantityScale,
      reorderLevel: reorderLevel,
      barcodes: barcodes,
      now: DateTime.utc(2026, 1, 1),
    );
  }

  group('PosBarcode', () {
    test('trims values and rejects empty or control characters', () {
      expect(PosBarcode('  12345  ').value, '12345');
      expect(() => PosBarcode(''), throwsA(isA<InvalidPosBarcodeException>()));
      expect(
        () => PosBarcode('123\n456'),
        throwsA(isA<InvalidPosBarcodeException>()),
      );
    });
  });

  group('PosProduct', () {
    test('creates a normalized product with exact money and quantity policy', () {
      final product = validProduct(
        quantityScale: 3,
        reorderLevel: PosQuantity.fromScaled(1250, scale: 3),
      );

      expect(product.id, 'product-1');
      expect(product.sku, 'SKU-1');
      expect(product.salePrice, amount(1500));
      expect(product.purchasePrice, amount(900));
      expect(product.reorderLevel.toExactString(), '1.25');
      expect(product.quantityScale, 3);
      expect(product.isActive, isTrue);
    });

    test('rejects missing identity and display fields', () {
      expect(
        () => PosProduct.create(
          id: '',
          sku: 'SKU-1',
          name: 'Product',
          currency: currency,
          salePrice: amount(100),
          purchasePrice: amount(50),
        ),
        throwsA(isA<InvalidPosProductException>()),
      );
      expect(
        () => PosProduct.create(
          id: 'id',
          sku: ' ',
          name: 'Product',
          currency: currency,
          salePrice: amount(100),
          purchasePrice: amount(50),
        ),
        throwsA(isA<InvalidPosProductException>()),
      );
      expect(
        () => PosProduct.create(
          id: 'id',
          sku: 'SKU',
          name: 'Product',
          unitName: ' ',
          currency: currency,
          salePrice: amount(100),
          purchasePrice: amount(50),
        ),
        throwsA(isA<InvalidPosProductException>()),
      );
    });

    test('rejects negative prices, mismatched currencies, and scales', () {
      expect(
        () => PosProduct.create(
          id: 'id',
          sku: 'SKU',
          name: 'Product',
          currency: currency,
          salePrice: amount(-1),
          purchasePrice: amount(50),
        ),
        throwsA(isA<InvalidPosProductException>()),
      );
      expect(
        () => validProduct(
          quantityScale: 2,
          reorderLevel: PosQuantity.fromScaled(1, scale: 3),
        ),
        throwsA(isA<InvalidPosProductException>()),
      );
    });

    test('rejects duplicate barcodes and adds unique ones immutably', () {
      final barcode = PosBarcode('12345');
      final product = validProduct(barcodes: [barcode]);

      expect(product.primaryBarcode, barcode);
      expect(
        () => validProduct(barcodes: [barcode, PosBarcode('12345')]),
        throwsA(isA<InvalidPosProductException>()),
      );

      final changed = product.addBarcode(PosBarcode('67890'));
      expect(product.barcodes, hasLength(1));
      expect(changed.barcodes, hasLength(2));
    });

    test('deactivates and reactivates without mutating the original', () {
      final product = validProduct();
      final deactivated = product.deactivate();
      final reactivated = deactivated.activate();

      expect(product.isActive, isTrue);
      expect(deactivated.isActive, isFalse);
      expect(reactivated.isActive, isTrue);
    });

    test('updateDetails can clear category and description', () {
      final product = PosProduct.create(
        id: 'product-1',
        sku: 'SKU-1',
        name: 'Coffee',
        currency: currency,
        salePrice: amount(1500),
        purchasePrice: amount(900),
        categoryId: 'category-1',
        description: 'Old description',
      );

      final changed = product.updateDetails(
        clearCategory: true,
        clearDescription: true,
      );

      expect(changed.categoryId, isNull);
      expect(changed.description, isNull);
      expect(product.categoryId, 'category-1');
      expect(product.description, 'Old description');
    });

    test('updateDetails rejects changing the quantity scale', () {
      final product = validProduct(quantityScale: 2);

      expect(
        () => product.updateDetails(quantityScale: 3),
        throwsA(isA<InvalidPosProductException>()),
      );
    });
  });
}
