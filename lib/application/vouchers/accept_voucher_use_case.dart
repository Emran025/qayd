import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/security/license_vault.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/value_objects/signable_receipt.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/domain/entities/audit_entry.dart';


/// Executed when the user taps "Accept" on an incoming pending claim.
///
/// Protocol §1 — Signature Execution Post-Matching:
/// 1. Resolves the current user's phone from LicenseVault.
/// 2. Generates an Ed25519 signature over the canonical payload.
/// 3. Attaches the signature locally and marks voucher as accepted.
/// 4. Dispatches an E2EE acceptance SyncNode via outbox (survives network
///    outages — same reliable path as all other sync events).
class AcceptVoucherUseCase {
  AcceptVoucherUseCase({
    required this.voucherRepository,
    required this.accountRepository,
    required this.signingService,
    required this.getCurrentUserKeyPair,
    required this.licenseVault,
    required this.entryGenerator,
    required this.idGenerator,
    this.syncEventDispatcher,
    this.auditLogService,
  });

  final VoucherRepository voucherRepository;
  final AccountRepository accountRepository;
  final ReceiptSigningService signingService;
  final Future<CryptoKeyPair> Function() getCurrentUserKeyPair;
  final LicenseVault licenseVault;
  final EntryGenerator entryGenerator;
  final IdGenerator idGenerator;

  /// Optional — when provided the acceptance is propagated via E2EE outbox sync.
  final SyncEventDispatcher? syncEventDispatcher;
  final AuditLogService? auditLogService;

  Future<Result<void>> call(String voucherId) async {
    try {
      final loaded = await voucherRepository.getById(VoucherId(voucherId));
      if (loaded.isFailure || loaded.valueOrNull == null) {
        return  FailureResult(
            ValidationFailure(messageAr: AppStrings.theBondDoesNot));
      }
      final draft = loaded.valueOrNull!;
      final oldVoucherState = {
        'id': draft.id.value,
        'state': draft.state.name,
        'receiver_status': draft.receiverStatus.name,
      };

      if (draft.receiverStatus == AgreementStatus.accepted) {
        return  FailureResult(
            ValidationFailure(messageAr: AppStrings.theBondIsPreaccepted));
      }

      // Resolve current user's phone from license data.
      final licenseData = await licenseVault.readLicenseData();
      final myPhone = licenseData?['phone'] as String? ?? '';

      // Resolve counterparty's phone for canonical payload.
      final counterpartyParty =
          await accountRepository.getPartyDetails(draft.counterpartyId);
      final counterpartyPhone =
          counterpartyParty.valueOrNull?.phoneNumber ?? draft.signerPhone ?? '';

      final keyPair = await getCurrentUserKeyPair();

      // 1. Generate Mathematical Signature for Acceptance.
      final signable = SignableReceipt(
        amountMinor: draft.amount.minorUnits,
        currencyCode: draft.currency.code,
        senderPhone: counterpartyPhone,
        receiverPhone: myPhone,
        dateIso: draft.date.toIso8601String().split('T').first,
        receiptUuid: draft.id.value,
      );

      final signature = signingService.signReceipt(signable, keyPair);
      final signatureHex = signature.signatureHex;
      final pubKeyHex = signature.signerPublicKeyHex;

      // 2. Attach Locally and Confirm.
      var signedVoucher = draft.attachSignature(
        signatureHex: signatureHex,
        publicKeyHex: pubKeyHex,
        isSender: false, // The user is accepting an inbound claim.
        status: AgreementStatus.accepted,
        signerPhone: myPhone,
        // counterpartyPhone = the original sender (A); myPhone = receiver (B).
        // These are frozen on first write so they never change after this call.
        canonicalSenderPhone: counterpartyPhone,
        canonicalReceiverPhone: myPhone,
      );

      // Auto-confirm state to record in local ledger.
      signedVoucher = signedVoucher.confirm(DateTime.now());

      // Generate Ledger Entries.
      final now = DateTime.now();
      final transactionId = TransactionId(idGenerator.next());
      final debitId = EntryId(idGenerator.next());
      final creditId = EntryId(idGenerator.next());

      final entries = entryGenerator.generateForConfirmedVoucher(
        voucher: signedVoucher,
        transactionId: transactionId,
        debitEntryId: debitId,
        creditEntryId: creditId,
        ledgerCreatedAt: now,
      );

      final saveResult = await voucherRepository.saveWithLedgerEntries(
        voucher: signedVoucher,
        ledgerEntries: entries,
      );
      if (saveResult.isFailure) return saveResult;

      await auditLogService?.log(
        entityType: 'voucher',
        entityId: signedVoucher.id.value,
        action: AuditAction.update,
        severity: AuditSeverity.info,
        oldData: oldVoucherState,
        newData: {
          'id': signedVoucher.id.value,
          'state': signedVoucher.state.name,
          'receiver_status': signedVoucher.receiverStatus.name,
        },
      );
      for (final entry in entries) {
        await auditLogService?.log(
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

      // §5.A — Dispatch acceptance via outbox (fire-and-forget, outbox-routed).
      // Using SyncEventDispatcher guarantees delivery across network outages
      // and properly stores routing hints for server delivery.
      syncEventDispatcher?.dispatchVoucherAcceptance(signedVoucher).ignore();

      return const Success(null);
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
