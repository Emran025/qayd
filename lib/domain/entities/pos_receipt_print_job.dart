import 'dart:collection';

/// Nominal receipt widths used by layout tests. Dot counts are common targets,
/// not a claim that any printer model has been verified.
enum PosReceiptPaperWidth {
  mm58(58, 384),
  mm80(80, 576);

  const PosReceiptPaperWidth(this.millimeters, this.nominalDots);

  final int millimeters;
  final int nominalDots;
}

enum PosReceiptTextAlignment { right, center, left }

final class PosReceiptLine {
  const PosReceiptLine(
    this.text, {
    this.alignment = PosReceiptTextAlignment.right,
    this.emphasized = false,
  });

  final String text;
  final PosReceiptTextAlignment alignment;
  final bool emphasized;
}

/// Printer-independent, immutable layout created only from a posted invoice
/// snapshot. A platform adapter must preserve RTL and rasterize Arabic when the
/// selected device cannot render the required glyphs natively.
final class PosReceiptPrintJob {
  PosReceiptPrintJob({
    required this.paperWidth,
    required this.isReprint,
    required List<PosReceiptLine> lines,
    this.rightToLeft = true,
    this.requiresRasterizedArabicFallback = true,
  }) : lines = UnmodifiableListView(List<PosReceiptLine>.of(lines));

  final PosReceiptPaperWidth paperWidth;
  final bool isReprint;
  final bool rightToLeft;
  final bool requiresRasterizedArabicFallback;
  final UnmodifiableListView<PosReceiptLine> lines;

  int get nominalWidthDots => paperWidth.nominalDots;
}
