import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/fiscal/fiscal_period_policy.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/domain/entities/voucher_attachment.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/application/vouchers/dtos/create_voucher_input.dart';
import 'package:qayd/application/vouchers/dtos/create_voucher_output.dart';
import 'package:qayd/domain/repositories/attachment_repository.dart';
import 'package:qayd/data/services/attachment_storage_service.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/cost_center_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/standard_account_classification_kind.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/tripartite_meta.dart';
import 'package:qayd/domain/value_objects/tripartite_role.dart';
import 'package:qayd/domain/value_objects/attachment_ref.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/value_objects/signable_receipt.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/data/security/license_vault.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';

import 'package:qayd/domain/entities/audit_entry.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/domain/repositories/collateral_repository.dart';
import 'package:qayd/domain/entities/collateral.dart';
import 'package:qayd/domain/value_objects/collateral_id.dart';
import 'package:qayd/domain/value_objects/collateral_status.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

class CreateVoucherUseCase {
  final VoucherRepository _voucherRepository;
  final CurrencyRepository _currencyRepository;
  final AttachmentRepository _attachmentRepository;
  final AttachmentStorageService _attachmentStorage;
  final IdGenerator _idGenerator;
  final GovernanceWriteGuard _writeGuard;
  final FiscalPeriodRepository _fiscalPeriodRepository;
  final AccountRepository? _accountRepository;
  final ReceiptSigningService? _signingService;
  final Future<CryptoKeyPair?> Function()? _getKeyPair;
  final LicenseVault? _licenseVault;
  final SyncEventDispatcher? _syncEventDispatcher;
  final CostCenterRepository? _costCenterRepository;
  final EntryGenerator? _entryGenerator;
  final AuditLogService? _auditLogService;
  final CollateralRepository? _collateralRepository;

  CreateVoucherUseCase(
    this._voucherRepository,
    this._currencyRepository,
    this._attachmentRepository,
    this._attachmentStorage,
    this._idGenerator,
    this._writeGuard,
    this._fiscalPeriodRepository, {
    AccountRepository? accountRepository,
    ReceiptSigningService? signingService,
    Future<CryptoKeyPair?> Function()? getKeyPair,
    LicenseVault? licenseVault,
    SyncEventDispatcher? syncEventDispatcher,
    CostCenterRepository? costCenterRepository,
    EntryGenerator? entryGenerator,
    AuditLogService? auditLogService,
    CollateralRepository? collateralRepository,
  })  : _accountRepository = accountRepository,
        _signingService = signingService,
        _getKeyPair = getKeyPair,
        _licenseVault = licenseVault,
        _syncEventDispatcher = syncEventDispatcher,
        _costCenterRepository = costCenterRepository,
        _entryGenerator = entryGenerator,
        _auditLogService = auditLogService,
        _collateralRepository = collateralRepository;

