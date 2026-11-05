import 'package:qayd/domain/entities/pos_receipt_print_job.dart';
import 'package:qayd/domain/services/pos_receipt_printer.dart';

/// Deliberate default until a printer, transport, OS and paper width pass a
/// physical-device test. PDF export remains the supported fallback.
final class UnavailablePosReceiptPrinter implements PosReceiptPrinter {
  const UnavailablePosReceiptPrinter();

  @override
  Future<void> printReceipt(PosReceiptPrintJob job) async {
    throw const PosReceiptPrinterException(
      PosReceiptPrinterFailureReason.unavailable,
    );
  }
}
