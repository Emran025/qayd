import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/application/pos/build_pos_invoice_pdf_use_case.dart';
import 'package:qayd/application/pos/build_pos_sales_return_posting_use_case.dart';
import 'package:qayd/application/pos/complete_pos_sales_return_use_case.dart';
import 'package:qayd/application/pos/get_pos_invoice_details_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_details.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pages/pos/pos_sales_return_page.dart';
import 'package:qayd/presentation/pos/pos_invoice_history_cubit.dart';
import 'package:qayd/presentation/pos/pos_money_display.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/utils/share_pdf_bytes.dart';
import 'package:qayd/presentation/widgets/qayd_scaffold.dart';

class PosInvoiceHistoryPage extends StatelessWidget {
  const PosInvoiceHistoryPage({
    super.key,
    required this.cubit,
    required this.detailsUseCase,
    required this.pdfUseCase,
    required this.completeReturnUseCase,
  });

  final PosInvoiceHistoryCubit cubit;
  final GetPosInvoiceDetailsUseCase detailsUseCase;
  final BuildPosInvoicePdfUseCase pdfUseCase;
  final CompletePosSalesReturnUseCase completeReturnUseCase;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      child: _HistoryView(
        detailsUseCase: detailsUseCase,
        pdfUseCase: pdfUseCase,
        completeReturnUseCase: completeReturnUseCase,
      ),
    );
  }
}

class _HistoryView extends StatefulWidget {
  const _HistoryView({
    required this.detailsUseCase,
    required this.pdfUseCase,
    required this.completeReturnUseCase,
  });

  final GetPosInvoiceDetailsUseCase detailsUseCase;
  final BuildPosInvoicePdfUseCase pdfUseCase;
  final CompletePosSalesReturnUseCase completeReturnUseCase;

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
    return QaydScaffold(
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
                  AppStrings.posWorkspaceLoadFailed),
            );
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
                      '${invoice.status.name} · ${formatPosMoney(invoice.total)}',
                    ),
                    trailing: Text(
                      '${AppStrings.posCheckoutAdvance}: ${formatPosMoney(invoice.paid)}',
                    ),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => PosInvoiceDetailPage(
                          invoiceId: invoice.id,
                          detailsUseCase: widget.detailsUseCase,
                          pdfUseCase: widget.pdfUseCase,
                          completeReturnUseCase: widget.completeReturnUseCase,
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

class PosInvoiceDetailPage extends StatefulWidget {
  const PosInvoiceDetailPage({
    super.key,
    required this.invoiceId,
    required this.detailsUseCase,
    required this.pdfUseCase,
    required this.completeReturnUseCase,
  });

  final String invoiceId;
  final GetPosInvoiceDetailsUseCase detailsUseCase;
  final BuildPosInvoicePdfUseCase pdfUseCase;
  final CompletePosSalesReturnUseCase completeReturnUseCase;

  @override
  State<PosInvoiceDetailPage> createState() => _PosInvoiceDetailPageState();
}

class _PosInvoiceDetailPageState extends State<PosInvoiceDetailPage> {
  late Future<Result<PosInvoiceDetails?>> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  void _loadDetails() {
    _detailsFuture = widget.detailsUseCase(widget.invoiceId);
  }

  void _refreshDetails() => setState(_loadDetails);

  @override
  Widget build(BuildContext context) {
    return QaydScaffold(
      appBar: QaydAppBar(title: AppStrings.posInvoiceDetailTitle),
      body: FutureBuilder<Result<PosInvoiceDetails?>>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final details = snapshot.data!.valueOrNull;
          if (details == null) {
            return Center(child: Text(AppStrings.posInvoiceNotFound));
          }
          return _InvoiceDetailsBody(
            details: details,
            pdfUseCase: widget.pdfUseCase,
            completeReturnUseCase: widget.completeReturnUseCase,
            onInvoiceChanged: _refreshDetails,
          );
        },
      ),
    );
  }
}

class _InvoiceDetailsBody extends StatefulWidget {
  const _InvoiceDetailsBody({
    required this.details,
    required this.pdfUseCase,
    required this.completeReturnUseCase,
    required this.onInvoiceChanged,
  });

  final PosInvoiceDetails details;
  final BuildPosInvoicePdfUseCase pdfUseCase;
  final CompletePosSalesReturnUseCase completeReturnUseCase;
  final VoidCallback onInvoiceChanged;

