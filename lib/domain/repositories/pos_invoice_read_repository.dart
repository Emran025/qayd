import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_details.dart';

abstract interface class PosInvoiceReadRepository {
  Future<Result<PosInvoiceDetails?>> getById(String invoiceId);

  Future<Result<List<PosInvoiceDetails>>> getReturnsForSource(
    String sourceInvoiceId,
  );

  Future<Result<List<PosInvoice>>> list({
    DateTime? from,
    DateTime? to,
    PosInvoiceType? type,
    int? limit,
  });
}
