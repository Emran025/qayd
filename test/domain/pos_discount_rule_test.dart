import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/domain/entities/pos_discount_rule.dart';
import 'package:qayd/domain/exceptions/invalid_pos_invoice_exception.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';

void main() {
  const sar = CurrencyCode(code: 'SAR', nameAr: 'ريال سعودي', symbol: 'ر.س');
  const usd = CurrencyCode(code: 'USD', nameAr: 'دولار', symbol: r'$');

  group('PosDiscountRule', () {
    test(
      'applies a fixed amount and rejects a different currency or excess',
      () {
        final rule = PosDiscountRule.fixed(
          amount: Money.fromMinorUnits(125, sar),
          reason: 'Promotion',
          actorId: 'device-1',
        );

        expect(
          rule.amountFor(Money.fromMinorUnits(500, sar)),
          Money.fromMinorUnits(125, sar),
        );
        expect(
          () => rule.amountFor(Money.fromMinorUnits(500, usd)),
          throwsA(isA<InvalidPosInvoiceException>()),
        );
        expect(
          () => rule.amountFor(Money.fromMinorUnits(124, sar)),
          throwsA(isA<InvalidPosInvoiceException>()),
        );
        final policyCapped = PosDiscountRule.fixed(
          amount: Money.fromMinorUnits(125, sar),
          policyMaximumBasisPoints: 2500,
          reason: 'Quarter cap',
          actorId: 'device-1',
        );
        expect(
          () => policyCapped.amountFor(Money.fromMinorUnits(400, sar)),
          throwsA(isA<InvalidPosInvoiceException>()),
        );
      },
    );

    test(
      'uses exact basis points with half-up rounding and a policy ceiling',
      () {
        final half = PosDiscountRule.percentage(
          basisPoints: 5000,
          reason: 'Half price',
          actorId: 'device-1',
        );
        expect(half.amountFor(Money.fromMinorUnits(1, sar)).minorUnits, 1);
        expect(half.amountFor(Money.fromMinorUnits(3, sar)).minorUnits, 2);

        final capped = PosDiscountRule.percentage(
          basisPoints: 2500,
          policyMaximumBasisPoints: 2500,
          reason: 'Quarter off',
          actorId: 'device-1',
        );
        expect(
          capped.amountFor(Money.fromMinorUnits(1000, sar)).minorUnits,
          250,
        );
        expect(
          () => PosDiscountRule.percentage(
            basisPoints: 2501,
            policyMaximumBasisPoints: 2500,
            reason: 'Too much',
            actorId: 'device-1',
          ),
          throwsA(isA<InvalidPosInvoiceException>()),
        );
      },
    );

    test('requires a reason and actor', () {
      expect(
        () => PosDiscountRule.fixed(
          amount: Money.fromMinorUnits(1, sar),
          reason: '  ',
          actorId: 'device-1',
        ),
        throwsA(isA<InvalidPosInvoiceException>()),
      );
      expect(
        () => PosDiscountRule.percentage(
          basisPoints: 100,
          reason: 'Promotion',
          actorId: '  ',
        ),
        throwsA(isA<InvalidPosInvoiceException>()),
      );
    });
  });
}
