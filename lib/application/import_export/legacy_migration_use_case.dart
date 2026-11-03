import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/entities/party_details.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/domain/value_objects/standard_account_classification_kind.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/domain/value_objects/predefined_currencies.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'dart:math';

import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/data/security/license_vault.dart';
import 'package:qayd/domain/value_objects/signable_receipt.dart';
import 'package:qayd/data/services/device_contacts_service.dart';
import 'package:qayd/data/services/phone_normalization_service.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';



// ─── Enums & Value Types ──────────────────────────────────────────────────────

/// How the user resolved a collision for a given legacy account.
enum ResolutionAction {
  /// Merge with an existing Qayd account (targetAccountId must be set).
  merge,

  /// Create a new Qayd account from the legacy data.
  createNew,

  /// Skip this account and all its transactions entirely.
  skip,
}

/// User decision for one legacy account during the conflict-resolution wizard.
class AccountResolution {
  /// The chosen action.
  final ResolutionAction action;

  /// Target Qayd account ID — required for [ResolutionAction.merge].
  final String? targetAccountId;

  /// Optional: override the parent root account when creating a new account.
  final String? forcedParentId;

  const AccountResolution.merge(String qaydId)
      : action = ResolutionAction.merge,
        targetAccountId = qaydId,
        forcedParentId = null;

  const AccountResolution.createNew({this.forcedParentId})
      : action = ResolutionAction.createNew,
        targetAccountId = null;

  const AccountResolution.skip()
      : action = ResolutionAction.skip,
        targetAccountId = null,
        forcedParentId = null;
}

// ─── Conflict Model ───────────────────────────────────────────────────────────

enum AccountConflictType {
  /// A Qayd account with the exact same name already exists.
  exactMatch,

  /// A Qayd account with the same phone was found (different name).
  partialMatch,

  /// No existing account could be matched — will be created fresh.
  noMatch,
}

class AccountMigrationConflict {
  final Map<String, dynamic> legacyData;
  final Account? existingAccount;
  final AccountConflictType type;

  /// Net balance per currency in the legacy system (positive = they owe us).
  final List<Map<String, dynamic>> legacyBalances;

  const AccountMigrationConflict({
    required this.legacyData,
    this.existingAccount,
    required this.type,
    this.legacyBalances = const [],
  });

  String get legacyIdStr => legacyData['legacy_id'].toString();
  String get name => legacyData['name']?.toString() ?? '';
  String get phone => legacyData['phone']?.toString() ?? '';
  String get groupName => legacyData['group_name']?.toString() ?? '';
}

// ─── Analysis Result ──────────────────────────────────────────────────────────

class MigrationAnalysisResult {
  final List<AccountMigrationConflict> accountConflicts;
  final Map<String, dynamic> stats;
  final Map<String, dynamic> rawBundle;

  const MigrationAnalysisResult({
    required this.accountConflicts,
    required this.stats,
    required this.rawBundle,
  });

  int get exactMatchCount => accountConflicts
      .where((c) => c.type == AccountConflictType.exactMatch)
      .length;

  int get partialMatchCount => accountConflicts
      .where((c) => c.type == AccountConflictType.partialMatch)
      .length;

  int get newAccountCount => accountConflicts
      .where((c) => c.type == AccountConflictType.noMatch)
      .length;
}

// ─── Use Case ─────────────────────────────────────────────────────────────────

class LegacyMigrationUseCase {
  final AccountRepository _accountRepo;
  final VoucherRepository _voucherRepo;
  final CurrencyRepository _currencyRepo;
  final EntryGenerator _entryGenerator;
  final IdGenerator _idGenerator;
  final ReceiptSigningService? _signingService;
  final Future<CryptoKeyPair?> Function()? _getKeyPair;
  final LicenseVault? _licenseVault;
  final DeviceContactsService _deviceContactsService;

