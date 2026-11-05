import 'package:qayd/domain/entities/pos_receipt_print_job.dart';

enum PosReceiptPrinterFailureReason {
  unavailable,
  unsupported,
  permissionDenied,
  connectionFailed,
  timedOut,
  disconnected,
  outOfPaper,
}

/// A platform adapter throws only a typed reason; it must not include invoice,
/// customer, or amount data in diagnostics.
final class PosReceiptPrinterException implements Exception {
  const PosReceiptPrinterException(this.reason);

  final PosReceiptPrinterFailureReason reason;
}

/// Platform lifecycle, discovery, permissions, connection and print transport
/// are owned by an Infrastructure implementation of this contract.
abstract interface class PosReceiptPrinter {
  Future<void> printReceipt(PosReceiptPrintJob job);
}