  Future<Result<CreateVoucherOutput>> call(CreateVoucherInput input) async {
    try {
      final isEdit = input.editingVoucherId != null;
      final voucherId = isEdit
          ? VoucherId(input.editingVoucherId!)
          : VoucherId(_idGenerator.next());
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }
      final currencyRes =
          await _currencyRepository.getByCode(input.currencyCode);
      if (currencyRes.isFailure || currencyRes.valueOrNull == null) {
        return FailureResult(ValidationFailure(
          messageAr: AppStrings.theSelectedCurrencyIs,
          code: 'invalid_currency',
        ));
      }
      final currency = currencyRes.valueOrNull!;
      final amount = Money.positiveAmount(input.amountMinorUnits, currency);

      final periodsR = await _fiscalPeriodRepository.listAllOrdered();
      if (periodsR.isSuccess &&
          FiscalPeriodPolicy.voucherDateInClosedPeriod(
            periodsR.valueOrNull!,
            input.date,
          )) {
        return FailureResult(
          ValidationFailure(
            messageAr: AppStrings.voucherDateInClosedPeriod,
            code: 'voucher_closed_period',
          ),
        );
      }

      // ── Automated Bridge Logic Detection ──────────────
      String actualAffectedAccountId = input.affectedAccountId;
      bool isAutomatedExpensePosting = false;

      if (_accountRepository != null) {
        final accountsRes = await _accountRepository!.getAll(
          activeOnly: false,
          excludeArchived: true,
        );
        if (accountsRes.isSuccess) {
          final accounts = accountsRes.valueOrNull!;
          final affected = accounts.firstWhere(
            (a) => a.id.value == input.affectedAccountId,
          );

          final isPersonal = affected.classification.standardKind ==
                  StandardAccountClassificationKind.personalExpenses ||
              affected.classification.standardKind ==
                  StandardAccountClassificationKind.personalRevenues;

          if (isPersonal) {
            final fund = accounts.firstWhere(
              (a) =>
                  a.classification.standardKind ==
                      StandardAccountClassificationKind.liquidAssets &&
                  a.isRoot,
              orElse: () => affected,
            );

            if (fund.id.value != affected.id.value) {
              actualAffectedAccountId = fund.id.value;
              isAutomatedExpensePosting = true;
            }
          }
        }
      }

      TripartiteMeta? tripartiteMeta;
      if (input.transferGroupId != null &&
          input.tripartiteRole != null &&
          input.linkedPartyId != null) {
        tripartiteMeta = TripartiteMeta(
          transferGroupId: input.transferGroupId!,
          role: TripartiteRole.values.firstWhere(
            (r) => r.name == input.tripartiteRole,
            orElse: () => TripartiteRole.intermediaryReceipt,
          ),
          linkedPartyId: AccountId(input.linkedPartyId!),
          isContingent: input.isContingent,
        );
      }

      // Phase 1: Encrypt & store attachments to disk early (before voucher
      // exists in DB). We do NOT yet write to the attachments table — that
      // must happen after the voucher row is committed to satisfy the FK.
      final List<VoucherAttachment> storedAttachments = [];
      final List<AttachmentRef> attachmentRefs = [];
      try {
        final stored = await Future.wait(
          input.attachments.map((a) => _attachmentStorage.store(a, voucherId)),
        );
        storedAttachments.addAll(stored);
        attachmentRefs.addAll(stored.map((s) => AttachmentRef(
              id: s.id,
              storagePath: s.storagePath,
              mimeType: s.mimeType,
              byteSize: s.byteSize,
              encryptedBlobHash: s.encryptedBlobHash,
              sourceType: s.sourceType,
            )));
      } catch (e) {
        rethrow;
      }

      Voucher voucher;
      if (isEdit) {
        final existingRes = await _voucherRepository.getById(voucherId);
        if (existingRes.isFailure) {
          return FailureResult(existingRes.failureOrNull!);
        }
        voucher = existingRes.valueOrNull!;

        final allRefs = [...voucher.attachmentRefs, ...attachmentRefs];
        voucher = voucher.updateDraft(
          type: input.type,
          date: input.date,
          amount: amount,
          currency: currency,
          counterpartyId: AccountId(input.counterpartyAccountId),
          affectedAccountId: AccountId(actualAffectedAccountId),
          referenceNumber: input.referenceNumber,
          description: input.description,
          notes: input.notes,
          attachmentRefs: allRefs,
        );
      } else {
        voucher = Voucher.draft(
          id: voucherId,
          type: input.type,
          date: input.date,
          amount: amount,
          currency: currency,
          counterpartyId: AccountId(input.counterpartyAccountId),
          affectedAccountId: AccountId(actualAffectedAccountId),
          createdAt: DateTime.now(),
          referenceNumber: input.referenceNumber,
          description: input.description,
          notes: input.notes,
          tripartiteMeta: tripartiteMeta,
          attachmentRefs: attachmentRefs,
          senderSignatureHex: input.senderSignatureHex,
          senderPublicKeyHex: input.senderPublicKeyHex,
          receiverSignatureHex: input.receiverSignatureHex,
          receiverPublicKeyHex: input.receiverPublicKeyHex,
          // Freeze canonical phones from QR if provided (v2.1 protocol).
          // qrSignerPhone = Party A (original QR issuer = sender).
          // qrReceiverPhone = Party B (scanner = current user = receiver).
          canonicalSenderPhone: input.qrSignerPhone,
          canonicalReceiverPhone: input.qrReceiverPhone,
          originVoucherId: input.originVoucherId != null
              ? VoucherId(input.originVoucherId!)
              : null,
        );
      }

      if (input.confirm) {
        if (_signingService != null && _getKeyPair != null) {
          final keyPair = await _getKeyPair?.call();
          if (keyPair != null) {
            final licenseData = await _licenseVault?.readLicenseData();
            final myPhone = licenseData?['phone'] as String? ?? '';

            String cpPhone = '';
            if (_accountRepository != null) {
              final cpParty = await _accountRepository!.getPartyDetails(
                AccountId(input.counterpartyAccountId),
              );
              cpPhone = cpParty.valueOrNull?.phoneNumber ?? '';
            }

            final signable = SignableReceipt(
              amountMinor: input.amountMinorUnits,
              currencyCode: input.currencyCode,
              senderPhone: myPhone,
              receiverPhone: cpPhone,
              dateIso: input.date.toIso8601String().split('T').first,
              receiptUuid: voucherId.value,
            );

            // If it already has a sender signature from QR, we sign as receiver.
            final shouldSignAsSender = voucher.senderSignatureHex == null;

            final signature = _signingService!.signReceipt(signable, keyPair);
            voucher = voucher.attachSignature(
              signatureHex: signature.signatureHex,
              publicKeyHex: signature.signerPublicKeyHex,
              isSender: shouldSignAsSender,
              status: AgreementStatus.accepted,
              signerPhone: myPhone,
              // Freeze canonical phones at point of signing.
              canonicalSenderPhone: shouldSignAsSender
                  ? myPhone
                  : (voucher.canonicalSenderPhone ?? voucher.signerPhone),
              canonicalReceiverPhone: shouldSignAsSender
                  ? cpPhone
                  : (voucher.canonicalReceiverPhone ?? myPhone),
            );
          }
        }
        voucher = voucher.confirm(DateTime.now());
      }

      // §6: Corrective Resubmission Logic
      if (input.originVoucherId != null) {
        final originRes =
            await _voucherRepository.getById(VoucherId(input.originVoucherId!));
        if (originRes.isSuccess) {
          final origin = originRes.valueOrNull!;
          if (origin.state.isDraft ||
              origin.receiverStatus == AgreementStatus.rejected) {
            final supercoded = origin.withdraw(DateTime.now());
            await _voucherRepository.save(supercoded);
          }
        }
      }

      final Result<void> saved;
      if (input.confirm && _entryGenerator != null) {
        final now = DateTime.now();
        final transactionId = TransactionId(_idGenerator.next());
        final debitId = EntryId(_idGenerator.next());
        final creditId = EntryId(_idGenerator.next());

        final entries = _entryGenerator!.generateForConfirmedVoucher(
          voucher: voucher,
          transactionId: transactionId,
          debitEntryId: debitId,
          creditEntryId: creditId,
          ledgerCreatedAt: now,
        );

        saved = await _voucherRepository.saveWithLedgerEntries(
          voucher: voucher,
          ledgerEntries: entries,
        );
      } else {
        saved = await _voucherRepository.save(voucher);
      }

      // ── Handle Automated Internal Bridge ──────────────
      if (saved.isSuccess && isAutomatedExpensePosting) {
        final internalVoucherId = VoucherId(_idGenerator.next());
        final internalVoucher = Voucher.draft(
          id: internalVoucherId,
          type: input.type,
          date: input.date,
          amount: amount,
          currency: currency,
          counterpartyId: AccountId(actualAffectedAccountId),
          affectedAccountId: AccountId(input.affectedAccountId),
          createdAt: DateTime.now(),
          description: input.description,
          notes: 'Automated expense posting linked to party transaction.',
          originVoucherId: voucher.id,
        ).confirm(DateTime.now());

        if (_entryGenerator != null) {
          final tId = TransactionId(_idGenerator.next());
          final dId = EntryId(_idGenerator.next());
          final cId = EntryId(_idGenerator.next());
          final iEntries = _entryGenerator!.generateForConfirmedVoucher(
            voucher: internalVoucher,
            transactionId: tId,
            debitEntryId: dId,
            creditEntryId: cId,
            ledgerCreatedAt: DateTime.now(),
          );
          await _voucherRepository.saveWithLedgerEntries(
            voucher: internalVoucher,
            ledgerEntries: iEntries,
          );
        } else {
          await _voucherRepository.save(internalVoucher);
        }
      }

      if (saved.isSuccess &&
          input.costCenterTags.isNotEmpty &&
          _costCenterRepository != null) {
        for (final tag in input.costCenterTags) {
          await _costCenterRepository!.attachVoucher(
            voucherId: voucher.id.value,
            costCenterId: tag.costCenterId,
            dimensionIds: tag.dimensionIds,
          );
        }
      }

      if (saved.isSuccess && input.confirm && _syncEventDispatcher != null) {
        _syncEventDispatcher!.dispatchVoucherClaim(voucher).ignore();
      }

      // ── Handle Collateral (رهن) ──────────────────────
      if (saved.isSuccess &&
          input.collateral != null &&
          _collateralRepository != null) {
        try {
          final collInput = input.collateral!;

          // 1. Save the collateral record FIRST (without images)
          //    This ensures the collateral exists locally even if image
          //    processing fails (e.g. file system error, Android permissions).
          final collateralId = CollateralId(_idGenerator.next());
          final collateralWithoutImages = Collateral(
            id: collateralId,
            voucherId: voucherId,
            description: collInput.description,
            estimatedValue:
                Money.positiveAmount(collInput.estimatedValueMinor, currency),
            currency: currency,
            status: CollateralStatus.active,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            expiryDate: collInput.expiryDate,
            imageRefs: const [],
          );
          final saveResult =
              await _collateralRepository!.save(collateralWithoutImages);
          if (saveResult.isFailure) {
            // Collateral save failed — voucher is still intact.
            await _auditLogService?.log(
              entityType: 'collateral',
              entityId: voucher.id.value,
              action: AuditAction.update,
              newData: {
                'error': saveResult.failureOrNull?.messageAr,
                'context': 'collateral_initial_save'
              },
            );
          }

          // 2. Attempt image processing — if this fails the collateral
          //    record is still safely stored (just without images).
          // §5.E: collateralWithImages is promoted to outer scope so the
          // dispatch step can include imageRefs + AES key in the sync payload.
          Collateral? collateralWithImages;

          if (collInput.imagePaths.isNotEmpty && saveResult.isSuccess) {
            try {
              final stored = await Future.wait(
                collInput.imagePaths.map(
                    (path) => _attachmentStorage.store(XFile(path), voucherId)),
              );
              await _attachmentRepository.saveAll(stored);
              final collImageRefs = stored
                  .map((s) => AttachmentRef(
                        id: s.id,
                        storagePath: s.storagePath,
                        mimeType: s.mimeType,
                        byteSize: s.byteSize,
                        encryptedBlobHash: s.encryptedBlobHash,
                        sourceType: s.sourceType,
                      ))
                  .toList();

              // 3. Update the collateral record with image refs
              collateralWithImages = Collateral(
                id: collateralId,
                voucherId: voucherId,
                description: collInput.description,
                estimatedValue: Money.positiveAmount(
                    collInput.estimatedValueMinor, currency),
                currency: currency,
                status: CollateralStatus.active,
                createdAt: collateralWithoutImages.createdAt,
                updatedAt: DateTime.now(),
                expiryDate: collInput.expiryDate,
                imageRefs: collImageRefs,
              );
              await _collateralRepository!.update(collateralWithImages);
            } catch (imgErr) {
              // Images failed — collateral record is already saved.
              await _auditLogService?.log(
                entityType: 'collateral',
                entityId: voucher.id.value,
                action: AuditAction.update,
                newData: {
                  'error': imgErr.toString(),
                  'context': 'collateral_image_processing'
                },
              );
            }
          }

          // 4. Dispatch sync event for collateral
          // §5.E: Use collateralWithImages when available so that imageRefs
          // and AES key are included in the sync payload for the counterparty.
          // Falls back to collateralWithoutImages if image processing failed.
          if (input.confirm &&
              _syncEventDispatcher != null &&
              saveResult.isSuccess) {
            final collateralToSync =
                collateralWithImages ?? collateralWithoutImages;
            _syncEventDispatcher!
                .dispatchCollateralSync(voucher, collateralToSync)
                .ignore();
          }
        } catch (e) {
          await _auditLogService?.log(
            entityType: 'collateral',
            entityId: voucher.id.value,
            action: AuditAction.update,
            newData: {'error': e.toString(), 'context': 'collateral_creation'},
          );
        }
      }

      if (saved.isSuccess) {
        await _auditLogService?.log(
          entityType: 'voucher',
          entityId: voucher.id.value,
          action: AuditAction.create,
          newData: {
            'id': voucher.id.value,
            'type': voucher.type.name,
            'date': voucher.date.toIso8601String(),
            'amount': voucher.amount.minorUnits,
            'currency': voucher.currency.code,
            'state': voucher.state.name,
          },
        );
      }

      return await saved.fold(
        (f) => FailureResult(f),
        (_) => Success(
          CreateVoucherOutput(
            voucherId: voucher.id.value,
            stateCode: voucher.state.name,
          ),
        ),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }
}
