import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/printer/unavailable_pos_receipt_printer.dart';
import 'package:qayd/domain/entities/pos_receipt_print_job.dart';
import 'package:qayd/domain/services/pos_receipt_printer.dart';

void main() {
  test(
    'reports unavailable without attempting a hardware connection',
    () async {
      const printer = UnavailablePosReceiptPrinter();
      final job = PosReceiptPrintJob(
        paperWidth: PosReceiptPaperWidth.mm58,
        isReprint: true,
        lines: const [PosReceiptLine('إعادة طباعة')],
      );

      await expectLater(
        printer.printReceipt(job),
        throwsA(
          isA<PosReceiptPrinterException>().having(
            (error) => error.reason,
            'reason',
            PosReceiptPrinterFailureReason.unavailable,
          ),
        ),
      );
    },
  );
}
