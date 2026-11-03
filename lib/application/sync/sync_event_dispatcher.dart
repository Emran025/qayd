import 'package:flutter/material.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/database/database_encryption_key_provider.dart';
import 'package:qayd/data/repositories/outbox_dao.dart';
import 'package:qayd/domain/entities/collateral.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/attachment_repository.dart';
import 'package:qayd/domain/repositories/identity_repository.dart';
import 'package:qayd/domain/services/e2ee_encryption_service.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/core/utils/text_sanitizer.dart';
import 'package:uuid/uuid.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Centralizes the encryption and enqueuing of financial mutations into the Local Outbox.
///
/// Protocol §5.A: Every voucher creation, state transition, signature attachment,
/// or metadata mutation is appended here before any network operation is attempted.
///
/// §5.C — Flexible Routing: During identity discovery, all plaintext routing
/// hints (phone, whatsapp, public key, server ID) are captured and stored in
/// the OutboxEntry so the server can route the node without decryption.
///
/// §6 — Privacy Policy: The policy is checked CLIENT-SIDE before encrypting.
/// If the receiver has blocked the sender (or the sender's discovery is
/// restricted), we abort with a clear failure and NEVER show the receiver as
/// "registered" to the sender. The server also enforces this independently.
class SyncEventDispatcher {
  SyncEventDispatcher({
    required this.outboxDao,
    required this.e2eeEncryptionService,
    required this.accountRepository,
    required this.identityRepository,
    required this.getCurrentUserKeyPair,
    required this.attachmentKeyProvider,
    this.attachmentRepository,
  });

  final OutboxDao outboxDao;
  final E2EEEncryptionService e2eeEncryptionService;
  final AccountRepository accountRepository;
  final IdentityRepository identityRepository;
  final Future<CryptoKeyPair?> Function() getCurrentUserKeyPair;

  /// §5.E — DB key provider (for legacy blob fallback only).
  final DatabaseEncryptionKeyProvider attachmentKeyProvider;

  /// §5.E — Used to read per-attachment keys from the DB before dispatch.
  final AttachmentRepository? attachmentRepository;

  /// Enqueues a 'claim' event for a new voucher.
  ///
  /// §5.E — Per-Attachment Key Embedding:
  /// For each [AttachmentRef] in [voucher.attachmentRefs], the unique AES key
  /// stored in the DB (`attachment_key_hex`) is fetched and embedded inside
  /// the E2EE payload. The counterparty decrypts the payload to get both the
  /// attachment metadata and the key needed to decrypt each blob.
  Future<void> dispatchVoucherClaim(Voucher voucher) async {
    // §5.E: Read per-attachment keys from DB.
    List<Map<String, dynamic>> attachmentMeta = [];

    if (voucher.attachmentRefs.isNotEmpty && attachmentRepository != null) {
      final attachmentsResult = await attachmentRepository!.getByVoucherId(
        voucher.id,
      );
      final fullAttachments = attachmentsResult.valueOrNull ?? [];

      // Map by ID for fast lookup.
      final keyMap = {
        for (final a in fullAttachments) a.id.value: a.attachmentKeyHex,
      };

      attachmentMeta = voucher.attachmentRefs
          .map(
            (ref) => {
              'id': ref.id.value,
              'mime_type': ref.mimeType,
              'byte_size': ref.byteSize,
              // Content-blind deduplication hash.
              'encrypted_blob_hash': ref.encryptedBlobHash,
              // §5.E: unique per-file AES key; null = legacy device-wide key.
              'attachment_key_hex': keyMap[ref.id.value],
            },
          )
          .toList();
    }

    await _enqueueMutation(
      voucher: voucher,
      eventType: 'claim',
      payload: {
        'voucher_id': voucher.id.value,
        'type': voucher.type.name,
        'amount_minor': voucher.amount.minorUnits,
        'currency_code': voucher.currency.code,
        'date': voucher.date.toIso8601String(),
        'description': voucher.description,
        'sender_signature_hex': voucher.senderSignatureHex,
        'sender_public_key_hex': voucher.senderPublicKeyHex,
        'signer_phone': voucher.signerPhone,
        'canonical_sender_phone': voucher.canonicalSenderPhone,
        'canonical_receiver_phone': voucher.canonicalReceiverPhone,
        'origin_voucher_id': voucher.originVoucherId?.value,
        'reference_number': voucher.referenceNumber,
        // §5.E — Per-attachment bundle (omitted when no attachments).
        if (attachmentMeta.isNotEmpty) 'attachments': attachmentMeta,
      },
    );
  }

