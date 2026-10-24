import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/application/vouchers/dtos/confirm_voucher_input.dart';
import 'package:qayd/application/vouchers/dtos/confirm_voucher_output.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/entry_side.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_state.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/domain/entities/audit_entry.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/value_objects/signable_receipt.dart';
import 'package:qayd/data/security/license_vault.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

class ConfirmVoucherUseCase {
  ConfirmVoucherUseCase(
    this._voucherRepository,
    this._entryGenerator,
    this._idGenerator,
    this._writeGuard,
    this._fiscalPeriodRepository, {
    AccountRepository? accountRepository,
    ReceiptSigningService? signingService,
    Future<CryptoKeyPair?> Function()? getKeyPair,
    LicenseVault? licenseVault,
    SyncEventDispatcher? syncEventDispatcher,
    AuditLogService? auditLogService,
  })  : _accountRepository = accountRepository,
        _signingService = signingService,
        _getKeyPair = getKeyPair,
        _licenseVault = licenseVault,
        _syncEventDispatcher = syncEventDispatcher,
        _auditLogService = auditLogService;

  final VoucherRepository _voucherRepository;
  final EntryGenerator _entryGenerator;
  final IdGenerator _idGenerator;
  final GovernanceWriteGuard _writeGuard;
  final FiscalPeriodRepository _fiscalPeriodRepository;
  final AccountRepository? _accountRepository;
  final ReceiptSigningService? _signingService;
  final Future<CryptoKeyPair?> Function()? _getKeyPair;
  final LicenseVault? _licenseVault;
  final SyncEventDispatcher? _syncEventDispatcher;
  final AuditLogService? _auditLogService;

