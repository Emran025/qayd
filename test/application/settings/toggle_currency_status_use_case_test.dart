import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/settings/toggle_currency_status_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';

class MockCurrencyRepository extends Mock implements CurrencyRepository {}

void main() {
  late ToggleCurrencyStatusUseCase useCase;
  late MockCurrencyRepository mockRepo;

  setUp(() {
    mockRepo = MockCurrencyRepository();
    useCase = ToggleCurrencyStatusUseCase(mockRepo);
    when(() => mockRepo.getByCode(any()))
        .thenAnswer((_) async => const Success(null));
  });

  group('ToggleCurrencyStatusUseCase', () {
    test('Should complete successfully when input is valid', () async {
      when(() => mockRepo.toggleActiveStatus('EUR', false))
          .thenAnswer((_) async => const Success(null));

      final result = await useCase('EUR', false);

      expect(result.isSuccess, isTrue);
      verify(() => mockRepo.toggleActiveStatus('EUR', false)).called(1);
    });

    test('Should return repository failure if operation fails', () async {
      final failure = DatabaseFailure(messageAr: 'DB Write Error');
      when(() => mockRepo.toggleActiveStatus('EUR', true))
          .thenAnswer((_) async => FailureResult(failure));

      final result = await useCase('EUR', true);

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, equals(failure));
    });
  });
}
