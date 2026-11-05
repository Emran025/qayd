import 'dart:convert';
import 'dart:io';

import 'package:qayd/di/injection_container.dart';
import 'package:qayd/domain/repositories/notification_message_repository.dart';
import 'package:qayd/domain/services/notification_filter_service.dart';
import 'package:qayd/core/result/result.dart';
import 'package:flutter/foundation.dart';
import 'package:qayd/domain/entities/sync_node.dart';
import 'package:qayd/domain/repositories/identity_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/repositories/ledger_repository.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/services/e2ee_encryption_service.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/domain/value_objects/voucher_state.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/domain/value_objects/signable_receipt.dart';
import 'package:qayd/domain/value_objects/digital_signature.dart';
import 'package:qayd/domain/repositories/attachment_repository.dart';
import 'package:qayd/domain/repositories/collateral_repository.dart';
import 'package:qayd/data/encryption/voucher_key_service.dart';
import 'package:qayd/domain/entities/voucher_attachment.dart';
import 'package:qayd/domain/value_objects/attachment_id.dart';
import 'package:qayd/domain/value_objects/attachment_source_type.dart';
import 'package:qayd/domain/entities/collateral.dart';
import 'package:qayd/domain/value_objects/collateral_id.dart';
import 'package:qayd/domain/value_objects/collateral_status.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/entities/collateral_revaluation.dart';
import 'package:qayd/domain/value_objects/tripartite_meta.dart';
import 'package:qayd/domain/value_objects/tripartite_role.dart';
import 'package:uuid/uuid.dart';
import 'package:qayd/application/pos/pos_credit_invoice_audit.dart';
import 'package:qayd/application/pos/pos_credit_invoice_chat_protocol.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/application/sync/audit_sync_processor.dart';
import 'package:qayd/domain/entities/audit_entry.dart';
import 'package:qayd/domain/entities/party_details.dart';

List<String> _orderedDecryptPublicKeys({
  required SyncNode node,
  required PartyDetails party,
}) {
  final authorizedKeys = <String>{
    for (final key in party.allAuthorizedKeys)
      if (key.trim().isNotEmpty) key.trim().toLowerCase(),
  };
  final out = <String>[];

  void add(String? hex) {
    final v = (hex ?? '').trim();
    if (v.isEmpty) return;
    final normalized = v.toLowerCase();
    if (!authorizedKeys.contains(normalized)) return;
    if (!out.contains(normalized)) {
      out.add(normalized);
    }
  }

  // Sender metadata is not an authorization source. On phone/WhatsApp
  // fallback, only keys already attached to this party may authenticate data.
  add(node.senderPublicKey);
  for (final k in party.allAuthorizedKeys) {
    add(k);
  }
  return out;
}

/// Intercepts inbound [SyncNode] streams, enforces E2EE Cryptographic rules,
/// decrypts the payloads, and mutates the local Drift databases securely.
class SyncPayloadProcessor {
  SyncPayloadProcessor({
    required this.identityRepository,
    required this.voucherRepository,
    required this.ledgerRepository,
    required this.accountRepository,
    required this.currencyRepository,
    required this.e2eeService,
    required this.signingService,
    required this.getCurrentUserKeyPair,
    required this.attachmentRepository,
    required this.collateralRepository,
    required this.voucherKeyService,
    required this.notificationMessageRepository,
    required this.notificationFilterService,
    this.auditLogService,
    this.auditSyncProcessor,
    this.onDecryptionFailure,
  });

  final IdentityRepository identityRepository;
  final VoucherRepository voucherRepository;
  final LedgerRepository ledgerRepository;
  final AccountRepository accountRepository;
  final CurrencyRepository currencyRepository;
  final NotificationMessageRepository notificationMessageRepository;
  final E2EEEncryptionService e2eeService;
  final ReceiptSigningService signingService;
  final Future<CryptoKeyPair> Function() getCurrentUserKeyPair;
  final AttachmentRepository attachmentRepository;
  final CollateralRepository collateralRepository;
  final VoucherKeyService voucherKeyService;
  final NotificationFilterService notificationFilterService;
  final AuditLogService? auditLogService;
  final AuditSyncProcessor? auditSyncProcessor;
  final void Function(String nodeId)? onDecryptionFailure;

  Future<PartyDetails?> _resolveInboundSenderParty(SyncNode node) async {
    AccountId? accountId;

    final envPk = node.senderPublicKey?.trim().toLowerCase() ?? '';
    if (envPk.isNotEmpty) {
      accountId = (await accountRepository.findAccountByPublicKey(
        envPk,
      )).valueOrNull;
    }

    final envPhone = node.senderPhone?.trim() ?? '';
    if (accountId == null && envPhone.isNotEmpty) {
      accountId = (await accountRepository.findAccountByPhone(
        envPhone,
      )).valueOrNull;
    }

    final envWa = node.senderWhatsapp?.trim() ?? '';
    if (accountId == null && envWa.isNotEmpty) {
      accountId = (await accountRepository.findAccountByWhatsApp(
        envWa,
      )).valueOrNull;
    }

    if (accountId == null) {
      // §5.D — Unknown sender with routing hints:
      // Instead of silently creating a shadow account (which bypasses user
      // consent), persist the raw SyncNode as a pending onboarding request.
      // The user will be notified and can create the counterparty account
      // manually. Once they do, [replayPendingNodesForSender] re-processes
      // all staged nodes so no voucher data is lost.
      if (envPk.isNotEmpty || envPhone.isNotEmpty || envWa.isNotEmpty) {
        // ── Deduplication guard ────────────────────────────────────────────
        // The server keeps returning unacknowledged nodes on every pull.
        // Check whether this node is already staged so we never make a
        // redundant network call or overwrite a previously-resolved name.
        final existing = await notificationMessageRepository.findById(node.id);

        if (existing != null) {
          // Node is already staged. Check if the name was already resolved.
          final existingRaw = existing.rawPayloadJson != null
              ? (jsonDecode(existing.rawPayloadJson!) as Map<String, dynamic>?)
              : null;
          final alreadyHasName = existingRaw?['sender_name'] as String?;

          if (alreadyHasName != null && alreadyHasName.isNotEmpty) {
            // Name already known — nothing to do.
            debugPrint(
              'Sync: Node [${node.id}] already staged with name [$alreadyHasName], skipping.',
            );
            return null;
          }

          // Staged without a name (e.g. was offline at first staging).
          // Resolve the name now and backfill the existing record.
          debugPrint(
            'Sync: Node [${node.id}] staged but missing name — backfilling from server.',
          );
          try {
            final result = await identityRepository.lookupSyncNodeSender(
              nodeId: node.id,
            );
            if (result != null && result.name.isNotEmpty) {
              final updatedPayload =
                  jsonDecode(existing.rawPayloadJson ?? '{}')
                      as Map<String, dynamic>;
              updatedPayload['sender_name'] = result.name;
              updatedPayload['sender_phone'] ??= result.phone.isNotEmpty
                  ? result.phone
                  : null;
              updatedPayload['sender_whatsapp'] ??= result.whatsappNumber;
              updatedPayload['sender_pk'] ??= result.publicKeyHex;
              await notificationMessageRepository.updateBodyAndPayload(
                id: node.id,
                bodyText: AppStrings.counterpartyOnboardingRequestFrom(
                  result.name,
                ),
                rawPayloadJson: jsonEncode(updatedPayload),
              );
              debugPrint(
                'Sync: Backfilled name [${result.name}] for node [${node.id}].',
              );
            }
          } catch (e) {
            debugPrint('Sync: Backfill name lookup failed (non-fatal): $e');
          }
          return null;
        }

        // Node not yet staged — run the full staging flow.
        debugPrint(
          'Sync: Unknown sender [Phone: $envPhone / PK: ${envPk.isNotEmpty ? envPk.substring(0, 8) : '—'}] — staging consent-based onboarding request.',
        );
        await stagePendingCounterpartyRequest(
          nodeId: node.id,
          node: node,
          publicKey: envPk.isEmpty ? null : envPk,
          phone: envPhone.isEmpty ? null : envPhone,
          whatsapp: envWa.isEmpty ? null : envWa,
        );
        return null;
      }
      return null;
    }

    final partyRow = await accountRepository.getPartyDetails(accountId);
    return partyRow.valueOrNull ?? PartyDetails(accountId: accountId);
  }

