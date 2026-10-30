import 'package:flutter/material.dart';
import 'package:qayd/application/pos/build_pos_daily_sales_report_use_case.dart';
import 'package:qayd/application/pos/build_pos_invoice_pdf_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_sales_report.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/widgets/qayd_scaffold.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pos/pos_money_display.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/utils/share_pdf_bytes.dart';

class PosDailySalesReportPage extends StatelessWidget {
  const PosDailySalesReportPage({
    super.key,
    required this.reportUseCase,
    required this.pdfUseCase,
    required this.currency,
  });

  final BuildPosDailySalesReportUseCase reportUseCase;
  final BuildPosInvoicePdfUseCase pdfUseCase;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    final day = DateTime.now();
    return QaydScaffold(
      appBar: QaydAppBar(title: AppStrings.posDailySalesReportTitle),
      body: FutureBuilder(
        future: reportUseCase(day: day, currency: currency),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final report = snapshot.data!.valueOrNull;
          if (report == null) {
            return Center(
              child: Text(snapshot.data!.failureOrNull?.messageAr ??
                  AppStrings.posDailySalesReportFailed),
            );
          }
          return _ReportBody(report: report, pdfUseCase: pdfUseCase);
        },
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report, required this.pdfUseCase});

  final PosSalesReport report;
  final BuildPosInvoicePdfUseCase pdfUseCase;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      children: [
        Text(
          '${report.from.toLocal().toString().split(' ').first} · ${report.invoices.length} ${AppStrings.posDailySalesInvoiceCount}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (report.excludedInvoiceCount > 0) ...[
          const SizedBox(height: SpacingTokens.sm),
          Text(
            '${AppStrings.posDailySalesOtherCurrenciesExcluded}: '
            '${report.excludedInvoiceCount}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: SpacingTokens.md),
        _MetricCard(
            label: AppStrings.posDailySalesGross,
            value: formatPosMoney(report.grossTotal)),
        const SizedBox(height: SpacingTokens.sm),
        _MetricCard(
            label: AppStrings.posDailySalesPaid,
            value: formatPosMoney(report.paidTotal)),
        const SizedBox(height: SpacingTokens.sm),
        _MetricCard(
            label: AppStrings.posDailySalesDue,
            value: formatPosMoney(report.dueTotal)),
        const SizedBox(height: SpacingTokens.lg),
        FilledButton.icon(
          onPressed: () => _export(context),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(AppStrings.posInvoiceExportPdf),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context) async {
    final result = await pdfUseCase.forSalesReport(report);
    if (!context.mounted) return;
    final bytes = result.valueOrNull;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result.failureOrNull?.messageAr ??
                AppStrings.posDailySalesReportFailed)),
      );
      return;
    }
    await sharePdfBytes(bytes,
        'pos-sales-${report.from.toIso8601String().split('T').first}.pdf');
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text(label),
          trailing: Text(value, style: Theme.of(context).textTheme.titleLarge),
        ),
      );
}
