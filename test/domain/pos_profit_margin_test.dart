import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/domain/entities/pos_product.dart';
import 'package:qayd/domain/entities/pos_profit_margin.dart';
import 'package:qayd/domain/exceptions/invalid_pos_product_exception.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

void main() {
  final sar = CurrencyCode(code: 'SAR', nameAr: 'ريال سعودي', symbol: 'ر.س');
  final usd = CurrencyCode(code: 'USD', nameAr: 'دولار أمريكي', symbol: '\$');

  Money money(int minorUnits, [CurrencyCode? currency]) =>
      Money.fromMinorUnits(minorUnits, currency ?? sar);

  PosProduct product({PosProfitMargin? margin}) => PosProduct.create(
        id: 'product-1',
        sku: 'SKU-1',
        name: 'Coffee',
        currency: sar,
        salePrice: money(1500),
        purchasePrice: money(900),
        profitMargin: margin,
        reorderLevel: PosQuantity.fromScaled(0, scale: 0),
      );

  group('PosProfitMargin', () {
    test('calculates percentage markup with integer round-half-up', () {
      final margin = PosProfitMargin.percentage(1250); // 12.5%

      expect(margin.calculateProposedSalePrice(money(101)), money(114));
      expect(margin.calculateProposedSalePrice(money(100)), money(113));
    });

    test('calculates fixed markup in the matching currency', () {
      final margin = PosProfitMargin.fixedAmount(money(275));

      expect(margin.calculateProposedSalePrice(money(900)), money(1175));
    });

    test('defaults to zero percentage and leaves sale price editable', () {
      final created = product();
      final changed = created.updateDetails(salePrice: money(1800));

      expect(created.profitMargin, const PosProfitMargin.zero());
      expect(created.calculateProposedSalePrice(), money(900));
      expect(changed.salePrice, money(1800));
      expect(changed.calculateProposedSalePrice(), money(900));
    });

    test('rejects a fixed margin whose currency differs from the product', () {
      expect(
        () => product(margin: PosProfitMargin.fixedAmount(money(100, usd))),
        throwsA(isA<InvalidPosProductException>()),
      );
    });

    test('rejects mismatched fixed margin on restore and update', () {
      final margin = PosProfitMargin.fixedAmount(money(100, usd));
      expect(
        () => PosProduct.restore(
          id: 'product-1',
          sku: 'SKU-1',
          name: 'Coffee',
          currency: sar,
          salePrice: money(1500),
          purchasePrice: money(900),
          quantityScale: 0,
          reorderLevel: PosQuantity.fromScaled(0, scale: 0),
          expiryTracking: false,
          isActive: true,
          barcodes: const [],
          profitMargin: margin,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        throwsA(isA<InvalidPosProductException>()),
      );
      expect(
        () => product().updateDetails(profitMargin: margin),
        throwsA(isA<InvalidPosProductException>()),
      );
    });
  });
}