  /// Enqueues a 'collateralSync' event for a collateral (رهن) attached to a voucher.
  ///
  /// §5.E — Collateral Image Key Embedding:
  /// If the collateral has [imageRefs], the unique per-image AES keys are
  /// read from the DB and embedded inside the E2EE payload.
  ///
  /// Note: Pass the collateral AFTER image processing completes so that
  /// [collateral.imageRefs] is populated.
  Future<void> dispatchCollateralSync(
    Voucher voucher,
    Collateral collateral,
  ) async {
    // §5.E: Build image metadata. Each image has its own key from the DB.
    List<Map<String, dynamic>> imageMeta = [];

    if (collateral.imageRefs.isNotEmpty && attachmentRepository != null) {
      final attachmentsResult = await attachmentRepository!.getByVoucherId(
        voucher.id,
      );
      final fullAttachments = attachmentsResult.valueOrNull ?? [];
      final keyMap = {
        for (final a in fullAttachments) a.id.value: a.attachmentKeyHex,
      };

      imageMeta = collateral.imageRefs
          .map(
            (ref) => {
              'id': ref.id.value,
              'mime_type': ref.mimeType,
              'byte_size': ref.byteSize,
              'encrypted_blob_hash': ref.encryptedBlobHash,
              // §5.E: unique per-image AES key.
              'attachment_key_hex': keyMap[ref.id.value],
            },
          )
          .toList();
    }

    await _enqueueMutation(
      voucher: voucher,
      eventType: 'collateralSync',
      payload: {
        'voucher_id': voucher.id.value,
        'collateral': {
          'id': collateral.id.value,
          'description': collateral.description,
          'value_minor': collateral.estimatedValue.minorUnits,
          'currency_code': collateral.currency.code,
          'status': collateral.status.name,
          'expiry_date': collateral.expiryDate?.toIso8601String(),
          // §5.E — Collateral image bundle (each image has its own key).
          if (imageMeta.isNotEmpty) 'image_refs': imageMeta,
        },
      },
    );
  }

  /// Enqueues an 'acceptance' event (digital signature) for an existing voucher.
  Future<void> dispatchVoucherAcceptance(Voucher voucher) async {
    await _enqueueMutation(
      voucher: voucher,
      eventType: 'acceptance',
      payload: {
        'voucher_id': voucher.id.value,
        'receiver_signature_hex': voucher.receiverSignatureHex,
        'receiver_public_key_hex': voucher.receiverPublicKeyHex,
        'signer_phone': voucher.signerPhone,
      },
    );
  }

  /// Enqueues a 'rejection' event.
  Future<void> dispatchVoucherRejection(Voucher voucher) async {
    await _enqueueMutation(
      voucher: voucher,
      eventType: 'rejection',
      payload: {
        'voucher_id': voucher.id.value,
        'rejection_reason': voucher.rejectionReason,
      },
    );
  }

  /// Enqueues a 'withdrawal' event.
  Future<void> dispatchVoucherWithdrawal(Voucher voucher) async {
    await _enqueueMutation(
      voucher: voucher,
      eventType: 'withdrawal',
      payload: {'voucher_id': voucher.id.value},
    );
  }

  /// Enqueues a generic E2EE-encrypted event for a counterparty.
  ///
  /// §5.A+§5.C+§6 combined flow:
  ///   1. Resolve counterparty identity (local cache → server discovery).
  ///   2. Check privacy policy (both sender and receiver sides).
  ///   3. Capture all routing hints into the OutboxEntry.
  ///   4. Encrypt payload strictly for receiver's public key.
  ///   5. Persist to outbox.
  Future<Result<void>> dispatchGenericEvent({
    required String counterpartyAccountId,
    required String eventType,
    required Map<String, dynamic> payload,
    String? voucherId,
    String? nodeId,
  }) async {
    try {
      final senderKeyPair = await getCurrentUserKeyPair();
      if (senderKeyPair == null) {
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.syncIdentityUnavailable),
        );
      }

      // ── Step 1: Resolve counterparty public key ──────────────────────────
      final partyResult = await accountRepository.getPartyDetails(
        AccountId(counterpartyAccountId),
      );
      final party = partyResult.valueOrNull;

      // Phone/whatsapp extracted from local party details (most reliable source)
      String? receiverPhone = party?.phoneNumber;
      String? receiverWhatsapp = party?.whatsappNumber;
      String? receiverPublicKey = party?.currentPublicKeyHex;
      // serverAccountId from PartyDetails = numeric server user ID
      int? receiverServerId = party?.serverAccountId;

