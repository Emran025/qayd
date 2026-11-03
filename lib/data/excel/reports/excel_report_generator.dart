import 'dart:typed_data';
import 'package:excel_plus/excel_plus.dart';
import 'package:qayd/application/reports/dtos/trial_balance_line_dto.dart';
import 'package:qayd/application/reports/dtos/trial_balance_output.dart';
import 'package:qayd/application/reports/dtos/balance_sheet_output.dart';
import 'package:qayd/di/injection_container.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/core/utils/currency_util.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/utils/qayd_header_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Professional Excel generator for financial reports.
///
/// Produces branded workbooks with proper headers, styled data rows,
/// and per-currency totals.
final class ExcelReportGenerator {
  const ExcelReportGenerator({SharedPreferences? sharedPreferences})
    : _sharedPreferences = sharedPreferences;

  final SharedPreferences? _sharedPreferences;

  SharedPreferences get _prefs =>
      _sharedPreferences ?? InjectionContainer.sharedPreferences;

  // ═══════════════════════════════════════════════════════════════════════
  // ── TRIAL BALANCE ──────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════

  Uint8List generateTrialBalance(TrialBalanceOutput report) {
    final excel = Excel.createExcel();
    final Sheet sheet = excel[AppStrings.trialBalance];
    excel.delete('Sheet1');

    final branding = QaydHeaderConfig.resolve(_prefs);

    // ── Styles ──────────────────────────────────────────────────────────
    final titleStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#0F2741'),
      fontColorHex: ExcelColor.fromHexString('#C9A227'),
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final headerStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#8FAADC'),
      fontColorHex: ExcelColor.fromHexString('#0F2741'),
      bold: true,
      fontSize: 10,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final parentStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#F1F5F9'),
      bold: true,
      verticalAlign: VerticalAlign.Center,
    );

    final dataStyle = CellStyle(verticalAlign: VerticalAlign.Center);

    final totalStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#0F2741'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    // ── Title row ───────────────────────────────────────────────────────
    sheet.appendRow([
      TextCellValue('${branding.title} — ${branding.subtitle}'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
    ]);
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('H1'));
    for (var i = 0; i < 8; i++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
              .cellStyle =
          titleStyle;
    }

