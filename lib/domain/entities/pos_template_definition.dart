import 'package:qayd/domain/value_objects/account_classification.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/standard_account_classification_kind.dart';

/// Stable identity of an account provisioned by the POS template.
enum PosTemplateAccountKey {
  inventoryAsset,
  salesRevenue,
  costOfGoodsSold,
  posCash,
  customerReceivables,
  supplierPayables,
  salesReturns,
  purchaseReturns,
  discounts,
  taxPayable,
  openingBalanceClearing,
  inventoryLossExpense;

  String get value => 'pos.${switch (this) {
        PosTemplateAccountKey.inventoryAsset => 'inventory_asset',
        PosTemplateAccountKey.salesRevenue => 'sales_revenue',
        PosTemplateAccountKey.costOfGoodsSold => 'cogs',
        PosTemplateAccountKey.posCash => 'cash',
        PosTemplateAccountKey.customerReceivables => 'customer_receivables',
        PosTemplateAccountKey.supplierPayables => 'supplier_payables',
        PosTemplateAccountKey.salesReturns => 'sales_returns',
        PosTemplateAccountKey.purchaseReturns => 'purchase_returns',
        PosTemplateAccountKey.discounts => 'discounts',
        PosTemplateAccountKey.taxPayable => 'tax_payable',
        PosTemplateAccountKey.openingBalanceClearing =>
          'opening_balance_clearing',
        PosTemplateAccountKey.inventoryLossExpense => 'inventory_loss_expense',
      }}';
}

/// One account specification in the opt-in POS template.
final class PosTemplateAccountSpec {
  const PosTemplateAccountSpec({
    required this.key,
    required this.name,
    required this.classification,
    required this.isOptional,
  });

  final PosTemplateAccountKey key;
  final String name;
  final AccountClassification classification;
  final bool isOptional;

  AccountNature get nature => classification.defaultNature;
}

/// Versioned, deterministic POS setup manifest.
///
/// This is a domain definition only. It never writes to the database. The
/// activation use case is responsible for installing it after explicit opt-in.
final class PosTemplateDefinition {
  const PosTemplateDefinition._({
    required this.templateKey,
    required this.version,
    required this.warehouseCode,
    required this.costMethod,
    required this.accounts,
  });

  static const String coreTemplateKey = 'pos.core';
  static const int currentVersion = 3;
  static const String weightedAverageCostMethod = 'weighted_average';

  final String templateKey;
  final int version;
  final String warehouseCode;
  final String costMethod;
  final List<PosTemplateAccountSpec> accounts;

  static PosTemplateDefinition current() {
    return PosTemplateDefinition._(
      templateKey: coreTemplateKey,
      version: currentVersion,
      warehouseCode: 'POS-MAIN',
      costMethod: weightedAverageCostMethod,
      accounts: List.unmodifiable(<PosTemplateAccountSpec>[
        PosTemplateAccountSpec(
          key: PosTemplateAccountKey.inventoryAsset,
          name: 'POS Inventory',
          classification: AccountClassification.custom(
            name: 'POS Inventory',
            nature: AccountNature.debit,
          ),
          isOptional: false,
        ),
        PosTemplateAccountSpec(
          key: PosTemplateAccountKey.openingBalanceClearing,
          name: 'POS Opening Balance Clearing',
          classification: AccountClassification.custom(
            name: 'POS Opening Balance Clearing',
            nature: AccountNature.credit,
          ),
          isOptional: false,
        ),
        PosTemplateAccountSpec(
          key: PosTemplateAccountKey.salesRevenue,
          name: 'POS Sales Revenue',
          classification: AccountClassification.custom(
            name: 'POS Sales Revenue',
            nature: AccountNature.credit,
          ),
          isOptional: false,
        ),
        PosTemplateAccountSpec(
          key: PosTemplateAccountKey.costOfGoodsSold,
          name: 'POS Cost of Goods Sold',
          classification: AccountClassification.custom(
            name: 'POS Cost of Goods Sold',
            nature: AccountNature.debit,
          ),
          isOptional: false,
        ),
        PosTemplateAccountSpec(
          key: PosTemplateAccountKey.inventoryLossExpense,
          name: 'POS Inventory Losses',
          classification: AccountClassification.custom(
            name: 'POS Inventory Losses',
            nature: AccountNature.debit,
          ),
          isOptional: false,
        ),
        PosTemplateAccountSpec(
          key: PosTemplateAccountKey.posCash,
          name: 'POS Cash',
          classification: AccountClassification.standard(
            StandardAccountClassificationKind.liquidAssets,
          ),
          isOptional: false,
        ),
        PosTemplateAccountSpec(
          key: PosTemplateAccountKey.customerReceivables,
          name: 'POS Customer Receivables',
          classification: AccountClassification.standard(
            StandardAccountClassificationKind.receivables,
          ),
          isOptional: false,
        ),
        PosTemplateAccountSpec(
          key: PosTemplateAccountKey.supplierPayables,
          name: 'POS Supplier Payables',
          classification: AccountClassification.standard(
            StandardAccountClassificationKind.payables,
          ),
          isOptional: false,
        ),
        PosTemplateAccountSpec(
          key: PosTemplateAccountKey.salesReturns,
          name: 'POS Sales Returns',
          classification: AccountClassification.custom(
            name: 'POS Sales Returns',
            nature: AccountNature.debit,
          ),
          isOptional: false,
        ),
        PosTemplateAccountSpec(
          key: PosTemplateAccountKey.purchaseReturns,
          name: 'POS Purchase Returns',
          classification: AccountClassification.custom(
            name: 'POS Purchase Returns',
            nature: AccountNature.credit,
          ),
          isOptional: false,
        ),
        PosTemplateAccountSpec(
          key: PosTemplateAccountKey.discounts,
          name: 'POS Discounts',
          classification: AccountClassification.custom(
            name: 'POS Discounts',
            nature: AccountNature.debit,
          ),
          isOptional: false,
        ),
        PosTemplateAccountSpec(
          key: PosTemplateAccountKey.taxPayable,
          name: 'POS Tax Payable',
          classification: AccountClassification.standard(
            StandardAccountClassificationKind.payables,
          ),
          isOptional: true,
        ),
      ]),
    );
  }

  PosTemplateAccountSpec account(PosTemplateAccountKey key) {
    return accounts.firstWhere((spec) => spec.key == key);
  }
}