  @override
  State<_InvoiceDetailsBody> createState() => _InvoiceDetailsBodyState();
}

class _InvoiceDetailsBodyState extends State<_InvoiceDetailsBody> {
  final IdGenerator _ids = UuidV4IdGenerator();
  BuildPosSalesReturnPostingInput? _pendingVoidInput;
  bool _isPostingVoid = false;

  Future<void> _openReturn(PosInvoice invoice) async {
    final returned = await Navigator.of(context).push<PosInvoice>(
      MaterialPageRoute(
        builder: (_) => PosSalesReturnPage(
          sourceInvoice: invoice,
          completeReturn: widget.completeReturnUseCase,
        ),
      ),
    );
    if (!mounted || returned == null) return;
    widget.onInvoiceChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.posSalesReturnSucceeded)),
    );
  }

  Future<void> _voidInvoice(PosInvoice invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.posSalesVoidAction),
        content: Text(AppStrings.posSalesVoidConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.actionConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isPostingVoid) return;

    final input = _pendingVoidInput ?? _newVoidInput(invoice);
    _pendingVoidInput = input;
    setState(() => _isPostingVoid = true);
    final result = await widget.completeReturnUseCase(input);
    if (!mounted) return;
    setState(() => _isPostingVoid = false);
    if (result.valueOrNull == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.failureOrNull?.messageAr ??
              AppStrings.posSalesVoidFailed),
        ),
      );
      return;
    }
    _pendingVoidInput = null;
    widget.onInvoiceChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.posSalesVoidSucceeded)),
    );
  }

  BuildPosSalesReturnPostingInput _newVoidInput(PosInvoice invoice) {
    final id = _ids.next();
    final now = DateTime.now().toUtc();
    return BuildPosSalesReturnPostingInput(
      returnInvoiceId: id,
      returnInvoiceNumber: 'R-${id.substring(0, 8)}',
      sourceInvoiceId: invoice.id,
      idempotencyKey: 'pos-sales-void:$id',
      lines: const [],
      invoiceDate: now,
      createdAt: now,
      voidSource: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.details.invoice;
    final isSale = invoice.type == PosInvoiceType.sale;
    final canReturn = isSale &&
        (invoice.status == PosDocumentStatus.paid ||
            invoice.status == PosDocumentStatus.partiallyReturned);
    final canVoid = isSale && invoice.status == PosDocumentStatus.paid;
    return ListView(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      children: [
        Card(
          child: ListTile(
            title: Text(invoice.invoiceNumber),
            subtitle: Text(
              '${invoice.status.name} · ${invoice.invoiceDate.toLocal().toString().split('.').first}',
            ),
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
                '${line.quantity.toExactString()} × ${formatPosMoney(line.unitPrice)}',
              ),
              trailing: Text(formatPosMoney(line.lineTotal)),
            ),
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text(AppStrings.posCheckoutSubtotal),
                trailing: Text(formatPosMoney(invoice.subtotal)),
              ),
              ListTile(
                title: Text(AppStrings.posCheckoutAdvance),
                trailing: Text(formatPosMoney(invoice.paid)),
              ),
              ListTile(
                title: Text(AppStrings.posInvoiceDueLabel),
                trailing: Text(formatPosMoney(invoice.due)),
              ),
            ],
          ),
        ),
        if (canReturn) ...[
          const SizedBox(height: SpacingTokens.md),
          OutlinedButton.icon(
            onPressed: _isPostingVoid ? null : () => _openReturn(invoice),
            icon: const Icon(Icons.assignment_return_outlined),
            label: Text(AppStrings.posSalesReturnAction),
          ),
        ],
        if (canVoid) ...[
          const SizedBox(height: SpacingTokens.sm),
          TextButton.icon(
            onPressed: _isPostingVoid ? null : () => _voidInvoice(invoice),
            icon: _isPostingVoid
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cancel_outlined),
            label: Text(AppStrings.posSalesVoidAction),
          ),
        ],
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
    final result = await widget.pdfUseCase.forInvoice(invoice);
    if (!context.mounted) return;
    final bytes = result.valueOrNull;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.failureOrNull?.messageAr ??
              AppStrings.posInvoicePdfFailed),
        ),
      );
      return;
    }
    await sharePdfBytes(bytes, '${invoice.invoiceNumber}.pdf');
  }
}