  /// Ingests a list of pushed/pulled encrypted sync nodes.
  ///
  /// Returns the set of [SyncNode.id] values that were fully handled (decrypted
  /// and domain logic applied). Callers should only [acknowledge] those ids.
  Future<Set<String>> processIncomingNodes(List<SyncNode> nodes) async {
    final myKeyPair = await getCurrentUserKeyPair();
    final appliedIds = <String>{};

    for (final node in nodes) {
      try {
        // §5.D — Hierarchical counterpart resolution ( pubkey → phone → whatsapp ).
        final party = await _resolveInboundSenderParty(node);

        if (party == null) {
          debugPrint(
            'Blocked SyncNode [${node.id}]: Untrusted or Unknown Sender Identity.',
          );
          continue; // DROP SILENTLY
        }

        final decryptKeys = _orderedDecryptPublicKeys(node: node, party: party);
        if (decryptKeys.isEmpty) {
          debugPrint(
            'Blocked SyncNode [${node.id}]: No public key available for Sender.',
          );
          continue;
        }

        Map<String, dynamic>? decryptedRawPayload;
        String? decryptionKeyHexUsed;
        for (final pk in decryptKeys) {
          try {
            decryptedRawPayload = await e2eeService.decryptPayload(
              encryptedPayload: node.encryptedPayload,
              receiverKeyPair: myKeyPair,
              senderPublicKeyHex: pk,
              nodeId: node.id,
              eventType: node.eventType.name,
            );
            decryptionKeyHexUsed = pk;
            break;
          } catch (_) {
            continue;
          }
        }

        if (decryptedRawPayload == null) {
          debugPrint('Decryption failed for SyncNode [${node.id}]');
          onDecryptionFailure?.call(node.id);
          continue;
        }

        final localSenderAccountIdStr = party.accountId.value;

        final senderPhone = party.phoneNumber ?? '';
        final senderEmail = party.email ?? '';

        // Process Domain Actions Structurally with Signatures
        switch (node.eventType) {
          case SyncEventType.claim:
            await _inboundVoucherClaim(
              decryptedRawPayload,
              node.id,
              localSenderAccountIdStr,
            );
            break;
          case SyncEventType.acceptance:
            await _inboundVoucherAcceptance(
              decryptedRawPayload,
              decryptionKeyHexUsed ?? decryptKeys.first,
              senderPhone,
              senderEmail,
              node.id,
              localSenderAccountIdStr,
            );
            break;
          case SyncEventType.rejection:
            await _inboundVoucherRejection(
              decryptedRawPayload,
              node.id,
              localSenderAccountIdStr,
            );
            break;
          case SyncEventType.journalEntry:
            await _inboundJournalEntryMirrored(decryptedRawPayload);
            break;
          case SyncEventType.attachmentSync:
            await _inboundAttachmentSync(decryptedRawPayload);
            break;
          case SyncEventType.collateralSync:
            await _inboundCollateralSync(decryptedRawPayload);
            break;
          case SyncEventType.collateralUpdate:
            await _inboundCollateralRevaluation(decryptedRawPayload);
            break;
          case SyncEventType.withdrawal:
            await _inboundVoucherWithdrawal(
              decryptedRawPayload,
              node.id,
              localSenderAccountIdStr,
            );
            break;
          case SyncEventType.settlement:
            await _inboundVoucherSettlement(
              decryptedRawPayload,
              node.id,
              localSenderAccountIdStr,
            );
            break;
          case SyncEventType.auditBatch:
            final applied = await _inboundAuditBatch(decryptedRawPayload);
            if (!applied) {
              debugPrint(
                'Sync: Skipping ack for SyncNode [${node.id}]: '
                'audit batch produced no local changes.',
              );
              continue;
            }
            break;
          case SyncEventType.credentialBootstrap:
            // Bootstrap is consumed in pre-auth companion flow.
            break;
          case SyncEventType.p2pHandshake:
            // P2P handshake is handled at the transport layer, not here.
            debugPrint(
              'P2P Handshake event received — delegating to P2P service.',
            );
            break;
          case SyncEventType.tripartiteRequest:
            await _inboundTripartiteRequest(
              decryptedRawPayload,
              localSenderAccountIdStr,
              node.id,
            );
            break;
          case SyncEventType.posCreditInvoice:
            final applied = await _inboundPosCreditInvoice(
              decryptedRawPayload,
              node.id,
              localSenderAccountIdStr,
            );
            if (!applied) continue;
            break;
          case SyncEventType.posCreditInvoiceAcknowledgment:
            final applied = await _inboundPosCreditInvoiceAcknowledgment(
              decryptedRawPayload,
              node.id,
              localSenderAccountIdStr,
              decryptionKeyHexUsed ?? decryptKeys.first,
            );
            if (!applied) continue;
            break;
          case SyncEventType.unknown:
            debugPrint('Warning: Unknown event type in SyncNode [${node.id}]');
            continue;
        }
        appliedIds.add(node.id);
      } catch (e) {
        debugPrint('Security Pipeline Failure for SyncNode [${node.id}]: $e');
      }
    }
    return appliedIds;
  }

  Future<bool> _inboundPosCreditInvoice(
    Map<String, dynamic> payload,
    String nodeId,
    String senderAccountId,
  ) async {
    try {
      final snapshot = PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
        payload,
        expectedNodeId: nodeId,
      );
      final existing = await notificationMessageRepository.findById(nodeId);
      if (existing != null) {
        if (existing.channel != PosCreditInvoiceChatProtocol.incomingChannel ||
            existing.counterpartyAccountId != senderAccountId) {
          return false;
        }
        final prior = PosCreditInvoiceChatProtocol.decodePayload(
          existing.rawPayloadJson,
        );
        final priorSnapshot =
            PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
              prior,
              expectedNodeId: nodeId,
            );
        final priorPdfSha256 =
            PosCreditInvoiceChatProtocol.pdfSha256FromEventPayload(
              prior,
              expectedInvoiceFingerprint: priorSnapshot.fingerprint,
            );
        final incomingPdfSha256 =
            PosCreditInvoiceChatProtocol.pdfSha256FromEventPayload(
              payload,
              expectedInvoiceFingerprint: snapshot.fingerprint,
            );
        final matchesPrior =
            priorSnapshot.invoiceId == snapshot.invoiceId &&
            priorSnapshot.fingerprint == snapshot.fingerprint &&
            priorPdfSha256 == incomingPdfSha256;
        if (!matchesPrior) return false;
        await recordPosCreditInvoiceAudit(
          auditLogService: auditLogService,
          action: AuditAction.update,
          requestNodeId: nodeId,
          eventId: nodeId,
          invoiceId: snapshot.invoiceId,
          partyAccountId: senderAccountId,
          fingerprint: snapshot.fingerprint,
          pdfSha256: incomingPdfSha256,
          event: 'invoice_received',
          result: 'duplicate_verified',
        );
        return true;
      }

