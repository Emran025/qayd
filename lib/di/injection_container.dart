import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:qayd/application/accruals/process_accrual_use_case.dart';
import 'package:qayd/application/app_updates/check_app_update_use_case.dart';
import 'package:qayd/application/app_updates/install_app_update_use_case.dart';
import 'package:qayd/application/backup/restore_from_backup_use_case.dart';
import 'package:qayd/application/cost_centers/update_cost_center_use_case.dart';
import 'package:qayd/application/identity/sync_identity_to_internal_accounts_use_case.dart';
import 'package:qayd/application/notifications/collateral_expiry_checker.dart';
import 'package:qayd/application/suggestions/analyze_for_suggestions_use_case.dart';
import 'package:qayd/application/vouchers/resolve_conflict_use_case.dart';
import 'package:qayd/data/file_system/backup_file_manager.dart';
import 'package:qayd/data/services/shorebird_app_update_repository.dart';
import 'package:qayd/domain/value_objects/mnemonic_phrase.dart';
import 'package:qayd/presentation/backup/restore_cubit.dart';
import 'package:qayd/presentation/updates/app_update_cubit.dart';
import 'package:qayd/presentation/sync/sync_status_cubit.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:qayd/application/accounts/batch_import_accounts_from_csv_use_case.dart';
import 'package:qayd/application/pos/activate_pos_feature_use_case.dart';
import 'package:qayd/application/pos/create_pos_product_use_case.dart';
import 'package:qayd/application/pos/create_pos_product_category_use_case.dart';
import 'package:qayd/application/pos/deactivate_pos_product_use_case.dart';
import 'package:qayd/application/pos/reactivate_pos_product_use_case.dart';
import 'package:qayd/application/pos/manage_pos_product_category_use_cases.dart';
import 'package:qayd/application/pos/find_pos_product_by_barcode_use_case.dart';
import 'package:qayd/application/pos/list_pos_products_use_case.dart';
import 'package:qayd/application/pos/list_pos_product_categories_use_case.dart';
import 'package:qayd/application/pos/resolve_pos_product_for_checkout_use_case.dart';
import 'package:qayd/application/pos/get_pos_stock_balance_use_case.dart';
import 'package:qayd/application/pos/record_pos_stock_movement_use_case.dart';
import 'package:qayd/application/pos/list_pos_stock_movements_use_case.dart';
import 'package:qayd/application/pos/build_pos_stock_adjustment_posting_use_case.dart';
import 'package:qayd/application/pos/post_pos_stock_adjustment_atomically_use_case.dart';
import 'package:qayd/application/pos/post_pos_opening_balance_atomically_use_case.dart';
import 'package:qayd/application/pos/post_pos_sale_atomically_use_case.dart';
import 'package:qayd/application/pos/post_pos_purchase_atomically_use_case.dart';
import 'package:qayd/application/pos/build_pos_opening_balance_posting_use_case.dart';
import 'package:qayd/application/pos/build_pos_sale_posting_use_case.dart';
import 'package:qayd/application/pos/complete_pos_sale_use_case.dart';
import 'package:qayd/application/pos/build_pos_sales_return_posting_use_case.dart';
import 'package:qayd/application/pos/complete_pos_sales_return_use_case.dart';
import 'package:qayd/application/pos/post_pos_sales_return_atomically_use_case.dart';
import 'package:qayd/application/pos/build_pos_purchase_posting_use_case.dart';
import 'package:qayd/application/pos/complete_pos_purchase_use_case.dart';
import 'package:qayd/application/pos/list_pos_invoices_use_case.dart';
import 'package:qayd/application/pos/get_pos_invoice_details_use_case.dart';
import 'package:qayd/application/pos/build_pos_daily_sales_report_use_case.dart';
import 'package:qayd/application/pos/manage_pos_currency_rates_use_cases.dart';
import 'package:qayd/application/pos/sign_pos_invoice_use_case.dart';
import 'package:qayd/application/pos/build_pos_invoice_pdf_use_case.dart';
import 'package:qayd/domain/services/pos_invoice_signing_service.dart';
import 'package:qayd/domain/repositories/pos_invoice_read_repository.dart';
import 'package:qayd/data/pdf/cairo_pos_invoice_pdf_generator.dart';
import 'package:qayd/data/repositories/sqlite_pos_invoice_read_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_currency_rate_repository.dart';
import 'package:qayd/domain/repositories/pos_currency_rate_repository.dart';
import 'package:qayd/domain/services/pos_currency_converter.dart';
import 'package:qayd/domain/services/pos_invoice_pdf_generator.dart';
import 'package:qayd/application/pos/save_pos_product_use_case.dart';
import 'package:qayd/data/repositories/sqlite_pos_product_category_repository.dart';
import 'package:qayd/application/import_export/legacy_migration_use_case.dart';
import 'package:qayd/application/accounts/create_account_use_case.dart';
import 'package:qayd/application/accounts/deactivate_account_use_case.dart';
import 'package:qayd/application/accounts/archive_account_use_case.dart';
import 'package:qayd/application/accounts/restore_account_use_case.dart';
import 'package:qayd/application/accounts/list_archived_accounts_use_case.dart';
import 'package:qayd/application/accounts/manage_account_default_cost_centers_use_case.dart';
import 'package:qayd/application/accounts/get_account_details_use_case.dart';
import 'package:qayd/application/accounts/get_account_statement_use_case.dart';
import 'package:qayd/application/accounts/list_account_statement_chat_use_case.dart';
import 'package:qayd/application/accounts/list_accounts_use_case.dart';
import 'package:qayd/application/accounts/update_account_use_case.dart';
import 'package:qayd/application/governance/check_governance_status_use_case.dart';
import 'package:qayd/application/governance/governance_write_guard.dart';
import 'package:qayd/application/governance/submit_activation_use_case.dart';
import 'package:qayd/application/messaging/create_message_template_use_case.dart';
import 'package:qayd/application/messaging/delete_message_template_use_case.dart';
import 'package:qayd/application/messaging/list_message_templates_use_case.dart';
import 'package:qayd/application/messaging/log_notification_intent_use_case.dart';
import 'package:qayd/application/reports/generate_trial_balance_use_case.dart';
import 'package:qayd/application/reports/generate_balance_sheet_use_case.dart';
import 'package:qayd/application/settings/get_active_transaction_fee_use_case.dart';
import 'package:qayd/application/settings/manage_transaction_fee_use_case.dart';
import 'package:qayd/application/settings/get_base_currency_use_case.dart';
import 'package:qayd/application/settings/list_currencies_use_case.dart';
import 'package:qayd/application/settings/set_base_currency_use_case.dart';
import 'package:qayd/application/settings/toggle_currency_status_use_case.dart';
import 'package:qayd/application/settings/add_currency_use_case.dart';
import 'package:qayd/application/suggestions/get_auto_suggestions_use_case.dart';
import 'package:qayd/application/suggestions/mark_notification_message_processed_use_case.dart';
import 'package:qayd/application/messaging/save_message_template_use_case.dart';
import 'package:qayd/application/vouchers/accept_voucher_use_case.dart';
import 'package:qayd/application/vouchers/confirm_voucher_use_case.dart';
import 'package:qayd/application/vouchers/reject_voucher_use_case.dart';
import 'package:qayd/application/vouchers/resubmit_voucher_use_case.dart';
import 'package:qayd/application/vouchers/create_dual_transfer_use_case.dart';
import 'package:qayd/application/vouchers/create_tripartite_transfer_use_case.dart';
import 'package:qayd/application/vouchers/create_voucher_use_case.dart';
import 'package:qayd/application/accounts/find_account_by_phone_use_case.dart';
import 'package:qayd/application/identity/can_sync_with_account_use_case.dart';
import 'package:qayd/application/identity/lookup_public_key_use_case.dart';
import 'package:qayd/application/identity/setup_identity_use_case.dart';
import 'package:qayd/application/identity/update_profile_use_case.dart';
import 'package:qayd/application/vouchers/get_voucher_details_use_case.dart';
import 'package:qayd/application/vouchers/list_vouchers_use_case.dart';
import 'package:qayd/application/fiscal/close_fiscal_period_use_case.dart';
import 'package:qayd/application/fiscal/create_fiscal_period_use_case.dart';
import 'package:qayd/application/fiscal/auto_fiscal_closing_service.dart';
import 'package:qayd/application/vouchers/update_draft_voucher_use_case.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/data/backup/auto_backup_service.dart';
import 'package:qayd/data/backup/backup_service.dart';
import 'package:qayd/data/backup/google_drive_backup_service.dart';
import 'package:qayd/data/database/database_encryption_key_provider.dart';
import 'package:qayd/data/database/database_provider.dart';
import 'package:qayd/data/database/hardware_backed_encryption_key_provider.dart';
import 'package:qayd/data/database/transaction_runner.dart';
import 'package:qayd/data/governance/remote/license_vault_governance_remote_data_source.dart';
import 'package:qayd/core/constants/api_endpoints.dart';
import 'package:qayd/data/network/api_client.dart';
import 'package:qayd/data/repositories/governance_repository_impl.dart';
import 'package:qayd/data/repositories/remote_auth_repository.dart';
import 'package:qayd/data/repositories/sqlite_account_repository.dart';
import 'package:qayd/data/repositories/sqlite_fiscal_period_repository.dart';
import 'package:qayd/data/repositories/sqlite_ledger_repository.dart';
import 'package:qayd/data/repositories/sqlite_message_template_repository.dart';
import 'package:qayd/data/repositories/sqlite_notification_log_repository.dart';
import 'package:qayd/data/repositories/sqlite_notification_message_repository.dart';
import 'package:qayd/data/pdf/account_statement_pdf_generator.dart';
import 'package:qayd/data/pdf/cairo_voucher_pdf_generator.dart';
import 'package:qayd/data/pdf/voucher_pdf_generator.dart';
import 'package:qayd/data/repositories/sqlite_currency_repository.dart';
import 'package:qayd/data/repositories/sqlite_transaction_fee_settings_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_activation_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_product_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_stock_movement_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_accounting_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_sale_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_sales_return_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_purchase_posting_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_purchase_request_identity_repository.dart';
import 'package:qayd/data/repositories/sqlite_pos_sales_return_request_identity_repository.dart';
import 'package:qayd/data/repositories/sqlite_voucher_repository.dart';
import 'package:qayd/data/security/app_pin_storage.dart';
import 'package:qayd/data/security/hardware_id_service.dart';
import 'package:qayd/data/security/license_vault.dart';
import 'package:qayd/data/security/monotonic_clock_guard.dart';
import 'package:qayd/data/security/panic_wipe_service.dart';
import 'package:qayd/domain/repositories/auth_repository.dart';
import 'package:qayd/domain/repositories/app_update_repository.dart';
import 'package:qayd/domain/repositories/identity_repository.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/message_template_repository.dart';
import 'package:qayd/domain/repositories/notification_log_repository.dart';
import 'package:qayd/domain/repositories/notification_message_repository.dart';
import 'package:qayd/domain/repositories/transaction_fee_settings_repository.dart';
import 'package:qayd/domain/repositories/pos_activation_repository.dart';
import 'package:qayd/domain/repositories/pos_product_repository.dart';
import 'package:qayd/domain/repositories/pos_product_category_repository.dart';
import 'package:qayd/domain/repositories/pos_stock_movement_repository.dart';
import 'package:qayd/domain/repositories/pos_template_installation_repository.dart';
import 'package:qayd/domain/repositories/pos_accounting_posting_repository.dart';
import 'package:qayd/domain/repositories/pos_sale_posting_repository.dart';
import 'package:qayd/domain/repositories/pos_sales_return_posting_repository.dart';
import 'package:qayd/domain/repositories/pos_purchase_posting_repository.dart';
import 'package:qayd/domain/repositories/pos_purchase_request_identity_repository.dart';
import 'package:qayd/domain/repositories/pos_sales_return_request_identity_repository.dart';
import 'package:qayd/domain/services/voucher_qr_service.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/domain/services/balance_calculator.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/services/trial_balance_generator.dart';
import 'package:qayd/domain/services/balance_sheet_generator.dart';
import 'package:qayd/presentation/security/security_cubit.dart';
import 'package:qayd/data/security/ed25519_identity_service.dart';
import 'package:qayd/data/security/identity_file_storage.dart';
import 'package:qayd/data/security/mnemonic_vault.dart';
import 'package:qayd/data/repositories/remote_identity_repository.dart';
import 'package:qayd/domain/services/crypto_identity_service.dart';
import 'package:qayd/application/sync/sync_coordinator_service.dart';
import 'package:qayd/application/sync/audit_sync_dispatcher.dart';
import 'package:qayd/application/sync/audit_sync_processor.dart';
import 'package:qayd/application/sync/companion_link_service.dart';
import 'package:qayd/application/sync/device_pairing_qr_service.dart';
import 'package:qayd/application/sync/device_pairing_service.dart';
import 'package:qayd/application/sync/device_pairing_facade.dart';
import 'package:qayd/application/sync/manual_link_service.dart';
import 'package:qayd/application/sync/sync_facade.dart';
import 'package:qayd/application/sync/sync_payload_processor.dart';
import 'package:qayd/data/network/sync_socket_service.dart';
import 'package:qayd/domain/services/native_notification_service.dart';
import 'package:qayd/domain/services/notification_filter_service.dart';
import 'package:qayd/data/services/local_notification_service_impl.dart';
import 'package:qayd/data/repositories/api_sync_repository.dart';
import 'package:qayd/data/repositories/api_device_registry_repository.dart';
import 'package:qayd/data/security/e2ee_encryption_service_impl.dart';
import 'package:qayd/domain/services/e2ee_encryption_service.dart';
import 'package:qayd/domain/repositories/sync_repository.dart';
import 'package:qayd/domain/repositories/device_registry_repository.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/repositories/fiscal_period_repository.dart';
import 'package:qayd/domain/repositories/ledger_repository.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qayd/domain/repositories/app_config_repository.dart';
import 'package:qayd/data/repositories/api_app_config_repository.dart';
import 'package:qayd/domain/repositories/attachment_repository.dart';
import 'package:qayd/domain/repositories/collateral_repository.dart';
import 'package:qayd/data/repositories/sqlite_attachment_repository.dart';
import 'package:qayd/data/repositories/sqlite_collateral_repository.dart';
import 'package:qayd/data/services/attachment_storage_service.dart';
import 'package:qayd/data/services/device_contacts_service.dart';
import 'package:qayd/data/encryption/voucher_key_service.dart';
import 'package:qayd/application/notifications/list_inbox_notifications_use_case.dart';
import 'package:qayd/application/vouchers/liquidate_collateral_use_case.dart';
import 'package:qayd/application/vouchers/verify_incoming_voucher_use_case.dart';
import 'package:qayd/application/vouchers/withdraw_voucher_use_case.dart';
import 'package:qayd/application/vouchers/create_reversal_voucher_use_case.dart';
import 'package:qayd/application/vouchers/settle_voucher_use_case.dart';
import 'package:qayd/application/sync/p2p_sync_service.dart';
import 'package:qayd/data/repositories/outbox_dao.dart';
import 'package:qayd/data/repositories/device_sync_outbox_dao.dart';
import 'package:qayd/data/repositories/sync_watermark_dao.dart';
import 'package:qayd/data/repositories/sqlite_device_session_repository.dart';
import 'package:qayd/domain/services/signature_verification_engine.dart';
import 'package:qayd/domain/services/counterparty_qr_service.dart';
import 'package:qayd/presentation/pages/settings/groups/appearance_settings_cubit.dart';
import 'package:qayd/presentation/pos/pos_catalog_cubit.dart';
import 'package:qayd/presentation/pos/pos_checkout_cubit.dart';
import 'package:qayd/presentation/pos/pos_workspace_cubit.dart';
import 'package:qayd/presentation/pos/pos_stock_cubit.dart';
import 'package:qayd/presentation/pos/pos_feature_cubit.dart';
import 'package:qayd/presentation/pages/notifications/notifications_cubit.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/application/accruals/list_accruals_use_case.dart';
import 'package:qayd/application/accruals/save_accrual_use_case.dart';
import 'package:qayd/data/repositories/sqlite_accrual_repository.dart';
import 'package:qayd/domain/repositories/accrual_repository.dart';
import 'package:qayd/application/cost_centers/activate_cost_center_use_case.dart';
import 'package:qayd/application/cost_centers/create_cost_center_use_case.dart';
import 'package:qayd/application/cost_centers/get_cost_center_details_use_case.dart';
import 'package:qayd/application/cost_centers/list_cost_centers_use_case.dart';
import 'package:qayd/application/cost_centers/manage_dimensions_use_case.dart';
import 'package:qayd/application/cost_centers/suspend_cost_center_use_case.dart';
import 'package:qayd/data/repositories/sqlite_cost_center_repository.dart';
import 'package:qayd/domain/repositories/cost_center_repository.dart';
import 'package:qayd/domain/repositories/audit_log_repository.dart';
import 'package:qayd/domain/repositories/device_session_repository.dart';
import 'package:qayd/data/repositories/sqlite_audit_log_repository.dart';
import 'package:qayd/application/governance/audit_log_service.dart';
import 'package:qayd/application/management/seed_expense_accounts_use_case.dart';
import 'package:qayd/application/identity/delete_account_use_case.dart';
import 'package:qayd/observability/sentry_dio_observer.dart';

