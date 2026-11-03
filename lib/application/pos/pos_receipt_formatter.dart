import 'package:qayd/domain/entities/pos_invoice_details.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_receipt_print_job.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Converts immutable invoice and payment snapshots to device-neutral receipt
/// content. It never reads mutable account/product data or writes to storage.
final class PosReceiptFormatter {
  const PosReceiptFormatter();

  PosReceiptPrintJob format({
    required PosInvoiceDetails details,
    required PosReceiptPaperWidth paperWidth,
    required bool isReprint,
  }) {
    final invoice = details.invoice;
    final lines = <PosReceiptLine>[
      PosReceiptLine('Qayd', alignment: PosReceiptTextAlignment.center),
      PosReceiptLine(
        AppStrings.posReceiptTitle,
        alignment: PosReceiptTextAlignment.center,
        emphasized: true,
      ),
      if (isReprint)
        PosReceiptLine(
          AppStrings.posReceiptReprintMark,
          alignment: PosReceiptTextAlignment.center,
          emphasized: true,
        ),
      PosReceiptLine(
        '${AppStrings.posReceiptNumberLabel}: ${invoice.invoiceNumber}',
      ),
      PosReceiptLine(
        '${AppStrings.posReceiptDateLabel}: ${_date(invoice.invoiceDate)}',
      ),
      if (invoice.counterpartyAccountId != null)
        PosReceiptLine(
          '${AppStrings.posReceiptPartyLabel}: '
          '${invoice.counterpartyAccountId!.value}',
        ),
      const PosReceiptLine('────────────────'),
    ];

    for (final line in invoice.lines) {
      lines.add(PosReceiptLine(line.productNameSnapshot, emphasized: true));
      lines.add(
        PosReceiptLine(
          '${line.quantity.toExactString()} × ${_money(line.unitPrice)}',
        ),
      );
      if (!line.discount.isZero) {
        lines.add(
          PosReceiptLine(
            '${AppStrings.posReceiptLineDiscountLabel}: '
            '${_money(line.discount)}',
          ),
        );
      }
      if (!line.tax.isZero) {
        lines.add(
          PosReceiptLine(
            '${AppStrings.posReceiptLineTaxLabel}: ${_money(line.tax)}',
          ),
        );
      }
      lines.add(
        PosReceiptLine(
          '${AppStrings.posReceiptLineTotalLabel}: ${_money(line.lineTotal)}',
          emphasized: true,
        ),
      );
    }

    lines.addAll([
      const PosReceiptLine('────────────────'),
      PosReceiptLine(
        '${AppStrings.posReceiptSubtotalLabel}: ${_money(invoice.subtotal)}',
      ),
      if (!invoice.discount.isZero)
        PosReceiptLine(
          '${AppStrings.posReceiptDiscountLabel}: ${_money(invoice.discount)}',
        ),
      if (!invoice.tax.isZero)
        PosReceiptLine(
          '${AppStrings.posReceiptTaxLabel}: ${_money(invoice.tax)}',
        ),
      PosReceiptLine(
        '${AppStrings.posReceiptTotalLabel}: ${_money(invoice.total)}',
        emphasized: true,
      ),
      PosReceiptLine(
        '${AppStrings.posReceiptPaidLabel}: ${_money(invoice.paid)}',
      ),
      PosReceiptLine(
        '${AppStrings.posReceiptDueLabel}: ${_money(invoice.due)}',
        emphasized: !invoice.due.isZero,
      ),
    ]);

    final methods = details.payments.map((payment) => payment.method).toSet();
    if (!invoice.due.isZero) methods.add(PosPaymentMethod.credit);
    if (methods.isNotEmpty) {
      lines.add(
        PosReceiptLine(
          '${AppStrings.posReceiptPaymentMethodLabel}: '
          '${methods.map(_paymentMethodLabel).join(', ')}',
        ),
      );
    }
    if (!invoice.due.isZero) {
      lines.add(
        PosReceiptLine(
          '${AppStrings.posReceiptDeferredDueLabel}: ${_money(invoice.due)}',
          emphasized: true,
        ),
      );
    }

    return PosReceiptPrintJob(
      paperWidth: paperWidth,
      isReprint: isReprint,
      lines: lines,
    );
  }

  String _paymentMethodLabel(PosPaymentMethod method) => switch (method) {
        PosPaymentMethod.cash => AppStrings.posReceiptCash,
        PosPaymentMethod.bank => AppStrings.posReceiptBank,
        PosPaymentMethod.credit => AppStrings.posReceiptCredit,
        PosPaymentMethod.other => AppStrings.posReceiptOther,
      };

  String _date(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _money(Money value) {
    final digits = value.currency.fractionalDigits;
    final absolute = value.minorUnits.abs();
    final sign = value.minorUnits < 0 ? '-' : '';
    if (digits == 0) return '$sign$absolute ${value.currency.symbol}';
    final divisor = _pow10(digits);
    final whole = absolute ~/ divisor;
    final fraction = (absolute % divisor).toString().padLeft(digits, '0');
    return '$sign$whole.$fraction ${value.currency.symbol}';
  }

  int _pow10(int digits) {
    var value = 1;
    for (var i = 0; i < digits; i++) {
      value *= 10;
    }
    return value;
  }
}
