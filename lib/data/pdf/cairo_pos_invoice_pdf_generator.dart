import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/pdf/cairo_pdf_fonts.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_sales_report.dart';
import 'package:qayd/domain/services/pos_invoice_pdf_generator.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Branded, RTL-capable POS invoice/report renderer.
final class CairoPosInvoicePdfGenerator implements PosInvoicePdfGenerator {
  const CairoPosInvoicePdfGenerator();

  static const _navy = PdfColor.fromInt(0xFF0F2741);
  static const _muted = PdfColor.fromInt(0xFF64748B);
  static const _border = PdfColor.fromInt(0xFFCBD5E1);
  static const _green = PdfColor.fromInt(0xFF047857);

  @override
  Future<Result<Uint8List>> buildInvoicePdf(PosInvoice invoice) async {
    try {
      final fontData = await rootBundle.load(CairoPdfFonts.asset);
      final font = pw.Font.ttf(fontData.buffer.asByteData());
      final doc =
          pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => _invoiceContent(invoice, font),
        ),
      );
      return Success(await doc.save());
    } catch (error) {
      return FailureResult(
        UnexpectedFailure(
            messageAr: '${AppStrings.theDrawingObjectCould}: $error'),
      );
    }
  }

  @override
  Future<Result<Uint8List>> buildSalesReportPdf(PosSalesReport report) async {
    try {
      final fontData = await rootBundle.load(CairoPdfFonts.asset);
      final font = pw.Font.ttf(fontData.buffer.asByteData());
      final doc =
          pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(28),
          header: (_) => _brandHeader(font, title: 'تقرير مبيعات POS'),
          footer: (context) =>
              _footer(font, context.pageNumber, context.pagesCount),
          build: (_) => _reportContent(report, font),
        ),
      );
      return Success(await doc.save());
    } catch (error) {
      return FailureResult(
        UnexpectedFailure(
            messageAr: '${AppStrings.theDrawingObjectCould}: $error'),
      );
    }
  }

  List<pw.Widget> _invoiceContent(PosInvoice invoice, pw.Font font) {
    return [
      _brandHeader(font, title: _documentTitle(invoice)),
      pw.SizedBox(height: 16),
      _metaCard(invoice, font),
      if (invoice.due.minorUnits > 0) ...[
        pw.SizedBox(height: 10),
        _creditTermsCard(invoice, font),
      ],
      pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(
        headers: const [
          'المادة',
          'الكمية',
          'سعر الوحدة',
          'الخصم',
          'الضريبة',
          'الإجمالي'
        ],
        data: invoice.lines
            .map(
              (line) => [
                line.productNameSnapshot,
                line.quantity.toExactString(),
                _money(line.unitPrice),
                _money(line.discount),
                _money(line.tax),
                _money(line.lineTotal),
              ],
            )
            .toList(),
        headerStyle: pw.TextStyle(
            font: font, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: _navy),
        cellStyle: pw.TextStyle(font: font, fontSize: 9),
        cellAlignment: pw.Alignment.centerRight,
        border: pw.TableBorder.all(color: _border),
        cellPadding: const pw.EdgeInsets.all(7),
      ),
      pw.SizedBox(height: 16),
      _totalsCard(invoice, font),
      pw.SizedBox(height: 16),
      _signatureCard(invoice, font),
    ];
  }

  List<pw.Widget> _reportContent(PosSalesReport report, pw.Font font) {
    return [
      pw.Text(
        'الفترة: ${_date(report.from)} — ${_date(report.to)}',
        style: pw.TextStyle(font: font, color: _muted),
      ),
      pw.SizedBox(height: 14),
      pw.Row(
        children: [
          _summaryBox(font, 'عدد الفواتير', '${report.invoices.length}'),
          _summaryBox(font, 'الإجمالي', _money(report.grossTotal)),
          _summaryBox(font, 'المدفوع', _money(report.paidTotal)),
          _summaryBox(font, 'المتبقي', _money(report.dueTotal)),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.TableHelper.fromTextArray(
        headers: const [
          'رقم الفاتورة',
          'التاريخ',
          'الحالة',
          'الإجمالي',
          'المدفوع',
          'المتبقي'
        ],
        data: report.invoices
            .map(
              (invoice) => [
                invoice.invoiceNumber,
                _date(invoice.invoiceDate),
                invoice.status.name,
                _money(invoice.total),
                _money(invoice.paid),
                _money(invoice.due),
              ],
            )
            .toList(),
        headerStyle: pw.TextStyle(
            font: font, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: _navy),
        cellStyle: pw.TextStyle(font: font, fontSize: 9),
        border: pw.TableBorder.all(color: _border),
        cellPadding: const pw.EdgeInsets.all(7),
      ),
    ];
  }

  pw.Widget _brandHeader(pw.Font font, {required String title}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFE8EDF3),
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Qayd',
            style: pw.TextStyle(
                font: font,
                fontSize: 19,
                color: _navy,
                fontWeight: pw.FontWeight.bold),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      font: font,
                      fontSize: 14,
                      color: _navy,
                      fontWeight: pw.FontWeight.bold)),
              pw.Text('نظام نقطة البيع',
                  style: pw.TextStyle(font: font, fontSize: 9, color: _muted)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _metaCard(PosInvoice invoice, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _border),
          borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _labelValue(font, 'رقم الفاتورة', invoice.invoiceNumber),
          _labelValue(font, 'التاريخ', _date(invoice.invoiceDate)),
          _labelValue(font, 'العملة', invoice.currency.code),
          _labelValue(font, 'الحالة', invoice.status.name),
        ],
      ),
    );
  }

  pw.Widget _creditTermsCard(PosInvoice invoice, pw.Font font) {
    final dueDate = invoice.creditDueDate == null
        ? AppStrings.posCreditInvoiceUnspecified
        : _date(invoice.creditDueDate!);
    final terms = invoice.creditTerms ?? AppStrings.posCreditInvoiceUnspecified;
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFFFFBEB),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            '${AppStrings.posCreditInvoiceDueDate}: $dueDate',
            style: pw.TextStyle(font: font, fontSize: 10),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${AppStrings.posCreditInvoiceTerms}: $terms',
            style: pw.TextStyle(font: font, fontSize: 10),
          ),
        ],
      ),
    );
  }

  pw.Widget _totalsCard(PosInvoice invoice, pw.Font font) {
    return pw.Container(
      alignment: pw.Alignment.centerLeft,
      child: pw.Container(
        width: 250,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFF8FAFC),
            border: pw.Border.all(color: _border)),
        child: pw.Column(
          children: [
            _totalRow(font, 'الإجمالي الفرعي', _money(invoice.subtotal)),
            _totalRow(font, 'الخصم', _money(invoice.discount)),
            _totalRow(font, 'الضريبة', _money(invoice.tax)),
            pw.Divider(color: _border),
            _totalRow(font, 'الإجمالي الكلي', _money(invoice.total),
                strong: true),
            _totalRow(font, 'المبلغ المقدم', _money(invoice.paid)),
            _totalRow(font, 'المتبقي', _money(invoice.due), strong: true),
          ],
        ),
      ),
    );
  }

  pw.Widget _signatureCard(PosInvoice invoice, pw.Font font) {
    final signature = invoice.signature;
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
          border: pw.Border.all(color: signature == null ? _border : _green)),
      child: signature == null
          ? pw.Text('التوقيع الإلكتروني: غير موقعة',
              style: pw.TextStyle(font: font, color: _muted))
          : pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('التوقيع الإلكتروني: موثّق',
                    style: pw.TextStyle(
                        font: font,
                        color: _green,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('Hash: ${signature.payloadHashHex}',
                    style:
                        pw.TextStyle(font: font, fontSize: 7, color: _muted)),
                pw.Text('Signed at: ${_date(signature.signedAt)}',
                    style:
                        pw.TextStyle(font: font, fontSize: 8, color: _muted)),
              ],
            ),
    );
  }

  pw.Widget _footer(pw.Font font, int page, int pages) => pw.Align(
        alignment: pw.Alignment.center,
        child: pw.Text('Qayd · $page / $pages',
            style: pw.TextStyle(font: font, fontSize: 8, color: _muted)),
      );

  pw.Widget _summaryBox(pw.Font font, String label, String value) =>
      pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(left: 5),
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _border)),
          child: pw.Column(children: [
            pw.Text(label,
                style: pw.TextStyle(font: font, fontSize: 8, color: _muted)),
            pw.SizedBox(height: 4),
            pw.Text(value,
                style: pw.TextStyle(
                    font: font,
                    fontSize: 11,
                    color: _navy,
                    fontWeight: pw.FontWeight.bold)),
          ]),
        ),
      );

  pw.Widget _labelValue(pw.Font font, String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(label,
              style: pw.TextStyle(font: font, fontSize: 8, color: _muted)),
          pw.SizedBox(height: 3),
          pw.Text(value,
              style: pw.TextStyle(
                  font: font,
                  fontSize: 10,
                  color: _navy,
                  fontWeight: pw.FontWeight.bold)),
        ],
      );

  pw.Widget _totalRow(pw.Font font, String label, String value,
          {bool strong = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(value,
                style: pw.TextStyle(
                    font: font,
                    fontSize: strong ? 10 : 9,
                    fontWeight:
                        strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(label,
                style: pw.TextStyle(
                    font: font,
                    fontSize: strong ? 10 : 9,
                    fontWeight:
                        strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  String _documentTitle(PosInvoice invoice) => switch (invoice.type) {
        PosInvoiceType.sale => 'فاتورة مبيعات',
        PosInvoiceType.purchase => 'فاتورة مشتريات',
        PosInvoiceType.salesReturn => 'مرتجع مبيعات',
        PosInvoiceType.purchaseReturn => 'مرتجع مشتريات',
      };

  String _date(DateTime value) {
    final d = value.toUtc();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _money(Money value) {
    final digits = value.currency.fractionalDigits;
    final negative = value.minorUnits < 0;
    final absolute = value.minorUnits.abs();
    if (digits == 0) {
      return '${negative ? '-' : ''}$absolute ${value.currency.symbol}';
    }
    final divisor = _pow10(digits);
    final whole = absolute ~/ divisor;
    final fraction = (absolute % divisor).toString().padLeft(digits, '0');
    return '${negative ? '-' : ''}$whole.$fraction ${value.currency.symbol}';
  }

  int _pow10(int digits) {
    var value = 1;
    for (var i = 0; i < digits; i++) {
      value *= 10;
    }
    return value;
  }
}