  const LegacyMigrationUseCase(
    this._accountRepo,
    this._voucherRepo,
    this._currencyRepo,
    this._entryGenerator,
    this._idGenerator, {
    ReceiptSigningService? signingService,
    Future<CryptoKeyPair?> Function()? getKeyPair,
    LicenseVault? licenseVault,
    required DeviceContactsService deviceContactsService,
  })  : _signingService = signingService,
        _getKeyPair = getKeyPair,
        _licenseVault = licenseVault,
        _deviceContactsService = deviceContactsService;

  // ── Phase 1: Analyse ────────────────────────────────────────────────────────

  /// Parses the JSON bundle (v1 or v2) and classifies every legacy account as
  /// exactMatch / partialMatch / noMatch against the current Qayd database.
  Future<Result<MigrationAnalysisResult>> analyzeBundle(
    String jsonContent,
  ) async {
    try {
      final bundle = json.decode(jsonContent) as Map<String, dynamic>;
      final legacyAccounts =
          (bundle['accounts'] as List? ?? []).cast<Map<String, dynamic>>();

      // Fetch all existing accounts once — avoids N+1 queries.
      final allResult = await _accountRepo.getAll();
      final allAccounts =
          allResult is Success<List<Account>> ? allResult.value : <Account>[];

      final conflicts = <AccountMigrationConflict>[];

      // 1. Determine Owner's Country Code for normalization
      final licenseData = await _licenseVault?.readLicenseData();
      final ownerPhone = licenseData?['phone']?.toString() ?? '';
      final normalizer = PhoneNormalizationService(ownerPhone: ownerPhone);

      // 2. Fetch device contacts and normalize them once
      final deviceContactsMap =
          await _deviceContactsService.fetchNormalizedPhoneMap(normalizer);
      final deviceContactE164s = deviceContactsMap.keys.toList();

      for (final legacy in legacyAccounts) {
        final name = legacy['name']?.toString().trim() ?? '';
        final phone =
            (legacy['phone'] ?? legacy['gsm'] ?? '').toString().trim();
        final legacyBalances =
            (legacy['balances'] as List? ?? []).cast<Map<String, dynamic>>();

        // ── Phone Normalization & Matching ─────────────────────────────────
        String resolvedPhone = phone;
        if (phone.isNotEmpty) {
          // الطبقة 1: Normalize مباشر (مثل واتساب)
          final normalized = normalizer.normalizeDigitsOnly(phone);
          resolvedPhone = normalized;

          // الطبقة 2: تحقق من جهات الاتصال (تأكيد أن الرقم حقيقي)
          if (deviceContactsMap.containsKey(normalized)) {
            // الرقم المُنسَّق موجود في جهات الاتصال — ممتاز
            // (اختياري: يمكن استخدام الرقم الخام من جهة الاتصال إذا فضلنا)
          } else {
            // حاول suffix matching كـ fallback ضد جهات الاتصال المنظمة
            final matched = _matchWithDeviceContacts(phone, deviceContactE164s);
            if (matched != null) {
              resolvedPhone = matched;
            }
          }
        }

        // 1. Try exact name match
        Account? existing = allAccounts
            .where((a) => a.name.trim().toLowerCase() == name.toLowerCase())
            .firstOrNull;

        // 2. Try phone match
        if (existing == null && resolvedPhone.isNotEmpty) {
          final phoneResult = await _accountRepo.findAccountByPhone(resolvedPhone);
          if (phoneResult is Success<AccountId?> && phoneResult.value != null) {
            final accResult = await _accountRepo.getById(phoneResult.value!);
            if (accResult is Success<Account>) existing = accResult.value;
          }
        }

        // 3. Try WhatsApp match
        if (existing == null && resolvedPhone.isNotEmpty) {
          final waResult = await _accountRepo.findAccountByWhatsApp(resolvedPhone);
          if (waResult is Success<AccountId?> && waResult.value != null) {
            final accResult = await _accountRepo.getById(waResult.value!);
            if (accResult is Success<Account>) existing = accResult.value;
          }
        }

        final conflictType = existing == null
            ? AccountConflictType.noMatch
            : (existing.name.trim().toLowerCase() == name.toLowerCase()
                ? AccountConflictType.exactMatch
                : AccountConflictType.partialMatch);

        // Update legacy data with the resolved phone if it was improved
        final updatedLegacy = Map<String, dynamic>.from(legacy);
        if (resolvedPhone != phone) {
          updatedLegacy['phone'] = resolvedPhone;
        }

        conflicts.add(AccountMigrationConflict(
          legacyData: updatedLegacy,
          existingAccount: existing,
          type: conflictType,
          legacyBalances: legacyBalances,
        ));
      }


      return Success(MigrationAnalysisResult(
        accountConflicts: conflicts,
        stats: (bundle['stats'] as Map<String, dynamic>? ?? {}),
        rawBundle: bundle,
      ));
    } catch (e) {
      return FailureResult(
          UnexpectedFailure(messageAr: 'فشل في تحليل ملف الهجرة: $e'));
    }
  }