      // ── Step 2: Active Public Key Discovery (§5.B) ───────────────────────
      // If local cache has no public key, query the server.
      if (receiverPublicKey == null || receiverPublicKey.isEmpty) {
        PublicKeyLookupResult? serverIdentity;

        if (receiverPhone != null && receiverPhone.isNotEmpty) {
          serverIdentity = await identityRepository.lookupByPhone(
            phone: receiverPhone,
          );
        } else if (party?.email != null && party!.email!.isNotEmpty) {
          serverIdentity = await identityRepository.lookupByEmail(
            email: party.email!,
          );
        }

        // ── §6: Bidirectional Privacy Policy Gate (Client-Side) ──────────
        // sync_blocked means EITHER party has restricted sync with the other.
        // The server enforces bidirectional checks (canSyncBidirectional) so
        // when sync_blocked is true, we CANNOT determine which party blocked.
        // We return a clean failure WITHOUT revealing whether the account
        // exists — the caller should treat this as "party not available".
        if (serverIdentity != null && serverIdentity.syncBlocked) {
          debugPrint(
            'Sync: 🚫 §6 Bidirectional privacy block for party $counterpartyAccountId. Suppressing.',
          );
          return FailureResult(
            ValidationFailure(
              messageAr: AppStrings.theCounterpartyHasRestricted,
            ),
          );
        }

        if (serverIdentity != null) {
          receiverPublicKey = serverIdentity.publicKeyHex;
          receiverPhone ??= serverIdentity.phone.isNotEmpty
              ? serverIdentity.phone
              : null;
          receiverWhatsapp ??= serverIdentity.whatsappNumber;
          receiverServerId ??= serverIdentity.serverId;

          // Update local party cache with discovered data (including serverId)
          if (party != null) {
            await accountRepository.savePartyDetails(
              party.copyWith(
                currentPublicKeyHex: receiverPublicKey,
                publicKeyHistoryHex: serverIdentity.allAuthorizedKeys,
                phoneNumber: receiverPhone ?? party.phoneNumber,
                whatsappNumber: receiverWhatsapp ?? party.whatsappNumber,
                serverAccountId: receiverServerId ?? party.serverAccountId,
              ),
            );
          }
        }
      } else {
        // Public key already known — capture server ID if party has it
        receiverServerId = party?.serverAccountId;
      }

      // ── §5.C Routing Prerequisite Check ──────────────────────────────────
      // We need at LEAST a public key to encrypt. Phone/whatsapp are needed
      // for server routing if serverId is unknown.
      // For "offline" counterparties (no server account), we still encrypt
      // if we have their public key from QR — and rely on phone routing.
      final hasRoutingHint =
          (receiverServerId != null) ||
          (receiverPhone?.isNotEmpty ?? false) ||
          (receiverWhatsapp?.isNotEmpty ?? false) ||
          (receiverPublicKey?.isNotEmpty ?? false);

      if (receiverPublicKey == null || receiverPublicKey.isEmpty) {
        // Cannot encrypt without a public key — suspend enqueue.
        debugPrint(
          'Sync: ⚠️ No public key for $counterpartyAccountId. Enqueueing suspended.',
        );
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.theCounterpartysPublicKey),
        );
      }

      if (!hasRoutingHint) {
        // Cannot route without any hint — suspend enqueue.
        debugPrint(
          'Sync: ⚠️ No routing hint for $counterpartyAccountId. Enqueueing suspended.',
        );
        return FailureResult(
          ValidationFailure(messageAr: AppStrings.theCounterpartysPublicKey),
        );
      }

      // ── Step 3: Encrypt payload for receiver ─────────────────────────────
      // The signed envelope binds these exact values to the ciphertext.
      final eventNodeId = nodeId ?? const Uuid().v4();
      final encrypted = await e2eeEncryptionService.encryptPayload(
        rawPayload: payload,
        senderKeyPair: senderKeyPair,
        receiverPublicKeyHex: receiverPublicKey,
        nodeId: eventNodeId,
        eventType: eventType,
      );

      // ── Step 4: Enqueue with all routing headers ──────────────────────────
      final enqueueRes = await outboxDao.enqueue(
        OutboxEntry(
          id: eventNodeId,
          eventType: eventType,
          voucherId: voucherId,
          counterpartyAccountId: counterpartyAccountId,
          encryptedPayload: encrypted,
          state: 'pending',
          retryCount: 0,
          createdAt: DateTime.now(),
          // §5.C Routing headers
          receiverPhone: receiverPhone,
          receiverWhatsapp: receiverWhatsapp,
          receiverPublicKey: receiverPublicKey,
          receiverServerId: receiverServerId,
        ),
      );

      return enqueueRes;
    } catch (e) {
      final msg =
          'فشل المزامنة المحلية: ${TextSanitizer.sanitizeErrorMessage(e)}';
      debugPrint('Sync: ❌ Dispatch failure for $eventType: $msg');
      return FailureResult(DatabaseFailure(messageAr: msg));
    }
  }

  /// Internal helper to resolve counterparty identity, encrypt, and enqueue.
  Future<void> _enqueueMutation({
    required Voucher voucher,
    required String eventType,
    required Map<String, dynamic> payload,
  }) async {
    await dispatchGenericEvent(
      counterpartyAccountId: voucher.counterpartyId.value,
      eventType: eventType,
      payload: payload,
      voucherId: voucher.id.value,
    );
  }
}
