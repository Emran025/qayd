import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/settings/set_base_currency_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';

class MockCurrencyRepository extends Mock implements CurrencyRepository {}

void main() {
  late SetBaseCurrencyUseCase useCase;
  late MockCurrencyRepository mockRepo;

  setUp(() {
    mockRepo = MockCurrencyRepository();
    useCase = SetBaseCurrencyUseCase(mockRepo);
    when(() => mockRepo.getBaseCurrencyCode())
        .thenAnswer((_) async => const Success('USD'));
  });

  group('SetBaseCurrencyUseCase', () {
    test('Should complete successfully when input is valid', () async {
      when(() => mockRepo.setBaseCurrencyCode('SAR'))
          .thenAnswer((_) async => const Success(null));

      final result = await useCase('SAR');

      expect(result.isSuccess, isTrue);
      verify(() => mockRepo.setBaseCurrencyCode('SAR')).called(1);
    });

    test('Should return repository failure if operation fails', () async {
      final failure = DatabaseFailure(messageAr: 'DB Write Error');
      when(() => mockRepo.setBaseCurrencyCode('SAR'))
          .thenAnswer((_) async => FailureResult(failure));

      final result = await useCase('SAR');

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, equals(failure));
    });
  });
}