  // ── Phase 2: Create & Resolve Accounts ──────────────────────────────────────

  /// Creates new Qayd accounts for all [noMatch] conflicts (or conflicts where
  /// the user chose [ResolutionAction.createNew]), and builds the final
  /// `legacyId → qaydAccountId` mapping used by [executeImport].
  ///
  /// New accounts are created as **children** of the appropriate parent root:
  ///   - classification == 'payables' (موردين)  → child of ذمم مدينة (لك)
  ///   - classification == 'receivables' / default → child of ذمم دائنة (عليك)
  ///
  /// [userResolutions] — user choices keyed by legacy account ID string.
  Future<Result<Map<String, String>>> resolveAccounts({
    required MigrationAnalysisResult analysis,
    required Map<String, AccountResolution> userResolutions,
  }) async {
    final resolved = <String, String>{};

    // ── Locate parent root accounts for receivables & payables ──────────
    final allResult = await _accountRepo.getAll();
    final allAccounts =
        allResult is Success<List<Account>> ? allResult.value : <Account>[];

    // Find the receivables root (ذمم دائنة (عليك))
    final receivablesRoot = allAccounts
        .where((a) =>
            a.isRoot &&
            a.classification.standardKind ==
                StandardAccountClassificationKind.receivables)
        .firstOrNull;

    // Find the payables root (ذمم مدينة (لك))
    final payablesRoot = allAccounts
        .where((a) =>
            a.isRoot &&
            a.classification.standardKind ==
                StandardAccountClassificationKind.payables)
        .firstOrNull;

    for (final conflict in analysis.accountConflicts) {
      final legacyId = conflict.legacyIdStr;
      final decision =
          userResolutions[legacyId] ?? const AccountResolution.createNew();

      switch (decision.action) {
        case ResolutionAction.skip:
          // Do not add to map — transactions for this account will be skipped.
          break;

        case ResolutionAction.merge:
          resolved[legacyId] = decision.targetAccountId!;
          break;

        case ResolutionAction.createNew:
          final newId = AccountId(const Uuid().v4());
          final accountName =
              conflict.name.isNotEmpty ? conflict.name : AppStrings.importedAccount;

          // Determine parent based on user override or bundle classification.
          Account? parentAccount;
          if (decision.forcedParentId != null) {
            parentAccount = allAccounts
                .where((a) => a.id.value == decision.forcedParentId)
                .firstOrNull;
          }

          if (parentAccount == null) {
            final legacyClassification =
                conflict.legacyData['classification']?.toString() ?? '';
            final isPayable = legacyClassification == 'payables';
            parentAccount = isPayable ? payablesRoot : receivablesRoot;
          }

          final Account newAccount;
          if (parentAccount != null) {
            // Create as child under the correct receivables / payables root.
            newAccount = Account.createChild(
              id: newId,
              name: accountName,
              parent: parentAccount,
              createdAt: DateTime.now(),
              metadata: {
                'source': 'legacy_import',
                'original_id': conflict.legacyData['legacy_id'],
                'group': conflict.groupName,
                if (conflict.phone.isNotEmpty) 'phone': conflict.phone,
              },
            );
          } else {
            // Fallback: if no parent root exists, create as root with
            // the appropriate classification.
            newAccount = Account.createRoot(
              id: newId,
              name: accountName,
              classification: parentAccount?.classification ??
                  AccountClassification.receivables,
              createdAt: DateTime.now(),
              metadata: {
                'source': 'legacy_import',
                'original_id': conflict.legacyData['legacy_id'],
                'group': conflict.groupName,
                if (conflict.phone.isNotEmpty) 'phone': conflict.phone,
              },
            );
          }

          final saveResult = await _accountRepo.save(newAccount);
          if (saveResult is FailureResult) {
            return FailureResult(
              UnexpectedFailure(
                messageAr:
                    'فشل في إنشاء حساب "${conflict.name}": ${saveResult.failure.messageAr}',
              ),
            );
          }

          // Save party details (phone, customer type) if available.
          if (conflict.phone.isNotEmpty) {
            final partyDetails = PartyDetails(
              accountId: newId,
              phoneNumber: conflict.phone,
              whatsappNumber: conflict.phone,
              partyType: conflict.legacyData['customer_type_name']?.toString(),
            );
            await _accountRepo.savePartyDetails(partyDetails);
          }

          resolved[legacyId] = newId.value;
          break;
      }
    }

    return Success(resolved);
  }

