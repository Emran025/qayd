import 'dart:collection';

import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';

/// Immutable report payload prepared by Application before PDF rendering.
final class PosSalesReport {
  PosSalesReport({
    required this.from,
    required this.to,
    required this.currency,
    required List<PosInvoice> invoices,
    this.excludedInvoiceCount = 0,
  }) : invoices = UnmodifiableListView(invoices);

  final DateTime from;
  final DateTime to;
  final CurrencyCode currency;
  final List<PosInvoice> invoices;
  final int excludedInvoiceCount;

  Money get grossTotal => invoices.fold(
        Money.zero(currency),
        (sum, invoice) => sum + invoice.total,
      );

  Money get paidTotal => invoices.fold(
        Money.zero(currency),
        (sum, invoice) => sum + invoice.paid,
      );

  Money get dueTotal => invoices.fold(
        Money.zero(currency),
        (sum, invoice) => sum + invoice.due,
      );
}