/// Result of attempting to open the encrypted database.
enum DatabaseOpenResult {
  /// Database opened successfully.
  success,

  /// The encryption key doesn't match the existing database file.
  /// User should be prompted to enter the primary key (mnemonic) or start fresh.
  keyMismatch,

  /// No database file exists yet (first run or after wipe).
  /// The database was created fresh — no recovery needed.
  freshCreated,

  /// An unexpected error occurred.
  otherError,
}

/// Composition root: encrypted DB, repositories, and use cases.
abstract final class InjectionContainer {
  static final UuidV4IdGenerator _idGenerator = UuidV4IdGenerator();

  static late DatabaseEncryptionKeyProvider _encryptionKeyProvider;

  /// Bumps after [reopenDatabaseAfterRestore] so the UI tree can rebuild.
  static final ValueNotifier<int> databaseEpoch = ValueNotifier<int>(0);

  /// Not `final`: replaced after a successful restore ([reopenDatabaseAfterRestore]).
  static late Database database;

  /// Whether the database has been successfully opened.
  static bool _databaseReady = false;

  /// Whether the database is ready for use.
  static bool get isDatabaseReady => _databaseReady;

  static late final BackupService backupService;
  static late final AutoBackupService autoBackupService;
  static late final GoogleDriveBackupService driveBackupService;
  static late final IdentityFileStorage identityFileStorage;

  // ── Phase 7: Security services ─────────────────────────────────────────────

  static late final AppPinStorage appPinStorage;
  static late final LicenseVault licenseVault;
  static late final HardwareIdService hardwareIdService;
  static late String currentDeviceId;
  static late final MonotonicClockGuard clockGuard;
  static late final PanicWipeService panicWipeService;
  static late final AuthRepository authRepository;
  static late final DeviceContactsService deviceContactsService;

  /// The unified security cubit — shared by [main.dart].
  static late final SecurityCubit securityCubit;

