import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/fiscal_period.dart';
import 'package:qayd/domain/entities/ledger_account_snapshot.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/ledger_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/services/balance_calculator.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/value_objects/date_range.dart';
import 'package:qayd/domain/value_objects/voucher_state.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class CloseFiscalPeriodUseCase {
  CloseFiscalPeriodUseCase(
    this._fiscal,
    this._ledger,
    this._accounts,
    this._vouchers,
    this._balanceCalculator,
    this._writeGuard,
    this._idGenerator,
    this._signingService,
    this._getKeyPair,
    this._prefs,
  );

  final FiscalPeriodRepository _fiscal;
  final LedgerRepository _ledger;
  final AccountRepository _accounts;
  final VoucherRepository _vouchers;
  final BalanceCalculator _balanceCalculator;
  final GovernanceWriteGuard _writeGuard;
  final IdGenerator _idGenerator;
  final ReceiptSigningService _signingService;
  final Future<CryptoKeyPair?> Function() _getKeyPair;
  final SharedPreferences _prefs;

  Future<Result<void>> call(
    String periodId, {
    bool byAutomation = false,
  }) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }
      final allR = await _fiscal.listAllOrdered();
      if (allR.isFailure) {
        return FailureResult(allR.failureOrNull!);
      }
      final periods = allR.valueOrNull!;
      final ix = periods.indexWhere((p) => p.id == periodId);
      if (ix < 0) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.fiscalPeriodNotFound,
            code: 'fiscal_period_missing',
          ),
        );
      }
      final period = periods[ix];
      if (period.status != FiscalPeriodStatus.open) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.fiscalPeriodNotOpen,
            code: 'fiscal_period_not_open',
          ),
        );
      }
      final vouchersR = await _vouchers.getAll();
      if (vouchersR.isFailure) {
        return FailureResult(vouchersR.failureOrNull!);
      }
      final draftsInPeriod = vouchersR.valueOrNull!.where(
        (v) =>
            v.state == VoucherState.draft &&
            period.containsCalendarDate(v.date),
      );
      if (draftsInPeriod.isNotEmpty) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.fiscalPeriodCloseDraftsRemain,
            code: 'fiscal_period_drafts',
          ),
        );
      }

      final closureNow = DateTime.now().toUtc();
      final closureDateOnly =
          DateTime(closureNow.year, closureNow.month, closureNow.day);
      final endDay = closureDateOnly
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));

      final entriesR = await _ledger.getAllEntries(
        dateRange: DateRange(
          start: DateTime(1970),
          end: endDay,
        ),
      );
      if (entriesR.isFailure) {
        return FailureResult(entriesR.failureOrNull!);
      }
      final entriesUpTo = entriesR.valueOrNull!;

      final accountsR = await _accounts.getAll();
      if (accountsR.isFailure) {
        return FailureResult(accountsR.failureOrNull!);
      }
      final accounts = accountsR.valueOrNull!;

      final snapshots = <LedgerAccountSnapshot>[];
      final rowHashes = <String>[];

      for (final Account a in accounts) {
        final perCurrency = _balanceCalculator.signedBalanceMinorUnitsPerCurrency(
          entries: entriesUpTo,
          accountId: a.id,
          nature: a.nature,
        );
        for (final entry in perCurrency.entries) {
          if (entry.value == 0) continue;
          final rowCanon =
              '${period.id}|${a.id.value}|${entry.key.code}|${entry.value}';
          final rowHash = sha256.convert(utf8.encode(rowCanon)).toString();
          rowHashes.add(rowHash);
          snapshots.add(
            LedgerAccountSnapshot(
              id: _idGenerator.next(),
              periodId: period.id,
              accountId: a.id,
              balanceMinorUnits: entry.value,
              currencyCode: entry.key.code,
              rowHash: rowHash,
            ),
          );
        }
      }

      rowHashes.sort();
      final aggregateCanon = rowHashes.join('\n');
      final aggregateHash =
          sha256.convert(utf8.encode(aggregateCanon)).toString();
      final signPayload = 'qayd_snapshot_v1|${period.id}|$aggregateHash';

      final keyPair = await _getKeyPair();
      if (keyPair == null) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.identityNotSetup,
            code: 'identity_missing',
          ),
        );
      }
      final signature =
          _signingService.signCanonicalString(signPayload, keyPair);

      final closed = FiscalPeriod(
        id: period.id,
        name: period.name,
        startDate: period.startDate,
        endDate: closureDateOnly,
        status: FiscalPeriodStatus.closed,
        closedAt: closureNow,
        closingVoucherId: period.closingVoucherId,
        aggregateSnapshotHash: aggregateHash,
        aggregateSignatureHex: signature.signatureHex,
        signerPublicKeyHex: signature.signerPublicKeyHex,
      );

      final closeResult = await _fiscal.closePeriodWithSnapshots(
        closed: closed,
        snapshots: snapshots,
      );
      if (closeResult.isFailure) {
        return closeResult;
      }

      final policy = _prefs.getString('fiscal_closing_policy');
      if (!byAutomation && policy == 'auto_periodic') {
        final anchor = DateTime.now().toUtc();
        await _prefs.setString(
          'fiscal_auto_start_date',
          DateTime(anchor.year, anchor.month, anchor.day).toIso8601String(),
        );
      }
      return const Success(null);
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