  Future<Result<ConfirmVoucherOutput>> call(ConfirmVoucherInput input) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }
      final loaded =
          await _voucherRepository.getById(VoucherId(input.voucherId));
      if (loaded.isFailure) {
        return FailureResult(loaded.failureOrNull!);
      }
      final draft = loaded.valueOrNull!;

      final periodsR = await _fiscalPeriodRepository.listAllOrdered();
      if (periodsR.isSuccess &&
          FiscalPeriodPolicy.voucherDateInClosedPeriod(
            periodsR.valueOrNull!,
            draft.date,
          )) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.voucherDateInClosedPeriod,
            code: 'voucher_closed_period',
          ),
        );
      }

      var voucherToConfirm = draft;

      // §2.A: Digital Signing
      if (_signingService != null &&
          _getKeyPair != null &&
          _licenseVault != null) {
        final keyPair = await _getKeyPair!();
        if (keyPair != null) {
          final licenseData = await _licenseVault!.readLicenseData();
          final myPhone = (licenseData?['user']?['phone'] ??
                  licenseData?['phone']) as String? ??
              '';

          String cpPhone = '';
          if (_accountRepository != null) {
            final cpParty = await _accountRepository!.getPartyDetails(
              draft.counterpartyId,
            );
            cpPhone = cpParty.valueOrNull?.phoneNumber ?? '';
          }

          final signable = SignableReceipt(
            amountMinor: draft.amount.minorUnits,
            currencyCode: draft.currency.code,
            senderPhone: myPhone,
            receiverPhone: cpPhone,
            dateIso: draft.date.toIso8601String().split('T').first,
            receiptUuid: draft.id.value,
          );

          // If it already has a sender signature (e.g. from QR scan), we sign as receiver.
          final shouldSignAsSender = draft.senderSignatureHex == null;

          final signature = _signingService!.signReceipt(signable, keyPair);
          voucherToConfirm = draft.attachSignature(
            signatureHex: signature.signatureHex,
            publicKeyHex: signature.signerPublicKeyHex,
            isSender: shouldSignAsSender,
            status: AgreementStatus.accepted,
            signerPhone: myPhone,
            // Freeze the canonical phones so verification can always reconstruct
            // the exact payload regardless of who opens the voucher details later.
            canonicalSenderPhone: shouldSignAsSender
                ? myPhone
                : draft.canonicalSenderPhone ?? draft.signerPhone,
            canonicalReceiverPhone: shouldSignAsSender
                ? cpPhone
                : (draft.canonicalReceiverPhone ?? myPhone),
          );
        }
      }

      // A local ledger write must be backed by at least one accepted signature.
      // The configured signing path above may add the creator's signature; if
      // it is unavailable or cannot sign, do not silently confirm an unsigned
      // restored voucher.
      if (voucherToConfirm.senderStatus != AgreementStatus.accepted &&
          voucherToConfirm.receiverStatus != AgreementStatus.accepted) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.theBondCannotBe,
            code: 'voucher_not_signed',
          ),
        );
      }

      final now = DateTime.now();
      final confirmed = voucherToConfirm.confirm(now);

      final transactionId = TransactionId(_idGenerator.next());
      final debitEntryId = EntryId(_idGenerator.next());
      final creditEntryId = EntryId(_idGenerator.next());

      final entries = _entryGenerator.generateForConfirmedVoucher(
        voucher: confirmed,
        transactionId: transactionId,
        debitEntryId: debitEntryId,
        creditEntryId: creditEntryId,
        ledgerCreatedAt: now,
      );

      final debitLine = entries.firstWhere((e) => e.side == EntrySide.debit);
      final creditLine = entries.firstWhere((e) => e.side == EntrySide.credit);

      final persisted = await _voucherRepository.saveWithLedgerEntries(
        voucher: confirmed,
        ledgerEntries: entries,
      );

      if (persisted.isFailure) {
        return FailureResult(persisted.failureOrNull!);
      }

      // §5.A: Enqueue acceptance into local outbox
      if (_syncEventDispatcher != null) {
        _syncEventDispatcher!.dispatchVoucherAcceptance(confirmed).ignore();
      }

      await _auditLogService?.log(
        entityType: 'voucher',
        entityId: confirmed.id.value,
        action: AuditAction.update,
        oldData: {
          'state': draft.state.name,
          'confirmed_at': draft.confirmedAt?.toIso8601String(),
        },
        newData: {
          'state': confirmed.state.name,
          'confirmed_at': confirmed.confirmedAt?.toIso8601String(),
        },
      );

      for (final entry in entries) {
        await _auditLogService?.log(
          entityType: 'ledger_entry',
          entityId: entry.id.value,
          action: AuditAction.create,
          severity: AuditSeverity.info,
          newData: {
            'id': entry.id.value,
            'transaction_id': entry.transactionId.value,
            'account_id': entry.accountId.value,
            'side': entry.side.name,
            'voucher_id': entry.voucherId.value,
            'amount_minor': entry.amount.minorUnits,
            'currency_code': entry.currency.code,
          },
        );
      }

      // ── Cascading release for tripartite transfers ─────────────────────
      // When confirming the receipt leg (A→C), automatically release
      // the contingent payment leg (C→B) so it can be shared/signed.
      await _cascadeTripartiteRelease(confirmed);

      return Success(
        ConfirmVoucherOutput(
          voucherId: confirmed.id.value,
          transactionId: transactionId.value,
          debitEntryId: debitLine.id.value,
          creditEntryId: creditLine.id.value,
          stateCode: VoucherState.confirmed.name,
        ),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }

  /// When an intermediary receipt is confirmed, find and release its
  /// contingent payment sibling within the same transfer group.
  Future<void> _cascadeTripartiteRelease(Voucher confirmed) async {
    final meta = confirmed.tripartiteMeta;
    if (meta == null) return;
    if (!meta.role.isReceipt) return;

    final groupResult = await _voucherRepository.getByTransferGroupId(
      meta.transferGroupId,
    );
    if (groupResult.isFailure) return;

    final siblings = groupResult.valueOrNull!;
    for (final sibling in siblings) {
      final siblingMeta = sibling.tripartiteMeta;
      if (siblingMeta == null) continue;
      if (!siblingMeta.role.isPayment) continue;
      if (!siblingMeta.isContingent) continue;

      // Release the contingent flag by restoring with updated meta.
      // Preserve canonical phones so verification remains possible after release.
      final released = Voucher.restore(
        id: sibling.id,
        type: sibling.type,
        referenceNumber: sibling.referenceNumber,
        date: sibling.date,
        amount: sibling.amount,
        currency: sibling.currency,
        counterpartyId: sibling.counterpartyId,
        affectedAccountId: sibling.affectedAccountId,
        state: sibling.state,
        description: sibling.description,
        attachmentRefs: sibling.attachmentRefs,
        notes: sibling.notes,
        tags: sibling.tags,
        createdAt: sibling.createdAt,
        confirmedAt: sibling.confirmedAt,
        settledAt: sibling.settledAt,
        senderStatus: sibling.senderStatus,
        receiverStatus: sibling.receiverStatus,
        senderSignatureHex: sibling.senderSignatureHex,
        receiverSignatureHex: sibling.receiverSignatureHex,
        senderPublicKeyHex: sibling.senderPublicKeyHex,
        receiverPublicKeyHex: sibling.receiverPublicKeyHex,
        lifecycleStatus: sibling.lifecycleStatus,
        signerPhone: sibling.signerPhone,
        canonicalSenderPhone: sibling.canonicalSenderPhone,
        canonicalReceiverPhone: sibling.canonicalReceiverPhone,
        tripartiteMeta: siblingMeta.release(),
      );
      await _voucherRepository.save(released);
    }
  }
}