  /// Cubit for managing global appearance settings (theme, language).
  static late final AppearanceSettingsCubit appearanceSettingsCubit;

  // ── Cryptographic identity ─────────────────────────────────────────────

  static late final CryptoIdentityService cryptoIdentityService;
  static late final MnemonicVault mnemonicVault;
  static late final IdentityRepository identityRepository;
  static late final SetupIdentityUseCase setupIdentityUseCase;
  static late final UpdateProfileUseCase updateProfileUseCase;
  static late SyncIdentityToInternalAccountsUseCase
      syncIdentityToInternalAccountsUseCase;
  static late final LookupPublicKeyUseCase lookupPublicKeyUseCase;
  static late final ReceiptSigningService receiptSigningService;
  static late CanSyncWithAccountUseCase canSyncWithAccountUseCase;
  static late DeleteAccountUseCase deleteAccountUseCase;

  // ── Governance ─────────────────────────────────────────────────────────────

  static late final CheckGovernanceStatusUseCase checkGovernanceStatusUseCase;
  static late final SubmitActivationUseCase submitActivationUseCase;
  static late final GovernanceWriteGuard governanceWriteGuard;

  // ── Accounting Repositories (Static for Sync access) ──────────────────────

  static late AccountRepository accountRepository;
  static late LedgerRepository ledgerRepository;
  static late FiscalPeriodRepository fiscalPeriodRepository;
  static late VoucherRepository voucherRepository;
  static late CurrencyRepository currencyRepository;
  static late PosCurrencyRateRepository posCurrencyRateRepository;
  static late PosCurrencyConverter posCurrencyConverter;
  static late RecordPosCurrencyRateUseCase recordPosCurrencyRateUseCase;
  static late ListPosCurrencyRateHistoryUseCase
      listPosCurrencyRateHistoryUseCase;

  // ── Accounting use cases ───────────────────────────────────────────────────

  static late CreateAccountUseCase createAccountUseCase;
  static late BatchImportAccountsFromCsvUseCase
      batchImportAccountsFromCsvUseCase;
  static late UpdateAccountUseCase updateAccountUseCase;
  static late DeactivateAccountUseCase deactivateAccountUseCase;
  static late GetAccountDetailsUseCase getAccountDetailsUseCase;
  static late FindAccountByPhoneUseCase findAccountByPhoneUseCase;
  static late ListAccountsUseCase listAccountsUseCase;
  static late CreateFiscalPeriodUseCase createFiscalPeriodUseCase;
  static late CloseFiscalPeriodUseCase closeFiscalPeriodUseCase;
  static AutoFiscalClosingService? autoFiscalClosingService;
  static late ArchiveAccountUseCase archiveAccountUseCase;
  static late RestoreAccountUseCase restoreAccountUseCase;
  static late ListArchivedAccountsUseCase listArchivedAccountsUseCase;
  static late GetAccountStatementUseCase getAccountStatementUseCase;
  static late ListAccountStatementChatUseCase listAccountStatementChatUseCase;
  static late CreateVoucherUseCase createVoucherUseCase;
  static late CreateTripartiteTransferUseCase createTripartiteTransferUseCase;
  static late CreateDualTransferUseCase createDualTransferUseCase;
  static late UpdateDraftVoucherUseCase updateDraftVoucherUseCase;
  static late AcceptVoucherUseCase acceptVoucherUseCase;
  static late ConfirmVoucherUseCase confirmVoucherUseCase;
  static late RejectVoucherUseCase rejectVoucherUseCase;
  static late ResubmitVoucherUseCase resubmitVoucherUseCase;
  static late ListVouchersUseCase listVouchersUseCase;
  static late GetVoucherDetailsUseCase getVoucherDetailsUseCase;
  static late ResolveConflictUseCase resolveConflictUseCase;
  static late GenerateTrialBalanceUseCase generateTrialBalanceUseCase;
  static late GenerateBalanceSheetUseCase generateBalanceSheetUseCase;
  static late VoucherPdfGenerator voucherPdfGenerator;
  static late ListInboxNotificationsUseCase listInboxNotificationsUseCase;
  static late NotificationsCubit notificationsCubit;
  static late AccountStatementPdfGenerator accountStatementPdfGenerator;
  static late PosInvoicePdfGenerator posInvoicePdfGenerator;
  static late PosInvoiceSigningService posInvoiceSigningService;
  static late SignPosInvoiceUseCase signPosInvoiceUseCase;
  static late BuildPosInvoicePdfUseCase buildPosInvoicePdfUseCase;

  static late MessageTemplateRepository messageTemplateRepository;
  static late NotificationLogRepository notificationLogRepository;
  static late ListMessageTemplatesUseCase listMessageTemplatesUseCase;
  static late SaveMessageTemplateUseCase saveMessageTemplateUseCase;
  static late DeleteMessageTemplateUseCase deleteMessageTemplateUseCase;
  static late CreateMessageTemplateUseCase createMessageTemplateUseCase;
  static late LogNotificationIntentUseCase logNotificationIntentUseCase;
  static late NotificationMessageRepository notificationMessageRepository;
  static late GetAutoSuggestionsUseCase getAutoSuggestionsUseCase;
  static late MarkNotificationMessageProcessedUseCase
      markNotificationMessageProcessedUseCase;
  static late ListCurrenciesUseCase listCurrenciesUseCase;
  static late GetBaseCurrencyUseCase getBaseCurrencyUseCase;
  static late SetBaseCurrencyUseCase setBaseCurrencyUseCase;
  static late ToggleCurrencyStatusUseCase toggleCurrencyStatusUseCase;
  static late AddCurrencyUseCase addCurrencyUseCase;
  static late TransactionFeeSettingsRepository transactionFeeSettingsRepository;
  static late GetActiveTransactionFeeUseCase getActiveTransactionFeeUseCase;
  static late ManageTransactionFeeUseCase manageTransactionFeeUseCase;
  static late PosActivationRepository posActivationRepository;
  static late PosTemplateInstallationRepository
      posTemplateInstallationRepository;
  static late ActivatePosFeatureUseCase activatePosFeatureUseCase;
  static late PosFeatureCubit posFeatureCubit;
  static late PosProductRepository posProductRepository;
  static late PosProductCategoryRepository posProductCategoryRepository;
  static late CreatePosProductCategoryUseCase createPosProductCategoryUseCase;
  static late PosStockMovementRepository posStockMovementRepository;
  static late PosAccountingPostingRepository posAccountingPostingRepository;
  static late PosSalePostingRepository posSalePostingRepository;
  static late PosSalesReturnPostingRepository posSalesReturnPostingRepository;
  static late PosPurchasePostingRepository posPurchasePostingRepository;
  static late PosPurchaseRequestIdentityRepository
      posPurchaseRequestIdentityRepository;
  static late PosSalesReturnRequestIdentityRepository
      posSalesReturnRequestIdentityRepository;
  static late PosInvoiceReadRepository posInvoiceReadRepository;
  static late ListPosInvoicesUseCase listPosInvoicesUseCase;
  static late GetPosInvoiceDetailsUseCase getPosInvoiceDetailsUseCase;
  static late BuildPosDailySalesReportUseCase buildPosDailySalesReportUseCase;
  static late BuildPosSalePostingUseCase buildPosSalePostingUseCase;
  static late CompletePosSaleUseCase completePosSaleUseCase;
  static late BuildPosSalesReturnPostingUseCase
      buildPosSalesReturnPostingUseCase;
  static late CompletePosSalesReturnUseCase completePosSalesReturnUseCase;
  static late BuildPosPurchasePostingUseCase buildPosPurchasePostingUseCase;
  static late CompletePosPurchaseUseCase completePosPurchaseUseCase;
  static late GetPosStockBalanceUseCase getPosStockBalanceUseCase;
  static late ListPosStockMovementsUseCase listPosStockMovementsUseCase;
  static late BuildPosStockAdjustmentPostingUseCase
      buildPosStockAdjustmentPostingUseCase;
  static late PostPosStockAdjustmentAtomicallyUseCase
      postPosStockAdjustmentAtomicallyUseCase;
  static late RecordPosStockMovementUseCase recordPosStockMovementUseCase;
  static late PosStockCubit posStockCubit;
  static late CreatePosProductUseCase createPosProductUseCase;
  static late SavePosProductUseCase savePosProductUseCase;
  static late ListPosProductsUseCase listPosProductsUseCase;
  static late ListPosProductCategoriesUseCase listPosProductCategoriesUseCase;
  static late ResolvePosProductForCheckoutUseCase
      resolvePosProductForCheckoutUseCase;
  static late PosCheckoutCubit posCheckoutCubit;
  static late FindPosProductByBarcodeUseCase findPosProductByBarcodeUseCase;
  static late DeactivatePosProductUseCase deactivatePosProductUseCase;
  static late ReactivatePosProductUseCase reactivatePosProductUseCase;
  static late SavePosProductCategoryUseCase savePosProductCategoryUseCase;
  static late DeactivatePosProductCategoryUseCase
      deactivatePosProductCategoryUseCase;
  static late ReactivatePosProductCategoryUseCase
      reactivatePosProductCategoryUseCase;
  static late PosCatalogCubit posCatalogCubit;
  static late PosWorkspaceCubit posWorkspaceCubit;
  static late PostPosOpeningBalanceAtomicallyUseCase
      postPosOpeningBalanceAtomicallyUseCase;
  static late PostPosSaleAtomicallyUseCase postPosSaleAtomicallyUseCase;
  static late PostPosSalesReturnAtomicallyUseCase
      postPosSalesReturnAtomicallyUseCase;
  static late PostPosPurchaseAtomicallyUseCase postPosPurchaseAtomicallyUseCase;

