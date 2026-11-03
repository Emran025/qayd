import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/reports/dtos/balance_sheet_output.dart';
import 'package:qayd/application/reports/dtos/trial_balance_line_dto.dart';
import 'package:qayd/application/reports/dtos/trial_balance_output.dart';
import 'package:qayd/data/excel/reports/excel_report_generator.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _textAt(Sheet sheet, int column, int row) {
  final value = sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
      .value;
  if (value is TextCellValue) return value.value.text ?? '';
  return value?.toString() ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ExcelReportGenerator generator;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'pdf_header_title': 'Qayd regression test',
      'pdf_header_subtitle': 'Excel export verification',
      'pdf_col_account': 'Ledger account',
      'pdf_col_currency': 'Money unit',
      'pdf_col_balance': 'Closing balance',
    });
    final preferences = await SharedPreferences.getInstance();
    generator = ExcelReportGenerator(sharedPreferences: preferences);
  });

  group('Excel financial report exports', () {
    test('exports a populated trial balance using excel_plus', () {
      final report = TrialBalanceOutput(
        lines: const [
          TrialBalanceLineDto(
            accountId: 'cash-1',
            accountCode: '101',
            accountName: 'Cash account regression',
            accountLevel: 0,
            isParent: false,
            currencyCode: 'YER',
            currencySymbol: 'ر.ي',
            currencyDigits: 2,
            openingDebitMinorUnits: 20000,
            openingCreditMinorUnits: 0,
            periodDebitMinorUnits: 5500,
            periodCreditMinorUnits: 0,
            closingDebitMinorUnits: 25500,
            closingCreditMinorUnits: 0,
          ),
        ],
        currencySections: const {
          'YER': TrialBalanceCurrencySectionDto(
            currencyCode: 'YER',
            currencySymbol: 'ر.ي',
            currencyDigits: 2,
            openingDebitMinorUnits: 20000,
            openingCreditMinorUnits: 0,
            periodDebitMinorUnits: 5500,
            periodCreditMinorUnits: 0,
            closingDebitMinorUnits: 25500,
            closingCreditMinorUnits: 0,
            isBalanced: true,
            imbalanceMinorUnits: 0,
          ),
        },
        isOverallBalanced: true,
        title: 'Trial balance',
        companyName: 'Qayd regression test',
        fromDate: DateTime(2026, 1, 1),
        toDate: DateTime(2026, 12, 31),
      );

      final workbook = Excel.decodeBytes(
        generator.generateTrialBalance(report),
      );
      expect(workbook.sheets.keys, contains(AppStrings.trialBalance));
      final sheet = workbook[AppStrings.trialBalance];
      expect(_textAt(sheet, 0, 0), contains('Qayd regression test'));
      expect(_textAt(sheet, 0, 1), 'Ledger account');
      expect(_textAt(sheet, 0, 2), contains('Cash account regression'));
      expect(
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 2))
            .value,
        const IntCellValue(200),
      );
    });

    test('exports a populated balance sheet using excel_plus', () {
      final report = BalanceSheetOutput(
        atDate: DateTime(2026, 12, 31),
        title: 'Balance sheet',
        companyName: 'Qayd regression test',
        lines: const [
          BalanceSheetLineDto(
            accountId: 'cash-asset-1',
            parentId: null,
            accountCode: '101',
            accountName: 'Cash reserve regression',
            level: 0,
            isParent: false,
            currencyCode: 'YER',
            currencySymbol: 'ر.ي',
            currencyDigits: 2,
            balanceMinorUnits: 12550,
            classification: AccountClassification.liquidAssets,
          ),
        ],
        currencySections: const {
          'YER': BalanceSheetCurrencySectionDto(
            currencyCode: 'YER',
            currencySymbol: 'ر.ي',
            currencyDigits: 2,
            totalAssetsMinorUnits: 12550,
            totalLiabilitiesMinorUnits: 0,
            totalEquityMinorUnits: 12550,
            isBalanced: true,
          ),
        },
      );

      final workbook = Excel.decodeBytes(
        generator.generateBalanceSheet(report),
      );
      expect(workbook.sheets.keys, contains(AppStrings.balanceSheet));
      final sheet = workbook[AppStrings.balanceSheet];
      expect(_textAt(sheet, 0, 0), contains('Qayd regression test'));
      expect(_textAt(sheet, 0, 1), 'Ledger account');
      expect(_textAt(sheet, 0, 3), contains('Cash reserve regression'));
      expect(
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 3))
            .value,
        const DoubleCellValue(125.5),
      );
    });
  });
}
