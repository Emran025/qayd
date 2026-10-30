import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_sales_report.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/repositories/pos_invoice_read_repository.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';

final class BuildPosDailySalesReportUseCase {
  const BuildPosDailySalesReportUseCase(
      {required PosInvoiceReadRepository repository})
      : _repository = repository;

  final PosInvoiceReadRepository _repository;

  Future<Result<PosSalesReport>> call({
    required DateTime day,
    required CurrencyCode currency,
  }) async {
    final from = DateTime.utc(day.year, day.month, day.day);
    final to = from.add(const Duration(days: 1));
    final result = await _repository.list(
      from: from,
      to: to,
      type: PosInvoiceType.sale,
      limit: 1000,
    );
    if (result.isFailure) return FailureResult(result.failureOrNull!);
    final allInvoices = result.valueOrNull!;
    final invoices = allInvoices
        .where((invoice) => invoice.currency == currency)
        .toList(growable: false);
    return Success(PosSalesReport(
      from: from,
      to: to,
      currency: currency,
      invoices: invoices,
      excludedInvoiceCount: allInvoices.length - invoices.length,
    ));
  }
}