  // ── Sync & Real-Time Components ──────────────────────────────────────────

  static late final NativeNotificationService nativeNotificationService;
  static late final NotificationFilterService notificationFilterService;
  static late SyncCoordinatorService syncCoordinatorService;
  static late final SyncSocketService syncSocketService;
  static late SyncPayloadProcessor syncPayloadProcessor;
  static late final SyncRepository syncRepository;
  static late final DeviceRegistryRepository deviceRegistryRepository;
  static late final E2EEEncryptionService e2eeService;

  // ── App Settings & Info ────────────────────────────────────────────────
  static late final SharedPreferences sharedPreferences;
  static late final AppConfigRepository appConfigRepository;
  static late final AppUpdateRepository appUpdateRepository;
  static late final CheckAppUpdateUseCase checkAppUpdateUseCase;
  static late final InstallAppUpdateUseCase installAppUpdateUseCase;
  static late final AppUpdateCubit appUpdateCubit;

  // ── Attachments & Collateral ────────────────────────────────────────────
  static late AttachmentRepository attachmentRepository;
  static late CollateralRepository collateralRepository;
  static late VoucherKeyService voucherKeyService;
  static late CollateralExpiryChecker collateralExpiryChecker;
  static late LiquidateCollateralUseCase liquidateCollateralUseCase;

  static late final AttachmentStorageService attachmentStorage;
  static late final RestoreFromBackupUseCase restoreFromBackupUseCase;
  static late final RestoreCubit restoreCubit;
  static late final SyncStatusCubit syncStatusCubit;

  // ── Digital Signature Protocol (§1–§5) ─────────────────────────────────
  static late SignatureVerificationEngine signatureVerificationEngine;
  static late VerifyIncomingVoucherUseCase verifyIncomingVoucherUseCase;
  static late final CounterpartyQrService counterpartyQrService;

  // ── Threaded Financial Interactions (Protocol v1.3) ─────────────────────
  static late WithdrawVoucherUseCase withdrawVoucherUseCase;
  static late CreateReversalVoucherUseCase createReversalVoucherUseCase;
  static late SettleVoucherUseCase settleVoucherUseCase;
  static late OutboxDao outboxDao;
  static late DeviceSyncOutboxDao deviceSyncOutboxDao;
  static late SyncWatermarkDao syncWatermarkDao;
  static late DeviceSessionRepository deviceSessionRepository;
  static late AuditSyncDispatcher auditSyncDispatcher;
  static late AuditSyncProcessor auditSyncProcessor;
  static late DevicePairingService devicePairingService;
  static late CompanionLinkService companionLinkService;
  static late ManualLinkService manualLinkService;
  static late DevicePairingFacade devicePairingFacade;
  static late SyncFacade syncFacade;
  static late P2PSyncService p2pSyncService;
  static late SyncEventDispatcher syncEventDispatcher;

  // ── Cost and Profit Centers ─────────────────────────────────────────────
  static late CostCenterRepository costCenterRepository;
  static late CreateCostCenterUseCase createCostCenterUseCase;
  static late AnalyzeForSuggestionsUseCase analyzeForSuggestionsUseCase;

  static late ListCostCentersUseCase listCostCentersUseCase;
  static late SuspendCostCenterUseCase suspendCostCenterUseCase;
  static late ActivateCostCenterUseCase activateCostCenterUseCase;
  static late GetCostCenterDetailsUseCase getCostCenterDetailsUseCase;
  static late ManageDimensionsUseCase manageDimensionsUseCase;
  static late UpdateCostCenterUseCase updateCostCenterUseCase;

  static late AccrualRepository accrualRepository;
  static late ListAccrualsUseCase listAccrualsUseCase;
  static late SaveAccrualUseCase saveAccrualUseCase;
  static late ProcessAccrualUseCase processAccrualUseCase;
  static late AuditLogRepository auditLogRepository;
  static late AuditLogService auditLogService;
  static late SeedExpenseAccountsUseCase seedExpenseAccountsUseCase;
  static late ManageAccountDefaultCostCentersUseCase
      manageAccountDefaultCostCentersUseCase;

  // ── Legacy Migration ───────────────────────────────────────────────────────
  static late LegacyMigrationUseCase legacyMigrationUseCase;

