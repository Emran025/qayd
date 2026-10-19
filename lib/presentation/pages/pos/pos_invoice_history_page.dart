import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/application/pos/build_pos_invoice_pdf_use_case.dart';
import 'package:qayd/application/pos/get_pos_invoice_details_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_details.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pos/pos_money_display.dart';
import 'package:qayd/presentation/pos/pos_invoice_history_cubit.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/utils/share_pdf_bytes.dart';

class PosInvoiceHistoryPage extends StatelessWidget {
  const PosInvoiceHistoryPage({
    super.key,
    required this.cubit,
    required this.detailsUseCase,
    required this.pdfUseCase,
  });

  final PosInvoiceHistoryCubit cubit;
  final GetPosInvoiceDetailsUseCase detailsUseCase;
  final BuildPosInvoicePdfUseCase pdfUseCase;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      child: _HistoryView(
        detailsUseCase: detailsUseCase,
        pdfUseCase: pdfUseCase,
      ),
    );
  }
}

class _HistoryView extends StatefulWidget {
  const _HistoryView({required this.detailsUseCase, required this.pdfUseCase});

  final GetPosInvoiceDetailsUseCase detailsUseCase;
  final BuildPosInvoicePdfUseCase pdfUseCase;

  @override
  State<_HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<_HistoryView> {
  @override
  void initState() {
    super.initState();
    context.read<PosInvoiceHistoryCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: QaydAppBar(title: AppStrings.posInvoiceHistoryTitle),
      body: BlocBuilder<PosInvoiceHistoryCubit, PosInvoiceHistoryState>(
        builder: (context, state) {
          if (state.status == PosInvoiceHistoryStatus.loading ||
              state.status == PosInvoiceHistoryStatus.initial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == PosInvoiceHistoryStatus.failure) {
            return Center(
                child: Text(state.failure?.messageAr ??
                    AppStrings.posWorkspaceLoadFailed));
          }
          if (state.invoices.isEmpty) {
            return Center(child: Text(AppStrings.posInvoiceHistoryEmpty));
          }
          return RefreshIndicator(
            onRefresh: context.read<PosInvoiceHistoryCubit>().load,
            child: ListView.separated(
              padding: const EdgeInsets.all(SpacingTokens.lg),
              itemCount: state.invoices.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: SpacingTokens.sm),
              itemBuilder: (_, index) {
                final invoice = state.invoices[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(invoice.invoiceNumber),
                    subtitle: Text(
                        '${invoice.status.name} · ${formatPosMoney(invoice.total)}'),
                    trailing: Text(
                        '${AppStrings.posCheckoutAdvance}: ${formatPosMoney(invoice.paid)}'),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => PosInvoiceDetailPage(
                          invoiceId: invoice.id,
                          detailsUseCase: widget.detailsUseCase,
                          pdfUseCase: widget.pdfUseCase,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class PosInvoiceDetailPage extends StatelessWidget {
  const PosInvoiceDetailPage({
    super.key,
    required this.invoiceId,
    required this.detailsUseCase,
    required this.pdfUseCase,
  });

  final String invoiceId;
  final GetPosInvoiceDetailsUseCase detailsUseCase;
  final BuildPosInvoicePdfUseCase pdfUseCase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: QaydAppBar(title: AppStrings.posInvoiceDetailTitle),
      body: FutureBuilder(
        future: detailsUseCase(invoiceId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snapshot.data!;
          final details = result.valueOrNull;
          if (details == null) {
            return Center(child: Text(AppStrings.posInvoiceNotFound));
          }
          return _InvoiceDetailsBody(details: details, pdfUseCase: pdfUseCase);
        },
      ),
    );
  }
}

class _InvoiceDetailsBody extends StatelessWidget {
  const _InvoiceDetailsBody({required this.details, required this.pdfUseCase});

  final PosInvoiceDetails details;
  final BuildPosInvoicePdfUseCase pdfUseCase;

  @override
  Widget build(BuildContext context) {
    final invoice = details.invoice;
    return ListView(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      children: [
        Card(
          child: ListTile(
            title: Text(invoice.invoiceNumber),
            subtitle: Text(
                '${invoice.status.name} · ${invoice.invoiceDate.toLocal().toString().split('.').first}'),
            trailing: Icon(invoice.signature == null
                ? Icons.warning_amber_outlined
                : Icons.verified_outlined),
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        ...invoice.lines.map(
          (line) => Card(
            child: ListTile(
              title: Text(line.productNameSnapshot),
              subtitle: Text(
                  '${line.quantity.toExactString()} × ${formatPosMoney(line.unitPrice)}'),
              trailing: Text(
                  formatPosMoney(line.lineTotal)),
            ),
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        Card(
          child: Column(
            children: [
              ListTile(
                  title: Text(AppStrings.posCheckoutSubtotal),
                  trailing: Text(formatPosMoney(invoice.subtotal))),
              ListTile(
                  title: Text(AppStrings.posCheckoutAdvance),
                  trailing: Text(formatPosMoney(invoice.paid))),
              ListTile(
                  title: Text(AppStrings.posInvoiceDueLabel),
                  trailing: Text(formatPosMoney(invoice.due))),
            ],
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        FilledButton.icon(
          onPressed: () => _sharePdf(context, invoice),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(AppStrings.posInvoiceExportPdf),
        ),
      ],
    );
  }

  Future<void> _sharePdf(BuildContext context, PosInvoice invoice) async {
    final result = await pdfUseCase.forInvoice(invoice);
    if (!context.mounted) return;
    final bytes = result.valueOrNull;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result.failureOrNull?.messageAr ??
                AppStrings.posInvoicePdfFailed)),
      );
      return;
    }
    await sharePdfBytes(bytes, '${invoice.invoiceNumber}.pdf');
  }
}