  // ── Phase 3: Execute Import ──────────────────────────────────────────────────

  /// Imports all currencies and transactions from the bundle.
  ///
  /// [accountResolutions] — the final map from [resolveAccounts]:
  ///   legacy_id (string) → qayd account ID (string).
  /// Transactions whose counterparty is NOT in this map are silently skipped.
  ///
  /// Vouchers are created in **draft / pending** state so the account holder
  /// can review and confirm them individually inside the Qayd app.
  Future<Result<ImportSummary>> executeImport({
    required Map<String, dynamic> bundle,
    required Map<String, String> accountResolutions,
    void Function(int current, int total)? onProgress,
  }) async {
    try {
      // ── Locate fund account ──────────────────────────────────────────────
      final allResult = await _accountRepo.getAll();
      if (allResult is FailureResult<List<Account>>) {
        return FailureResult(allResult.failure);
      }
      final allAccounts = (allResult as Success<List<Account>>).value;

      // We must restrict our search to liquid assets primarily, because other
      // root accounts (like Fixed Assets) might also be marked as isDefault=true.
      final fundAccount = allAccounts
              .where((a) =>
                  a.classification.standardKind ==
                      StandardAccountClassificationKind.liquidAssets &&
                  (a.isDefault ||
                      a.name == AppStrings.theBox ||
                      a.name.contains(AppStrings.restriction)))
              .firstOrNull ??
          allAccounts
              .where((a) =>
                  a.classification.standardKind ==
                  StandardAccountClassificationKind.liquidAssets)
              .firstOrNull ??
          allAccounts
              .where((a) => a.name == AppStrings.theBox || a.name.contains(AppStrings.restriction))
              .firstOrNull;

      if (fundAccount == null) {
        return  FailureResult(
          UnexpectedFailure(
            messageAr:
                AppStrings.theMainFundAccount,
          ),
        );
      }

      // ── Ensure required currencies exist ─────────────────────────────────
      final bundleCurrencies =
          (bundle['currencies'] as List? ?? []).cast<Map<String, dynamic>>();

      final currencyByCode = <String, CurrencyCode>{};

      for (final bc in bundleCurrencies) {
        final code = bc['mapped_code']?.toString() ?? 'USD';
        final existing = await _currencyRepo.getByCode(code);
        if (existing is Success<CurrencyCode?> && existing.value != null) {
          currencyByCode[code] = existing.value!;
        } else {
          // Auto-create using predefined catalogue or deduce.
          final predefined =
              PredefinedCurrencies.all.where((c) => c.code == code).firstOrNull;
          final currency = predefined ??
              CurrencyCode(
                code: code,
                nameAr: bc['name_ar']?.toString() ?? _fallbackNameAr(code),
                symbol: bc['symbol']?.toString() ?? _fallbackSymbol(code),
                fractionalDigits: 2,
              );
          await _currencyRepo.save(currency);
          currencyByCode[code] = currency;
        }
      }

      // Ensure we always have a fallback currency object for codes that came
      // from transactions but weren't in the currencies list.
      CurrencyCode resolveCurrency(String code) {
        return currencyByCode[code] ??
            CurrencyCode(
              code: code,
              nameAr: _fallbackNameAr(code),
              symbol: _fallbackSymbol(code),
              fractionalDigits: 2,
            );
      }

      // ── Import transactions ───────────────────────────────────────────────
      final legacyTransactions =
          (bundle['transactions'] as List? ?? []).cast<Map<String, dynamic>>();

      CryptoKeyPair? keyPair;
      String myPhone = '';
      if (_signingService != null && _getKeyPair != null) {
        keyPair = await _getKeyPair.call();
        final licenseData = await _licenseVault?.readLicenseData();
        myPhone = licenseData?['phone'] as String? ?? '';
      }

      int imported = 0;
      int skipped = 0;
      int transfers = 0;
      final int totalTx = legacyTransactions.length;

      for (int i = 0; i < totalTx; i++) {
        final tx = legacyTransactions[i];
        final cusLegacyId = tx['counterparty_legacy_id']?.toString() ?? '';
        final transferTargetId = tx['transfer_target_legacy_id'];
        final isTransfer = tx['type'] == 'transfer' && transferTargetId != null;

        // ── Regular receipt / payment ────────────────────────────────────
        if (!isTransfer) {
          final targetId = accountResolutions[cusLegacyId];
          if (targetId == null) {
            skipped++;
            continue;
          }

          final voucher = await _buildVoucher(
            tx: tx,
            counterpartyId: AccountId(targetId),
            fundAccountId: fundAccount.id,
            resolveCurrency: resolveCurrency,
            keyPair: keyPair,
            myPhone: myPhone,
          );

          // Save as draft — user confirms in app (pending state).
          // As requested, we sign/confirm imported vouchers so they appear on account cards.
          final now = DateTime.now();
          final transactionId = TransactionId(_idGenerator.next());
          final debitId = EntryId(_idGenerator.next());
          final creditId = EntryId(_idGenerator.next());

          final entries = _entryGenerator.generateForConfirmedVoucher(
            voucher: voucher,
            transactionId: transactionId,
            debitEntryId: debitId,
            creditEntryId: creditId,
            ledgerCreatedAt: now,
          );

          await _voucherRepo.saveWithLedgerEntries(
            voucher: voucher,
            ledgerEntries: entries,
          );
          imported++;
        } else {
          // ── Transfer: cus_id → t_cus_id through the fund ─────────────
          final fromId = accountResolutions[cusLegacyId];
          final toIdStr = transferTargetId.toString();
          final toId = accountResolutions[toIdStr];

          // Create receipt leg (from → fund)
          if (fromId != null) {
            final receiptVoucher = await _buildVoucher(
              tx: tx,
              counterpartyId: AccountId(fromId),
              fundAccountId: fundAccount.id,
              resolveCurrency: resolveCurrency,
              forceType: VoucherType.receipt,
              extraNotes:
                  'تحويل إلى: ${_lookupAccountName(legacyTransactions, toIdStr)}',
              keyPair: keyPair,
              myPhone: myPhone,
            );

            final now = DateTime.now();
            final transactionId = TransactionId(_idGenerator.next());
            final debitId = EntryId(_idGenerator.next());
            final creditId = EntryId(_idGenerator.next());

            final entries = _entryGenerator.generateForConfirmedVoucher(
              voucher: receiptVoucher,
              transactionId: transactionId,
              debitEntryId: debitId,
              creditEntryId: creditId,
              ledgerCreatedAt: now,
            );

            await _voucherRepo.saveWithLedgerEntries(
              voucher: receiptVoucher,
              ledgerEntries: entries,
            );
            imported++;
          }

          // Create payment leg (fund → to)
          if (toId != null) {
            final paymentVoucher = await _buildVoucher(
              tx: tx,
              counterpartyId: AccountId(toId),
              fundAccountId: fundAccount.id,
              resolveCurrency: resolveCurrency,
              forceType: VoucherType.payment,
              extraNotes:
                  'تحويل من: ${_lookupAccountName(legacyTransactions, cusLegacyId)}',
              keyPair: keyPair,
              myPhone: myPhone,
            );

            final now = DateTime.now();
            final transactionId = TransactionId(_idGenerator.next());
            final debitId = EntryId(_idGenerator.next());
            final creditId = EntryId(_idGenerator.next());

            final entries = _entryGenerator.generateForConfirmedVoucher(
              voucher: paymentVoucher,
              transactionId: transactionId,
              debitEntryId: debitId,
              creditEntryId: creditId,
              ledgerCreatedAt: now,
            );

            await _voucherRepo.saveWithLedgerEntries(
              voucher: paymentVoucher,
              ledgerEntries: entries,
            );
            imported++;
          }

          transfers++;
          if (fromId == null && toId == null) skipped++;
        }

        if (onProgress != null && i % 5 == 0) {
          onProgress(i + 1, totalTx);
        }
      }

      if (onProgress != null && totalTx > 0) {
        onProgress(totalTx, totalTx);
      }

      return Success(ImportSummary(
        imported: imported,
        skipped: skipped,
        transfers: transfers,
      ));
    } catch (e) {
      return FailureResult(
          UnexpectedFailure(messageAr: 'فشل في استيراد البيانات: $e'));
    }
  }

