import 'dart:io';

import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/accounts/dtos/account_statement_line_dto.dart';
import 'package:qayd/application/accounts/dtos/account_summary_dto.dart';
import 'package:qayd/application/vouchers/dtos/voucher_summary_dto.dart';
import 'package:qayd/data/export/qayd_excel_workbook.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/utils/excel_data_export.dart';

String _textAt(Sheet sheet, int column, int row) {
  final value = sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
      .value;
  if (value is TextCellValue) return value.value.text ?? '';
  return value?.toString() ?? '';
}

VoucherSummaryDto _voucher() => const VoucherSummaryDto(
  id: 'voucher-123456789',
  typeCode: 'payment',
  stateCode: 'confirmed',
  dateIso: '2026-05-12T00:00:00.000',
  createdAtIso: '2026-05-12T00:00:00.000',
  amountMinorUnits: 12550,
  currencyCode: 'YER',
  currencyNameAr: 'ريال يمني',
  currencySymbol: 'ر.ي',
  currencyDigits: 2,
  counterpartyAccountId: 'party-1',
  counterpartyName: 'عميل اختبار',
  affectedAccountId: 'cash-1',
  affectedName: 'صندوق تجريبي',
  senderStatusCode: 'accepted',
  receiverStatusCode: 'accepted',
  description: 'دفعة اختبار',
);

AccountSummaryDto _account() => const AccountSummaryDto(
  id: 'account-101',
  name: 'صندوق الاختبار',
  natureCode: 'debit',
  isActive: true,
  isRoot: true,
  balancesMinorUnits: {'YER': 12550},
);

AccountStatementLineDto _statementLine() => const AccountStatementLineDto(
  dateIso: '2026-05-12T00:00:00.000',
  description: 'كشف حركة اختبار',
  debitMinorUnits: 12550,
  creditMinorUnits: 0,
  balanceMinorUnits: 12550,
  voucherId: 'voucher-statement-1',
  currencyCode: 'YER',
  currencySymbol: 'ر.ي',
  currencyDigits: 2,
);

void main() {
  group('excel_plus reads and writes Qayd XLSX files', () {
    test(
      'reads a workbook produced by the previous excel 4.0.6 dependency',
      () {
        final legacy = Excel.decodeBytes(
          File('test/fixtures/legacy_excel_workbook.xlsx').readAsBytesSync(),
        );
        expect(legacy.sheets.keys, contains('Legacy Ledger'));
        final sheet = legacy['Legacy Ledger'];
        expect(_textAt(sheet, 0, 0), 'Legacy XLSX export');
        expect(_textAt(sheet, 0, 1), 'فاتورة قديمة');
        expect(
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
              .value,
          const DoubleCellValue(125.5),
        );
      },
    );

    test(
      'round-trips the low-level voucher, account, statement and combined workbooks',
      () {
        final vouchers = Excel.decodeBytes(
          QaydExcelWorkbook.buildVouchers(
            headers: const ['Date', 'Amount'],
            rows: const [
              <Object?>['2026-05-12', '125.50'],
            ],
          ),
        );
        expect(vouchers.sheets.keys, contains(AppStrings.bonds));
        expect(_textAt(vouchers[AppStrings.bonds], 1, 1), '125.50');

        final accounts = Excel.decodeBytes(
          QaydExcelWorkbook.buildAccounts(
            headers: const ['Account', 'Balance'],
            rows: const [
              <Object?>['Cash', '125.50'],
            ],
          ),
        );
        expect(accounts.sheets.keys, contains(AppStrings.theAccounts));
        expect(_textAt(accounts[AppStrings.theAccounts], 0, 1), 'Cash');

        final statement = Excel.decodeBytes(
          QaydExcelWorkbook.buildAccountStatement(
            accountName: 'Main Account',
            headers: const [
              'Date',
              'Voucher',
              'Description',
              'State',
              'Debit',
              'Credit',
            ],
            rows: const [
              <Object?>[
                '2026-05-12',
                'V-1',
                'Statement line',
                '—',
                '125.50',
                '',
              ],
            ],
            totalDebit: '125.50',
          ),
        );
        final statementSheet = statement['كشف_Main Account'];
        expect(_textAt(statementSheet, 2, 10), 'Statement line');

        final combined = Excel.decodeBytes(
          QaydExcelWorkbook.buildCombined(
            voucherHeaders: const ['Voucher'],
            voucherRows: const [
              <Object?>['V-1'],
            ],
            accountHeaders: const ['Account'],
            accountRows: const [
              <Object?>['Cash'],
            ],
          ),
        );
        expect(
          combined.sheets.keys,
          containsAll([AppStrings.bonds, AppStrings.theAccounts]),
        );
        expect(_textAt(combined[AppStrings.bonds], 0, 1), 'V-1');
        expect(_textAt(combined[AppStrings.theAccounts], 0, 1), 'Cash');
      },
    );

    test('round-trips every public DTO export and isolate wrapper', () {
      final voucher = _voucher();
      final account = _account();

      final voucherWorkbook = Excel.decodeBytes(
        buildVouchersExcelBytes([voucher]),
      );
      expect(_textAt(voucherWorkbook[AppStrings.bonds], 7, 1), voucher.id);
      expect(
        _textAt(voucherWorkbook[AppStrings.bonds], 5, 1),
        voucher.counterpartyName,
      );

      final accountWorkbook = Excel.decodeBytes(
        buildAccountsExcelBytes([account]),
      );
      expect(
        _textAt(accountWorkbook[AppStrings.theAccounts], 0, 1),
        account.name,
      );
      expect(
        _textAt(accountWorkbook[AppStrings.theAccounts], 5, 1),
        account.id,
      );
      expect(
        _textAt(accountWorkbook[AppStrings.theAccounts], 2, 1),
        contains('YER'),
      );

      final statementWorkbook = Excel.decodeBytes(
        buildAccountStatementExcelBytes(
          accountName: 'Main Account',
          lines: [_statementLine()],
          issuerName: 'Qayd test',
        ),
      );
      expect(
        _textAt(statementWorkbook['كشف_Main Account'], 2, 10),
        'كشف حركة اختبار',
      );

      final combinedWorkbook = Excel.decodeBytes(
        buildCombinedExportExcelBytes(vouchers: [voucher], accounts: [account]),
      );
      expect(
        _textAt(combinedWorkbook[AppStrings.bonds], 5, 1),
        voucher.counterpartyName,
      );
      expect(
        _textAt(combinedWorkbook[AppStrings.theAccounts], 0, 1),
        account.name,
      );

      final wrapperWorkbook = Excel.decodeBytes(
        buildCombinedExportWrapper({
          'vouchers': [voucher],
          'accounts': [account],
        }),
      );
      expect(_textAt(wrapperWorkbook[AppStrings.bonds], 0, 1), isNotEmpty);
      expect(
        _textAt(wrapperWorkbook[AppStrings.theAccounts], 0, 1),
        account.name,
      );

      final voucherWrapper = Excel.decodeBytes(
        buildVouchersExportWrapper([voucher]),
      );
      expect(_textAt(voucherWrapper[AppStrings.bonds], 7, 1), voucher.id);

      final statementWrapper = Excel.decodeBytes(
        buildAccountStatementWrapper({
          'accountName': 'Main Account',
          'lines': [_statementLine()],
          'issuerName': 'Qayd test',
        }),
      );
      expect(
        _textAt(statementWrapper['كشف_Main Account'], 2, 10),
        'كشف حركة اختبار',
      );
    });
  });
}