      final localPayload = PosCreditInvoiceChatProtocol.localInvoicePayload(
        eventPayload: payload,
        acknowledgementStatus: 'pending',
        deliveryStatus: 'received',
      );
      final inserted = await notificationMessageRepository.insert(
        id: nodeId,
        bodyText:
            '${AppStrings.posCreditInvoiceChatTitle} #${snapshot.invoiceNumber}',
        channel: PosCreditInvoiceChatProtocol.incomingChannel,
        counterpartyAccountId: senderAccountId,
        createdAtIso: snapshot.postedAt.toUtc().toIso8601String(),
        rawPayloadJson: jsonEncode(localPayload),
      );
      if (!inserted.isSuccess) return false;
      await recordPosCreditInvoiceAudit(
        auditLogService: auditLogService,
        action: AuditAction.create,
        requestNodeId: nodeId,
        eventId: nodeId,
        invoiceId: snapshot.invoiceId,
        partyAccountId: senderAccountId,
        fingerprint: snapshot.fingerprint,
        pdfSha256: PosCreditInvoiceChatProtocol.pdfSha256FromEventPayload(
          payload,
          expectedInvoiceFingerprint: snapshot.fingerprint,
        ),
        event: 'invoice_received',
        result: 'stored',
      );
      return true;
    } catch (error) {
      debugPrint('Rejected invalid POS credit invoice event [$nodeId]: $error');
      return false;
    }
  }

  Future<bool> _inboundPosCreditInvoiceAcknowledgment(
    Map<String, dynamic> payload,
    String acknowledgementNodeId,
    String senderAccountId,
    String senderPublicKeyHex,
  ) async {
    try {
      final invoiceNodeIdValue = payload['invoice_node_id'];
      if (invoiceNodeIdValue is! String ||
          !PosCreditInvoiceChatProtocol.isValidAcknowledgmentEventPayload(
            payload,
            expectedNodeId: invoiceNodeIdValue,
          )) {
        return false;
      }
      final invoiceNodeId = invoiceNodeIdValue;
      final invoiceId = payload['invoice_id'] as String;
      final fingerprint = payload['fingerprint'] as String;
      final pdfSha256 = payload['pdf_sha256'] as String;
      final status = payload['status'] as String;
      final respondedAt = payload['responded_at'] as String;
      final signature = DigitalSignature.fromHex(
        signatureHex: payload['signature_hex'] as String,
        signerPublicKeyHex: payload['signer_public_key_hex'] as String,
        payloadHashHex: payload['payload_hash_hex'] as String,
      );
      if (signature.signerPublicKeyHex != senderPublicKeyHex.toLowerCase() ||
          !signingService.verifyRaw(
            signatureBytes: signature.signatureBytes,
            payloadHash: signature.payloadHash,
            publicKey: signature.signerPublicKey,
          )) {
        return false;
      }
      if (PosCreditInvoiceChatProtocol.acknowledgementNodeId(
            invoiceNodeId,
            fingerprint,
          ) !=
          acknowledgementNodeId) {
        return false;
      }

      final outgoing = await notificationMessageRepository.findById(
        invoiceNodeId,
      );
      if (outgoing == null ||
          outgoing.channel != PosCreditInvoiceChatProtocol.outgoingChannel ||
          outgoing.counterpartyAccountId != senderAccountId) {
        return false;
      }
      var latest = outgoing;
      for (var attempt = 0; attempt < 3; attempt++) {
        final localPayload = PosCreditInvoiceChatProtocol.decodePayload(
          latest.rawPayloadJson,
        );
        final snapshot = PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
          localPayload,
          expectedNodeId: invoiceNodeId,
        );
        if (snapshot.invoiceId != invoiceId ||
            snapshot.fingerprint != fingerprint ||
            PosCreditInvoiceChatProtocol.pdfSha256FromEventPayload(
                  localPayload,
                  expectedInvoiceFingerprint: fingerprint,
                ) !=
                pdfSha256) {
          return false;
        }
        final currentStatus =
            localPayload['acknowledgment_status'] as String? ?? 'pending';
        if (currentStatus == status) {
          return localPayload['acknowledgment_node_id'] ==
              acknowledgementNodeId;
        }
        if (currentStatus != 'pending') return false;

        localPayload['acknowledgment_status'] = status;
        localPayload['acknowledgment_received_at'] = DateTime.parse(
          respondedAt,
        ).toUtc().toIso8601String();
        localPayload['acknowledgment_node_id'] = acknowledgementNodeId;
        final updated = await notificationMessageRepository
            .updateBodyAndPayloadIfUnchanged(
              id: latest.id,
              expectedRawPayloadJson: latest.rawPayloadJson!,
              bodyText: status == 'accepted'
                  ? AppStrings.posCreditInvoiceAccepted
                  : AppStrings.posCreditInvoiceRejected,
              rawPayloadJson: jsonEncode(localPayload),
            );
        if (!updated.isSuccess) return false;
        if (updated.valueOrNull == true) {
          await recordPosCreditInvoiceAudit(
            auditLogService: auditLogService,
            action: AuditAction.update,
            requestNodeId: invoiceNodeId,
            eventId: acknowledgementNodeId,
            invoiceId: invoiceId,
            partyAccountId: senderAccountId,
            fingerprint: fingerprint,
            pdfSha256: pdfSha256,
            signerPublicKeyHex: signature.signerPublicKeyHex,
            event: 'acknowledgment_received',
            result: status,
            occurredAt: DateTime.parse(respondedAt),
          );
          return true;
        }
        final refreshed = await notificationMessageRepository.findById(
          invoiceNodeId,
        );
        if (refreshed == null ||
            refreshed.channel != PosCreditInvoiceChatProtocol.outgoingChannel ||
            refreshed.counterpartyAccountId != senderAccountId) {
          return false;
        }
        latest = refreshed;
      }
      return false;
    } catch (error) {
      debugPrint(
        'Rejected invalid POS credit invoice acknowledgment '
        '[$acknowledgementNodeId]: $error',
      );
      return false;
    }
  }

  /// Returns `true` when at least one audit entry was ingested locally.
  Future<bool> _inboundAuditBatch(Map<String, dynamic> payload) async {
    final processor = auditSyncProcessor;
    if (processor == null) return false;

    final encoding = payload['encoding'] as String?;
    final maps = <Map<String, dynamic>>[];
    if (encoding == 'gzip+base64') {
      final encoded = payload['entries_gzip'] as String?;
      if (encoded == null || encoded.isEmpty) return false;
      final unzipped = gzip.decode(base64Decode(encoded));
      final decoded = jsonDecode(utf8.decode(unzipped)) as List<dynamic>;
      maps.addAll(
        decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
    } else {
      final entries = payload['entries'] as List<dynamic>? ?? const [];
      maps.addAll(
        entries.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
    }
    if (maps.isEmpty) return false;
    await processor.processBatch(maps);

    final batchIndex = payload['batch_index'] as int?;
    final totalBatches = payload['total_batches'] as int?;
    if (batchIndex != null && totalBatches != null) {
      await InjectionContainer.licenseVault.writeInitialSyncProgress(
        batchIndex,
        totalBatches,
      );
    }

    final isLastBatch = payload['is_last_batch'] == true;
    if (isLastBatch) {
      debugPrint(
        'SyncPayloadProcessor: Received last batch of initial snapshot.',
      );
      await InjectionContainer.licenseVault.markInitialSyncComplete();
    }
    return true;
  }

  Future<void> _inboundVoucherClaim(
    Map<String, dynamic> payload,
    String nodeId,
    String senderId,
  ) async {
    // Protocol §5 — Inbound Voucher Claim Processing.
    final String? voucherIdStr = payload['voucher_id'] as String?;
    if (voucherIdStr == null) return;

    // 1. Idempotency Guard
    final existingResult = await voucherRepository.getById(
      VoucherId(voucherIdStr),
    );
    if (existingResult.isSuccess && existingResult.valueOrNull != null) return;

    // 2. Flip Logic: From their perspective to ours.
    final typeStr = payload['type'] as String? ?? 'receipt';
    // If they sent a Receipt (they got money), for us it is a Payment (we gave money).
    final myType = typeStr == 'receipt'
        ? VoucherType.payment
        : VoucherType.receipt;

    final amountMinor = payload['amount_minor'] as int? ?? 0;
    final currencyCode = payload['currency_code'] as String? ?? 'YER';
    final date =
        DateTime.tryParse(payload['date'] as String? ?? '') ?? DateTime.now();

    // 3. Counterparty mapping: The one who sent the sync node is our counterparty.
    // (Sender ID is handled in the caller processIncomingNodes, but we need the AccountId here)
    // For now, we rely on the payload's counterparty mapping if available,
    // but better to resolve from the Node's sender.
    // In our system, the sender of the claim IS the counterparty.
    final senderParty = await accountRepository.findAccountByPhone(
      payload['signer_phone'] ?? '',
    );
    final counterpartyId =
        senderParty.valueOrNull ?? AccountId(payload['counterparty_id'] ?? '');

    // 4. Affected Account mapping: For inbound claims, our default fund is usually affected.
    final allAccounts = await accountRepository.getAll();
    final myFund = allAccounts.valueOrNull?.firstWhere(
      (a) => a.classification.standardKind?.name == 'liquidAssets',
      orElse: () => allAccounts.valueOrNull!.first,
    );
    final affectedAccountId = myFund?.id ?? AccountId('default-fund');

    // 5. Currency Lookup
    final currencyResult = await currencyRepository.getByCode(currencyCode);
    final currency = currencyResult.valueOrNull!;

    // 6. Entity Reconstruction
    final tripartiteData = payload['tripartite_meta'] as Map<String, dynamic>?;
    TripartiteMeta? tripartiteMeta;
    if (tripartiteData != null) {
      tripartiteMeta = TripartiteMeta(
        transferGroupId: tripartiteData['transfer_group_id'] as String? ?? '',
        role:
            TripartiteRole.fromColumnValue(tripartiteData['role'] as String?) ??
            TripartiteRole.intermediaryReceipt,
        linkedPartyId: AccountId(
          tripartiteData['linked_party_id'] as String? ?? '',
        ),
        mediatorAccountId: tripartiteData['mediator_account_id'] != null
            ? AccountId(tripartiteData['mediator_account_id'] as String)
            : null,
        isContingent: tripartiteData['is_contingent'] as bool? ?? false,
      );
    }

    final voucher = Voucher.restore(
      id: VoucherId(voucherIdStr),
      type: myType,
      date: date,
      amount: Money.positiveAmount(amountMinor, currency),
      currency: currency,
      counterpartyId: counterpartyId,
      affectedAccountId: affectedAccountId,
      state: VoucherState
          .draft, // Inbound claims are always drafts until WE accept them.
      createdAt: DateTime.now(),
      description: payload['description'],
      referenceNumber: payload['reference_number'],
      senderStatus: AgreementStatus.accepted, // They signed it.
      receiverStatus: AgreementStatus.underRequest, // We haven't.
      senderSignatureHex: payload['sender_signature_hex'],
      senderPublicKeyHex: payload['sender_public_key_hex'],
      signerPhone: payload['signer_phone'],
      // v2.1: record canonical phones when available from sync payload.
      canonicalSenderPhone:
          payload['canonical_sender_phone'] as String? ??
          payload['signer_phone'] as String?,
      canonicalReceiverPhone: payload['canonical_receiver_phone'] as String?,
      originVoucherId: payload['origin_voucher_id'] != null
          ? VoucherId(payload['origin_voucher_id'])
          : null,
      tripartiteMeta: tripartiteMeta,
      // §5 Protocol: This voucher was created by the counterparty and pushed
      // to us.  Mark it so the chat UI can correctly compute [isCreator = false]
      // regardless of which account happens to own affectedAccountId.
      isInbound: true,
    );

    // 7. Persist
    await voucherRepository.save(voucher);
    await auditLogService?.log(
      actorId: 'sync:$senderId',
      entityType: 'voucher',
      entityId: voucher.id.value,
      action: AuditAction.create,
      severity: AuditSeverity.info,
      newData: {
        'id': voucher.id.value,
        'state': voucher.state.name,
        'type': voucher.type.name,
        'date': voucher.date.toIso8601String(),
      },
    );
    debugPrint('VoucherClaim [$voucherIdStr]: Ingested and stored as $myType.');

    // 7.5. §5.E: Extract and persist attachment metadata + per-attachment AES keys.
    // The blob files are NOT downloaded here — that happens via a background
    // download queue (attachmentSync event or on-demand). We store the metadata
    // and key now so the UI can show placeholders and decrypt blobs once downloaded.
    final attachmentsList = payload['attachments'] as List<dynamic>?;
    if (attachmentsList != null && attachmentsList.isNotEmpty) {
      final voucherId = VoucherId(voucherIdStr);
      final mappedAttachments = attachmentsList.map((dynamic a) {
        final map = a as Map<String, dynamic>;
        return VoucherAttachment(
          id: AttachmentId(map['id'] as String? ?? const Uuid().v4()),
          voucherId: voucherId,
          fileName: map['file_name'] as String? ?? 'attachment.jpg',
          // Empty path = not yet downloaded; AttachmentStorageService will
          // handle path resolution after the blob is downloaded.
          storagePath: '',
          encryptedBlobHash: map['encrypted_blob_hash'] as String? ?? '',
          mimeType: map['mime_type'] as String? ?? 'image/jpeg',
          byteSize: map['byte_size'] as int? ?? 0,
          sourceType: AttachmentSourceType.gallery,
          createdAt: DateTime.now(),
          // §5.E: per-attachment decryption key from the sender's payload.
          attachmentKeyHex: map['attachment_key_hex'] as String?,
        );
      }).toList();

      if (mappedAttachments.isNotEmpty) {
        await attachmentRepository.saveAll(mappedAttachments);
        debugPrint(
          'VoucherClaim [$voucherIdStr]: saved ${mappedAttachments.length} attachment record(s) with keys.',
        );
      }
    }

    // 8. Reciprocal Matching (Conflict Detection)
    // We always create a notification for a new claim, but customize it if it's a conflict.
    final reciprocalResult = await voucherRepository.findReciprocalMatch(
      amountMinor: amountMinor,
      currencyCode: currencyCode,
      counterpartyAccountId: counterpartyId.value,
      type: myType.name,
      referenceDate: date,
    );

    String bodyText = AppStrings.newVoucherClaim(
      (amountMinor / 100).toString(),
      currencyCode,
    );
    String channel = 'voucher_event';

    if (reciprocalResult.isSuccess && reciprocalResult.valueOrNull != null) {
      final localMatch = reciprocalResult.valueOrNull!;
      bodyText = AppStrings.matchingBondWouldYou;
      channel = 'conflict';

      // We still use voucher_event as base but keep the conflict logic
      if (notificationFilterService.isPeerActivityEnabled) {
        await notificationMessageRepository.insert(
          id: nodeId, // Use the sync node ID to prevent duplicates
          bodyText: bodyText,
          counterpartyAccountId: counterpartyId.value,
          createdAtIso: DateTime.now().toIso8601String(),
          channel: channel,
          rawPayloadJson: json.encode({
            'event_type': 'claim',
            'voucher_id': voucherIdStr,
            'local_voucher_id': localMatch.id.value,
            'inbound_payload': payload,
            'has_tripartite_meta': tripartiteMeta != null,
          }),
        );
      }
    } else {
      if (notificationFilterService.isPeerActivityEnabled) {
        await notificationMessageRepository.insert(
          id: nodeId,
          bodyText: bodyText,
          counterpartyAccountId: counterpartyId.value,
          createdAtIso: DateTime.now().toIso8601String(),
          channel: channel,
          rawPayloadJson: json.encode({
            'event_type': 'claim',
            'voucher_id': voucherIdStr,
            'inbound_payload': payload,
            'has_tripartite_meta': tripartiteMeta != null,
          }),
        );
      }
    }
  }

  Future<void> _inboundVoucherAcceptance(
    Map<String, dynamic> payload,
    String senderPublicKey,
    String senderPhone,
    String senderEmail,
    String nodeId,
    String senderId,
  ) async {
    final String voucherIdStr = payload['voucher_id'];
    final String receiverSignatureHex = payload['receiver_signature_hex'];

    final voucherResult = await voucherRepository.getById(
      VoucherId(voucherIdStr),
    );
    if (voucherResult.isFailure || voucherResult.valueOrNull == null) return;
    final draft = voucherResult.valueOrNull!;

    // Resolve current user's phone for canonical payload construction.
    final myPartyResult = await accountRepository.getPartyDetails(
      draft.affectedAccountId,
    );
    final myPhone = myPartyResult.valueOrNull?.phoneNumber ?? '';

    // Build canonical payload for signature verification.
    final signable = SignableReceipt(
      amountMinor: draft.amount.minorUnits,
      currencyCode: draft.currency.code,
      senderPhone: myPhone,
      receiverPhone: senderPhone,
      dateIso: draft.date.toIso8601String().split('T').first,
      receiptUuid: draft.id.value,
    );

    final payloadHash = signingService.hashPayload(signable.canonicalPayload);
    final Uint8List signatureBytes = _hexToBytes(receiverSignatureHex);

    // ── Protocol §5: Cross-Vector Key-List Verification ──────────────────
    // Build the full list of keys to try: claimed key first, then
    // any known historical keys for this sender.
    final keysToTry = <String>[senderPublicKey];

    // Fetch local party details for the sender to get historical keys.
    var senderAccountResult = await accountRepository.findAccountByPhone(
      senderPhone,
    );
    if (senderAccountResult.valueOrNull == null && senderEmail.isNotEmpty) {
      senderAccountResult = await accountRepository.findAccountByEmail(
        senderEmail,
      );
    }

    final senderAccountId = senderAccountResult.valueOrNull;
    if (senderAccountId != null) {
      final senderParty = await accountRepository.getPartyDetails(
        senderAccountId,
      );
      final party = senderParty.valueOrNull;
      if (party != null) {
        for (final histKey in party.allAuthorizedKeys) {
          if (!keysToTry.contains(histKey)) {
            keysToTry.add(histKey);
          }
        }
      }
    }

    // If no local keys beyond the claimed one, try server lookup.
    if (keysToTry.length == 1) {
      PublicKeyLookupResult? serverResult;
      if (senderPhone.isNotEmpty) {
        serverResult = await identityRepository.lookupByPhone(
          phone: senderPhone,
        );
      }
      if (serverResult == null && senderEmail.isNotEmpty) {
        serverResult = await identityRepository.lookupByEmail(
          email: senderEmail,
        );
      }
      if (serverResult != null) {
        for (final key in serverResult.allAuthorizedKeys) {
          if (!keysToTry.contains(key)) {
            keysToTry.add(key);
          }
        }
      }
    }

    // Iterate through all known keys (current + historical).
    bool verified = false;
    String? matchedKey;
    for (final keyHex in keysToTry) {
      try {
        final pubKeyBytes = _hexToBytes(keyHex);
        final isValid = signingService.verifyRaw(
          signatureBytes: signatureBytes,
          payloadHash: payloadHash,
          publicKey: pubKeyBytes,
        );
        if (isValid) {
          verified = true;
          matchedKey = keyHex;
          break;
        }
      } catch (_) {
        // Invalid key format — skip.
        continue;
      }
    }

    if (verified) {
      // §5.5 Success: Mutual digital signature achieved.
      final signedVoucher = draft.attachSignature(
        signatureHex: receiverSignatureHex,
        publicKeyHex: matchedKey!,
        isSender: false, // The counterparty (receiver) signed.
        status: AgreementStatus.accepted,
        signerPhone: senderPhone,
        // Freeze canonical phones: myPhone = A (original sender), senderPhone = B (acceptor).
        canonicalSenderPhone: myPhone,
        canonicalReceiverPhone: senderPhone,
      );
      await voucherRepository.save(signedVoucher);
      await auditLogService?.log(
        actorId: 'sync:$senderId',
        entityType: 'voucher',
        entityId: signedVoucher.id.value,
        action: AuditAction.update,
        severity: AuditSeverity.info,
        oldData: {
          'id': draft.id.value,
          'receiver_status': draft.receiverStatus.name,
        },
        newData: {
          'id': signedVoucher.id.value,
          'receiver_status': signedVoucher.receiverStatus.name,
        },
      );
      debugPrint(
        'Voucher [$voucherIdStr] accepted — verified with key ${matchedKey.substring(0, 8)}…',
      );

      // Create notification for acceptance
      if (notificationFilterService.isPeerActivityEnabled) {
        await notificationMessageRepository.insert(
          id: nodeId,
          bodyText: AppStrings.theBondIsApproved,
          counterpartyAccountId: senderId,
          createdAtIso: DateTime.now().toIso8601String(),
          channel: 'voucher_event',
          rawPayloadJson: json.encode({
            'event_type': 'acceptance',
            'voucher_id': voucherIdStr,
          }),
        );
      }
    } else {
      // §5.6 Failure: Suspended as unapproved claim.
      final suspendedVoucher = draft.attachSignature(
        signatureHex: receiverSignatureHex,
        publicKeyHex: senderPublicKey,
        isSender: false, // The counterparty (receiver) signed poorly.
        status: AgreementStatus.unverified,
        signerPhone: senderPhone,
      );
      await voucherRepository.save(suspendedVoucher);
      await auditLogService?.log(
        actorId: 'sync:$senderId',
        entityType: 'voucher',
        entityId: suspendedVoucher.id.value,
        action: AuditAction.update,
        severity: AuditSeverity.warning,
        oldData: {
          'id': draft.id.value,
          'receiver_status': draft.receiverStatus.name,
        },
        newData: {
          'id': suspendedVoucher.id.value,
          'receiver_status': suspendedVoucher.receiverStatus.name,
        },
      );
      debugPrint(
        'SECURITY: Voucher [$voucherIdStr] SUSPENDED — '
        'signature mismatch across ${keysToTry.length} key(s).',
      );
    }
  }

  Future<void> _inboundVoucherRejection(
    Map<String, dynamic> payload,
    String nodeId,
    String senderId,
  ) async {
    final String voucherIdStr = payload['voucher_id'];
    final voucherResult = await voucherRepository.getById(
      VoucherId(voucherIdStr),
    );
    if (voucherResult.isFailure || voucherResult.valueOrNull == null) return;

    final rejectedVoucher = voucherResult.valueOrNull!.attachRejection(
      reason: payload['rejection_reason'] as String? ?? '',
      status: AgreementStatus.rejected,
    );
    await voucherRepository.save(rejectedVoucher);
    await auditLogService?.log(
      actorId: 'sync:$senderId',
      entityType: 'voucher',
      entityId: rejectedVoucher.id.value,
      action: AuditAction.update,
      severity: AuditSeverity.warning,
      newData: {
        'id': rejectedVoucher.id.value,
        'receiver_status': rejectedVoucher.receiverStatus.name,
      },
    );

    // Create notification for rejection
    if (notificationFilterService.isPeerActivityEnabled) {
      await notificationMessageRepository.insert(
        id: nodeId,
        bodyText: AppStrings.voucherRejectedWithReason(
          payload['rejection_reason'] ?? '',
        ),
        counterpartyAccountId: senderId,
        createdAtIso: DateTime.now().toIso8601String(),
        channel: 'voucher_event',
        rawPayloadJson: json.encode({
          'event_type': 'rejection',
          'voucher_id': voucherIdStr,
          'reason': payload['rejection_reason'],
        }),
      );
    }
  }

  Future<void> _inboundJournalEntryMirrored(
    Map<String, dynamic> payload,
  ) async {
    // Secure generation of isolated dual-entry mirror ...
  }

  Future<void> _inboundAttachmentSync(Map<String, dynamic> payload) async {
    final voucherIdStr = payload['voucher_id'] as String?;
    if (voucherIdStr == null) {
      debugPrint('AttachmentSync: missing voucher_id');
      return;
    }

    final attachments = payload['attachments'] as List<dynamic>? ?? [];
    debugPrint(
      'AttachmentSync: received ${attachments.length} attachment(s) for voucher $voucherIdStr',
    );

    final voucherId = VoucherId(voucherIdStr);

    final mappedAttachments = attachments.map((dynamic a) {
      final map = a as Map<String, dynamic>;
      return VoucherAttachment(
        id: AttachmentId(map['id'] as String? ?? const Uuid().v4()),
        voucherId: voucherId,
        fileName: map['file_name'] as String? ?? 'attachment.jpg',
        storagePath: '', // populated after blob download
        encryptedBlobHash:
            map['encrypted_blob_hash'] as String? ??
            map['blob_hash'] as String? ??
            '',
        mimeType: map['mime_type'] as String? ?? 'image/jpeg',
        byteSize: map['byte_size'] as int? ?? 0,
        sourceType: AttachmentSourceType.gallery,
        createdAt: DateTime.now(),
        // §5.E: per-attachment AES key sent inside the E2EE payload.
        attachmentKeyHex: map['attachment_key_hex'] as String?,
      );
    }).toList();

    if (mappedAttachments.isNotEmpty) {
      await attachmentRepository.saveAll(mappedAttachments);
      for (final attachment in mappedAttachments) {
        await auditLogService?.log(
          actorId: 'sync:remote',
          entityType: 'attachment',
          entityId: attachment.id.value,
          action: AuditAction.create,
          severity: AuditSeverity.info,
          newData: {
            'id': attachment.id.value,
            'voucher_id': attachment.voucherId.value,
          },
        );
      }
      debugPrint(
        'AttachmentSync [$voucherIdStr]: saved ${mappedAttachments.length} attachment record(s) with keys.',
      );
    }

    // Blob downloading happens via on-demand decryption in AttachmentFileOpener.
  }

  Future<void> _inboundCollateralSync(Map<String, dynamic> payload) async {
    final voucherIdStr = payload['voucher_id'] as String?;
    final collateralData = payload['collateral'] as Map<String, dynamic>?;
    if (voucherIdStr == null || collateralData == null) {
      debugPrint('CollateralSync: missing voucher_id or collateral data');
      return;
    }
    debugPrint('CollateralSync: received collateral for voucher $voucherIdStr');

    final collateralIdStr =
        collateralData['id'] as String? ?? const Uuid().v4();
    final valueMinor = collateralData['value_minor'] as int? ?? 0;
    final currencyCode = collateralData['currency_code'] as String? ?? 'USD';
    final statusStr = collateralData['status'] as String? ?? 'active';
    final expiryIso = collateralData['expiry_date'] as String?;
    // Note: description normally comes decrypted here from processing pipeline
    final description =
        collateralData['description'] as String? ?? 'Collateral item';

    final currencyObj = CurrencyCode(
      code: currencyCode,
      nameAr: currencyCode,
      symbol: currencyCode,
      fractionalDigits: 2,
    );

    final collateral = Collateral(
      id: CollateralId(collateralIdStr),
      voucherId: VoucherId(voucherIdStr),
      description: description,
      estimatedValue: valueMinor > 0
          ? Money.positiveAmount(valueMinor, currencyObj)
          : Money.zero(currencyObj),
      currency: currencyObj,
      status: CollateralStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => CollateralStatus.active,
      ),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      expiryDate: expiryIso != null ? DateTime.tryParse(expiryIso) : null,
    );

    // Get existing to determine insert vs update
    final existing = await collateralRepository.getById(collateral.id);
    if (existing.isSuccess) {
      await collateralRepository.update(collateral);
      await auditLogService?.log(
        entityType: 'collateral',
        actorId: 'sync:remote',
        entityId: collateral.id.value,
        action: AuditAction.update,
        severity: AuditSeverity.info,
        newData: {'id': collateral.id.value, 'status': collateral.status.name},
      );
    } else {
      await collateralRepository.save(collateral);
      await auditLogService?.log(
        entityType: 'collateral',
        actorId: 'sync:remote',
        entityId: collateral.id.value,
        action: AuditAction.create,
        severity: AuditSeverity.info,
        newData: {'id': collateral.id.value, 'status': collateral.status.name},
      );
    }

    // §5.E: Extract and persist collateral image refs + per-image AES keys.
    final imageRefsList = collateralData['image_refs'] as List<dynamic>?;
    if (imageRefsList != null && imageRefsList.isNotEmpty) {
      final voucherId = VoucherId(voucherIdStr);
      final imageAttachments = imageRefsList.map((dynamic img) {
        final map = img as Map<String, dynamic>;
        return VoucherAttachment(
          id: AttachmentId(map['id'] as String? ?? const Uuid().v4()),
          voucherId: voucherId,
          fileName: 'collateral_${map['id']}.jpg',
          storagePath: '', // not downloaded yet
          encryptedBlobHash: map['encrypted_blob_hash'] as String? ?? '',
          mimeType: map['mime_type'] as String? ?? 'image/jpeg',
          byteSize: map['byte_size'] as int? ?? 0,
          sourceType: AttachmentSourceType.gallery,
          createdAt: DateTime.now(),
          // §5.E: per-image decryption key from the sender's payload.
          attachmentKeyHex: map['attachment_key_hex'] as String?,
        );
      }).toList();

      await attachmentRepository.saveAll(imageAttachments);
      for (final attachment in imageAttachments) {
        await auditLogService?.log(
          actorId: 'sync:remote',
          entityType: 'attachment',
          entityId: attachment.id.value,
          action: AuditAction.create,
          severity: AuditSeverity.info,
          newData: {
            'id': attachment.id.value,
            'voucher_id': attachment.voucherId.value,
          },
        );
      }
      debugPrint(
        'CollateralSync [$voucherIdStr]: saved ${imageAttachments.length} image record(s) with keys.',
      );
    }
  }

  Future<void> _inboundCollateralRevaluation(
    Map<String, dynamic> payload,
  ) async {
    final collateralIdStr = payload['collateral_id'] as String?;
    if (collateralIdStr == null) {
      debugPrint('CollateralRevaluation: missing collateral_id');
      return;
    }
    debugPrint(
      'CollateralRevaluation: received update for collateral $collateralIdStr',
    );

    final collateralId = CollateralId(collateralIdStr);
    final existingR = await collateralRepository.getById(collateralId);
    if (existingR.isFailure) return;

    final existing = existingR.valueOrNull!;

    final newMinor = payload['new_value_minor'] as int?;
    final newExpiryStr = payload['new_expiry'] as String?;
    final reason = payload['reason'] as String? ?? 'Remote update';

    final revalAudit = CollateralRevaluation(
      id: const Uuid().v4(),
      collateralId: collateralId,
      oldValueMinor: existing.estimatedValue.minorUnits,
      newValueMinor: newMinor ?? existing.estimatedValue.minorUnits,
      oldExpiryDate: existing.expiryDate,
      newExpiryDate: newExpiryStr != null
          ? DateTime.tryParse(newExpiryStr)
          : existing.expiryDate,
      reason: reason,
      evaluatedAt: DateTime.now(),
    );

    final updated = existing.revaluate(
      newValue: newMinor != null
          ? (newMinor > 0
                ? Money.positiveAmount(newMinor, existing.currency)
                : Money.zero(existing.currency))
          : null,
      newExpiryDate: newExpiryStr != null
          ? DateTime.tryParse(newExpiryStr)
          : null,
    );

    await collateralRepository.update(updated);
    await collateralRepository.saveRevaluation(revalAudit);
    await auditLogService?.log(
      entityType: 'collateral',
      actorId: 'sync:remote',
      entityId: updated.id.value,
      action: AuditAction.update,
      severity: AuditSeverity.info,
      newData: {'id': updated.id.value, 'status': updated.status.name},
    );
  }

  // ── Threaded Financial Interactions handlers ──────────────────────────

  Future<void> _inboundVoucherWithdrawal(
    Map<String, dynamic> payload,
    String nodeId,
    String senderId,
  ) async {
    final String? voucherIdStr = payload['voucher_id'] as String?;
    if (voucherIdStr == null) {
      debugPrint('VoucherWithdrawal: missing voucher_id');
      return;
    }

    final voucherResult = await voucherRepository.getById(
      VoucherId(voucherIdStr),
    );
    if (voucherResult.isFailure || voucherResult.valueOrNull == null) {
      debugPrint(
        'VoucherWithdrawal [$voucherIdStr]: voucher not found locally.',
      );
      return;
    }

    final voucher = voucherResult.valueOrNull!;

    // ── Protocol Guard: Prevent Withdrawal if Already Accepted ────────────────
    // If the voucher has already been accepted by both parties, we drop the
    // withdrawal request silently to prevent state corruption across nodes.
    if (voucher.receiverStatus == AgreementStatus.accepted ||
        voucher.state.isSettled) {
      debugPrint(
        'VoucherWithdrawal [$voucherIdStr]: Dropped silently because the '
        'voucher is already fully accepted or settled.',
      );
      return;
    }

    // Protocol §2.A: A withdrawal is only valid if we (the receiver) haven't accepted it yet.
    if (voucher.state.isDraft &&
        voucher.receiverStatus != AgreementStatus.accepted) {
      // Withdraw the local copy
      final withdrawn = voucher.withdraw(DateTime.now());
      await voucherRepository.save(withdrawn);
      await auditLogService?.log(
        actorId: 'sync:$senderId',
        entityType: 'voucher',
        entityId: withdrawn.id.value,
        action: AuditAction.update,
        severity: AuditSeverity.warning,
        oldData: {'id': voucher.id.value, 'state': voucher.state.name},
        newData: {'id': withdrawn.id.value, 'state': withdrawn.state.name},
      );
      debugPrint('VoucherWithdrawal [$voucherIdStr]: local copy withdrawn.');

      // Create notification for withdrawal
      if (notificationFilterService.isPeerActivityEnabled) {
        await notificationMessageRepository.insert(
          id: nodeId,
          bodyText: AppStrings.theBondIsWithdrawn,
          counterpartyAccountId: senderId,
          createdAtIso: DateTime.now().toIso8601String(),
          channel: 'voucher_event',
          rawPayloadJson: json.encode({
            'event_type': 'withdrawal',
            'voucher_id': voucherIdStr,
          }),
        );
      }
    } else {
      debugPrint(
        'VoucherWithdrawal [$voucherIdStr]: cannot withdraw — '
        'current state is ${voucher.state.name}.',
      );
    }
  }

  Future<void> _inboundVoucherSettlement(
    Map<String, dynamic> payload,
    String nodeId,
    String senderId,
  ) async {
    final String? voucherIdStr = payload['voucher_id'] as String?;
    if (voucherIdStr == null) {
      debugPrint('VoucherSettlement: missing voucher_id');
      return;
    }

    final voucherResult = await voucherRepository.getById(
      VoucherId(voucherIdStr),
    );
    if (voucherResult.isFailure || voucherResult.valueOrNull == null) {
      debugPrint(
        'VoucherSettlement [$voucherIdStr]: voucher not found locally.',
      );
      return;
    }

    final voucher = voucherResult.valueOrNull!;
    if (voucher.state.isConfirmed) {
      final settled = voucher.settle(DateTime.now());
      await voucherRepository.save(settled);
      await auditLogService?.log(
        actorId: 'sync:$senderId',
        entityType: 'voucher',
        entityId: settled.id.value,
        action: AuditAction.update,
        severity: AuditSeverity.info,
        oldData: {'id': voucher.id.value, 'state': voucher.state.name},
        newData: {'id': settled.id.value, 'state': settled.state.name},
      );
      debugPrint('VoucherSettlement [$voucherIdStr]: marked as settled.');

      // Create notification for settlement
      if (notificationFilterService.isPeerActivityEnabled) {
        await notificationMessageRepository.insert(
          id: nodeId,
          bodyText: AppStrings.theBondHasBeen1,
          counterpartyAccountId: senderId,
          createdAtIso: DateTime.now().toIso8601String(),
          channel: 'voucher_event',
          rawPayloadJson: json.encode({
            'event_type': 'settlement',
            'voucher_id': voucherIdStr,
          }),
        );
      }
    } else {
      debugPrint(
        'VoucherSettlement [$voucherIdStr]: cannot settle — '
        'current state is ${voucher.state.name}.',
      );
    }
  }

  Future<void> _inboundTripartiteRequest(
    Map<String, dynamic> payload,
    String senderId,
    String nodeId,
  ) async {
    // Protocol §5 — Inbound Tripartite Request from Sender (A).
    // The mediator (B) saves this as a notification to allow deep-linking to the creation page.
    final now = DateTime.now();

    // Resolve sender name for the notification UI
    final accountResult = await accountRepository.getById(AccountId(senderId));
    final senderName = accountResult.valueOrNull?.name ?? AppStrings.sender1;

    if (notificationFilterService.isPeerActivityEnabled) {
      await notificationMessageRepository.insert(
        id: nodeId, // Consistent use of sync node ID
        counterpartyAccountId: senderId,
        bodyText: AppStrings.newTripartiteRequestFrom(senderName),
        channel: 'tripartite_event',
        createdAtIso: now.toIso8601String(),
        rawPayloadJson: jsonEncode(payload),
      );
    }

    debugPrint('TripartiteRequest [$senderName -> B]: Ingested and stored.');
  }

  /// Stages a consent-based onboarding request for an unknown sender,
  /// resolving their real registered name from the server identity registry
  /// before persisting the notification so the user sees a meaningful name
  /// rather than a raw phone number or public key fragment.
  Future<void> stagePendingCounterpartyRequest({
    required String nodeId,
    required SyncNode node,
    String? publicKey,
    String? phone,
    String? whatsapp,
  }) async {
    // ── Step 1: Resolve the sender's real name from the server ───────────────
    // Try phone lookup first (fastest), then reverse-lookup by public key.
    // Both are non-fatal: if offline or the sender isn't registered, we fall
    // back gracefully to the phone number / pk fragment as the display ID.
    String? resolvedName;
    String? resolvedPhone = phone;
    String? resolvedWhatsapp = whatsapp;
    String? resolvedPk = publicKey;

    try {
      // ── Primary: use the server-authoritative sender_id FK on the node ──────
      // This bypasses the bidirectional privacy gate on identity/lookup, which
      // can withhold the name even after a successful push. Since the push-time
      // §6 check already passed, the sender has consented to contacting us.
      final nodeResult = await identityRepository.lookupSyncNodeSender(
        nodeId: nodeId,
      );
      if (nodeResult != null && nodeResult.name.isNotEmpty) {
        resolvedName = nodeResult.name;
        resolvedPhone ??= nodeResult.phone.isNotEmpty ? nodeResult.phone : null;
        resolvedWhatsapp ??= nodeResult.whatsappNumber;
        resolvedPk ??= nodeResult.publicKeyHex;
      }

      // ── Fallback 1: phone lookup (covers offline-node scenarios) ────────────
      if (resolvedName == null && phone?.isNotEmpty == true) {
        final result = await identityRepository.lookupByPhone(phone: phone!);
        if (result != null && result.name.isNotEmpty) {
          resolvedName = result.name;
          resolvedPhone ??= result.phone;
          resolvedWhatsapp ??= result.whatsappNumber;
          resolvedPk ??= result.publicKeyHex;
        }
      }

      // ── Fallback 2: reverse public-key lookup ────────────────────────────────
      if (resolvedName == null && publicKey?.isNotEmpty == true) {
        final result = await identityRepository.reverseLookupByPublicKey(
          publicKeyHex: publicKey!,
        );
        if (result != null && result.name.isNotEmpty) {
          resolvedName = result.name;
          resolvedPhone ??= result.phone;
          resolvedWhatsapp ??= result.whatsappNumber;
          resolvedPk ??= result.publicKeyHex ?? publicKey;
        }
      }
    } catch (e) {
      // Network failures are non-fatal; proceed with raw identifiers.
      debugPrint('Sync: Identity lookup failed during staging (non-fatal): $e');
    }

    // ── Step 2: Derive the best display identifier ───────────────────────────
    final displayId =
        resolvedName ??
        resolvedPhone ??
        resolvedWhatsapp ??
        (resolvedPk?.isNotEmpty == true
            ? resolvedPk!.substring(0, 12)
            : nodeId.substring(0, 8));

    // Use a sentinel that won't conflict with real account UUIDs.
    final sentinelId =
        'pending:${resolvedPhone ?? resolvedWhatsapp ?? (resolvedPk?.substring(0, 16) ?? nodeId)}';

    // ── Step 3: Persist the staged request ──────────────────────────────────
    await notificationMessageRepository.insert(
      id: nodeId,
      bodyText: AppStrings.counterpartyOnboardingRequestFrom(displayId),
      channel: 'counterparty_request',
      counterpartyAccountId: sentinelId,
      createdAtIso: DateTime.now().toIso8601String(),
      rawPayloadJson: jsonEncode({
        'node': node.toJson(),
        'sender_phone': resolvedPhone,
        'sender_pk': resolvedPk,
        'sender_whatsapp': resolvedWhatsapp,
        'sender_name': resolvedName, // real name from server (may be null)
      }),
    );

    debugPrint(
      'Sync: Staged counterparty onboarding request for [$displayId] (name: ${resolvedName ?? '—'}), node [$nodeId]',
    );
  }

  /// Called after the user successfully creates a new counterparty account.
  ///
  /// Finds all staged [SyncNode]s that match the provided sender identifiers,
  /// marks them as processed, and re-runs them through [processIncomingNodes]
  /// so the original voucher claims are now applied against the real account.
  Future<void> replayPendingNodesForSender({
    String? phone,
    String? publicKey,
    String? whatsapp,
  }) async {
    final pendingResult = await notificationMessageRepository
        .listPendingCounterpartyRequests();
    if (pendingResult.isFailure) {
      debugPrint(
        'SyncPayloadProcessor: Failed to load pending counterparty requests.',
      );
      return;
    }

    final nodes = <SyncNode>[];
    for (final msg in pendingResult.valueOrNull!) {
      if (msg.rawPayloadJson == null) continue;
      try {
        final raw = jsonDecode(msg.rawPayloadJson!) as Map<String, dynamic>;
        final sPhone = raw['sender_phone'] as String?;
        final sPk = raw['sender_pk'] as String?;
        final sWa = raw['sender_whatsapp'] as String?;

        final matches =
            (phone != null && phone.isNotEmpty && sPhone == phone) ||
            (publicKey != null && publicKey.isNotEmpty && sPk == publicKey) ||
            (whatsapp != null && whatsapp.isNotEmpty && sWa == whatsapp);

        if (!matches) continue;

        final nodeJson = raw['node'] as Map<String, dynamic>?;
        if (nodeJson == null) continue;

        nodes.add(SyncNode.fromJson(nodeJson));
        await notificationMessageRepository.markProcessed(msg.id);
      } catch (e) {
        debugPrint(
          'SyncPayloadProcessor: Failed to parse staged node ${msg.id}: $e',
        );
      }
    }

    if (nodes.isNotEmpty) {
      debugPrint(
        'SyncPayloadProcessor: Replaying ${nodes.length} staged node(s) for newly onboarded counterparty.',
      );
      await processIncomingNodes(nodes);
    }
  }

  Uint8List _hexToBytes(String hex) {
    if (hex.length % 2 != 0) throw Exception('Odd length hex string');
    var result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