  // ── Private Helpers ─────────────────────────────────────────────────────────

  Future<Voucher> _buildVoucher({
    required Map<String, dynamic> tx,
    required AccountId counterpartyId,
    required AccountId fundAccountId,
    required CurrencyCode Function(String) resolveCurrency,
    VoucherType? forceType,
    String? extraNotes,
    CryptoKeyPair? keyPair,
    String? myPhone,
  }) async {
    final typeStr = tx['type']?.toString() ?? 'receipt';
    final voucherType = forceType ??
        (typeStr == 'payment' ? VoucherType.payment : VoucherType.receipt);

    final currCode = tx['currency_code']?.toString() ?? 'YER';
    final currency = resolveCurrency(currCode);
    final amount = (tx['amount_raw'] as num? ?? 0).toDouble();
    final money = _toMoney(amount, currency);

    // Prefer the pre-parsed ISO date from v2 bundle, fall back to raw.
    final dateParsed =
        tx['date_parsed']?.toString() ?? tx['date']?.toString() ?? '';
    final date = _parseIsoDate(dateParsed) ?? DateTime.now();

    final description = tx['description']?.toString() ?? '';
    final legacyId = tx['legacy_id']?.toString() ?? '';

    final notes = [
      'مستورد من النظام القديم (ID: $legacyId)',
      if (extraNotes != null) extraNotes,
    ].join(' | ');

    // Voucher is created as draft then immediately confirmed as per user request.
    var voucher = Voucher.draft(
      id: VoucherId(_idGenerator.next()),
      type: voucherType,
      date: date,
      amount: money,
      currency: currency,
      counterpartyId: counterpartyId,
      affectedAccountId: fundAccountId,
      createdAt: DateTime.now(),
      description: description,
      notes: notes,
    );

    // Apply real cryptographic signature if keys are available
    if (keyPair != null && myPhone != null && _signingService != null) {
      String cpPhone = '';
      final cpParty = await _accountRepo.getPartyDetails(counterpartyId);
      if (cpParty.isSuccess) {
        cpPhone = cpParty.valueOrNull?.phoneNumber ?? '';
      }

      final signable = SignableReceipt(
        amountMinor: money.minorUnits,
        currencyCode: currCode,
        senderPhone: myPhone,
        receiverPhone: cpPhone,
        dateIso: date.toIso8601String().split('T').first,
        receiptUuid: voucher.id.value,
      );

      final signature = _signingService.signReceipt(signable, keyPair);
      voucher = voucher.attachSignature(
        signatureHex: signature.signatureHex,
        publicKeyHex: signature.signerPublicKeyHex,
        isSender: true,
        status: AgreementStatus.accepted,
        signerPhone: myPhone,
      );
    }
    return voucher.confirm(date);
  }

