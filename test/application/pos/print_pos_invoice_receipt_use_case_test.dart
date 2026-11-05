import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/pos/pos_receipt_formatter.dart';
import 'package:qayd/application/pos/print_pos_invoice_receipt_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_details.dart';
import 'package:qayd/domain/entities/pos_receipt_print_job.dart';
import 'package:qayd/domain/services/pos_receipt_printer.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

void main() {
  const currency = CurrencyCode(
    code: 'YER',
    nameAr: 'ريال يمني',
    symbol: 'ر.ي',
    fractionalDigits: 2,
  );

  PosInvoiceDetails buildDetails({bool posted = true, bool returned = false}) {
    const invoiceId = 'invoice-safe-print';
    final line = PosInvoiceLine.create(
      id: 'line-safe-print',
      invoiceId: invoiceId,
      productId: 'product-safe-print',
      productNameSnapshot: 'صنف اختبار',
      quantity: PosQuantity.fromScaled(1, scale: 0),
      unitPrice: Money.fromMinorUnits(500, currency),
      unitCost: Money.fromMinorUnits(250, currency),
      discount: Money.zero(currency),
      tax: Money.zero(currency),
      createdAt: DateTime.utc(2026, 4, 5, 10),
    );
    var invoice = PosInvoice.draft(
      id: invoiceId,
      invoiceNumber: 'S-SAFE-1',
      type: PosInvoiceType.sale,
      warehouseId: 'warehouse-1',
      currency: currency,
      lines: [line],
      idempotencyKey: 'sale:$invoiceId',
      invoiceDate: DateTime.utc(2026, 4, 5, 10),
      now: DateTime.utc(2026, 4, 5, 10),
      counterpartyAccountId: AccountId('customer-snapshot'),
    );
    if (posted) invoice = invoice.post(DateTime.utc(2026, 4, 5, 10, 1));
    if (returned) {
      invoice = PosInvoice.fromPersistence(
        id: invoice.id,
        invoiceNumber: invoice.invoiceNumber,
        type: invoice.type,
        status: PosDocumentStatus.partiallyReturned,
        counterpartyAccountId: invoice.counterpartyAccountId,
        warehouseId: invoice.warehouseId,
        sourceInvoiceId: invoice.sourceInvoiceId,
        currency: invoice.currency,
        lines: invoice.lines,
        subtotal: invoice.subtotal,
        discount: invoice.discount,
        cartDiscount: invoice.cartDiscount,
        cartDiscountRule: invoice.cartDiscountRule,
        tax: invoice.tax,
        total: invoice.total,
        paid: invoice.paid,
        due: invoice.due,
        idempotencyKey: invoice.idempotencyKey,
        invoiceDate: invoice.invoiceDate,
        createdAt: invoice.createdAt,
        updatedAt: invoice.updatedAt,
        postedAt: invoice.postedAt,
        signature: invoice.signature,
      );
    }
    return PosInvoiceDetails(invoice: invoice, payments: const []);
  }

  test('rejects a draft before the printer is called', () async {
    final printer = _FakePosReceiptPrinter();
    final useCase = _useCase(printer);

    final result = await useCase(
      details: buildDetails(posted: false),
      paperWidth: PosReceiptPaperWidth.mm58,
    );

    expect(result.isFailure, isTrue);
    expect(
      result.failureOrNull,
      isA<ValidationFailure>().having(
        (failure) => failure.code,
        'code',
        'pos_receipt_invoice_not_printable',
      ),
    );
    expect(printer.jobs, isEmpty);
  });

  test(
    'rejects a returned invoice instead of printing the original as current',
    () async {
      final printer = _FakePosReceiptPrinter();
      final result = await _useCase(printer)(
        details: buildDetails(returned: true),
        paperWidth: PosReceiptPaperWidth.mm58,
        isReprint: true,
      );

      expect(result.isFailure, isTrue);
      expect(printer.jobs, isEmpty);
    },
  );

  test(
    'prints only a formatted snapshot and labels a history copy as reprint',
    () async {
      final printer = _FakePosReceiptPrinter();
      final details = buildDetails();
      final useCase = _useCase(printer);

      final result = await useCase(
        details: details,
        paperWidth: PosReceiptPaperWidth.mm58,
        isReprint: true,
      );

      expect(result, isA<Success<void>>());
      expect(printer.jobs, hasLength(1));
      expect(printer.jobs.single.isReprint, isTrue);
      expect(
        printer.jobs.single.lines.map((line) => line.text).join('\n'),
        contains('S-SAFE-1'),
      );
      expect(
        printer.jobs.single.lines.map((line) => line.text).join('\n'),
        contains('customer-snapshot'),
      );
    },
  );

  test(
    'retry repeats the print request with the same snapshot, not a sale',
    () async {
      final printer = _FakePosReceiptPrinter(
        failures: [
          const PosReceiptPrinterException(
            PosReceiptPrinterFailureReason.disconnected,
          ),
        ],
      );
      final useCase = _useCase(printer);
      final details = buildDetails();

      final first = await useCase(
        details: details,
        paperWidth: PosReceiptPaperWidth.mm80,
        isReprint: true,
      );
      final second = await useCase(
        details: details,
        paperWidth: PosReceiptPaperWidth.mm80,
        isReprint: true,
      );

      expect(first.isFailure, isTrue);
      expect(second.isSuccess, isTrue);
      expect(printer.jobs, hasLength(2));
      expect(
        printer.jobs[0].lines.map((line) => line.text).toList(),
        printer.jobs[1].lines.map((line) => line.text).toList(),
      );
      expect(details.invoice.status, PosDocumentStatus.posted);
      expect(details.invoice.paid.minorUnits, 0);
      expect(details.invoice.due.minorUnits, details.invoice.total.minorUnits);
    },
  );

  for (final reason in PosReceiptPrinterFailureReason.values) {
    test('maps ${reason.name} to a safe retryable result', () async {
      final printer = _FakePosReceiptPrinter(
        failures: [PosReceiptPrinterException(reason)],
      );
      final result = await _useCase(printer)(
        details: buildDetails(),
        paperWidth: PosReceiptPaperWidth.mm58,
        isReprint: true,
      );

      expect(result.isFailure, isTrue);
      expect(
        result.failureOrNull,
        isA<ValidationFailure>().having(
          (failure) => failure.code,
          'code',
          'pos_receipt_printer_${reason.name}',
        ),
      );
      expect(printer.jobs, hasLength(1));
    });
  }

  test('does not surface unexpected platform exception details', () async {
    final printer = _FakePosReceiptPrinter(
      unexpectedError: StateError('amount=999'),
    );
    final result = await _useCase(printer)(
      details: buildDetails(),
      paperWidth: PosReceiptPaperWidth.mm58,
    );

    expect(result.isFailure, isTrue);
    expect(result.failureOrNull?.messageAr, isNot(contains('999')));
  });
}

PrintPosInvoiceReceiptUseCase _useCase(_FakePosReceiptPrinter printer) =>
    PrintPosInvoiceReceiptUseCase(
      printer: printer,
      formatter: const PosReceiptFormatter(),
    );

final class _FakePosReceiptPrinter implements PosReceiptPrinter {
  _FakePosReceiptPrinter({this.failures = const [], this.unexpectedError});

  final List<Object> failures;
  final Object? unexpectedError;
  final List<PosReceiptPrintJob> jobs = [];
  var _failureIndex = 0;

  @override
  Future<void> printReceipt(PosReceiptPrintJob job) async {
    jobs.add(job);
    if (_failureIndex < failures.length) {
      throw failures[_failureIndex++];
    }
    final error = unexpectedError;
    if (error != null) throw error;
  }
}