  /// Kept for backward compatibility (tests, etc.).
  /// Calls [initPreAuth] followed by [initDatabase].
  static Future<void> init({
    DatabaseEncryptionKeyProvider? encryptionKeyProvider,
  }) async {
    await initPreAuth(encryptionKeyProvider: encryptionKeyProvider);
    await initDatabase();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Phase A — Pre-Auth: lightweight services that do NOT require the database.
  // Called from main() at startup.
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> initPreAuth({
    DatabaseEncryptionKeyProvider? encryptionKeyProvider,
  }) async {
    // Force SharedPreferences up early as Pigeon channels for it can be finicky after hot restarts
    sharedPreferences = await SharedPreferences.getInstance();

    appearanceSettingsCubit = AppearanceSettingsCubit(sharedPreferences);

    appUpdateRepository = ShorebirdAppUpdateRepository();
    checkAppUpdateUseCase = CheckAppUpdateUseCase(
      repository: appUpdateRepository,
    );
    installAppUpdateUseCase = InstallAppUpdateUseCase(
      repository: appUpdateRepository,
    );
    appUpdateCubit = AppUpdateCubit(
      checkUpdate: checkAppUpdateUseCase,
      installUpdate: installAppUpdateUseCase,
    );

    // ── Phase 7: Security bootstrap ─────────────────────────────────────────

    appPinStorage = AppPinStorage();
    licenseVault = LicenseVault();
    hardwareIdService = HardwareIdService();
    clockGuard = MonotonicClockGuard();

    final hwId = await hardwareIdService.obtainHardwareId();
    currentDeviceId = hwId;
    identityFileStorage = IdentityFileStorage(hardwareId: hwId);

    panicWipeService = PanicWipeService(
      licenseVault: licenseVault,
      clockGuard: clockGuard,
      pinStorage: appPinStorage,
      identityFileStorage: identityFileStorage,
    );
    final apiClient = ApiClient(
      baseUrl: ApiEndpoints.baseUrl,
      tokenProvider: () => licenseVault.readJwt(),
      deviceIdProvider: () async => currentDeviceId,
      interceptors: <Interceptor>[
        SentryDioObserver(),
      ],
      onSecurityError: () {
        // As soon as any API call returns a 403 (Banned/Closed),
        // we force the security cubit to refresh its state and lock the UI.
        // We use isForced: true to bypass the refresh throttling.
        securityCubit.refreshLicenseStatus(isForced: true).ignore();
      },
      onDeviceRevoked: () {
        securityCubit.handleDeviceRevoked().ignore();
      },
    );

    appConfigRepository = ApiAppConfigRepository(
      apiClient: apiClient,
      sharedPreferences: sharedPreferences,
    );

    authRepository = RemoteAuthRepository(apiClient: apiClient);

    // ── Governance ──────────────────────────────────────────────────────────
    // Uses LicenseVault (populated by Auth API) as the authoritative source.
    // This ensures GovernanceWriteGuard reflects real server state without
    // a separate API call.
    final governanceRemote = LicenseVaultGovernanceRemoteDataSource(
      licenseVault: licenseVault,
    );
    final governanceRepository = GovernanceRepositoryImpl(governanceRemote);
    checkGovernanceStatusUseCase = CheckGovernanceStatusUseCase(
      governanceRepository,
    );
    submitActivationUseCase = SubmitActivationUseCase(governanceRepository);
    governanceWriteGuard = GovernanceWriteGuard(checkGovernanceStatusUseCase);

    // ── Native Notifications & E2EE Service ──────────────────────────────────
    nativeNotificationService = LocalNotificationServiceImpl(sharedPreferences);
    await nativeNotificationService.initialize();
    notificationFilterService = NotificationFilterService(sharedPreferences);
    e2eeService = const E2EEEncryptionServiceImpl();
    counterpartyQrService = const CounterpartyQrService();
    syncRepository = ApiSyncRepository(
      apiClient,
      currentDeviceId: currentDeviceId,
    );
    deviceRegistryRepository = ApiDeviceRegistryRepository(
      apiClient: apiClient,
      currentDeviceId: currentDeviceId,
    );
    deviceContactsService = const DeviceContactsService();

    // ── Cryptographic identity ─────────────────────────────────────────────

    cryptoIdentityService = const Ed25519IdentityService();
    mnemonicVault = MnemonicVault();
    identityRepository = RemoteIdentityRepository(apiClient: apiClient);
    setupIdentityUseCase = SetupIdentityUseCase(
      cryptoService: cryptoIdentityService,
      mnemonicVault: mnemonicVault,
      identityRepository: identityRepository,
      identityFileStorage: identityFileStorage,
      accountRepositoryProvider: () => accountRepository,
    );
    companionLinkService = CompanionLinkService(
      qrService: const DevicePairingQrService(),
      e2eeService: e2eeService,
      apiClient: apiClient,
      mnemonicVault: mnemonicVault,
      licenseVault: licenseVault,
      setupIdentityUseCase: setupIdentityUseCase,
      getCurrentKeyPair: () => setupIdentityUseCase.getKeyPair(),
      cryptoIdentityService: cryptoIdentityService,
      deviceRegistryRepository: deviceRegistryRepository,
      getCurrentDeviceId: () async => currentDeviceId,
      // deviceSessionRepository is injected later in _initializeDatabaseDependentStack
      // once the SQLite stack is ready (it requires the DB to be open).
    );
    manualLinkService = ManualLinkService(apiClient: apiClient);
    updateProfileUseCase = UpdateProfileUseCase(
      identityRepository: identityRepository,
      licenseVault: licenseVault,
    );
    lookupPublicKeyUseCase = LookupPublicKeyUseCase(
      identityRepository: identityRepository,
    );
    receiptSigningService = ReceiptSigningService(
      cryptoService: cryptoIdentityService,
    );
    posInvoiceSigningService = PosInvoiceSigningService(
      receiptSigningService: receiptSigningService,
    );
    signPosInvoiceUseCase = SignPosInvoiceUseCase(
      signingService: posInvoiceSigningService,
      setupIdentityUseCase: setupIdentityUseCase,
    );

    if (!await mnemonicVault.hasIdentity()) {
      await identityFileStorage.restoreToVaultIfAvailable(mnemonicVault);
    }

    // ── Encryption key provider ─────────────────────────────────────────────

    _encryptionKeyProvider = encryptionKeyProvider ??
        HardwareBackedEncryptionKeyProvider(
          hardwareIdService: hardwareIdService,
          licenseVault: licenseVault,
        );

    backupService = BackupService(keyProvider: _encryptionKeyProvider);
    autoBackupService = AutoBackupService();
    driveBackupService = GoogleDriveBackupService();

    restoreFromBackupUseCase = RestoreFromBackupUseCase(
      backupService: backupService,
      identityFileStorage: identityFileStorage,
      mnemonicVault: mnemonicVault,
    );

    restoreCubit = RestoreCubit(
      autoBackupService: autoBackupService,
      driveService: driveBackupService,
      restoreUseCase: restoreFromBackupUseCase,
      keyProvider:
          _encryptionKeyProvider as HardwareBackedEncryptionKeyProvider,
      mnemonicVault: mnemonicVault,
    );

    attachmentStorage = AttachmentStorageService(
      keyProvider: _encryptionKeyProvider,
      voucherKeyService: const VoucherKeyService(),
    );

    // ── Sync Socket (needs no DB) ───────────────────────────────────────────
    final baseUrl = ApiEndpoints.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse(baseUrl);
    final protocol = uri.scheme == 'https' ? 'wss' : 'ws';
    final host = uri.host;
    final port = uri.hasPort ? ':${uri.port}' : '';
    const appKey = String.fromEnvironment(
      'REVERB_APP_KEY',
      defaultValue: 'gpdnqol0mdp28abcbdl7',
    );

    syncSocketService = SyncSocketService(
      wsUrl:
          '$protocol://$host$port/app/$appKey?protocol=7&client=js&version=8.3.0',
      tokenProvider: () => licenseVault.readJwt(),
      authUrl: '$baseUrl/api/broadcasting/auth',
    );

    syncStatusCubit = SyncStatusCubit();

    // ── Phase 7: Security bootstrap (pre-auth — no DB deps) ─────────────────
    securityCubit = SecurityCubit(
      pinStorage: appPinStorage,
      licenseVault: licenseVault,
      hardwareIdService: hardwareIdService,
      clockGuard: clockGuard,
      panicWipeService: panicWipeService,
      authRepository: authRepository,
      // syncIdentityUseCase is DB-dependent; bound later in initDatabase().
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Phase B — Post-Auth: opens the encrypted database and wires up the full
  // SQLite stack, sync engine, and remaining use cases.
  // Called ONLY after the user has been authenticated.
  // ═══════════════════════════════════════════════════════════════════════════

  /// Opens the database and registers all DB-dependent services.
  ///
  /// Returns [DatabaseOpenResult.success] on happy path.
  /// Returns [DatabaseOpenResult.keyMismatch] when the existing DB file
  /// can't be decrypted with the current key — the caller should prompt
  /// for the primary key (mnemonic) or offer to start fresh.
  static Future<DatabaseOpenResult> initDatabase() async {
    // Check whether a database file already exists.
    final dbPath = await DatabaseProvider.databaseFilePath();
    final dbFileExists = File(dbPath).existsSync();

    try {
      database =
          await DatabaseProvider.open(keyProvider: _encryptionKeyProvider);
    } on DatabaseException catch (e) {
      debugPrint('InjectionContainer: Database open failed: $e');
      if (dbFileExists) {
        // A file exists but the key didn't work → key mismatch.
        return DatabaseOpenResult.keyMismatch;
      }
      // No file existed and creation still failed → unexpected.
      return DatabaseOpenResult.otherError;
    } catch (e) {
      debugPrint('InjectionContainer: Unexpected DB error: $e');
      return DatabaseOpenResult.otherError;
    }

    await _initializeDatabaseDependentStack();

    // § Sync Repair: Ensure all confirmed/settled vouchers have ledger entries
    // This repairs legacy vouchers synced from primary devices before AuditLog
    // correctly tracked ledger_entry creations.
    try {
      await auditLogService.repairMissingLedgerEntries();
    } catch (e) {
      debugPrint('DevicePairing: ⚠️ Failed to repair ledger entries: $e');
    }

    autoBackupService.performIfDue().ignore();
    driveBackupService.performIfDue().ignore();

    return dbFileExists
        ? DatabaseOpenResult.success
        : DatabaseOpenResult.freshCreated;
  }

  /// Attempts to open the database with a key derived from the user's mnemonic.
  ///
  /// Used when [initDatabase] returns [DatabaseOpenResult.keyMismatch].
  /// Returns `true` if the database opened successfully.
  static Future<bool> retryDatabaseWithMnemonic(String mnemonic) async {
    final hwProvider =
        _encryptionKeyProvider as HardwareBackedEncryptionKeyProvider;
    final derivedKey = await hwProvider.deriveKeyFromMnemonic(mnemonic);
    await hwProvider.updateCachedKey(derivedKey);
    final result = await initDatabase();

    if (result == DatabaseOpenResult.success ||
        result == DatabaseOpenResult.freshCreated) {
      try {
        final phrase = MnemonicPhrase.fromPhrase(mnemonic);
        await setupIdentityUseCase.recoverFromMnemonic(phrase);
        await licenseVault.setIsCompanionDevice(false);
      } catch (e) {
        debugPrint('Failed to fully recover identity from mnemonic: $e');
      }
      return true;
    }
    return false;
  }

  /// Deletes the existing database file and creates a new empty one.
  ///
  /// Used when the user chooses to "start fresh" after a key mismatch.
  static Future<DatabaseOpenResult> resetDatabaseAndInit() async {
    final dbPath = await DatabaseProvider.databaseFilePath();
    await deleteDatabase(dbPath);
    return initDatabase();
  }

  static Future<void> closeDatabaseForRestore() async {
    if (_databaseReady) {
      syncCoordinatorService.stop();
      await database.close();
      _databaseReady = false;
    }
  }

  static Future<void> reopenDatabaseAfterRestore() async {
    database = await DatabaseProvider.open(keyProvider: _encryptionKeyProvider);
    await _initializeDatabaseDependentStack();
    databaseEpoch.value++;

    // §5.E: After restore, heal stale attachment storage paths.
    // Absolute paths in the DB may point to the old device's filesystem.
    // This is a best-effort operation; failures are non-fatal.
    try {
      final freshAttachRepo = SqliteAttachmentRepository(database);
      final imagesDir = await const BackupFileManager().externalImagesDir();
      if (imagesDir != null) {
        await freshAttachRepo.healStoragePathsAfterRestore(imagesDir);
      }
    } catch (e) {
      debugPrint('InjectionContainer: healStoragePaths failed (non-fatal): $e');
    }
  }

  /// Wipes the local database and identity completely, without wiping the current
  /// authentication session (JWT/LicenseVault).
  /// Used when switching accounts to prevent data mixing.
  static Future<void> wipeLocalDataForAccountSwitch() async {
    await closeDatabaseForRestore();

    final dbPath = await DatabaseProvider.databaseFilePath();
    await deleteDatabase(dbPath);

    await mnemonicVault.deleteAll();
    await appPinStorage.clearPinAndLock();
    await identityFileStorage.delete();
    await clockGuard.delete();

    // Sign out of Google Drive to prevent the new user from syncing to the previous user's drive
    try {
      await driveBackupService.signOut();
    } catch (_) {
      // Ignore errors (e.g., no internet or play services missing)
    }
  }

  static Future<void> _initializeDatabaseDependentStack() async {
    _registerSqliteStack();
    _databaseReady = true;

    // §C-6: Now that the SQLite stack is ready, inject deviceSessionRepository
    // into companionLinkService so companion registration can persist locally.
    companionLinkService.deviceSessionRepository = deviceSessionRepository;

    // ── Bind DB-dependent services to the SecurityCubit ──────────────────────
    securityCubit.syncIdentityUseCase = syncIdentityToInternalAccountsUseCase;

    // ── Real-Time Sync Engine ────────────────────────────────────────────────
    syncPayloadProcessor = SyncPayloadProcessor(
      identityRepository: identityRepository,
      voucherRepository: voucherRepository,
      ledgerRepository: ledgerRepository,
      accountRepository: accountRepository,
      currencyRepository: currencyRepository,
      e2eeService: e2eeService,
      signingService: receiptSigningService,
      getCurrentUserKeyPair: () =>
          setupIdentityUseCase.getKeyPair().then((v) => v!),
      attachmentRepository: attachmentRepository,
      collateralRepository: collateralRepository,
      voucherKeyService: voucherKeyService,
      notificationMessageRepository: notificationMessageRepository,
      notificationFilterService: notificationFilterService,
      auditLogService: auditLogService,
      auditSyncProcessor: auditSyncProcessor,
      onDecryptionFailure: (nodeId) =>
          syncStatusCubit.reportDecryptionfailure(nodeId),
    );

    // ── Collateral expiry monitoring (must init before sync coordinator) ──
    collateralExpiryChecker = CollateralExpiryChecker(
      collateralRepository: collateralRepository,
      notificationService: nativeNotificationService,
    );

    // ── Real-time Sync Engine Initialization ─────────────────────────────────
    final licenseData = await licenseVault.readLicenseData();
    final userId = (licenseData?['id'] as num?)?.toInt() ?? 0;

    syncCoordinatorService = SyncCoordinatorService(
      syncRepository: syncRepository,
      socketService: syncSocketService,
      payloadProcessor: syncPayloadProcessor,
      nativeNotificationService: nativeNotificationService,
      notificationFilterService: notificationFilterService,
      currentUserId: userId,
      collateralExpiryChecker: collateralExpiryChecker,
      notificationMessageRepository: notificationMessageRepository,
      outboxDao: outboxDao,
      deviceSyncOutboxDao: deviceSyncOutboxDao,
      watermarkDao: syncWatermarkDao,
      voucherRepository: voucherRepository,
      syncEventDispatcher: syncEventDispatcher,
      currentDeviceId: currentDeviceId,
    );
    syncFacade = SyncFacade(syncCoordinatorService);

    devicePairingService = DevicePairingService(
      deviceSessionRepository: deviceSessionRepository,
      deviceRegistryRepository: deviceRegistryRepository,
      auditLogRepository: auditLogRepository,
      auditSyncDispatcher: auditSyncDispatcher,
      companionLinkService: companionLinkService,
      licenseVault: licenseVault,
      syncCoordinatorService: syncCoordinatorService,
      database: database,
    );

    devicePairingFacade = DevicePairingFacade(
      pairingService: devicePairingService,
      sessionRepository: deviceSessionRepository,
      manualLinkService: manualLinkService,
    );

    if (userId > 0) {
      syncCoordinatorService.start();
    }
    autoFiscalClosingService?.start();

    seedExpenseAccountsUseCase = SeedExpenseAccountsUseCase(
      accountRepository,
      createAccountUseCase,
      costCenterRepository,
      createCostCenterUseCase,
      manageDimensionsUseCase,
    );

    deleteAccountUseCase = DeleteAccountUseCase(
      identityRepository: identityRepository,
      autoBackupService: autoBackupService,
      driveBackupService: driveBackupService,
      mnemonicVault: mnemonicVault,
      licenseVault: licenseVault,
      appPinStorage: appPinStorage,
      identityFileStorage: identityFileStorage,
      database: database,
    );
  }

  static void _registerSqliteStack() {
    outboxDao = OutboxDao(database);
    deviceSyncOutboxDao = DeviceSyncOutboxDao(database);
    syncWatermarkDao = SyncWatermarkDao(database);
    deviceSessionRepository = SqliteDeviceSessionRepository(database);

    syncEventDispatcher = SyncEventDispatcher(
      outboxDao: outboxDao,
      e2eeEncryptionService: e2eeService,
      accountRepository: SqliteAccountRepository(database),
      identityRepository: identityRepository,
      getCurrentUserKeyPair: () => setupIdentityUseCase.getKeyPair(),
      attachmentKeyProvider: _encryptionKeyProvider,
      // §5.E: attachmentRepository is initialized later in _registerSqliteStack,
      // but SyncEventDispatcher only calls it lazily during dispatchVoucherClaim,
      // which is always after full initialization — so this forward reference is safe.
      attachmentRepository: SqliteAttachmentRepository(database),
    );

    accountRepository = SqliteAccountRepository(database);
    signatureVerificationEngine = SignatureVerificationEngine(
      signingService: receiptSigningService,
      accountRepository: accountRepository,
      identityRepository: identityRepository,
    );
    ledgerRepository = SqliteLedgerRepository(database);
    fiscalPeriodRepository = SqliteFiscalPeriodRepository(database);
    final transactionRunner = DatabaseTransactionRunner(database);
    final sqliteVoucherRepository =
        SqliteVoucherRepository(database, transactionRunner);
    voucherRepository = sqliteVoucherRepository;
    currencyRepository = SqliteCurrencyRepository(database);
    posCurrencyRateRepository = SqlitePosCurrencyRateRepository(
      database,
      currencyRepository,
    );
    posCurrencyConverter = PosCurrencyConverter(posCurrencyRateRepository);
    recordPosCurrencyRateUseCase = RecordPosCurrencyRateUseCase(
      rateRepository: posCurrencyRateRepository,
      currencyRepository: currencyRepository,
      writeGuard: governanceWriteGuard,
      idGenerator: _idGenerator,
    );
    listPosCurrencyRateHistoryUseCase =
        ListPosCurrencyRateHistoryUseCase(posCurrencyRateRepository);
    posInvoiceReadRepository = SqlitePosInvoiceReadRepository(
      database,
      currencyRepository,
    );
    listPosInvoicesUseCase = ListPosInvoicesUseCase(
      repository: posInvoiceReadRepository,
    );
    getPosInvoiceDetailsUseCase = GetPosInvoiceDetailsUseCase(
      repository: posInvoiceReadRepository,
    );
    buildPosDailySalesReportUseCase = BuildPosDailySalesReportUseCase(
      repository: posInvoiceReadRepository,
    );
    attachmentRepository = SqliteAttachmentRepository(database);
    collateralRepository = SqliteCollateralRepository(database);
    messageTemplateRepository = SqliteMessageTemplateRepository(database);
    notificationLogRepository = SqliteNotificationLogRepository(database);
    notificationMessageRepository = SqliteNotificationMessageRepository(
      database,
    );
    voucherKeyService = const VoucherKeyService();
    const balanceCalculator = BalanceCalculator();
    const entryGenerator = EntryGenerator();
    const trialBalanceGenerator = TrialBalanceGenerator();
    const balanceSheetGenerator = BalanceSheetGenerator();
    const voucherQrService = VoucherQrService();

    // ── Cost and Profit Centers ───────────────────────────────────────────
    costCenterRepository = SqliteCostCenterRepository(database);
    auditLogRepository = SqliteAuditLogRepository(database);
    auditSyncDispatcher = AuditSyncDispatcher(
      outboxDao: deviceSyncOutboxDao,
      e2eeService: e2eeService,
      getCurrentKeyPair: () => setupIdentityUseCase.getKeyPair(),
    );
    auditLogService = AuditLogService(
      auditRepo: auditLogRepository,
      database: database,
      auditSyncDispatcher: auditSyncDispatcher,
      deviceSessionRepository: deviceSessionRepository,
      getCurrentDeviceId: () async => currentDeviceId,
    );
    auditSyncProcessor = AuditSyncProcessor(
      auditLogRepository: auditLogRepository,
      auditLogService: auditLogService,
    );

    transactionFeeSettingsRepository = SqliteTransactionFeeSettingsRepository(
      database,
    );
    getActiveTransactionFeeUseCase = GetActiveTransactionFeeUseCase(
      transactionFeeSettingsRepository,
    );
    manageTransactionFeeUseCase = ManageTransactionFeeUseCase(
      transactionFeeSettingsRepository,
      _idGenerator,
      auditLogService: auditLogService,
    );

    final sqlitePosActivationRepository = SqlitePosActivationRepository(
      database,
      _idGenerator,
    );
    posActivationRepository = sqlitePosActivationRepository;
    posTemplateInstallationRepository = sqlitePosActivationRepository;
    activatePosFeatureUseCase = ActivatePosFeatureUseCase(
      posActivationRepository,
      governanceWriteGuard,
    );
    posFeatureCubit = PosFeatureCubit(
      activateUseCase: activatePosFeatureUseCase,
      repository: posActivationRepository,
      deviceIdProvider: () => currentDeviceId,
    );

    posProductRepository = SqlitePosProductRepository(
      database,
      currencyRepository,
    );
    posProductCategoryRepository = SqlitePosProductCategoryRepository(database);
    listPosProductCategoriesUseCase = ListPosProductCategoriesUseCase(
      posProductCategoryRepository,
    );
    createPosProductCategoryUseCase = CreatePosProductCategoryUseCase(
      posProductCategoryRepository,
      governanceWriteGuard,
      _idGenerator,
    );
    savePosProductCategoryUseCase = SavePosProductCategoryUseCase(
      posProductCategoryRepository,
      governanceWriteGuard,
    );
    deactivatePosProductCategoryUseCase = DeactivatePosProductCategoryUseCase(
      posProductCategoryRepository,
      governanceWriteGuard,
    );
    reactivatePosProductCategoryUseCase = ReactivatePosProductCategoryUseCase(
      posProductCategoryRepository,
      governanceWriteGuard,
    );
    final sqliteStockMovementRepository =
        SqlitePosStockMovementRepository(database, currencyRepository);
    posStockMovementRepository = sqliteStockMovementRepository;
    posAccountingPostingRepository = SqlitePosAccountingPostingRepository(
      transactionRunner,
      sqliteStockMovementRepository,
      sqliteVoucherRepository,
    );
    final sqlitePosSalePostingRepository = SqlitePosSalePostingRepository(
      transactionRunner,
      sqliteStockMovementRepository,
      sqliteVoucherRepository,
    );
    posSalePostingRepository = sqlitePosSalePostingRepository;
    final sqlitePosSalesReturnPostingRepository =
        SqlitePosSalesReturnPostingRepository(
      transactionRunner,
      sqliteStockMovementRepository,
      sqliteVoucherRepository,
    );
    posSalesReturnPostingRepository = sqlitePosSalesReturnPostingRepository;
    final sqlitePosPurchasePostingRepository =
        SqlitePosPurchasePostingRepository(
      transactionRunner,
      sqliteStockMovementRepository,
      sqliteVoucherRepository,
    );
    posPurchasePostingRepository = sqlitePosPurchasePostingRepository;
    posPurchaseRequestIdentityRepository =
        SqlitePosPurchaseRequestIdentityRepository(database);
    posSalesReturnRequestIdentityRepository =
        SqlitePosSalesReturnRequestIdentityRepository(database);
    postPosOpeningBalanceAtomicallyUseCase =
        PostPosOpeningBalanceAtomicallyUseCase(
      writeGuard: governanceWriteGuard,
      installationRepository: posTemplateInstallationRepository,
      productRepository: posProductRepository,
      accountRepository: accountRepository,
      fiscalPeriodRepository: fiscalPeriodRepository,
      buildPosting: BuildPosOpeningBalancePostingUseCase(),
      postingRepository: posAccountingPostingRepository,
      idGenerator: _idGenerator,
    );
    buildPosSalePostingUseCase = BuildPosSalePostingUseCase(
      productRepository: posProductRepository,
      stockRepository: posStockMovementRepository,
      installationRepository: posTemplateInstallationRepository,
      accountRepository: accountRepository,
      idGenerator: _idGenerator,
      currencyConverter: posCurrencyConverter,
    );
    postPosSaleAtomicallyUseCase = PostPosSaleAtomicallyUseCase(
      writeGuard: governanceWriteGuard,
      fiscalPeriodRepository: fiscalPeriodRepository,
      postingRepository: posSalePostingRepository,
    );
    completePosSaleUseCase = CompletePosSaleUseCase(
      buildPosting: buildPosSalePostingUseCase,
      postAtomically: postPosSaleAtomicallyUseCase,
      signInvoice: signPosInvoiceUseCase,
    );
    buildPosSalesReturnPostingUseCase = BuildPosSalesReturnPostingUseCase(
      invoiceRepository: posInvoiceReadRepository,
      installationRepository: posTemplateInstallationRepository,
    );
    postPosSalesReturnAtomicallyUseCase = PostPosSalesReturnAtomicallyUseCase(
      writeGuard: governanceWriteGuard,
      fiscalPeriodRepository: fiscalPeriodRepository,
      postingRepository: posSalesReturnPostingRepository,
    );
    completePosSalesReturnUseCase = CompletePosSalesReturnUseCase(
      buildPosting: buildPosSalesReturnPostingUseCase,
      postAtomically: postPosSalesReturnAtomicallyUseCase,
      signInvoice: signPosInvoiceUseCase,
      invoiceRepository: posInvoiceReadRepository,
      requestIdentityRepository: posSalesReturnRequestIdentityRepository,
    );
    buildPosPurchasePostingUseCase = BuildPosPurchasePostingUseCase(
      productRepository: posProductRepository,
      installationRepository: posTemplateInstallationRepository,
      accountRepository: accountRepository,
      currencyConverter: posCurrencyConverter,
    );
    postPosPurchaseAtomicallyUseCase = PostPosPurchaseAtomicallyUseCase(
      writeGuard: governanceWriteGuard,
      fiscalPeriodRepository: fiscalPeriodRepository,
      postingRepository: posPurchasePostingRepository,
    );
    completePosPurchaseUseCase = CompletePosPurchaseUseCase(
      buildPosting: buildPosPurchasePostingUseCase,
      postAtomically: postPosPurchaseAtomicallyUseCase,
      signInvoice: signPosInvoiceUseCase,
    );
    getPosStockBalanceUseCase = GetPosStockBalanceUseCase(
      posStockMovementRepository,
    );
    listPosStockMovementsUseCase = ListPosStockMovementsUseCase(
      posStockMovementRepository,
    );
    buildPosStockAdjustmentPostingUseCase =
        const BuildPosStockAdjustmentPostingUseCase();
    postPosStockAdjustmentAtomicallyUseCase =
        PostPosStockAdjustmentAtomicallyUseCase(
      writeGuard: governanceWriteGuard,
      installationRepository: posTemplateInstallationRepository,
      productRepository: posProductRepository,
      stockRepository: posStockMovementRepository,
      accountRepository: accountRepository,
      fiscalPeriodRepository: fiscalPeriodRepository,
      buildPosting: buildPosStockAdjustmentPostingUseCase,
      postingRepository: posAccountingPostingRepository,
      idGenerator: _idGenerator,
    );
    recordPosStockMovementUseCase = RecordPosStockMovementUseCase(
      posStockMovementRepository,
      posProductRepository,
      governanceWriteGuard,
      _idGenerator,
    );
    posStockCubit = PosStockCubit(
      getBalanceUseCase: getPosStockBalanceUseCase,
      recordMovementUseCase: recordPosStockMovementUseCase,
    );
    createPosProductUseCase = CreatePosProductUseCase(
      posProductRepository,
      currencyRepository,
      governanceWriteGuard,
      _idGenerator,
    );
    savePosProductUseCase = SavePosProductUseCase(
      posProductRepository,
      governanceWriteGuard,
    );
    listPosProductsUseCase = ListPosProductsUseCase(posProductRepository);
    findPosProductByBarcodeUseCase = FindPosProductByBarcodeUseCase(
      posProductRepository,
    );
    resolvePosProductForCheckoutUseCase =
        ResolvePosProductForCheckoutUseCase(posProductRepository);
    posCheckoutCubit = PosCheckoutCubit(
      resolveProduct: resolvePosProductForCheckoutUseCase,
      listProducts: listPosProductsUseCase,
      currencyConverter: posCurrencyConverter,
      completeSale: completePosSaleUseCase,
      idGenerator: _idGenerator,
    );
    deactivatePosProductUseCase = DeactivatePosProductUseCase(
      posProductRepository,
      governanceWriteGuard,
    );
    reactivatePosProductUseCase = ReactivatePosProductUseCase(
      posProductRepository,
      governanceWriteGuard,
    );
    posCatalogCubit = PosCatalogCubit(
      listUseCase: listPosProductsUseCase,
      saveUseCase: savePosProductUseCase,
      createUseCase: createPosProductUseCase,
      deactivateUseCase: deactivatePosProductUseCase,
      reactivateUseCase: reactivatePosProductUseCase,
    );

    listCurrenciesUseCase = ListCurrenciesUseCase(currencyRepository);
    getBaseCurrencyUseCase = GetBaseCurrencyUseCase(currencyRepository);
    posWorkspaceCubit = PosWorkspaceCubit(
      activationRepository: posActivationRepository,
      getBaseCurrencyUseCase: getBaseCurrencyUseCase,
      listCurrenciesUseCase: listCurrenciesUseCase,
    );
    setBaseCurrencyUseCase = SetBaseCurrencyUseCase(
      currencyRepository,
      auditLogService: auditLogService,
    );
    toggleCurrencyStatusUseCase = ToggleCurrencyStatusUseCase(
      currencyRepository,
      auditLogService: auditLogService,
    );
    addCurrencyUseCase = AddCurrencyUseCase(
      currencyRepository,
      auditLogService: auditLogService,
    );

    createAccountUseCase = CreateAccountUseCase(
      accountRepository,
      _idGenerator,
      governanceWriteGuard,
      licenseVault,
      auditLogService: auditLogService,
    );

    batchImportAccountsFromCsvUseCase = BatchImportAccountsFromCsvUseCase(
      createAccountUseCase,
    );
    updateAccountUseCase = UpdateAccountUseCase(
      accountRepository,
      governanceWriteGuard,
      licenseVault,
      auditLogService: auditLogService,
    );

    archiveAccountUseCase = ArchiveAccountUseCase(
      accountRepository,
      ledgerRepository,
      balanceCalculator,
      governanceWriteGuard,
      auditLogService: auditLogService,
    );
    restoreAccountUseCase = RestoreAccountUseCase(
      accountRepository,
      governanceWriteGuard,
      auditLogService: auditLogService,
    );
    listArchivedAccountsUseCase =
        ListArchivedAccountsUseCase(accountRepository);
    deactivateAccountUseCase = DeactivateAccountUseCase(
      accountRepository,
      ledgerRepository,
      balanceCalculator,
      governanceWriteGuard,
      auditLogService: auditLogService,
    );
    getAccountDetailsUseCase = GetAccountDetailsUseCase(
      accountRepository,
      ledgerRepository,
      balanceCalculator,
    );
    findAccountByPhoneUseCase =
        FindAccountByPhoneUseCase(accountRepository, licenseVault);
    manageAccountDefaultCostCentersUseCase =
        ManageAccountDefaultCostCentersUseCase(accountRepository);
    listAccountsUseCase = ListAccountsUseCase(
      accountRepository,
      ledgerRepository,
      balanceCalculator,
      voucherRepository,
      fiscalPeriodRepository,
    );
    createFiscalPeriodUseCase = CreateFiscalPeriodUseCase(
      fiscalPeriodRepository,
      governanceWriteGuard,
      _idGenerator,
    );
    closeFiscalPeriodUseCase = CloseFiscalPeriodUseCase(
      fiscalPeriodRepository,
      ledgerRepository,
      accountRepository,
      voucherRepository,
      balanceCalculator,
      governanceWriteGuard,
      _idGenerator,
      receiptSigningService,
      () => setupIdentityUseCase.getKeyPair(),
      sharedPreferences,
    );
    autoFiscalClosingService?.stop();
    autoFiscalClosingService = AutoFiscalClosingService(
      prefs: sharedPreferences,
      fiscalRepository: fiscalPeriodRepository,
      createFiscalPeriodUseCase: createFiscalPeriodUseCase,
      closeFiscalPeriodUseCase: closeFiscalPeriodUseCase,
    );

    getAccountStatementUseCase = GetAccountStatementUseCase(
      accountRepository,
      ledgerRepository,
      voucherRepository,
    );
    listAccountStatementChatUseCase = ListAccountStatementChatUseCase(
      accountRepository: accountRepository,
      voucherRepository: voucherRepository,
      fiscalPeriodRepository: fiscalPeriodRepository,
      notificationMessageRepository: notificationMessageRepository,
    );
    createVoucherUseCase = CreateVoucherUseCase(
      voucherRepository,
      currencyRepository,
      attachmentRepository,
      attachmentStorage,
      _idGenerator,
      governanceWriteGuard,
      fiscalPeriodRepository,
      accountRepository: accountRepository,
      signingService: receiptSigningService,
      getKeyPair: () => setupIdentityUseCase.getKeyPair(),
      licenseVault: licenseVault,
      syncEventDispatcher: syncEventDispatcher,
      costCenterRepository: costCenterRepository,
      entryGenerator: entryGenerator,
      auditLogService: auditLogService,
      collateralRepository: collateralRepository,
    );
    createTripartiteTransferUseCase = CreateTripartiteTransferUseCase(
      voucherRepository,
      currencyRepository,
      _idGenerator,
      governanceWriteGuard,
      getActiveTransactionFeeUseCase,
      accountRepository,
      entryGenerator,
      syncEventDispatcher: syncEventDispatcher,
      auditLogService: auditLogService,
    );
    createDualTransferUseCase = CreateDualTransferUseCase(
      voucherRepository,
      currencyRepository,
      _idGenerator,
      governanceWriteGuard,
      accountRepository,
      entryGenerator,
      syncEventDispatcher: syncEventDispatcher,
      auditLogService: auditLogService,
    );
    updateDraftVoucherUseCase = UpdateDraftVoucherUseCase(
      voucherRepository,
      currencyRepository,
      governanceWriteGuard,
      fiscalPeriodRepository,
      auditLogService: auditLogService,
    );
    confirmVoucherUseCase = ConfirmVoucherUseCase(
      voucherRepository,
      entryGenerator,
      _idGenerator,
      governanceWriteGuard,
      fiscalPeriodRepository,
      accountRepository: accountRepository,
      signingService: receiptSigningService,
      getKeyPair: () => setupIdentityUseCase.getKeyPair(),
      licenseVault: licenseVault,
      syncEventDispatcher: syncEventDispatcher,
      auditLogService: auditLogService,
    );
    rejectVoucherUseCase = RejectVoucherUseCase(
      voucherRepository,
      governanceWriteGuard,
      syncEventDispatcher: syncEventDispatcher,
      auditLogService: auditLogService,
    );
    resubmitVoucherUseCase = ResubmitVoucherUseCase(
      voucherRepository,
      governanceWriteGuard,
      auditLogService: auditLogService,
    );
    listVouchersUseCase = ListVouchersUseCase(
      voucherRepository,
      accountRepository,
      collateralRepository,
    );

    getVoucherDetailsUseCase = GetVoucherDetailsUseCase(
      voucherRepository,
      accountRepository,
      voucherQrService,
      licenseVault,
      attachmentRepository,
      collateralRepository,
      costCenterRepository,
      ledgerRepository,
      signatureVerificationEngine,
    );

    syncIdentityToInternalAccountsUseCase =
        SyncIdentityToInternalAccountsUseCase(
      accountRepository: accountRepository,
      licenseVault: licenseVault,
    );

    canSyncWithAccountUseCase = CanSyncWithAccountUseCase(
      identityRepository: identityRepository,
      accountRepository: accountRepository,
    );

    generateTrialBalanceUseCase = GenerateTrialBalanceUseCase(
      accountRepository,
      ledgerRepository,
      trialBalanceGenerator,
    );
    generateBalanceSheetUseCase = GenerateBalanceSheetUseCase(
      accountRepository,
      ledgerRepository,
      balanceSheetGenerator,
    );
    voucherPdfGenerator = const CairoVoucherPdfGenerator();
    accountStatementPdfGenerator = const CairoAccountStatementPdfGenerator();
    posInvoicePdfGenerator = const CairoPosInvoicePdfGenerator();
    buildPosInvoicePdfUseCase = BuildPosInvoicePdfUseCase(
      generator: posInvoicePdfGenerator,
    );

    analyzeForSuggestionsUseCase = AnalyzeForSuggestionsUseCase(
      voucherRepository,
      notificationMessageRepository,
    );
    listMessageTemplatesUseCase = ListMessageTemplatesUseCase(
      messageTemplateRepository,
    );
    saveMessageTemplateUseCase = SaveMessageTemplateUseCase(
      messageTemplateRepository,
      auditLogService: auditLogService,
    );
    deleteMessageTemplateUseCase = DeleteMessageTemplateUseCase(
      messageTemplateRepository,
      auditLogService: auditLogService,
    );
    createMessageTemplateUseCase = CreateMessageTemplateUseCase(
      messageTemplateRepository,
      _idGenerator,
      auditLogService: auditLogService,
    );
    getAutoSuggestionsUseCase = GetAutoSuggestionsUseCase(
      notificationMessageRepository,
      voucherRepository,
    );
    markNotificationMessageProcessedUseCase =
        MarkNotificationMessageProcessedUseCase(notificationMessageRepository);
    logNotificationIntentUseCase = LogNotificationIntentUseCase(
      notificationLogRepository,
      notificationMessageRepository,
      _idGenerator,
    );

    listInboxNotificationsUseCase = ListInboxNotificationsUseCase(
      notificationRepo: notificationMessageRepository,
      accountRepository: accountRepository,
    );
    notificationsCubit = NotificationsCubit(
      listInboxNotificationsUseCase,
      markNotificationMessageProcessedUseCase,
    );

    // ── Collateral services ──────────────────────────────────────────────
    // (collateralExpiryChecker initialized earlier — before sync coordinator)

    liquidateCollateralUseCase = LiquidateCollateralUseCase(
      collateralRepository: collateralRepository,
      voucherRepository: voucherRepository,
      ledgerRepository: ledgerRepository,
      accountRepository: accountRepository,
      entryGenerator: entryGenerator,
      balanceCalculator: balanceCalculator,
      idGenerator: _idGenerator,
      governanceWriteGuard: governanceWriteGuard,
      auditLogService: auditLogService,
    );

    // ── Digital Signature Protocol services ────────────────────────────────
    verifyIncomingVoucherUseCase = VerifyIncomingVoucherUseCase(
      voucherRepository: voucherRepository,
      accountRepository: accountRepository,
      verificationEngine: signatureVerificationEngine,
      licenseVault: licenseVault,
    );
    acceptVoucherUseCase = AcceptVoucherUseCase(
      voucherRepository: voucherRepository,
      accountRepository: accountRepository,
      signingService: receiptSigningService,
      getCurrentUserKeyPair: () =>
          setupIdentityUseCase.getKeyPair().then((v) => v!),
      licenseVault: licenseVault,
      entryGenerator: entryGenerator,
      idGenerator: _idGenerator,
      syncEventDispatcher: syncEventDispatcher,
      auditLogService: auditLogService,
    );

    // ── Threaded Financial Interactions ──────────────────────────────────
    withdrawVoucherUseCase = WithdrawVoucherUseCase(
      voucherRepository,
      governanceWriteGuard,
      syncEventDispatcher: syncEventDispatcher,
      auditLogService: auditLogService,
    );
    createReversalVoucherUseCase = CreateReversalVoucherUseCase(
      voucherRepository,
      currencyRepository,
      _idGenerator,
      governanceWriteGuard,
      auditLogService: auditLogService,
    );
    settleVoucherUseCase = SettleVoucherUseCase(
      voucherRepository,
      governanceWriteGuard,
      auditLogService: auditLogService,
    );
    p2pSyncService = P2PSyncService(
      outboxDao: outboxDao,
      watermarkDao: syncWatermarkDao,
    );
    resolveConflictUseCase = ResolveConflictUseCase(
      notificationMessageRepository,
      confirmVoucherUseCase,
    );

    // ── Cost and Profit Centers ───────────────────────────────────────────
    createCostCenterUseCase = CreateCostCenterUseCase(
      costCenterRepository,
      _idGenerator,
    );
    listCostCentersUseCase = ListCostCentersUseCase(costCenterRepository);
    suspendCostCenterUseCase = SuspendCostCenterUseCase(
      costCenterRepository,
      auditLogService: auditLogService,
    );
    activateCostCenterUseCase = ActivateCostCenterUseCase(
      costCenterRepository,
      auditLogService: auditLogService,
    );
    getCostCenterDetailsUseCase = GetCostCenterDetailsUseCase(
      costCenterRepository,
    );
    updateCostCenterUseCase = UpdateCostCenterUseCase(
      costCenterRepository,
      auditLogService: auditLogService,
    );
    manageDimensionsUseCase = ManageDimensionsUseCase(
      costCenterRepository,
      _idGenerator,
      auditLogService: auditLogService,
    );

    accrualRepository = SqliteAccrualRepository(database);
    listAccrualsUseCase = ListAccrualsUseCase(accrualRepository);
    saveAccrualUseCase = SaveAccrualUseCase(
      accrualRepository,
      _idGenerator,
      auditLogService: auditLogService,
    );
    processAccrualUseCase =
        ProcessAccrualUseCase(accrualRepository, createVoucherUseCase);

    // ── Legacy Migration ─────────────────────────────────────────────────────
    legacyMigrationUseCase = LegacyMigrationUseCase(
      accountRepository,
      voucherRepository,
      currencyRepository,
      entryGenerator,
      _idGenerator,
      signingService: receiptSigningService,
      getKeyPair: () => setupIdentityUseCase.getKeyPair(),
      licenseVault: licenseVault,
      deviceContactsService: deviceContactsService,
    );
  }
}
