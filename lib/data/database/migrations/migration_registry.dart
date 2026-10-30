import 'package:qayd/data/database/migrations/migration_001.dart';
import 'package:qayd/data/database/migrations/migration_002_voucher_fts.dart';
import 'package:qayd/data/database/migrations/migration_003_message_templates.dart';
import 'package:qayd/data/database/migrations/migration_004_notification_messages.dart';
import 'package:qayd/data/database/migrations/migration_005_notification_messages_suggestion_columns.dart';
import 'package:qayd/data/database/migrations/migration_006.dart';
import 'package:qayd/data/database/migrations/migration_007_party_details.dart';
import 'package:qayd/data/database/migrations/migration_008_voucher_signatures.dart';
import 'package:qayd/data/database/migrations/migration_009_imported_signatures.dart';
import 'package:qayd/data/database/migrations/migration_010_tripartite_transfer.dart';
import 'package:qayd/data/database/migrations/migration_011_default_accounts.dart';
import 'package:qayd/data/database/migrations/migration_012_currency_is_active.dart';
import 'package:qayd/data/database/migrations/migration_013_transaction_fees.dart';
import 'package:qayd/data/database/migrations/migration_014_attachments.dart';
import 'package:qayd/data/database/migrations/migration_015_collaterals.dart';
import 'package:qayd/data/database/migrations/migration_016_counterparty_keys.dart';
import 'package:qayd/data/database/migrations/migration_017_threaded_interactions.dart';
import 'package:qayd/data/database/migrations/migration_018_outbox.dart';
import 'package:qayd/data/database/migrations/migration_019_sync_watermarks.dart';
import 'package:qayd/data/database/migrations/migration_020_cost_centers.dart';
import 'package:qayd/data/database/migrations/migration_021_remittance.dart';
import 'package:qayd/data/database/migrations/migration_022_personal_economy_upgrade.dart';
import 'package:qayd/data/database/migrations/migration_023_fix_fts_triggers.dart';
import 'package:qayd/data/database/migrations/migration_024_audit_logs.dart';
import 'package:qayd/data/database/migrations/migration_025_account_archive.dart';
import 'package:qayd/data/database/migrations/migration_026_account_default_cost_centers.dart';
import 'package:qayd/data/database/migrations/migration_027_gold_silver_currencies.dart';
import 'package:qayd/data/database/migrations/migration_028_canonical_phones.dart';
import 'package:qayd/data/database/migrations/migration_029_outbox_routing_headers.dart';
import 'package:qayd/data/database/migrations/migration_030_attachment_key.dart';
import 'package:qayd/data/database/migrations/migration_031_audit_log_enhancements.dart';
import 'package:qayd/data/database/migrations/migration_032_audit_log_severity_and_indexes.dart';
import 'package:qayd/data/database/migrations/migration_033_add_fee_type.dart';
import 'package:qayd/data/database/migrations/migration_034_device_sync.dart';
import 'package:qayd/data/database/migrations/migration_035_fiscal_periods.dart';
import 'package:qayd/data/database/migrations/migration_036_backfill_audit_sync_seq.dart';
import 'package:qayd/data/database/migrations/migration_037_voucher_is_inbound.dart';
import 'package:qayd/data/database/migrations/migration_038_device_role.dart';
import 'package:qayd/data/database/migrations/migration_039_backfill_default_accounts_audit.dart';
import 'package:qayd/data/database/migrations/migration_040_pos_foundation.dart';
import 'package:qayd/data/database/migrations/migration_041_pos_invoice_metadata.dart';
import 'package:qayd/data/database/migrations/migration_042_pos_product_categories.dart';
import 'package:qayd/data/database/migrations/migration_043_pos_line_cost_currency.dart';
import 'package:qayd/data/database/migrations/migration_044_pos_currency_rates.dart';
import 'package:qayd/data/database/migrations/migration_045_pos_currency_snapshots_and_margins.dart';
import 'package:qayd/data/database/migrations/schema_migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Ordered migrations; [applyFromTo] runs `up` for versions in (from, to].
final class MigrationRegistry {
  MigrationRegistry._();

  static final List<SchemaMigration> _all = [
    Migration001(),
    Migration002VoucherFts(),
    Migration003MessageTemplates(),
    Migration004NotificationMessages(),
    Migration005NotificationMessagesSuggestionColumns(),
    Migration006(),
    Migration007PartyDetails(),
    Migration008VoucherSignatures(),
    Migration009ImportedSignatures(),
    Migration010TripartiteTransfer(),
    Migration011DefaultAccounts(),
    Migration012CurrencyIsActive(),
    Migration013TransactionFees(),
    Migration014Attachments(),
    Migration015Collaterals(),
    Migration016CounterpartyKeys(),
    Migration017ThreadedInteractions(),
    Migration018Outbox(),
    Migration019SyncWatermarks(),
    Migration020CostCenters(),
    Migration021Remittance(),
    Migration022PersonalEconomyUpgrade(),
    Migration023FixFtsTriggers(),
    Migration024AuditLogs(),
    Migration025AccountArchive(),
    Migration026AccountDefaultCostCenters(),
    Migration027GoldSilverCurrencies(),
    Migration028CanonicalPhones(),
    Migration029OutboxRoutingHeaders(),
    Migration030AttachmentKey(),
    Migration031AuditLogEnhancements(),
    Migration032AuditLogSeverityAndIndexes(),
    Migration033AddFeeType(),
    Migration034DeviceSync(),
    Migration035FiscalPeriods(),
    Migration036BackfillAuditSyncSeq(),
    Migration037VoucherIsInbound(),
    Migration038DeviceRole(),
    Migration039BackfillDefaultAccountsAudit(),
    Migration040PosFoundation(),
    Migration041PosInvoiceMetadata(),
    Migration042PosProductCategories(),
    Migration043PosLineCostCurrency(),
    Migration044PosCurrencyRates(),
    Migration045PosCurrencySnapshotsAndMargins(),
  ];

  static List<SchemaMigration> get ordered {
    final copy = [..._all];
    copy.sort((a, b) => a.version.compareTo(b.version));
    return List.unmodifiable(copy);
  }

  static Future<void> applyFromTo(
    Database db, {
    required int fromVersion,
    required int toVersion,
  }) async {
    for (final m in ordered) {
      if (m.version > fromVersion && m.version <= toVersion) {
        await m.up(db);
      }
    }
  }
}