    // ── Column headers ──────────────────────────────────────────────────
    sheet.appendRow([
      TextCellValue(
        _prefs.getString('pdf_col_account') ?? AppStrings.theAccount,
      ),
      TextCellValue(
        _prefs.getString('pdf_col_currency') ?? AppStrings.currency,
      ),
      TextCellValue(AppStrings.myEditorialIsIndebted),
      TextCellValue(AppStrings.creditOpening),
      TextCellValue(AppStrings.madianMovement),
      TextCellValue(AppStrings.creditMovement),
      TextCellValue(AppStrings.myConclusionIsIndebted),
      TextCellValue(AppStrings.creditClosing),
    ]);
    for (var i = 0; i < 8; i++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1))
              .cellStyle =
          headerStyle;
    }

    // ── Group Data ──────────────────────────────────────────────────────
    final groups = <String, List<TrialBalanceLineDto>>{};
    for (final line in report.lines) {
      if (!groups.containsKey(line.accountId)) {
        groups[line.accountId] = [];
      }
      groups[line.accountId]!.add(line);
    }

    // ── Data rows ───────────────────────────────────────────────────────
    for (final group in groups.values) {
      if (group.isEmpty) continue;
      final startRow = sheet.maxRows;
      final first = group.first;
      final isParent = first.isParent;
      final accountRepresentation =
          '${'  ' * first.accountLevel}[${first.accountCode}] ${first.accountName}';

      for (var i = 0; i < group.length; i++) {
        final line = group[i];
        final divisor = _divisor(line.currencyDigits);
        sheet.appendRow([
          TextCellValue(i == 0 ? accountRepresentation : ''),
          TextCellValue(
            CurrencyUtil.getLocalizedName(
              line.currencyCode,
            ).replaceAll('﷼', AppStrings.sar),
          ),
          DoubleCellValue(line.openingDebitMinorUnits / divisor),
          DoubleCellValue(line.openingCreditMinorUnits / divisor),
          DoubleCellValue(line.periodDebitMinorUnits / divisor),
          DoubleCellValue(line.periodCreditMinorUnits / divisor),
          DoubleCellValue(line.closingDebitMinorUnits / divisor),
          DoubleCellValue(line.closingCreditMinorUnits / divisor),
        ]);

        for (var col = 0; col < 8; col++) {
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: col,
              rowIndex: startRow + i,
            ),
          );
          cell.cellStyle = isParent ? parentStyle : dataStyle;
        }
      }

      final endRow = sheet.maxRows - 1;
      if (endRow > startRow) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow),
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: endRow),
        );
      }
    }

    // ── Per-currency totals ─────────────────────────────────────────────
    sheet.appendRow([TextCellValue('')]);
    for (final section in report.currencySections.values) {
      final totalRowIndex = sheet.maxRows;
      final divisor = _divisor(section.currencyDigits);
      sheet.appendRow([
        TextCellValue(AppStrings.total),
        TextCellValue(
          CurrencyUtil.getLocalizedName(
            section.currencyCode,
          ).replaceAll('﷼', AppStrings.sar),
        ),
        DoubleCellValue(section.openingDebitMinorUnits / divisor),
        DoubleCellValue(section.openingCreditMinorUnits / divisor),
        DoubleCellValue(section.periodDebitMinorUnits / divisor),
        DoubleCellValue(section.periodCreditMinorUnits / divisor),
        DoubleCellValue(section.closingDebitMinorUnits / divisor),
        DoubleCellValue(section.closingCreditMinorUnits / divisor),
      ]);

      for (var i = 0; i < 8; i++) {
        sheet
                .cell(
                  CellIndex.indexByColumnRow(
                    columnIndex: i,
                    rowIndex: totalRowIndex,
                  ),
                )
                .cellStyle =
            totalStyle;
      }
    }

    return Uint8List.fromList(excel.encode()!);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ── BALANCE SHEET ──────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════

  Uint8List generateBalanceSheet(BalanceSheetOutput report) {
    final excel = Excel.createExcel();
    final Sheet sheet = excel[AppStrings.balanceSheet];
    excel.delete('Sheet1');

    final branding = QaydHeaderConfig.resolve(_prefs);

    // ── Styles ──────────────────────────────────────────────────────────
    final titleStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#0F2741'),
      fontColorHex: ExcelColor.fromHexString('#C9A227'),
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final headerStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#8FAADC'),
      fontColorHex: ExcelColor.fromHexString('#0F2741'),
      bold: true,
      fontSize: 10,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final sectionHeaderStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#F1F5F9'),
      bold: true,
      fontSize: 11,
      verticalAlign: VerticalAlign.Center,
    );

    final parentStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#F8FAFC'),
      bold: true,
      verticalAlign: VerticalAlign.Center,
    );

    final dataStyle = CellStyle(verticalAlign: VerticalAlign.Center);

    final totalStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#0F2741'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    // ── Title row ───────────────────────────────────────────────────────
    sheet.appendRow([
      TextCellValue('${branding.title} — ${branding.subtitle}'),
      TextCellValue(''),
      TextCellValue(''),
    ]);
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('C1'));
    for (var i = 0; i < 3; i++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
              .cellStyle =
          titleStyle;
    }

    // ── Column headers ──────────────────────────────────────────────────
    sheet.appendRow([
      TextCellValue(
        _prefs.getString('pdf_col_account') ?? AppStrings.theAccount,
      ),
      TextCellValue(
        _prefs.getString('pdf_col_currency') ?? AppStrings.currency,
      ),
      TextCellValue(_prefs.getString('pdf_col_balance') ?? AppStrings.balance),
    ]);
    for (var i = 0; i < 3; i++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1))
              .cellStyle =
          headerStyle;
    }

    // ── Group and output by section ─────────────────────────────────────
    _writeBalanceSheetSection(
      sheet,
      sectionHeaderStyle,
      parentStyle,
      dataStyle,
      AppStrings.assets1,
      report.lines.where((l) => _isAsset(l.classification)).toList(),
    );

    _writeBalanceSheetSection(
      sheet,
      sectionHeaderStyle,
      parentStyle,
      dataStyle,
      AppStrings.liabilities,
      report.lines.where((l) => _isLiability(l.classification)).toList(),
    );

    _writeBalanceSheetSection(
      sheet,
      sectionHeaderStyle,
      parentStyle,
      dataStyle,
      AppStrings.equity,
      report.lines.where((l) => _isEquity(l.classification)).toList(),
    );

    // ── Per-currency totals ─────────────────────────────────────────────
    sheet.appendRow([TextCellValue('')]);
    for (final section in report.currencySections.values) {
      final divisor = _divisor(section.currencyDigits);

      // Assets total
      final assetsRowIdx = sheet.maxRows;
      sheet.appendRow([
        TextCellValue(AppStrings.totalAssets),
        TextCellValue(
          CurrencyUtil.getLocalizedName(
            section.currencyCode,
          ).replaceAll('﷼', AppStrings.sar),
        ),
        DoubleCellValue(section.totalAssetsMinorUnits / divisor),
      ]);
      for (var i = 0; i < 3; i++) {
        sheet
                .cell(
                  CellIndex.indexByColumnRow(
                    columnIndex: i,
                    rowIndex: assetsRowIdx,
                  ),
                )
                .cellStyle =
            totalStyle;
      }

      // Liabilities total
      final liabRowIdx = sheet.maxRows;
      sheet.appendRow([
        TextCellValue(AppStrings.totalLiabilities),
        TextCellValue(
          CurrencyUtil.getLocalizedName(
            section.currencyCode,
          ).replaceAll('﷼', AppStrings.sar),
        ),
        DoubleCellValue(section.totalLiabilitiesMinorUnits / divisor),
      ]);
      for (var i = 0; i < 3; i++) {
        sheet
                .cell(
                  CellIndex.indexByColumnRow(
                    columnIndex: i,
                    rowIndex: liabRowIdx,
                  ),
                )
                .cellStyle =
            totalStyle;
      }

      // Equity total
      final eqRowIdx = sheet.maxRows;
      sheet.appendRow([
        TextCellValue(AppStrings.propertyRights),
        TextCellValue(
          CurrencyUtil.getLocalizedName(
            section.currencyCode,
          ).replaceAll('﷼', AppStrings.sar),
        ),
        DoubleCellValue(section.totalEquityMinorUnits / divisor),
      ]);
      for (var i = 0; i < 3; i++) {
        sheet
                .cell(
                  CellIndex.indexByColumnRow(
                    columnIndex: i,
                    rowIndex: eqRowIdx,
                  ),
                )
                .cellStyle =
            totalStyle;
      }
    }

    return Uint8List.fromList(excel.encode()!);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ── HELPERS ────────────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════

  void _writeBalanceSheetSection(
    Sheet sheet,
    CellStyle sectionStyle,
    CellStyle parentStyle,
    CellStyle dataStyle,
    String sectionTitle,
    List<BalanceSheetLineDto> lines,
  ) {
    if (lines.isEmpty) return;

    // Section header row
    final sectionRowIdx = sheet.maxRows;
    sheet.appendRow([
      TextCellValue(sectionTitle),
      TextCellValue(''),
      TextCellValue(''),
    ]);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: sectionRowIdx),
      CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: sectionRowIdx),
    );
    for (var i = 0; i < 3; i++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(
                  columnIndex: i,
                  rowIndex: sectionRowIdx,
                ),
              )
              .cellStyle =
          sectionStyle;
    }

    // Grouping
    final groups = <String, List<BalanceSheetLineDto>>{};
    for (final line in lines) {
      if (!groups.containsKey(line.accountId)) {
        groups[line.accountId] = [];
      }
      groups[line.accountId]!.add(line);
    }

    // Data rows
    for (final group in groups.values) {
      if (group.isEmpty) continue;
      final startRow = sheet.maxRows;
      final first = group.first;
      final isParent = first.isParent;
      final accountRepresentation =
          '${'  ' * first.level}[${first.accountCode}] ${first.accountName}';

      for (var i = 0; i < group.length; i++) {
        final line = group[i];
        final divisor = _divisor(line.currencyDigits);
        sheet.appendRow([
          TextCellValue(i == 0 ? accountRepresentation : ''),
          TextCellValue(
            CurrencyUtil.getLocalizedName(
              line.currencyCode,
            ).replaceAll('﷼', AppStrings.sar),
          ),
          DoubleCellValue(line.balanceMinorUnits / divisor),
        ]);

        for (var col = 0; col < 3; col++) {
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: col,
              rowIndex: startRow + i,
            ),
          );
          cell.cellStyle = isParent ? parentStyle : dataStyle;
        }
      }

      final endRow = sheet.maxRows - 1;
      if (endRow > startRow) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow),
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: endRow),
        );
      }
    }
  }

  /// Dynamically computes the divisor from fractional digits instead of
  /// hardcoding 100 (which only works for 2-digit currencies).
  double _divisor(int currencyDigits) {
    double d = 1;
    for (var i = 0; i < currencyDigits; i++) {
      d *= 10;
    }
    return d;
  }

  // String _getClassificationDisplayName(AccountClassification classification) {
  //   if (classification.customName != null) return classification.customName!;

  //   if (_isAsset(classification)) return AppStrings.assets;
  //   if (_isLiability(classification)) return AppStrings.adversaries;
  //   if (_isEquity(classification)) return AppStrings.propertyRights;

  //   return classification.standardKind?.name ?? AppStrings.other;
  // }

  static bool _isAsset(AccountClassification c) =>
      c == AccountClassification.liquidAssets ||
      c == AccountClassification.receivables ||
      c == AccountClassification.fixedProfitableAssets ||
      c == AccountClassification.fixedDepreciableAssets;

  static bool _isLiability(AccountClassification c) =>
      c == AccountClassification.payables ||
      c == AccountClassification.settlements ||
      c == AccountClassification.clearingRemittances;

  static bool _isEquity(AccountClassification c) =>
      c == AccountClassification.personalExpenses ||
      c == AccountClassification.personalRevenues ||
      c == AccountClassification.remittanceFees;
}
