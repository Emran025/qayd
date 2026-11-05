import 'package:qayd/application/pos/pos_receipt_formatter.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_details.dart';
import 'package:qayd/domain/entities/pos_receipt_print_job.dart';
import 'package:qayd/domain/services/pos_receipt_printer.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Prints a receipt without any posting, payment, stock, discount or ledger
/// dependency. Reprinting the same snapshot is intentionally repeatable.
final class PrintPosInvoiceReceiptUseCase {
  const PrintPosInvoiceReceiptUseCase({
    required PosReceiptPrinter printer,
    required PosReceiptFormatter formatter,
  }) : _printer = printer,
       _formatter = formatter;

  final PosReceiptPrinter _printer;
  final PosReceiptFormatter _formatter;

  Future<Result<void>> call({
    required PosInvoiceDetails details,
    required PosReceiptPaperWidth paperWidth,
    bool isReprint = false,
  }) async {
    final invoice = details.invoice;
    const printableStatuses = {
      PosDocumentStatus.posted,
      PosDocumentStatus.partiallyPaid,
      PosDocumentStatus.paid,
    };
    if (invoice.type != PosInvoiceType.sale ||
        invoice.postedAt == null ||
        !printableStatuses.contains(invoice.status)) {
      return FailureResult<void>(
        ValidationFailure(
          messageAr: AppStrings.posReceiptPrintRequiresPostedInvoice,
          code: 'pos_receipt_invoice_not_printable',
        ),
      );
    }

    final job = _formatter.format(
      details: details,
      paperWidth: paperWidth,
      isReprint: isReprint,
    );
    try {
      await _printer.printReceipt(job);
      return const Success<void>(null);
    } on PosReceiptPrinterException catch (error) {
      return FailureResult<void>(
        ValidationFailure(
          messageAr: _messageFor(error.reason),
          code: 'pos_receipt_printer_${error.reason.name}',
        ),
      );
    } catch (_) {
      // Do not surface exception text: a platform/plugin exception can include
      // device payloads or other data that should not enter diagnostics/UI.
      return FailureResult<void>(
        UnexpectedFailure(messageAr: AppStrings.posReceiptPrintUnknownFailure),
      );
    }
  }

  String _messageFor(PosReceiptPrinterFailureReason reason) => switch (reason) {
    PosReceiptPrinterFailureReason.unavailable =>
      AppStrings.posReceiptPrintUnavailable,
    PosReceiptPrinterFailureReason.unsupported =>
      AppStrings.posReceiptPrintUnsupported,
    PosReceiptPrinterFailureReason.permissionDenied =>
      AppStrings.posReceiptPrintPermissionDenied,
    PosReceiptPrinterFailureReason.connectionFailed =>
      AppStrings.posReceiptPrintConnectionFailed,
    PosReceiptPrinterFailureReason.timedOut =>
      AppStrings.posReceiptPrintTimedOut,
    PosReceiptPrinterFailureReason.disconnected =>
      AppStrings.posReceiptPrintDisconnected,
    PosReceiptPrinterFailureReason.outOfPaper =>
      AppStrings.posReceiptPrintOutOfPaper,
  };
}
