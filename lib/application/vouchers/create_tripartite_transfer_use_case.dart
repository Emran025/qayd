import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/vouchers/dtos/create_tripartite_transfer_input.dart';
import 'package:qayd/application/vouchers/dtos/create_tripartite_transfer_output.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/tripartite_meta.dart';
import 'package:qayd/domain/entities/fee_calculation_type.dart';
import 'package:qayd/domain/entities/transaction_fee_type.dart';
import 'package:qayd/application/settings/get_active_transaction_fee_use_case.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/value_objects/tripartite_role.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/standard_account_classification_kind.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/domain/entities/audit_entry.dart';

/// Creates a tripartite intermediary transfer (A → Me → B).
///
/// Atomically persists two linked draft vouchers:
/// - **Receipt** (A → C): Cr Source, Dr MyAccount
/// - **Payment** (C → B): Dr Destination, Cr MyAccount — initially contingent
///
/// The payment voucher is locked (`isContingent = true`) until the receipt
/// voucher is confirmed, preventing premature fund disbursement.
class CreateTripartiteTransferUseCase {
  CreateTripartiteTransferUseCase(
    this._voucherRepository,
    this._currencyRepository,
    this._idGenerator,
    this._writeGuard,
    this._getActiveFee,
    this._accountRepository,
    this._entryGenerator, {
    SyncEventDispatcher? syncEventDispatcher,
    AuditLogService? auditLogService,
  })  : _syncEventDispatcher = syncEventDispatcher,
        _auditLogService = auditLogService;

  final VoucherRepository _voucherRepository;
  final CurrencyRepository _currencyRepository;
  final IdGenerator _idGenerator;
  final GovernanceWriteGuard _writeGuard;
  final GetActiveTransactionFeeUseCase _getActiveFee;
  final AccountRepository _accountRepository;
  final EntryGenerator _entryGenerator;
  final SyncEventDispatcher? _syncEventDispatcher;
  final AuditLogService? _auditLogService;

