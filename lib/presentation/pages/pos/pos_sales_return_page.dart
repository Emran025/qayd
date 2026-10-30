import 'package:flutter/material.dart';
import 'package:qayd/application/pos/build_pos_sales_return_posting_use_case.dart';
import 'package:qayd/application/pos/complete_pos_sales_return_use_case.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/presentation/components/atomic/qayd_app_bar.dart';
import 'package:qayd/presentation/components/inputs/qayd_numeric_field.dart';
import 'package:qayd/presentation/components/inputs/qayd_text_field.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/pos/pos_money_display.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/widgets/qayd_scaffold.dart';

/// Review screen for a partial or full item return.
/// All accounting, stock, signing and source-state work stays in the use case.
final class PosSalesReturnPage extends StatefulWidget {
  const PosSalesReturnPage({
    super.key,
    required this.sourceInvoice,
    required this.completeReturn,
  });

  final PosInvoice sourceInvoice;
  final CompletePosSalesReturnUseCase completeReturn;

  @override
  State<PosSalesReturnPage> createState() => _PosSalesReturnPageState();
}

final class _PosSalesReturnPageState extends State<PosSalesReturnPage> {
  final IdGenerator _ids = UuidV4IdGenerator();
  final TextEditingController _reasonController = TextEditingController();
  final Map<String, TextEditingController> _quantityControllers = {};
  BuildPosSalesReturnPostingInput? _pendingInput;
  String? _failure;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    for (final line in widget.sourceInvoice.lines) {
      _quantityControllers[line.id] = TextEditingController(text: '0');
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isBusy) return;
    final requested = <BuildPosSalesReturnLineInput>[];
    try {
      for (final line in widget.sourceInvoice.lines) {
        final text = _quantityControllers[line.id]!.text.trim();
        final quantity = _parseQuantity(text, line.quantity.scale);
        if (quantity.scaledUnits > line.quantity.scaledUnits) {
          throw const FormatException('pos_sales_return_quantity_exceeds_source');
        }
        if (quantity.isPositive) {
          requested.add(
            BuildPosSalesReturnLineInput(
              sourceLineId: line.id,
              quantity: quantity,
            ),
          );
        }
      }
    } on FormatException {
      setState(() => _failure = AppStrings.posSalesReturnQuantityInvalid);
      return;
    }
    if (requested.isEmpty) {
      setState(() => _failure = AppStrings.posSalesReturnNothingSelected);
      return;
    }

    final input = _pendingInput ?? _newInput(requested);
    _pendingInput = input;
    setState(() {
      _isBusy = true;
      _failure = null;
    });
    final result = await widget.completeReturn(input);
    if (!mounted) return;
    setState(() => _isBusy = false);
    final returnedInvoice = result.valueOrNull;
    if (returnedInvoice == null) {
      setState(() {
        _failure = result.failureOrNull?.messageAr ??
            AppStrings.posSalesReturnFailed;
      });
      return;
    }
    Navigator.of(context).pop(returnedInvoice);
  }

  BuildPosSalesReturnPostingInput _newInput(
    List<BuildPosSalesReturnLineInput> lines,
  ) {
    final id = _ids.next();
    final now = DateTime.now().toUtc();
    final reason = _reasonController.text.trim();
    return BuildPosSalesReturnPostingInput(
      returnInvoiceId: id,
      returnInvoiceNumber: 'R-${id.substring(0, 8)}',
      sourceInvoiceId: widget.sourceInvoice.id,
      idempotencyKey: 'pos-sales-return:$id',
      lines: List.unmodifiable(lines),
      invoiceDate: now,
      createdAt: now,
      reason: reason.isEmpty ? null : reason,
    );
  }

  PosQuantity _parseQuantity(String text, int scale) {
    if (text.isEmpty) return PosQuantity.fromScaled(0, scale: scale);
    final parts = text.split('.');
    if (parts.length > 2 || (parts.length == 2 && parts[1].length > scale)) {
      throw const FormatException();
    }
    final integerText = parts.first.isEmpty ? '0' : parts.first;
    if (!RegExp(r'^\d+$').hasMatch(integerText) ||
        (parts.length == 2 && parts[1].isNotEmpty &&
            !RegExp(r'^\d+$').hasMatch(parts[1]))) {
      throw const FormatException();
    }
    final factor = _pow10(scale);
    final fractionText = parts.length == 1 ? '' : parts[1];
    final fraction = fractionText.isEmpty
        ? 0
        : int.parse(fractionText.padRight(scale, '0'));
    return PosQuantity.fromScaled(
      int.parse(integerText) * factor + fraction,
      scale: scale,
    );
  }

  int _pow10(int exponent) {
    var result = 1;
    for (var index = 0; index < exponent; index++) {
      result *= 10;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.sourceInvoice;
    final canReturn = invoice.status == PosDocumentStatus.paid ||
        invoice.status == PosDocumentStatus.partiallyReturned;
    return QaydScaffold(
      appBar: QaydAppBar(title: AppStrings.posSalesReturnTitle),
      body: !canReturn
          ? Center(child: Text(AppStrings.posSalesReturnUnavailable))
          : ListView(
              padding: const EdgeInsets.all(SpacingTokens.lg),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(invoice.invoiceNumber),
                    subtitle: Text(AppStrings.posSalesReturnDescription),
                    trailing: Text(formatPosMoney(invoice.total)),
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
                ...invoice.lines.map(
                  (line) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(SpacingTokens.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(line.productNameSnapshot,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: SpacingTokens.xs),
                          Text(
                            '${line.quantity.toExactString()} × ${formatPosMoney(line.unitPrice)} · ${formatPosMoney(line.lineTotal)}',
                          ),
                          const SizedBox(height: SpacingTokens.sm),
                          QaydNumericField(
                            controller: _quantityControllers[line.id],
                            label: AppStrings.posSalesReturnQuantity,
                            helperText: '${AppStrings.posSalesReturnMaximum}: ${line.quantity.toExactString()}',
                            isDecimal: line.quantity.scale > 0,
                            onChanged: (_) => setState(() {
                              _pendingInput = null;
                              _failure = null;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
                QaydTextField(
                  controller: _reasonController,
                  label: AppStrings.posSalesReturnReason,
                  onChanged: (_) => setState(() {
                    _pendingInput = null;
                    _failure = null;
                  }),
                ),
                if (_failure != null) ...[
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    _failure!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: SpacingTokens.lg),
                FilledButton.icon(
                  onPressed: _isBusy ? null : _submit,
                  icon: _isBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.assignment_return_outlined),
                  label: Text(AppStrings.posSalesReturnSubmit),
                ),
              ],
            ),
    );
  }
}
