import 'package:qayd/application/accounts/dtos/create_account_input.dart';
import 'package:qayd/application/accounts/dtos/create_account_output.dart';
import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/entities/party_details.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/standard_account_classification_kind.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/domain/entities/audit_entry.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/data/security/license_vault.dart';
import 'package:qayd/data/services/phone_normalization_service.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';



class CreateAccountUseCase {
  final AccountRepository _accountRepository;
  final IdGenerator _idGenerator;
  final GovernanceWriteGuard _writeGuard;
  final LicenseVault _licenseVault;
  final AuditLogService? _auditLogService;

  CreateAccountUseCase(
    this._accountRepository,
    this._idGenerator,
    this._writeGuard,
    this._licenseVault, {
    AuditLogService? auditLogService,
  }) : _auditLogService = auditLogService;



  Future<Result<CreateAccountOutput>> call(CreateAccountInput input) async {
    try {
      final gate = await _writeGuard.assertWritesPermitted();
      if (gate.isFailure) {
        return FailureResult(gate.failureOrNull!);
      }

      // ── Phone Normalization ──────────────────────────────────────────────
      final licenseData = await _licenseVault.readLicenseData();
      final ownerPhone = licenseData?['phone']?.toString() ?? '';
      final normalizer = PhoneNormalizationService(ownerPhone: ownerPhone);

      String? normalizedPhone;
      if (input.phoneNumber?.isNotEmpty == true) {
        normalizedPhone = normalizer.normalizeDigitsOnly(input.phoneNumber!);
        
        final existingByPhone =
            await _accountRepository.findAccountByPhone(normalizedPhone);
        if (existingByPhone.valueOrNull != null) {
          return  FailureResult(ValidationFailure(
            messageAr: AppStrings.thereIsAlreadyAn,
          ));
        }
      }

      String? normalizedWhatsApp;
      if (input.whatsappNumber?.isNotEmpty == true) {
        normalizedWhatsApp = normalizer.normalizeDigitsOnly(input.whatsappNumber!);
      } else if (normalizedPhone != null) {
        // Default WhatsApp to phone if not provided
        normalizedWhatsApp = normalizedPhone;
      }

      if (input.email?.isNotEmpty == true) {
        final existingByEmail =
            await _accountRepository.findAccountByEmail(input.email!);
        if (existingByEmail.valueOrNull != null) {
          return  FailureResult(ValidationFailure(
            messageAr: AppStrings.thereIsAnAccount,
          ));
        }
      }

      final id = AccountId(_idGenerator.next());
      final now = DateTime.now();
      final Account account;
      if (input.parentAccountId == null) {
        _validateRootClassification(input);
        final classification = _rootClassification(input);
        account = Account.createRoot(
          id: id,
          name: input.name,
          classification: classification,
          createdAt: now,
          isDefault: input.isDefault,
          metadata: input.metadata,
        );
      } else {
        final parentR = await _accountRepository.getById(
          AccountId(input.parentAccountId!),
        );
        if (parentR.isFailure) {
          return FailureResult(parentR.failureOrNull!);
        }
        final parent = parentR.valueOrNull!;
        account = Account.createChild(
          id: id,
          name: input.name,
          parent: parent,
          createdAt: now,
          isDefault: input.isDefault,
          metadata: input.metadata,
        );
      }

      final saved = await _accountRepository.save(account);
      if (saved.isFailure) {
        return FailureResult(saved.failureOrNull!);
      }

      final hasPartyDetails = input.phoneNumber?.isNotEmpty == true ||
          input.whatsappNumber?.isNotEmpty == true ||
          input.bankAccountInfo?.isNotEmpty == true ||
          input.partyType?.isNotEmpty == true;

      if (hasPartyDetails) {
        final partyDetails = PartyDetails(
          accountId: id,
          phoneNumber: normalizedPhone,
          email: input.email,
          whatsappNumber: normalizedWhatsApp,

          bankAccountInfo: input.bankAccountInfo,
          partyType: input.partyType,
          currentPublicKeyHex: input.currentPublicKeyHex,
          publicKeyHistoryHex: input.publicKeyHistoryHex ?? [],
          serverAccountId: input.serverAccountId,
        );
        await _accountRepository.savePartyDetails(partyDetails);
      }

      if (input.defaultCostCenters.isNotEmpty) {
        for (final tag in input.defaultCostCenters) {
          await _accountRepository.saveDefaultCostCenter(
            accountId: id,
            costCenterId: tag.costCenterId,
            dimensionIds: tag.dimensionIds,
          );
        }
      }

      await _auditLogService?.log(
        entityType: 'account',
        entityId: id.value,
        action: AuditAction.create,
        newData: {
          'id': id.value,
          'name': input.name,
          'created_at': now.toIso8601String(),
          'classification': account.classification.standardKind?.name ??
              input.customClassificationName,
        },
      );

      return Success(
        CreateAccountOutput(
          accountId: account.id.value,
          name: account.name,
          natureCode: _natureCode(account),
          isRoot: account.isRoot,
          parentAccountId: account.parentId?.value,
          createdAtIso: account.createdAt.toIso8601String(),
        ),
      );
    } catch (e) {
      return FailureResult(failureFromDomainException(e));
    }
  }

  void _validateRootClassification(CreateAccountInput input) {
    final hasStd = input.rootStandardKind != null;
    final hasCustom = input.customClassificationName != null &&
        input.customClassificationNature != null;
    if (hasStd == hasCustom) {
      throw ArgumentError(
        AppStrings.youMustChooseA,
      );
    }
    if (hasCustom && input.customClassificationName!.trim().isEmpty) {
      throw ArgumentError(AppStrings.customTaxonomyNameIs);
    }
  }

  AccountClassification _rootClassification(CreateAccountInput input) {
    final k = input.rootStandardKind;
    if (k != null) {
      switch (k) {
        case StandardAccountClassificationKind.settlements:
          return AccountClassification.settlements;
        case StandardAccountClassificationKind.payables:
          return AccountClassification.payables;
        case StandardAccountClassificationKind.receivables:
          return AccountClassification.receivables;
        case StandardAccountClassificationKind.liquidAssets:
          return AccountClassification.liquidAssets;
        case StandardAccountClassificationKind.personalExpenses:
          return AccountClassification.personalExpenses;
        case StandardAccountClassificationKind.personalRevenues:
          return AccountClassification.personalRevenues;
        case StandardAccountClassificationKind.clearingRemittances:
          return AccountClassification.clearingRemittances;
        case StandardAccountClassificationKind.remittanceFees:
          return AccountClassification.remittanceFees;
        case StandardAccountClassificationKind.fixedDepreciableAssets:
          return AccountClassification.fixedDepreciableAssets;
        case StandardAccountClassificationKind.fixedProfitableAssets:
          return AccountClassification.fixedProfitableAssets;
      }
    }
    return AccountClassification.custom(
      name: input.customClassificationName!,
      nature: input.customClassificationNature!,
    );
  }

  String _natureCode(Account account) =>
      account.nature == AccountNature.debit ? 'debit' : 'credit';
}
