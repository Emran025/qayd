import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/vouchers/dtos/create_dual_transfer_input.dart';
import 'package:qayd/application/vouchers/dtos/create_dual_transfer_output.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/dual_transfer_meta.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/domain/value_objects/tripartite_meta.dart';
import 'package:qayd/domain/value_objects/tripartite_role.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/standard_account_classification_kind.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/domain/entities/audit_entry.dart';

/// Creates a dual transfer (two standard vouchers through the fund/cashbox).
///
/// Unlike the tripartite transfer which acts as a bridge (fund not affected),
/// the dual transfer creates two real vouchers that impact the fund:
///
/// 1. **Receipt** (Sender → Fund): Debits the sender, credits the fund.
///    - counterparty = Sender, affectedAccount = Fund
///    - Description: AppStrings.deductingAnAmountfromThe
///
/// 2. **Payment** (Fund → Receiver): Debits the fund, credits the receiver.
///    - counterparty = Receiver, affectedAccount = Fund
///    - Description: AppStrings.addAnAmounttoRecipients
///
/// Both vouchers are linked via a shared [dualGroupId] and carry
/// [DualTransferMeta] so the UI can distinguish them from regular vouchers.
class CreateDualTransferUseCase {
  CreateDualTransferUseCase(
    this._voucherRepository,
    this._currencyRepository,
    this._idGenerator,
    this._writeGuard,
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
  final AccountRepository _accountRepository;
  final EntryGenerator _entryGenerator;
  final SyncEventDispatcher? _syncEventDispatcher;
  final AuditLogService? _auditLogService;

  Future<Result<CreateDualTransferOutput>> call(
    CreateDualTransferInput input,
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
      final senderId = AccountId(input.senderAccountId);
      final receiverId = AccountId(input.receiverAccountId);
      final fundId = AccountId(input.fundAccountId);

      if (senderId == receiverId) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.theSenderAndRecipient,
            code: 'dual_same_sender_receiver',
          ),
        );
      }
      if (senderId == fundId || receiverId == fundId) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.theFundAccountMust,
            code: 'dual_fund_conflict',
          ),
        );
      }

      // 4. Resolve account names for descriptions
      final senderName = await _resolveAccountName(senderId);
      final receiverName = await _resolveAccountName(receiverId);

      // 5. Generate shared identifiers
      final dualGroupId = _idGenerator.next();
      final receiptId = VoucherId(_idGenerator.next());
      final paymentId = VoucherId(_idGenerator.next());
      final now = DateTime.now();
      final amount = Money.positiveAmount(input.amountMinorUnits, currency);

      // 5.5 Handle Fee Deduction
      final feeMinor = input.feeAmountMinorUnits ?? 0;
      final netAmountMinor = input.amountMinorUnits - feeMinor;

      if (netAmountMinor <= 0 && feeMinor > 0) {
        return FailureResult(
          ValidationFailure(
            messageAr:
                'مبلغ الرسوم لا يمكن أن يكون أكبر من أو يساوي مبلغ التحويل.',
            code: 'fee_exceeds_amount',
          ),
        );
      }

      final netAmount = Money.positiveAmount(netAmountMinor, currency);

      // Build description text
      final feeDesc = feeMinor > 0 ? ' (رسوم: ${feeMinor / 100})' : '';

      final senderDesc =
          input.description != null && input.description!.isNotEmpty
              ? '${input.description} — خصم من حساب $senderName$feeDesc'
              : 'خصم مبلغ من حساب $senderName (تحويل مزدوج)$feeDesc';

      final receiverDesc =
          input.description != null && input.description!.isNotEmpty
              ? '${input.description} — إضافة إلى حساب $receiverName'
              : 'إضافة مبلغ إلى حساب $receiverName (تحويل مزدوج)';

      // 6. Create Receipt Voucher (Sender → Fund)
      // counterparty = Sender, affectedAccount = Fund
      // type = receipt (money coming IN from sender to fund)
      final receiptVoucher = Voucher.draft(
        id: receiptId,
        type: VoucherType.receipt,
        date: input.date,
        amount: amount,
        currency: currency,
        counterpartyId: senderId,
        affectedAccountId: fundId,
        createdAt: now,
        description: senderDesc,
        notes: input.notes,
        tripartiteMeta: TripartiteMeta(
          transferGroupId: dualGroupId,
          role: TripartiteRole.intermediaryReceipt,
          linkedPartyId: receiverId,
          mediatorAccountId: fundId,
          isContingent: false,
        ),
      );

      // 7. Create Payment Voucher (Fund → Receiver)
      // counterparty = Receiver, affectedAccount = Fund
      // type = payment (money going OUT from fund to receiver)
      final paymentVoucher = Voucher.draft(
        id: paymentId,
        type: VoucherType.payment,
        date: input.date,
        amount: netAmount,
        currency: currency,
        counterpartyId: receiverId,
        affectedAccountId: fundId,
        createdAt: now,
        description: receiverDesc,
        notes: input.notes,
        tripartiteMeta: TripartiteMeta(
          transferGroupId: dualGroupId,
          role: TripartiteRole.intermediaryPayment,
          linkedPartyId: senderId,
          mediatorAccountId: fundId,
          isContingent: false,
          feeAmount:
              feeMinor > 0 ? Money.positiveAmount(feeMinor, currency) : null,
        ),
      );

      // 8. Persist both vouchers atomically
      // Check if Fund is a Cashbox/Liquid Asset (Automatic confirmation)
      final fundRes = await _accountRepository.getById(fundId);
      bool isCashbox = false;
      if (fundRes.isSuccess) {
        final kind = fundRes.valueOrNull!.classification.standardKind;
        isCashbox = kind == StandardAccountClassificationKind.liquidAssets ||
            kind == StandardAccountClassificationKind.clearingRemittances;
      }

      Result<void> saveResult;

      if (isCashbox) {
        // Automatically confirm and sign as "The Box" (Internal signature)
        // We only sign for the box (creator) and leave the counterparty as Under Request
        final confirmedReceipt = receiptVoucher.confirm(now).attachSignature(
              signatureHex: 'internal_box_sig',
              publicKeyHex: 'system',
              isSender: true, // The box is the creator (sender of the document)
              status: AgreementStatus.accepted,
            );

        // Payment is signed by the box (sender) only
        final confirmedPayment = paymentVoucher.confirm(now).attachSignature(
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
              batchId: dualGroupId,
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
        }
      } else {
        saveResult = await _voucherRepository.saveTripartitePair(
          receiptVoucher: receiptVoucher,
          paymentVoucher: paymentVoucher,
        );
      }

      if (saveResult.isFailure) {
        return FailureResult(saveResult.failureOrNull!);
      }
      await _auditLogService?.log(
        batchId: dualGroupId,
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
        batchId: dualGroupId,
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
        CreateDualTransferOutput(
          receiptVoucherId: receiptId.value,
          paymentVoucherId: paymentId.value,
          dualGroupId: dualGroupId,
        ),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }

  Future<String> _resolveAccountName(AccountId id) async {
    final r = await _accountRepository.getById(id);
    return r.isSuccess ? r.valueOrNull!.name : id.value;
  }
}
