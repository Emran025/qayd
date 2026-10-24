import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/identity_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/domain/value_objects/digital_signature.dart';
import 'package:qayd/domain/value_objects/signable_receipt.dart';
import 'package:qayd/domain/value_objects/voucher_query_filter.dart';
import 'package:qayd/domain/value_objects/voucher_state.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';


/// Matches an incoming signed QR payload to a local draft voucher.
///
/// Implements the hierarchical key verification requested:
/// 1. Try currently active public key for the party.
/// 2. If it fails, try historical (rotated) keys.
/// 3. If no key matches, mark as 'unverified'.
class MatchSignatureToVoucherUseCase {
  const MatchSignatureToVoucherUseCase({
    required VoucherRepository voucherRepository,
    required ReceiptSigningService signingService,
    required IdentityRepository identityRepository,
  })  : _voucherRepository = voucherRepository,
        _signingService = signingService,
        _identityRepository = identityRepository;

  final VoucherRepository _voucherRepository;
  final ReceiptSigningService _signingService;
  final IdentityRepository _identityRepository;

  Future<Result<Voucher>> call({
    required SignableReceipt incomingReceipt,
    required String signatureHex,
    required String signerPublicKeyHex,
  }) async {
    try {
      // 1. Discovery authorized keys for the sender
      final lookup = await _identityRepository.lookupByPhone(
        phone: incomingReceipt.senderPhone,
      );

      AgreementStatus agreementStatus = AgreementStatus.unverified;
      String finalSignerKey = signerPublicKeyHex;

      if (lookup != null) {
        // Try all authorized keys for this identity
        final keysToTry = lookup.allAuthorizedKeys;

        bool isAuthorized = false;
        for (final authKey in keysToTry) {
          final digitalSignature = DigitalSignature.fromHex(
            signatureHex: signatureHex,
            signerPublicKeyHex: authKey, // Verify against authorized key
            payloadHashHex: _signingService
                .hashPayload(incomingReceipt.canonicalPayload)
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(),
          );

          if (_signingService.verifyReceiptSignature(
              incomingReceipt, digitalSignature)) {
            isAuthorized = true;
            finalSignerKey = authKey;
            break;
          }
        }

        if (isAuthorized) {
          agreementStatus = AgreementStatus.accepted;
        } else {
          // Mathematical fail or unknown key for this phone number
          agreementStatus = AgreementStatus.unverified;
        }
      } else {
        // Phone number not registered with a key vault yet
        agreementStatus = AgreementStatus.unverified;
      }

      // 2. Find a matching draft voucher locally
      final draftsResult = await _voucherRepository.getAll(
        filter: const VoucherQueryFilter(state: VoucherState.draft),
      );

      if (draftsResult.isFailure) {
        return FailureResult(
            DatabaseFailure(messageAr: AppStrings.unableToSearchFor));
      }

      final drafts = draftsResult.valueOrNull!;
      final matchingDrafts = drafts
          .where((v) =>
              v.amount.minorUnits == incomingReceipt.amountMinor &&
              v.date.toIso8601String().startsWith(incomingReceipt.dateIso))
          .toList();

      if (matchingDrafts.isEmpty) {
        return  FailureResult(ValidationFailure(
          messageAr:
              AppStrings.noDraftReceiptMatching,
          code: 'no_match',
        ));
      }

      // 3. Attach Signature and Update Status
      // If multiple matches exist, we pick the first. Phase-A uses deterministic selection.
      final matchedVoucher = matchingDrafts.first;
      final updatedVoucher = matchedVoucher.attachSignature(
        signatureHex: signatureHex,
        publicKeyHex: finalSignerKey,
        isSender: false, // The counterparty (receiver) signed.
        status: agreementStatus,
        signerPhone: incomingReceipt.senderPhone,
        // Canonical phones: senderPhone = A (the QR issuer), receiverPhone = B (us).
        canonicalSenderPhone: incomingReceipt.senderPhone,
        canonicalReceiverPhone: incomingReceipt.receiverPhone,
      );

      final saveResult = await _voucherRepository.save(updatedVoucher);
      if (saveResult.isFailure) {
        return FailureResult(
            DatabaseFailure(messageAr: AppStrings.unableToSaveThe));
      }

      return Success(updatedVoucher);
    } catch (e) {
      return FailureResult(ValidationFailure(
        messageAr: AppStrings.anUnexpectedErrorOccurred,
        code: 'match_exception',
      ));
    }
  }
}