  Money _toMoney(double decimal, CurrencyCode currency) {
    final digits =
        currency.fractionalDigits > 0 ? currency.fractionalDigits : 2;
    final minor = (decimal * pow(10, digits)).round();
    return Money.positiveAmount(minor, currency);
  }

  /// Parses yyyy-mm-dd produced by the web tool. Tolerates missing values.
  DateTime? _parseIsoDate(String s) {
    if (s.isEmpty) return null;
    try {
      // yyyy-mm-dd
      if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) {
        return DateTime.parse('${s.substring(0, 10)}T00:00:00');
      }
      // dd-mm-yyyy (legacy raw)
      if (RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(s)) {
        final p = s.split('-');
        return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      }
    } catch (_) {}
    return null;
  }

  String _fallbackNameAr(String code) {
    final map = {
      'SAR': AppStrings.saudiRiyals,
      'YER': AppStrings.yemeni,
      'USD': AppStrings.usDollars,
      'EGP': AppStrings.egyptianPound,
      'AED': AppStrings.emiratiDirham,
      'KWD': AppStrings.kuwaitiDinar,
      'QAR': AppStrings.qatari,
      'OMR': AppStrings.omani,
      'BHD': AppStrings.bahrainiDinar,
      'JOD': AppStrings.jordanianDinar,
      'EUR': AppStrings.euro,
      'GBP': AppStrings.britishPounds,
      'XAU': AppStrings.aGramOfGold,
      'XAG': AppStrings.gramOfSilver,
    };
    return map[code] ?? 'عملة $code';
  }

  String _fallbackSymbol(String code) {
    final map = {
      'SAR': '﷼',
      'YER': '﷼',
      'QAR': '﷼',
      'OMR': '﷼',
      'USD': r'$',
      'EUR': '€',
      'GBP': '£',
      'EGP': AppStrings.jm,
      'AED': AppStrings.de,
      'KWD': AppStrings.kwd,
      'BHD': AppStrings.bear,
      'JOD': AppStrings.da1,
      'XAU': AppStrings.cD,
      'XAG': AppStrings.dry,
    };
    return map[code] ?? code;
  }

  /// Best-effort lookup of an account name by legacy ID from the transaction list.
  String _lookupAccountName(
      List<Map<String, dynamic>> txList, String legacyId) {
    return legacyId;
  }

  // ── Suffix Matching Helpers ────────────────────────────────────────────────

  String? _matchWithDeviceContacts(String target, List<String> candidates) {
    final cleanTarget = _normalizePhone(target);
    if (cleanTarget.length < 5) return null;

    String? bestMatch;
    double bestRatio = 0;

    for (final cand in candidates) {
      final cleanCand = _normalizePhone(cand);
      
      // Check if target is a suffix of candidate
      if (cleanCand.endsWith(cleanTarget)) {
        // 100% match of the target string length
        return cand;
      }

      // Percentage matching of the suffix
      int matchCount = 0;
      final minLen = min(cleanTarget.length, cleanCand.length);
      for (int i = 1; i <= minLen; i++) {
        if (cleanTarget[cleanTarget.length - i] ==
            cleanCand[cleanCand.length - i]) {
          matchCount++;
        } else {
          break;
        }
      }

      final ratio = matchCount / cleanTarget.length;
      if (ratio >= 0.7 && ratio > bestRatio) {
        bestRatio = ratio;
        bestMatch = cand;
      }
    }

    return bestMatch;
  }

  String _normalizePhone(String p) {
    return p.replaceAll(RegExp(r'\D'), '');
  }
}

// ─── Import Summary ───────────────────────────────────────────────────────────

class ImportSummary {
  final int imported;
  final int skipped;
  final int transfers;

  const ImportSummary({
    required this.imported,
    required this.skipped,
    required this.transfers,
  });

  @override
  String toString() =>
      'تم استيراد $imported سند، تخطي $skipped، منها $transfers تحويل.';
}
