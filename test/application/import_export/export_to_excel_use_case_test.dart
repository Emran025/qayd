import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/import_export/export_to_excel_use_case.dart';

void main() {
  group('ExportToExcelUseCase', () {
    test('constructor smoke check only; export behavior is unimplemented', () {
      const useCase = ExportToExcelUseCase();
      expect(useCase, isA<ExportToExcelUseCase>());

      // This does not test workbook generation. Production exports are covered
      // separately through their actual workbook builders.
    });
  });
}
