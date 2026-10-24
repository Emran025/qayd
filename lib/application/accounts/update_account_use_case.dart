import 'package:qayd/application/accounts/dtos/update_account_input.dart';
import 'package:qayd/application/accounts/dtos/update_account_output.dart';
import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/party_details.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/entities/audit_entry.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/data/security/license_vault.dart';
import 'package:qayd/data/services/phone_normalization_service.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';

import 'package:qayd/domain/value_objects/account_nature.dart';

class UpdateAccountUseCase {
  final AccountRepository _accountRepository;
  final GovernanceWriteGuard _writeGuard;
  final LicenseVault _licenseVault;
  final AuditLogService? _auditLogService;

  UpdateAccountUseCase(
    this._accountRepository,
    this._writeGuard,
    this._licenseVault, {
    AuditLogService? auditLogService,
  }) : _auditLogService = auditLogService;


  Future<Result<UpdateAccountOutput>> call(UpdateAccountInput input) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }

      // ── 1. Load account ───────────────────────────────────────────────────
      final loaded =
          await _accountRepository.getById(AccountId(input.accountId));
      if (loaded.isFailure) {
        return FailureResult(loaded.failureOrNull!);
      }
      final account = loaded.valueOrNull!;

      // ── 2. Capture old state for audit ────────────────────────────────────
      final oldData = <String, dynamic>{
        'name': account.name,
        'parentId': account.parentId?.value,
        'nature': account.nature.name,
        'classification': account.classification.standardKind?.name ??
            account.classification.customName,
      };

      // ── 3. Apply changes ───────────────────────────────────────────────────
      var updated = account.rename(input.newName);

      // Handle structural updates (Parent / Classification)
      if (input.parentAccountId != null) {
        // Moving child to a new parent
        final parentRes =
            await _accountRepository.getById(AccountId(input.parentAccountId!));
        if (parentRes.isFailure) return FailureResult(parentRes.failureOrNull!);
        final parent = parentRes.valueOrNull!;

        updated = updated.move(parent.id, parent.nature, parent.classification);
      } else if (input.rootStandardKind != null) {
        // Changing root to a standard kind
        final classification =
            AccountClassification.standard(input.rootStandardKind!);
        updated =
            updated.reclassify(classification, classification.defaultNature);
      } else if (input.customClassificationName != null) {
        // Changing root to a custom kind
        final nature = input.customClassificationNature ?? AccountNature.debit;
        final classification = AccountClassification.custom(
          name: input.customClassificationName!,
          nature: nature,
        );
        updated = updated.reclassify(classification, nature);
      }

      final saved = await _accountRepository.save(updated);
      if (saved.isFailure) {
        return FailureResult(saved.failureOrNull!);
      }

      // ── 4. Phone Normalization ───────────────────────────────────────────
      final licenseData = await _licenseVault.readLicenseData();
      final ownerPhone = licenseData?['phone']?.toString() ?? '';
      final normalizer = PhoneNormalizationService(ownerPhone: ownerPhone);

      String? normalizedPhone;
      if (input.phoneNumber != null) {
        normalizedPhone = input.phoneNumber!.trim().isNotEmpty
            ? normalizer.normalizeDigitsOnly(input.phoneNumber!)
            : null;
      }

      String? normalizedWhatsApp;
      if (input.whatsappNumber != null) {
        normalizedWhatsApp = input.whatsappNumber!.trim().isNotEmpty
            ? normalizer.normalizeDigitsOnly(input.whatsappNumber!)
            : null;
      }

      // ── 5. Update party details (if any field was provided) ───────────────
      final hasPartyUpdate = normalizedPhone != null ||
          normalizedWhatsApp != null ||
          input.bankAccountInfo != null ||
          input.partyType != null;


      if (hasPartyUpdate) {
        final existingPartyResult = await _accountRepository
            .getPartyDetails(AccountId(input.accountId));
        final existing = existingPartyResult.valueOrNull;

        if (existing != null) {
          oldData['party'] = {
            'phoneNumber': existing.phoneNumber,
            'whatsappNumber': existing.whatsappNumber,
            'bankAccountInfo': existing.bankAccountInfo,
            'partyType': existing.partyType,
          };
        }

        final updatedParty = PartyDetails(
          accountId: AccountId(input.accountId),
          phoneNumber: normalizedPhone,
          email: existing?.email,
          whatsappNumber: normalizedWhatsApp,

          bankAccountInfo: _nonEmpty(input.bankAccountInfo),
          partyType: _nonEmpty(input.partyType),
          currentPublicKeyHex: existing?.currentPublicKeyHex,
          publicKeyHistoryHex: existing?.publicKeyHistoryHex ?? [],
          serverAccountId: existing?.serverAccountId,
        );
        await _accountRepository.savePartyDetails(updatedParty);
      }

      // ── 5. Replace default cost centers (if list provided) ────────────────
      final newCostCenters = input.defaultCostCenters;
      if (newCostCenters != null) {
        final accountId = AccountId(input.accountId);
        final currentResult =
            await _accountRepository.getDefaultCostCenters(accountId);
        final current = currentResult.valueOrNull ?? [];

        oldData['defaultCostCenters'] = current
            .map((c) => {
                  'costCenterId': c.costCenterId,
                  'dimensionIds': c.dimensionIds,
                })
            .toList();

        final newIds = newCostCenters.map((t) => t.costCenterId).toSet();
        final oldIds = current.map((c) => c.costCenterId).toSet();

        for (final removed in oldIds.difference(newIds)) {
          await _accountRepository.removeDefaultCostCenter(
            accountId: accountId,
            costCenterId: removed,
          );
        }
        for (final tag in newCostCenters) {
          await _accountRepository.saveDefaultCostCenter(
            accountId: accountId,
            costCenterId: tag.costCenterId,
            dimensionIds: tag.dimensionIds,
          );
        }
      }

      // ── 6. Audit log ──────────────────────────────────────────────────────
      final newData = {
        'name': updated.name,
        'nature': updated.nature.name,
        'classification': updated.classification.standardKind?.name ??
            updated.classification.customName,
        if (hasPartyUpdate)
          'party': {
            'phoneNumber': input.phoneNumber,
            'whatsappNumber': input.whatsappNumber,
            'bankAccountInfo': input.bankAccountInfo,
            'partyType': input.partyType,
          },
        if (newCostCenters != null)
          'defaultCostCenters': newCostCenters
              .map((t) => {
                    'costCenterId': t.costCenterId,
                    'dimensionIds': t.dimensionIds,
                  })
              .toList(),
      };

      await _auditLogService?.log(
        entityType: 'account',
        entityId: updated.id.value,
        action: AuditAction.update,
        oldData: oldData,
        newData: newData,
      );

      return Success(
        UpdateAccountOutput(
          accountId: updated.id.value,
          name: updated.name,
        ),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }

  static String? _nonEmpty(String? v) =>
      (v != null && v.trim().isNotEmpty) ? v.trim() : null;
}