  Future<Result<CreateTripartiteTransferOutput>> call(
    CreateTripartiteTransferInput input,
  ) async {
    try {
      // 1. Governance gate
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }

      // 2. Validate currency
      final currencyRes = await _currencyRepository.getByCode(
        input.currencyCode,
      );
      if (currencyRes.isFailure || currencyRes.valueOrNull == null) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.theSelectedCurrencyIs,
            code: 'invalid_currency',
          ),
        );
      }
      final currency = currencyRes.valueOrNull!;

      // 3. Validate parties are distinct
      final sourceId = AccountId(input.sourceAccountId);
      final destId = AccountId(input.destinationAccountId);
      final affectedId = AccountId(input.affectedAccountId);

      if (sourceId == destId) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.theSourceAndDestination,
            code: 'tripartite_same_source_dest',
          ),
        );
      }
      if (sourceId == affectedId || destId == affectedId) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.theIntermediateAccountMust,
            code: 'tripartite_affected_conflict',
          ),
        );
      }

      // 4. Generate shared identifiers
      final transferGroupId = _idGenerator.next();
      final receiptId = VoucherId(_idGenerator.next());
      final paymentId = VoucherId(_idGenerator.next());
      final now = DateTime.now();
      final amount = Money.positiveAmount(input.amountMinorUnits, currency);

      // Handle fee calculation up-front
      final feeRes = await _getActiveFee(TransactionFeeType.tripartite);
      int? calculatedFeeMinor;
      if (feeRes.isSuccess && feeRes.valueOrNull != null) {
        final feeSetting = feeRes.valueOrNull!;
        if (feeSetting.calculationType == FeeCalculationType.fixed) {
          calculatedFeeMinor = feeSetting.value;
        } else {
          calculatedFeeMinor =
              (input.amountMinorUnits * (feeSetting.value / 10000)).round();
        }
      }

      // 5. Create Receipt Voucher (A → C)
      // counterparty = Source (A), affectedAccount = MyAccount (C)
      // type = receipt (money coming IN from A)
      final receiptVoucher = Voucher.draft(
        id: receiptId,
        type: VoucherType.receipt,
        date: input.date,
        amount: amount,
        currency: currency,
        counterpartyId: sourceId,
        affectedAccountId: affectedId,
        createdAt: now,
        description: input.description,
        notes: input.notes,
        tripartiteMeta: TripartiteMeta(
          transferGroupId: transferGroupId,
          role: TripartiteRole.intermediaryReceipt,
          linkedPartyId:
              destId, // The destination B is the linked party on the receipt
          isContingent: true, // locked until receipt is confirmed
          mediatorAccountId: affectedId,
          feeAmount: null, // Fee belongs to the fee voucher
        ),
      );
      // 6. Create Payment Voucher (C → B) — contingent
      // counterparty = Destination (B), affectedAccount = MyAccount (C)
      // type = payment (money going OUT to B)
      final paymentVoucher = Voucher.draft(
        id: paymentId,
        type: VoucherType.payment,
        date: input.date,
        amount: amount,
        currency: currency,
        counterpartyId: destId,
        affectedAccountId: affectedId,
        createdAt: now,
        description: input.description,
        notes: input.notes,
        tripartiteMeta: TripartiteMeta(
          transferGroupId: transferGroupId,
          role: TripartiteRole.intermediaryPayment,
          linkedPartyId: sourceId, // A is the linked party on the payment
          isContingent: true, // locked until receipt is confirmed
          mediatorAccountId: affectedId,
          feeAmount: calculatedFeeMinor != null
              ? Money.positiveAmount(calculatedFeeMinor, currency)
              : null,
        ),
      );

      // 7. Handle Transaction Fee (Scenario 2)
      Voucher? feeVoucher;
      if (feeRes.isSuccess && feeRes.valueOrNull != null) {
        // Lookup or create 'Transaction Fees' revenue account
        final accountsRes = await _accountRepository.getAll(
          excludeArchived: true,
        );
        Account? feeAccount;
        Account? clearingRemittancesAccount;
        if (accountsRes.isSuccess) {
          feeAccount = accountsRes.valueOrNull!
              .where((a) => a.name == AppStrings.transferFeeIncome)
              .firstOrNull;
          clearingRemittancesAccount = accountsRes.valueOrNull!
              .where((a) => a.name == AppStrings.remittanceClearing)
              .firstOrNull;

          if (clearingRemittancesAccount == null) {
            // Auto-create a revenue/settlement account for fees
            final clearingRemittancesAccountId = AccountId(_idGenerator.next());
            clearingRemittancesAccount = Account.createRoot(
              id: clearingRemittancesAccountId,
              name: AppStrings.remittanceClearing,
              classification: AccountClassification.clearingRemittances,
              createdAt: now,
            );
            await _accountRepository.save(clearingRemittancesAccount);
          }
          if (feeAccount == null) {
            // Auto-create a revenue/settlement account for fees
            final feeAccountId = AccountId(_idGenerator.next());
            feeAccount = Account.createRoot(
              id: feeAccountId,
              name: AppStrings.transferFeeIncome,
              classification: AccountClassification.remittanceFees,
              createdAt: now,
            );
            await _accountRepository.save(feeAccount);
          }
        }

        if (feeAccount != null) {
          final feeAmount = Money.positiveAmount(
            calculatedFeeMinor!,
            currency,
          );
          final feeVoucherId = VoucherId(_idGenerator.next());

          feeVoucher = Voucher.draft(
            id: feeVoucherId,
            type: VoucherType.receipt,
            date: input.date,
            amount: feeAmount,
            currency: currency,
            counterpartyId:
                affectedId, // Fee is from the mediator (transfers account)
            affectedAccountId: feeAccount.id,
            createdAt: now,
            description:
                'رسوم تحويل من ${input.description ?? ""} — مقابل عملية تحويل من المرسل إلى المستلم',
          );
        }
      }

      // 8. Atomic persist
      final List<Voucher> vouchers = [receiptVoucher, paymentVoucher];
      if (feeVoucher != null) vouchers.add(feeVoucher);

      // Check if mediator is a Cashbox/Fund (Automatic confirmation)
      final mediatorRes = await _accountRepository.getById(affectedId);
      bool isCashbox = false;
      if (mediatorRes.isSuccess) {
        final kind = mediatorRes.valueOrNull!.classification.standardKind;
        isCashbox = kind == StandardAccountClassificationKind.liquidAssets ||
            kind == StandardAccountClassificationKind.clearingRemittances;
      }

      Result<void> saveResult;

      if (isCashbox) {
        // Automatically confirm and sign as "The Box"
        // We only sign for the box (creator) and leave the counterparty as Under Request.
        final confirmedReceipt = receiptVoucher.confirm(now).attachSignature(
              signatureHex: 'internal_box_sig',
              publicKeyHex: 'system',
              isSender: true, // The box is the creator (sender of the document)
              status: AgreementStatus.accepted,
            );

        // Payment is signed by the box (sender) only.
        // We also release contingency because the box is immediate.
        final confirmedPayment =
            paymentVoucher.confirm(now).releaseContingency().attachSignature(
                  signatureHex: 'internal_box_sig',
                  publicKeyHex: 'system',
                  isSender: true,
                  status: AgreementStatus.accepted,
                );

        // Generate entries
        final rTransactionId = TransactionId(_idGenerator.next());
        final rEntries = _entryGenerator.generateForConfirmedVoucher(
          voucher: confirmedReceipt,
          transactionId: rTransactionId,
          debitEntryId: EntryId(_idGenerator.next()),
          creditEntryId: EntryId(_idGenerator.next()),
          ledgerCreatedAt: now,
        );

        final pTransactionId = TransactionId(_idGenerator.next());
        final pEntries = _entryGenerator.generateForConfirmedVoucher(
          voucher: confirmedPayment,
          transactionId: pTransactionId,
          debitEntryId: EntryId(_idGenerator.next()),
          creditEntryId: EntryId(_idGenerator.next()),
          ledgerCreatedAt: now,
        );

        saveResult =
            await _voucherRepository.saveTripartitePairWithLedgerEntries(
          receiptVoucher: confirmedReceipt,
          receiptEntries: rEntries,
          paymentVoucher: confirmedPayment,
          paymentEntries: pEntries,
        );

        if (saveResult.isSuccess) {
          for (final entry in [...rEntries, ...pEntries]) {
            await _auditLogService?.log(
              batchId: transferGroupId,
              entityType: 'ledger_entry',
              entityId: entry.id.value,
              action: AuditAction.create,
              severity: AuditSeverity.info,
              newData: {
                'id': entry.id.value,
                'voucher_id': entry.voucherId.value,
                'account_id': entry.accountId.value,
                'side': entry.side.name,
                'amount_minor': entry.amount.minorUnits,
              },
            );
          }
          if (_syncEventDispatcher != null) {
            _syncEventDispatcher!
                .dispatchVoucherAcceptance(confirmedReceipt)
                .ignore();
            _syncEventDispatcher!
                .dispatchVoucherAcceptance(confirmedPayment)
                .ignore();
          }
          if (feeVoucher != null) {
            await _voucherRepository.save(feeVoucher);
          }
        }
      } else {
        saveResult = await _voucherRepository.saveTripartitePair(
          receiptVoucher: receiptVoucher,
          paymentVoucher: paymentVoucher,
        );
        if (saveResult.isSuccess && feeVoucher != null) {
          await _voucherRepository.save(feeVoucher);
        }
      }

      if (saveResult.isFailure) {
        return FailureResult(saveResult.failureOrNull!);
      }
      await _auditLogService?.log(
        batchId: transferGroupId,
        entityType: 'voucher',
        entityId: receiptVoucher.id.value,
        action: AuditAction.create,
        severity: AuditSeverity.info,
        newData: {
          'id': receiptVoucher.id.value,
          'type': receiptVoucher.type.name,
          'state': receiptVoucher.state.name,
          'date': receiptVoucher.date.toIso8601String(),
        },
      );
      await _auditLogService?.log(
        batchId: transferGroupId,
        entityType: 'voucher',
        entityId: paymentVoucher.id.value,
        action: AuditAction.create,
        severity: AuditSeverity.info,
        newData: {
          'id': paymentVoucher.id.value,
          'type': paymentVoucher.type.name,
          'state': paymentVoucher.state.name,
          'date': paymentVoucher.date.toIso8601String(),
        },
      );
      return Success(
        CreateTripartiteTransferOutput(
          receiptVoucherId: receiptId.value,
          paymentVoucherId: paymentId.value,
          transferGroupId: transferGroupId,
        ),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
