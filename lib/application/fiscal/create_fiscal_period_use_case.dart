import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/fiscal_period.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class CreateFiscalPeriodUseCase {
  CreateFiscalPeriodUseCase(
    this._repository,
    this._writeGuard,
    this._idGenerator,
  );

  final FiscalPeriodRepository _repository;
  final GovernanceWriteGuard _writeGuard;
  final IdGenerator _idGenerator;

  Future<Result<String>> call({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }
      final s = DateTime(startDate.year, startDate.month, startDate.day);
      final e = DateTime(endDate.year, endDate.month, endDate.day);
      if (e.isBefore(s)) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.fiscalPeriodInvalidRange,
            code: 'fiscal_period_range',
          ),
        );
      }
      final openR = await _repository.findOpenPeriod();
      if (openR.isFailure) {
        return FailureResult(openR.failureOrNull!);
      }
      if (openR.valueOrNull != null) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.fiscalPeriodOpenAlreadyExists,
            code: 'fiscal_period_open_exists',
          ),
        );
      }
      final allR = await _repository.listAllOrdered();
      if (allR.isFailure) {
        return FailureResult(allR.failureOrNull!);
      }
      final existing = allR.valueOrNull!;
      if (FiscalPeriodPolicy.rangeOverlapsExisting(existing, s, e)) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.fiscalPeriodOverlap,
            code: 'fiscal_period_overlap',
          ),
        );
      }
      final id = _idGenerator.next();
      final period = FiscalPeriod(
        id: id,
        name: name,
        startDate: s,
        endDate: e,
        status: FiscalPeriodStatus.open,
      );
      final ins = await _repository.insert(period);
      if (ins.isFailure) {
        return FailureResult(ins.failureOrNull!);
      }
      return Success(id);
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
