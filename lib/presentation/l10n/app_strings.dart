import 'app_strings_base.dart';
import 'app_strings_ar.dart';
import 'app_strings_en.dart';

class AppStrings {
  static AppStringsBase i = AppStringsAr();

  static String languageCode = 'ar';

  static void setLocale(String languageCode) {
    AppStrings.languageCode = languageCode;
    if (languageCode == 'en') {
      i = AppStringsEn();
    } else {
      i = AppStringsAr();
    }
  }

  static String get aBondThatHas => i.aBondThatHas;
  static String get aBridgeBetweenSender => i.aBridgeBetweenSender;
  static String get aCollectionCenterFor => i.aCollectionCenterFor;
  static String get aConfirmedOrSettled => i.aConfirmedOrSettled;
  static String get aConfirmedOrSettled1 => i.aConfirmedOrSettled1;
  static String get aFinancialAccountAnd => i.aFinancialAccountAnd;
  static String get aGramOfGold => i.aGramOfGold;
  static String get aGramOfSilver => i.aGramOfSilver;
  static String get aNewDigitalIdentity => i.aNewDigitalIdentity;
  static String get aPossibleMatchHas => i.aPossibleMatchHas;
  static String get aReturnCannotBe => i.aReturnCannotBe;
  static String get aSettledBondIs => i.aSettledBondIs;
  static String get acceptedAndSigned => i.acceptedAndSigned;
  static String get accessToContacts => i.accessToContacts;
  static String get account => i.account;
  static String get accountAnalysis => i.accountAnalysis;
  static String get accountBalanceDefaultTemplate =>
      i.accountBalanceDefaultTemplate;
  static String get accountBalanceLabel => i.accountBalanceLabel;
  static String get accountCreatedSuccess => i.accountCreatedSuccess;
  static String get accountDetailTitle => i.accountDetailTitle;
  static String get accountDetailsAccountnamencurrentBalance =>
      i.accountDetailsAccountnamencurrentBalance;
  static String get accountErasureIsA => i.accountErasureIsA;
  static String get accountHolderData => i.accountHolderData;
  static String get accountId => i.accountId;
  static String get accountId1 => i.accountId1;
  static String get accountLabel => i.accountLabel;
  static String get accountName => i.accountName;
  static String get accountName1 => i.accountName1;
  static String get accountNameLabel => i.accountNameLabel;
  static String get accountNameRequired => i.accountNameRequired;
  static String get accountSendMessageTooltip => i.accountSendMessageTooltip;
  static String get accountStatement => i.accountStatement;
  static String get accountStatement1 => i.accountStatement1;
  static String get accountStatementASystem => i.accountStatementASystem;
  static String get accountStatementConversation =>
      i.accountStatementConversation;
  static String get accountStatementExportPdfTooltip =>
      i.accountStatementExportPdfTooltip;
  static String get accountTransactionsCouldNot =>
      i.accountTransactionsCouldNot;
  static String get accountTypeChild => i.accountTypeChild;
  static String get accountTypeLabel => i.accountTypeLabel;
  static String get accountTypeRoot => i.accountTypeRoot;
  static String get accountUpdatedSuccess => i.accountUpdatedSuccess;
  static String get accountingRecordingSystem => i.accountingRecordingSystem;
  static String get accounts => i.accounts;
  static String get accountsCouldNotBe => i.accountsCouldNotBe;
  static String get accountsEmpty => i.accountsEmpty;
  static String get accountsEmptyFiltered => i.accountsEmptyFiltered;
  static String get accountsPayableYouOwe => i.accountsPayableYouOwe;
  static String get accountsReceivableYours => i.accountsReceivableYours;
  static String get accrualActiveLabel => i.accrualActiveLabel;
  static String get accrualAddFab => i.accrualAddFab;
  static String get accrualAmountInvalid => i.accrualAmountInvalid;
  static String get accrualAmountLabel => i.accrualAmountLabel;
  static String get accrualCategoryLabel => i.accrualCategoryLabel;
  static String get accrualCreateTitle => i.accrualCreateTitle;
  static String get accrualDescriptionLabel => i.accrualDescriptionLabel;
  static String get accrualDestAccountHint => i.accrualDestAccountHint;
  static String get accrualDestAccountLabel => i.accrualDestAccountLabel;
  static String get accrualDestAccountRequired => i.accrualDestAccountRequired;
  static String get accrualDueSoonLabel => i.accrualDueSoonLabel;
  static String get accrualEmptyState => i.accrualEmptyState;
  static String get accrualFrequencyLabel => i.accrualFrequencyLabel;
  static String get accrualListTitle => i.accrualListTitle;
  static String get accrualMonthlySummaryLabel => i.accrualMonthlySummaryLabel;
  static String get accrualNameHint => i.accrualNameHint;
  static String get accrualNameLabel => i.accrualNameLabel;
  static String get accrualNameRequired => i.accrualNameRequired;
  static String get accrualNextDueDateLabel => i.accrualNextDueDateLabel;
  static String get accrualNextDuePrefix => i.accrualNextDuePrefix;
  static String get accrualPayTooltip => i.accrualPayTooltip;
  static String get accrualProcessConfirmAction =>
      i.accrualProcessConfirmAction;
  static String get accrualProcessConfirmTitle => i.accrualProcessConfirmTitle;
  static String get accrualProcessedSuccess => i.accrualProcessedSuccess;
  static String get accrualSaveAction => i.accrualSaveAction;
  static String get accrualSavedSuccess => i.accrualSavedSuccess;
  static String get accrualSourceAccountHint => i.accrualSourceAccountHint;
  static String get accrualSourceAccountLabel => i.accrualSourceAccountLabel;
  static String get accrualsAndLiabilitiesTitle =>
      i.accrualsAndLiabilitiesTitle;
  static String get acquisitionCurrency => i.acquisitionCurrency;
  static String get actionAdd => i.actionAdd;
  static String get actionAttachImages => i.actionAttachImages;
  static String get actionCall => i.actionCall;
  static String get actionCopy => i.actionCopy;
  static String get actionCopyBank => i.actionCopyBank;
  static String get actionDelete => i.actionDelete;
  static String get actionDetails => i.actionDetails;
  static String get actionCancel => i.actionCancel;
  static String get actionConfirm => i.actionConfirm;
  static String get actionOk => i.actionOk;
  static String get actionOpenSettings => i.actionOpenSettings;
  static String get actionProceedAndConfirm => i.actionProceedAndConfirm;
  static String get actionRecordTransaction => i.actionRecordTransaction;
  static String get actionShare => i.actionShare;
  static String get actionWhatsApp => i.actionWhatsApp;
  static String get activationCouldNotBe => i.activationCouldNotBe;
  static String get activationDataIsIncorrect => i.activationDataIsIncorrect;
  static String get activationFieldRequired => i.activationFieldRequired;
  static String get activationHasExpiredPlease => i.activationHasExpiredPlease;
  static String get activationLicenseLabel => i.activationLicenseLabel;
  static String get activationOrgIdLabel => i.activationOrgIdLabel;
  static String get activationSubmit => i.activationSubmit;
  static String get activationSubtitle => i.activationSubtitle;
  static String get active => i.active;
  static String get actualSellingValue => i.actualSellingValue;
  static String get addADefaultCost => i.addADefaultCost;
  static String get addAMortgagesecurity => i.addAMortgagesecurity;
  static String get addANewCurrency => i.addANewCurrency;
  static String get addAccountFab => i.addAccountFab;
  static String get addAnAmounttoRecipients => i.addAnAmounttoRecipients;
  static String get addChildAccountTooltip => i.addChildAccountTooltip;
  static String get addCostCenterFab => i.addCostCenterFab;
  static String get addInternalVoucherFab => i.addInternalVoucherFab;
  static String get addition => i.addition;
  static String get addressingBondConflicts => i.addressingBondConflicts;
  static String get adoption => i.adoption;
  static String get adversaries => i.adversaries;
  static String get affectedAccount => i.affectedAccount;
  static String get affectedAccountSection => i.affectedAccountSection;
  static String get afghanistan => i.afghanistan;
  static String get agreeToTermsRequired => i.agreeToTermsRequired;
  static String get agreementAccepted => i.agreementAccepted;
  static String get agreementRejected => i.agreementRejected;
  static String get agreementUnderRequest => i.agreementUnderRequest;
  static String get agreementUnverified => i.agreementUnverified;
  static String get ahmedKamalAlNasser => i.ahmedKamalAlNasser;
  static String get albania => i.albania;
  static String get alderney => i.alderney;
  static String get alertMortgageDueDate => i.alertMortgageDueDate;
  static String get algeria => i.algeria;
  static String get allLabel => i.allLabel;
  static String get allMovements => i.allMovements;
  static String get allowAccess => i.allowAccess;
  static String get allowList => i.allowList;
  static String get allowsEveryoneExceptUsers => i.allowsEveryoneExceptUsers;
  static String get almost => i.almost;
  static String get alnasserExchangeAndTransfers =>
      i.alnasserExchangeAndTransfers;
  static String get amendment => i.amendment;
  static String get americanSamoa => i.americanSamoa;
  static String get amount => i.amount;
  static String get anAccountThatHas => i.anAccountThatHas;
  static String get anAccountWithA => i.anAccountWithA;
  static String get anAccountWithA1 => i.anAccountWithA1;
  static String get anAccountWithA2 => i.anAccountWithA2;
  static String get anErrorOccurred => i.anErrorOccurred;
  static String get anErrorOccurredWhile => i.anErrorOccurredWhile;
  static String get anErrorOccurredWhile1 => i.anErrorOccurredWhile1;
  static String get anUnexpectedErrorOccurred => i.anUnexpectedErrorOccurred;
  static String get anUnexpectedErrorOccurred1 => i.anUnexpectedErrorOccurred1;
  static String get anUnexpectedErrorOccurred2 => i.anUnexpectedErrorOccurred2;
  static String get anUnexpectedErrorOccurred3 => i.anUnexpectedErrorOccurred3;
  static String get and => i.and;
  static String get andLabel => i.andLabel;
  static String get andorra => i.andorra;
  static String get angola => i.angola;
  static String get anguilla => i.anguilla;
  static String get annually => i.annually;
  static String get anonymousParty => i.anonymousParty;
  static String get antarctica => i.antarctica;
  static String get antiguaAndBarbuda => i.antiguaAndBarbuda;
  static String get appTitle => i.appTitle;
  static String get appearanceLanguage => i.appearanceLanguage;
  static String get appearanceThemeMode => i.appearanceThemeMode;
  static String get approved => i.approved;
  static String get april => i.april;
  static String get archiveAccountAction => i.archiveAccountAction;
  static String get archiveAccountConfirm => i.archiveAccountConfirm;
  static String get archiveAccountSuccess => i.archiveAccountSuccess;
  static String get archiveAccountWarningText => i.archiveAccountWarningText;
  static String get archivedAccountsEmpty => i.archivedAccountsEmpty;
  static String get archivedAccountsTitle => i.archivedAccountsTitle;
  static String get argentina => i.argentina;
  static String get armenia => i.armenia;
  static String get arrestDocument => i.arrestDocument;
  static String get aruba => i.aruba;
  static String get asNumtostringasfixed0Hour => i.asNumtostringasfixed0Hour;
  static String get assetWizardIncomeSourceLabel =>
      i.assetWizardIncomeSourceLabel;
  static String get assetWizardInvestmentTitle => i.assetWizardInvestmentTitle;
  static String get assetWizardPossessionTitle => i.assetWizardPossessionTitle;
  static String get assets => i.assets;
  static String get assets1 => i.assets1;
  static String get assetsEmptyList => i.assetsEmptyList;
  static String get assetsLabel => i.assetsLabel;
  static String get attachPhotos => i.attachPhotos;
  static String get attachment => i.attachment;
  static String get attachments => i.attachments;
  static String get auditLogTitle => i.auditLogTitle;
  static String get august => i.august;
  static String get australia => i.australia;
  static String get austria => i.austria;
  static String get autoBackupLastBackupLabel => i.autoBackupLastBackupLabel;
  static String get autoBackupNever => i.autoBackupNever;
  static String get autoBackupRunNow => i.autoBackupRunNow;
  static String get autoBackupRunNowSuccess => i.autoBackupRunNowSuccess;
  static String get autoBackupSaveToDevice => i.autoBackupSaveToDevice;
  static String get autoBackupSavedExternal => i.autoBackupSavedExternal;
  static String get autoBackupToggleSubtitle => i.autoBackupToggleSubtitle;
  static String get autoBackupToggleTitle => i.autoBackupToggleTitle;
  static String get automaticClassificationGeneration =>
      i.automaticClassificationGeneration;
  static String get automaticallyDetecting => i.automaticallyDetecting;
  static String get automaticallyExportedAndDigitally =>
      i.automaticallyExportedAndDigitally;
  static String accountStatementShareText(String accountName, String format) =>
      i.accountStatementShareText(accountName, format);
  static String voucherTripartiteShareText(
          String sender, String receiver, String amount, String reference) =>
      i.voucherTripartiteShareText(sender, receiver, amount, reference);
  static String voucherStandardShareText(
          String voucherType, String counterpartyName, String amount) =>
      i.voucherStandardShareText(voucherType, counterpartyName, amount);
  static String shareTextAccount(String name) => i.shareTextAccount(name);
  static String shareTextDescription(String desc) =>
      i.shareTextDescription(desc);
  static String shareTextNetBalance(String balance) =>
      i.shareTextNetBalance(balance);
  static String shareTextReference(String ref) => i.shareTextReference(ref);
  static String shareTextVerificationFingerprint(String fingerprint) =>
      i.shareTextVerificationFingerprint(fingerprint);
  static String voucherReceiptShareText(String reference) =>
      i.voucherReceiptShareText(reference);
  static String get dateLabel => i.dateLabel;
  static String get amountLabel => i.amountLabel;
  static String get clientLabel => i.clientLabel;
  static String get senderLabel => i.senderLabel;
  static String get receiverLabel => i.receiverLabel;
  static String get mediatorLabel => i.mediatorLabel;
  static String get signatureSenderLabel => i.signatureSenderLabel;
  static String get signatureReceiverLabel => i.signatureReceiverLabel;
  static String get autostring => i.autostring;
  static String get autostring1 => i.autostring1;
  static String get autostring2 => i.autostring2;
  static String get autostring3 => i.autostring3;
  static String get autostring4 => i.autostring4;
  static String get autostring5 => i.autostring5;
  static String get azerbaijan => i.azerbaijan;
  static String get back => i.back;
  static String get backToLogin => i.backToLogin;
  static String get backToThisPoint => i.backToThisPoint;
  static String get bahamas => i.bahamas;
  static String get bahrain => i.bahrain;
  static String get bahrainiDinar => i.bahrainiDinar;
  static String get balance => i.balance;
  static String get balanceSheet => i.balanceSheet;
  static String get balanceSheetCryptocurrencySystem =>
      i.balanceSheetCryptocurrencySystem;
  static String get balanceSheetRecordingSystem =>
      i.balanceSheetRecordingSystem;
  static String get balanceSheetTitle => i.balanceSheetTitle;
  static String get balanced => i.balanced;
  static String get balanced1 => i.balanced1;
  static String get balancedLabel => i.balancedLabel;
  static String get bangladesh => i.bangladesh;
  static String get bankInfoCopied => i.bankInfoCopied;
  static String get barbados => i.barbados;
  static String get basic => i.basic;
  static String get basicCurrencySettings => i.basicCurrencySettings;
  static String get bear => i.bear;
  static String get beauvaisIsland => i.beauvaisIsland;
  static String get belarus => i.belarus;
  static String get belgium => i.belgium;
  static String get belize => i.belize;
  static String get bermuda => i.bermuda;
  static String get bhutan => i.bhutan;
  static String get billOfExchange => i.billOfExchange;
  static String get billOfExchange1 => i.billOfExchange1;
  static String get biometricUnlock => i.biometricUnlock;
  static String get blockList => i.blockList;
  static String get blockchainVerification => i.blockchainVerification;
  static String get bolivia => i.bolivia;
  static String get bondApproval => i.bondApproval;
  static String get bondConflict => i.bondConflict;
  static String get bondCouldNotBe => i.bondCouldNotBe;
  static String get bondEntriesDoNot => i.bondEntriesDoNot;
  static String get bondNumber => i.bondNumber;
  static String get bondNumber1 => i.bondNumber1;
  static String get bondSettlementOnly => i.bondSettlementOnly;
  static String get bondWasDenied => i.bondWasDenied;
  static String get bonds => i.bonds;
  static String get bondsAreApprovedFrom => i.bondsAreApprovedFrom;
  static String get bondsCanBeDeleted => i.bondsCanBeDeleted;
  static String get bondsCouldNotBe => i.bondsCouldNotBe;
  static String get bondsCreatedInPending => i.bondsCreatedInPending;
  static String get bootstrapMessage => i.bootstrapMessage;
  static String get bosniaAndHerzegovina => i.bosniaAndHerzegovina;
  static String get botswana => i.botswana;
  static String get boys => i.boys;
  static String get brazil => i.brazil;
  static String get britishIndianOceanTerritory =>
      i.britishIndianOceanTerritory;
  static String get britishPounds => i.britishPounds;
  static String get britishVirginIslands => i.britishVirginIslands;
  static String get brokerConversion => i.brokerConversion;
  static String get brokerTransferNotice => i.brokerTransferNotice;
  static String get brokerageTransferDetails => i.brokerageTransferDetails;
  static String get bruneiDarussalam => i.bruneiDarussalam;
  static String get buildingCFordCar => i.buildingCFordCar;
  static String get bulgaria => i.bulgaria;
  static String get burkinaFaso => i.burkinaFaso;
  static String get burundi => i.burundi;
  static String get cD => i.cD;
  static String get callNow => i.callNow;
  static String get cambodia => i.cambodia;
  static String get camera => i.camera;
  static String get cameraOrPhotos => i.cameraOrPhotos;
  static String get cameroon => i.cameroon;
  static String get canada => i.canada;
  static String get cancellation => i.cancellation;
  static String get showRevertedOperations => i.showRevertedOperations;
  static String get actionLabel => i.actionLabel;
  static String get severityLabel => i.severityLabel;
  static String get capeVerde => i.capeVerde;
  static String get carFurniturePersonalItems => i.carFurniturePersonalItems;
  static String get cashAndLiquidity => i.cashAndLiquidity;
  static String get catchDefaultTemplate => i.catchDefaultTemplate;
  static String get catchStr => i.catchStr;
  static String get caymanIslands => i.caymanIslands;
  static String get cellPhone => i.cellPhone;
  static String get centralAfricanRepublic => i.centralAfricanRepublic;
  static String get chad => i.chad;
  static String get channelDefaultDesc => i.channelDefaultDesc;
  static String get channelDefaultTitle => i.channelDefaultTitle;
  static String get channelImportantDesc => i.channelImportantDesc;
  static String get channelImportantSummary => i.channelImportantSummary;
  static String get channelImportantTitle => i.channelImportantTitle;
  static String get chartOfAccountsTitle => i.chartOfAccountsTitle;
  static String get checkTheBond => i.checkTheBond;
  static String get chile => i.chile;
  static String get china => i.china;
  static String get chooseADateOptional => i.chooseADateOptional;
  static String get chooseAccount => i.chooseAccount;
  static String get chooseExpenseOrTrade => i.chooseExpenseOrTrade;
  static String get chooseFromContacts => i.chooseFromContacts;
  static String get chooseHowToShare => i.chooseHowToShare;
  static String get choosePackageFileJson => i.choosePackageFileJson;
  static String get chooseTheAppTo => i.chooseTheAppTo;
  static String get chooseTheConversionType => i.chooseTheConversionType;
  static String get chooseYourIncomeSource => i.chooseYourIncomeSource;
  static String get christmasIsland => i.christmasIsland;
  static String get chronologyAndDependency => i.chronologyAndDependency;
  static String get classification => i.classification;
  static String get classificationLabel => i.classificationLabel;
  static String get classificationOfEconomicAsset =>
      i.classificationOfEconomicAsset;
  static String get classificationOther => i.classificationOther;
  static String get classificationSectionTitle => i.classificationSectionTitle;
  static String get collateral => i.collateral;
  static String get collaterals => i.collaterals;
  static String get clearingAccountName => i.clearingAccountName;
  static String get clickAnyColoredText => i.clickAnyColoredText;
  static String get clickToChooseThe => i.clickToChooseThe;
  static String get clickToEdit => i.clickToEdit;
  static String get closedToEveryone => i.closedToEveryone;
  static String get closing => i.closing;
  static String get closing1 => i.closing1;
  static String get closingBalances => i.closingBalances;
  static String get colombia => i.colombia;
  static String get comingSoonBadge => i.comingSoonBadge;
  static String get comoros => i.comoros;
  static String get companyName => i.companyName;
  static String get complete => i.complete;
  static String get confirmAndDecrypt => i.confirmAndDecrypt;
  static String get confirmAndRegisterThe => i.confirmAndRegisterThe;
  static String get confirmAndSend => i.confirmAndSend;
  static String get confirmDeletionTitle => i.confirmDeletionTitle;
  static String get confirmFiltering => i.confirmFiltering;
  static String get confirmPasswordHint => i.confirmPasswordHint;
  static String get confirmRollback => i.confirmRollback;
  static String get confirmRedoOperations => i.confirmRedoOperations;
  static String get confirmSelection => i.confirmSelection;
  static String get confirmSystematicReversal => i.confirmSystematicReversal;
  static String get systematicReversalExplainer =>
      i.systematicReversalExplainer;
  static String get systematicRedoExplainer => i.systematicRedoExplainer;
  static String get confirmationDate => i.confirmationDate;
  static String get congo => i.congo;
  static String get contactTechnicalSupport => i.contactTechnicalSupport;
  static String get conversionSettings => i.conversionSettings;
  static String get cookIslands => i.cookIslands;
  static String get copyFromGoogleDrive => i.copyFromGoogleDrive;
  static String get correctionAndRedirection => i.correctionAndRedirection;
  static String get costCenter => i.costCenter;
  static String get costCenters => i.costCenters;
  static String get costCenterActivateAction => i.costCenterActivateAction;
  static String get costCenterActivateConfirmTitle =>
      i.costCenterActivateConfirmTitle;
  static String get costCenterActivateSnackbar => i.costCenterActivateSnackbar;
  static String get costCenterActiveBadge => i.costCenterActiveBadge;
  static String get costCenterActivitySection => i.costCenterActivitySection;
  static String get costCenterAddCenter => i.costCenterAddCenter;
  static String get costCenterAllAddedAllAvailable =>
      i.costCenterAllAddedAllAvailable;
  static String get costCenterAllDimensionsFilter =>
      i.costCenterAllDimensionsFilter;
  static String get costCenterApplyDimensions => i.costCenterApplyDimensions;
  static String get costCenterAvgVoucherSize => i.costCenterAvgVoucherSize;
  static String get costCenterBudgetGaugeTitle => i.costCenterBudgetGaugeTitle;
  static String get costCenterBudgetHint => i.costCenterBudgetHint;
  static String get costCenterBudgetLabel => i.costCenterBudgetLabel;
  static String get costCenterBudgetNoneHint => i.costCenterBudgetNoneHint;
  static String get costCenterBudgetPrefix => i.costCenterBudgetPrefix;
  static String get costCenterCreatedSnackbar => i.costCenterCreatedSnackbar;
  static String get costCenterCreatedSuccess => i.costCenterCreatedSuccess;
  static String get costCenterCurrentMonthLabel =>
      i.costCenterCurrentMonthLabel;
  static String get costCenterCustomizeDimensions =>
      i.costCenterCustomizeDimensions;
  static String get costCenterDeleteAction => i.costCenterDeleteAction;
  static String get costCenterDescHint => i.costCenterDescHint;
  static String get costCenterDescriptionLabel => i.costCenterDescriptionLabel;
  static String get costCenterDetailTitle => i.costCenterDetailTitle;
  static String get costCenterDimensionBreakdownTitle =>
      i.costCenterDimensionBreakdownTitle;
  static String get costCenterDimensionSelectorLabel =>
      i.costCenterDimensionSelectorLabel;
  static String get costCenterDoesNot => i.costCenterDoesNot;
  static String get costCenterEditAction => i.costCenterEditAction;
  static String get costCenterGrowthLabel => i.costCenterGrowthLabel;
  static String get costCenterKpiSection => i.costCenterKpiSection;
  static String get costCenterLedgerSubtitle => i.costCenterLedgerSubtitle;
  static String get costCenterLedgerTitle => i.costCenterLedgerTitle;
  static String get costCenterNameHint => i.costCenterNameHint;
  static String get costCenterNameLabel => i.costCenterNameLabel;
  static String get costCenterNameValidator => i.costCenterNameValidator;
  static String get costCenterNoBudget => i.costCenterNoBudget;
  static String get costCenterNoCentersAvailable =>
      i.costCenterNoCentersAvailable;
  static String get costCenterNoDimensionData => i.costCenterNoDimensionData;
  static String get costCenterNoRecentVouchers => i.costCenterNoRecentVouchers;
  static String get costCenterNoTrendData => i.costCenterNoTrendData;
  static String get costCenterNoneLinked => i.costCenterNoneLinked;
  static String get costCenterOpenLedger => i.costCenterOpenLedger;
  static String get costCenterOverBudgetWarning =>
      i.costCenterOverBudgetWarning;
  static String get costCenterQuickPayAction => i.costCenterQuickPayAction;
  static String get costCenterQuickReceiveAction =>
      i.costCenterQuickReceiveAction;
  static String get costCenterRemoveError => i.costCenterRemoveError;
  static String get costCenterSaveAction => i.costCenterSaveAction;
  static String get costCenterSaveError => i.costCenterSaveError;
  static String get costCenterSelectionTitle => i.costCenterSelectionTitle;
  static String get costCenterSuspendAction => i.costCenterSuspendAction;
  static String get costCenterSuspendConfirmTitle =>
      i.costCenterSuspendConfirmTitle;
  static String get costCenterSuspendSnackbar => i.costCenterSuspendSnackbar;
  static String get costCenterSuspendedBadge => i.costCenterSuspendedBadge;
  static String get costCenterTagsLabel => i.costCenterTagsLabel;
  static String get costCenterTotalLabel => i.costCenterTotalLabel;
  static String get costCenterTrendSection => i.costCenterTrendSection;
  static String get costCenterTypeCost => i.costCenterTypeCost;
  static String get costCenterTypeCostGroup => i.costCenterTypeCostGroup;
  static String get costCenterTypeLabel => i.costCenterTypeLabel;
  static String get costCenterTypeProfit => i.costCenterTypeProfit;
  static String get costCenterTypeProfitGroup => i.costCenterTypeProfitGroup;
  static String get costCenterTypeSelectorLabel =>
      i.costCenterTypeSelectorLabel;
  static String get costCenterViewMoreVouchers => i.costCenterViewMoreVouchers;
  static String get costCenterViewVouchers => i.costCenterViewVouchers;
  static String get costCenterVoucherCountLabel =>
      i.costCenterVoucherCountLabel;
  static String get costCentersEmpty => i.costCentersEmpty;
  static String get costCentersTitle => i.costCentersTitle;
  static String get costaRica => i.costaRica;
  static String get couldNotOpenThe => i.couldNotOpenThe;
  static String get couldNotUpdateThe => i.couldNotUpdateThe;
  static String get counterpartySection => i.counterpartySection;
  static String get counterparty => i.counterparty;
  static String get createANewIdentity => i.createANewIdentity;
  static String get createAccount => i.createAccount;
  static String get createNew => i.createNew;
  static String get created0930Am04092026 => i.created0930Am04092026;
  static String get createdAtLabel => i.createdAtLabel;
  static String get creationDate => i.creationDate;
  static String get creditClosing => i.creditClosing;
  static String get creditMovement => i.creditMovement;
  static String get creditOpening => i.creditOpening;
  static String get creditor => i.creditor;
  static String get creditorToYou => i.creditorToYou;
  static String get croatiaHrvatska => i.croatiaHrvatska;
  static String get cryptocurrencySystem => i.cryptocurrencySystem;
  static String get cteDivoireIvoryCoast => i.cteDivoireIvoryCoast;
  static String get cuba => i.cuba;
  static String get curacao => i.curacao;
  static String get currency => i.currency;
  static String get currencyLabel => i.currencyLabel;
  static String get currencySymbolExampleUsd => i.currencySymbolExampleUsd;
  static String get customClassificationNameLabel =>
      i.customClassificationNameLabel;
  static String get customClassificationNameRequired =>
      i.customClassificationNameRequired;
  static String get customClassificationTab => i.customClassificationTab;
  static String get customNatureLabel => i.customNatureLabel;
  static String get customTaxonomyNameIs => i.customTaxonomyNameIs;
  static String get customizeBondIdentity => i.customizeBondIdentity;
  static String get customizeVisualIdentityLogo =>
      i.customizeVisualIdentityLogo;
  static String get cyprus => i.cyprus;
  static String get czechRepublic => i.czechRepublic;
  static String get da => i.da;
  static String get da1 => i.da1;
  static String get daily => i.daily;
  static String get dangerZone => i.dangerZone;
  static String get dbEnterPrimaryKeyAction => i.dbEnterPrimaryKeyAction;
  static String get dbKeyMismatchBody => i.dbKeyMismatchBody;
  static String get dbKeyMismatchRetryFailed => i.dbKeyMismatchRetryFailed;
  static String get dbKeyMismatchTitle => i.dbKeyMismatchTitle;
  static String get dbMnemonicHint => i.dbMnemonicHint;
  static String get dbOpenErrorBody => i.dbOpenErrorBody;
  static String get dbOpenErrorTitle => i.dbOpenErrorTitle;
  static String get dbOpeningProgress => i.dbOpeningProgress;
  static String get dbRetryAction => i.dbRetryAction;
  static String get dbStartFreshAction => i.dbStartFreshAction;
  static String get dbStartFreshConfirmAction => i.dbStartFreshConfirmAction;
  static String get dbStartFreshConfirmBody => i.dbStartFreshConfirmBody;
  static String get dbStartFreshConfirmTitle => i.dbStartFreshConfirmTitle;
  static String get dbUnlockAction => i.dbUnlockAction;
  static String get de => i.de;
  static String get dearCustomer => i.dearCustomer;
  static String get dearCustomernweWouldLike => i.dearCustomernweWouldLike;
  static String get dearCustomernweWouldLike1 => i.dearCustomernweWouldLike1;
  static String get dearCustomernweWouldLike2 => i.dearCustomernweWouldLike2;
  static String get dearue000 => i.dearue000;
  static String get debitDataFromThe => i.debitDataFromThe;
  static String get debtSettlement => i.debtSettlement;
  static String get debtor => i.debtor;
  static String get december => i.december;
  static String get decryptingImages => i.decryptingImages;
  static String get deductingAnAmountfromThe => i.deductingAnAmountfromThe;
  static String get defaultCostCentersDesc => i.defaultCostCentersDesc;
  static String get defaultCostCentersEmpty => i.defaultCostCentersEmpty;
  static String get defaultCostCentersTitle => i.defaultCostCentersTitle;
  static String get democraticRepublicOfThe => i.democraticRepublicOfThe;
  static String get denmark => i.denmark;
  static String get deposit => i.deposit;
  static String get deposit1 => i.deposit1;
  static String get deposited => i.deposited;
  static String get description => i.description;
  static String get descriptionOfTheMortgagesecurity =>
      i.descriptionOfTheMortgagesecurity;
  static String get detailedStatement => i.detailedStatement;
  static String get determineWhoCanSync => i.determineWhoCanSync;
  static String get digitalAuditLog => i.digitalAuditLog;
  static String get digitallySigned => i.digitallySigned;
  static String get dimCategoryIndividual => i.dimCategoryIndividual;
  static String get dimCategoryProject => i.dimCategoryProject;
  static String get dimCategorySpatial => i.dimCategorySpatial;
  static String get disbursementNotice => i.disbursementNotice;
  static String get displayTheBillOf => i.displayTheBillOf;
  static String get djibouti => i.djibouti;
  static String get dominican => i.dominican;
  static String get dominicanRepublic => i.dominicanRepublic;
  static String get doubleConversionWithBox => i.doubleConversionWithBox;
  static String get draft => i.draft;
  static String get drawn => i.drawn;
  static String get driveBackupAccountLabel => i.driveBackupAccountLabel;
  static String get driveBackupFrequencyDaily => i.driveBackupFrequencyDaily;
  static String get driveBackupFrequencyLabel => i.driveBackupFrequencyLabel;
  static String get driveBackupLastDate => i.driveBackupLastDate;
  static String get driveBackupNoAccount => i.driveBackupNoAccount;
  static String get driveBackupNow => i.driveBackupNow;
  static String get driveBackupRestoreAction => i.driveBackupRestoreAction;
  static String get driveBackupRestoreBody => i.driveBackupRestoreBody;
  static String get driveBackupRestoreTitle => i.driveBackupRestoreTitle;
  static String get driveBackupSignIn => i.driveBackupSignIn;
  static String get driveBackupSignOut => i.driveBackupSignOut;
  static String get driveBackupSignOutBody => i.driveBackupSignOutBody;
  static String get driveBackupSignOutTitle => i.driveBackupSignOutTitle;
  static String get driveBackupSuspendedNotice => i.driveBackupSuspendedNotice;
  static String get driveBackupToggleSubtitle => i.driveBackupToggleSubtitle;
  static String get driveBackupToggleTitle => i.driveBackupToggleTitle;
  static String get driveBackupUploadSuccess => i.driveBackupUploadSuccess;
  static String get dry => i.dry;
  static String get dueDate => i.dueDate;
  static String get dutchCaribbeanIslands => i.dutchCaribbeanIslands;
  static String get eastTimor => i.eastTimor;
  static String get ecuador => i.ecuador;
  static String get editAccountClassificationLocked =>
      i.editAccountClassificationLocked;
  static String get editAccountTitle => i.editAccountTitle;
  static String get editAccountTooltip => i.editAccountTooltip;
  static String get editor => i.editor;
  static String get editorial => i.editorial;
  static String get egypt => i.egypt;
  static String get egyptianPound => i.egyptianPound;
  static String get elSalvador => i.elSalvador;
  static String get electronicSignature => i.electronicSignature;
  static String get emailIsAlreadyRegistered => i.emailIsAlreadyRegistered;
  static String get emiratiDirham => i.emiratiDirham;
  static String get encryptionKeyRequired => i.encryptionKeyRequired;
  static String get enterNewTextHere => i.enterNewTextHere;
  static String get enterRecoveryPhraseHere => i.enterRecoveryPhraseHere;
  static String get entertainmentAndLifestyle => i.entertainmentAndLifestyle;
  static String get entitlementDoesNotExist => i.entitlementDoesNotExist;
  static String get entitlementsCouldNotBe => i.entitlementsCouldNotBe;
  static String get entryPersonalAccounting => i.entryPersonalAccounting;
  static String get equatorialGuinea => i.equatorialGuinea;
  static String get equity => i.equity;
  static String get equityLabel => i.equityLabel;
  static String get eritrea => i.eritrea;
  static String get errorLoadingTripleConversion =>
      i.errorLoadingTripleConversion;
  static String get errorTheAssetRoot => i.errorTheAssetRoot;
  static String get errorTitle => i.errorTitle;
  static String get estimatedValue => i.estimatedValue;
  static String get estonia => i.estonia;
  static String get ethiopia => i.ethiopia;
  static String get euro => i.euro;
  static String get excelExport => i.excelExport;
  static String get exchange => i.exchange;
  static String get exchangeDefaultTemplate => i.exchangeDefaultTemplate;
  static String get exhibition => i.exhibition;
  static String get expenseCategoriesEmpty => i.expenseCategoriesEmpty;
  static String get expenseWizardHeaderDesc => i.expenseWizardHeaderDesc;
  static String get expenseWizardHeaderTitle => i.expenseWizardHeaderTitle;
  static String get expenseWizardNameHint => i.expenseWizardNameHint;
  static String get expenseWizardNameLabel => i.expenseWizardNameLabel;
  static String get expenseWizardNameRequired => i.expenseWizardNameRequired;
  static String get expenseWizardRootError => i.expenseWizardRootError;
  static String get expenseWizardSubmit => i.expenseWizardSubmit;
  static String get expenseWizardSuccess => i.expenseWizardSuccess;
  static String get expenseWizardTitle => i.expenseWizardTitle;
  static String get expensesAndConsumption => i.expensesAndConsumption;
  static String get expired => i.expired;
  static String get exportExcelStatement => i.exportExcelStatement;
  static String get exportPdf => i.exportPdf;
  static String get exportPdfShareError => i.exportPdfShareError;
  static String get exportPdfStatement => i.exportPdfStatement;
  static String get exportSharePdfTooltip => i.exportSharePdfTooltip;
  static String get exportTheReport => i.exportTheReport;
  static String get failedToChargeMortgage => i.failedToChargeMortgage;
  static String get failedToDeleteBond => i.failedToDeleteBond;
  static String get failedToDeleteThe => i.failedToDeleteThe;
  static String get failedToDownloadAttachments =>
      i.failedToDownloadAttachments;
  static String get failedToDownloadCopy => i.failedToDownloadCopy;
  static String get failedToDownloadMortgage => i.failedToDownloadMortgage;
  static String get failedToInquireAbout => i.failedToInquireAbout;
  static String get failedToLoadMortgages => i.failedToLoadMortgages;
  static String get failedToLoadRevaluation => i.failedToLoadRevaluation;
  static String get failedToSaveRevaluation => i.failedToSaveRevaluation;
  static String get failedToSaveSome => i.failedToSaveSome;
  static String get failedToSaveThe => i.failedToSaveThe;
  static String get failedToUpdateLicense => i.failedToUpdateLicense;
  static String get failedToUpdateMortgage => i.failedToUpdateMortgage;
  static String get failureToInspectMortgages => i.failureToInspectMortgages;
  static String get failureToSaveThe => i.failureToSaveThe;
  static String get falklandIslands => i.falklandIslands;
  static String get familyAndDependents => i.familyAndDependents;
  static String get faroeIslands => i.faroeIslands;
  static String get february => i.february;
  static String get fiscalPeriodCloseButton => i.fiscalPeriodCloseButton;
  static String get fiscalPeriodCloseConfirm => i.fiscalPeriodCloseConfirm;
  static String get fiscalPeriodCloseDraftsRemain =>
      i.fiscalPeriodCloseDraftsRemain;
  static String get fiscalPeriodCreateTitle => i.fiscalPeriodCreateTitle;
  static String get fiscalPeriodDividerClosed => i.fiscalPeriodDividerClosed;
  static String get fiscalPeriodDividerOpen => i.fiscalPeriodDividerOpen;
  static String get fiscalPeriodEmpty => i.fiscalPeriodEmpty;
  static String get fiscalPeriodEndLabel => i.fiscalPeriodEndLabel;
  static String get fiscalPeriodInvalidRange => i.fiscalPeriodInvalidRange;
  static String get fiscalPeriodNameLabel => i.fiscalPeriodNameLabel;
  static String get fiscalPeriodNotFound => i.fiscalPeriodNotFound;
  static String get fiscalPeriodNotOpen => i.fiscalPeriodNotOpen;
  static String get fiscalPeriodOpenAlreadyExists =>
      i.fiscalPeriodOpenAlreadyExists;
  static String get fiscalPeriodOverlap => i.fiscalPeriodOverlap;
  static String get fiscalPeriodPolicyAuto => i.fiscalPeriodPolicyAuto;
  static String get fiscalPeriodPolicyLabel => i.fiscalPeriodPolicyLabel;
  static String get fiscalPeriodPolicyManual => i.fiscalPeriodPolicyManual;
  static String get fiscalPeriodStartLabel => i.fiscalPeriodStartLabel;
  static String get fiscalPeriodsPageTitle => i.fiscalPeriodsPageTitle;
  static String get fijiIslands => i.fijiIslands;
  static String get file => i.file;
  static String get filterApplied => i.filterApplied;
  static String get filterByCostCenter => i.filterByCostCenter;
  static String get filterLedger => i.filterLedger;
  static String get filterLedgerTitle => i.filterLedgerTitle;
  static String get filterNatureAll => i.filterNatureAll;
  static String get filterNatureCredit => i.filterNatureCredit;
  static String get filterNatureDebit => i.filterNatureDebit;
  static String get filterTheFinancialRecord => i.filterTheFinancialRecord;
  static String get filtered => i.filtered;
  static String get financial => i.financial;
  static String get financialAndPersonalSettlements =>
      i.financialAndPersonalSettlements;
  static String get financialBalancePerformance =>
      i.financialBalancePerformance;
  static String get financialBond => i.financialBond;
  static String get financialCenterPrefix => i.financialCenterPrefix;
  static String get financialMovementType => i.financialMovementType;
  static String get financialReceiptVoucherPreview =>
      i.financialReceiptVoucherPreview;
  static String get financialReports => i.financialReports;
  static String get fingerprintsignaturesigsignaturessafaf0932128 =>
      i.fingerprintsignaturesigsignaturessafaf0932128;
  static String get finished => i.finished;
  static String get finland => i.finland;
  static String get firstCustomerSignature => i.firstCustomerSignature;
  static String get fixedAssetsDepreciated => i.fixedAssetsDepreciated;
  static String get fixedAssetsProfitable => i.fixedAssetsProfitable;
  static String get footerRightsText => i.footerRightsText;
  static String get forEachAccountMerge => i.forEachAccountMerge;
  static String get forgotPassword => i.forgotPassword;
  static String get formatPdfFilesAnd => i.formatPdfFilesAnd;
  static String get france => i.france;
  static String get frenchGuiana => i.frenchGuiana;
  static String get frenchPolynesia => i.frenchPolynesia;
  static String get from => i.from;
  static String get fromTheCustomersAccount => i.fromTheCustomersAccount;
  static String get fullDebtSettlement => i.fullDebtSettlement;
  static String get fundBroker => i.fundBroker;
  static String get gabon => i.gabon;
  static String get gambia => i.gambia;
  static String get gateBypassIdentity => i.gateBypassIdentity;
  static String get gateCheckingBackups => i.gateCheckingBackups;
  static String get gateCheckingStatus => i.gateCheckingStatus;
  static String get gateContinueToApp => i.gateContinueToApp;
  static String get gateDeviceLockSubtitle => i.gateDeviceLockSubtitle;
  static String get gateDeviceLockTitle => i.gateDeviceLockTitle;
  static String get gateEnterPrimaryKey => i.gateEnterPrimaryKey;
  static String get gateIdentitySetupSubtitle => i.gateIdentitySetupSubtitle;
  static String get gateIdentitySetupTitle => i.gateIdentitySetupTitle;
  static String get gateNetworkCreateNew => i.gateNetworkCreateNew;
  static String get gateNetworkCreateNewWarning =>
      i.gateNetworkCreateNewWarning;
  static String get gateNetworkErrorSubtitle => i.gateNetworkErrorSubtitle;
  static String get gateNetworkErrorTitle => i.gateNetworkErrorTitle;
  static String get gateNetworkRetry => i.gateNetworkRetry;
  static String get gateNetworkRetryHint => i.gateNetworkRetryHint;
  static String get gateNoBackupSubtitle => i.gateNoBackupSubtitle;
  static String get gateNoBackupTitle => i.gateNoBackupTitle;
  static String get gateRestoreAndKeepIdentity => i.gateRestoreAndKeepIdentity;
  static String get gateRestoreDriveOption => i.gateRestoreDriveOption;
  static String get gateRestoreLocalOption => i.gateRestoreLocalOption;
  static String get gateRestoreNewIdentity => i.gateRestoreNewIdentity;
  static String get gateRestoreSubtitle => i.gateRestoreSubtitle;
  static String get gateRestoreTitle => i.gateRestoreTitle;
  static String get gateSetupBiometric => i.gateSetupBiometric;
  static String get gateSetupComplete => i.gateSetupComplete;
  static String get gateSetupCompleteBody => i.gateSetupCompleteBody;
  static String get gateSetupPin => i.gateSetupPin;
  static String get gateSkipDeviceLock => i.gateSkipDeviceLock;
  static String get gateSkipRestore => i.gateSkipRestore;
  static String get georgia => i.georgia;
  static String get germany => i.germany;
  static String get ghana => i.ghana;
  static String get gibraltar => i.gibraltar;
  static String get googleLoginFailed => i.googleLoginFailed;
  static String get governanceContactAdmin => i.governanceContactAdmin;
  static String get governanceOwnerAccountLabel =>
      i.governanceOwnerAccountLabel;
  static String get governancePaymentInstruction =>
      i.governancePaymentInstruction;
  static String get governanceRecheckAction => i.governanceRecheckAction;
  static String get governanceSuspendedBanner => i.governanceSuspendedBanner;
  static String get gramOfSilver => i.gramOfSilver;
  static String get greece => i.greece;
  static String get greenland => i.greenland;
  static String get grenada => i.grenada;
  static String get guadeloupe => i.guadeloupe;
  static String get guam => i.guam;
  static String get guatemala => i.guatemala;
  static String get guinea => i.guinea;
  static String get guineaBissau => i.guineaBissau;
  static String get guyana => i.guyana;
  static String get haiti => i.haiti;
  static String get headerSubdescription => i.headerSubdescription;
  static String get healthAndPersonalCare => i.healthAndPersonalCare;
  static String get heardIslandAndMcdonald => i.heardIslandAndMcdonald;
  static String get holland => i.holland;
  static String get honduras => i.honduras;
  static String get hongKongSpecialAdministrative =>
      i.hongKongSpecialAdministrative;
  static String get housingAndLiving => i.housingAndLiving;
  static String get howDoesImportWork => i.howDoesImportWork;
  static String get hungary => i.hungary;
  static String get iAgreeTo => i.iAgreeTo;
  static String get iDeposited => i.iDeposited;
  static String get iHaveAPrevious => i.iHaveAPrevious;
  static String get iReceived => i.iReceived;
  static String get iceland => i.iceland;
  static String get id => i.id;
  static String get identifyAndMatchDuplicate => i.identifyAndMatchDuplicate;
  static String get identityBackupDone => i.identityBackupDone;
  static String get identityBackupPending => i.identityBackupPending;
  static String get identityBackupStatus => i.identityBackupStatus;
  static String get identityKeyGenerationLabel => i.identityKeyGenerationLabel;
  static String get identityNotSetup => i.identityNotSetup;
  static String get identityPublicKeyCopied => i.identityPublicKeyCopied;
  static String get identityPublicKeyCopy => i.identityPublicKeyCopy;
  static String get identityPublicKeyLabel => i.identityPublicKeyLabel;
  static String get identityRecoveryBypassAction =>
      i.identityRecoveryBypassAction;
  static String get identityRecoveryBypassWarning =>
      i.identityRecoveryBypassWarning;
  static String get identityRecoveryEnterKeyAction =>
      i.identityRecoveryEnterKeyAction;
  static String get identityRecoveryHint => i.identityRecoveryHint;
  static String get identityRecoveryInputRequired =>
      i.identityRecoveryInputRequired;
  static String get identityRecoveryRequiredBody =>
      i.identityRecoveryRequiredBody;
  static String get identityRecoveryRequiredTitle =>
      i.identityRecoveryRequiredTitle;
  static String get identitySeedCopied => i.identitySeedCopied;
  static String get identitySeedCopy => i.identitySeedCopy;
  static String get identitySeedDialogBody => i.identitySeedDialogBody;
  static String get identitySeedShare => i.identitySeedShare;
  static String get identitySeedWarning => i.identitySeedWarning;
  static String get identitySettingsSection => i.identitySettingsSection;
  static String get identitySetupAction => i.identitySetupAction;
  static String get identityShareSeedSubject => i.identityShareSeedSubject;
  static String get identityViewSeed => i.identityViewSeed;
  static String get identityViewSeedSubtitle => i.identityViewSeedSubtitle;
  static String get identityViewSeedWarningBody =>
      i.identityViewSeedWarningBody;
  static String get identityViewSeedWarningTitle =>
      i.identityViewSeedWarningTitle;
  static String get ignoreIncomingDuplicate => i.ignoreIncomingDuplicate;
  static String get image => i.image;
  static String get inactive => i.inactive;
  static String get deactivated => i.deactivated;
  static String get implementationInProgress => i.implementationInProgress;
  static String get importAccountsAndFinancial => i.importAccountsAndFinancial;
  static String get importAndFormat => i.importAndFormat;
  static String get importAndImmigration => i.importAndImmigration;
  static String get importAnotherFile => i.importAnotherFile;
  static String get importBonds => i.importBonds;
  static String get importCompleted => i.importCompleted;
  static String get importData => i.importData;
  static String get importDataFromAn => i.importDataFromAn;
  static String get importModuleFromOld => i.importModuleFromOld;
  static String get importedAccount => i.importedAccount;
  static String get importedBonds => i.importedBonds;
  static String get importingData => i.importingData;
  static String get includedWithDigitalDocumentation =>
      i.includedWithDigitalDocumentation;
  static String get includingTransfers => i.includingTransfers;
  static String get incomeAndWork => i.incomeAndWork;
  static String get incomeSourceInvestmentAsset =>
      i.incomeSourceInvestmentAsset;
  static String get incomeSourceInvestmentAssetDesc =>
      i.incomeSourceInvestmentAssetDesc;
  static String get incomeSourceOther => i.incomeSourceOther;
  static String get incomeSourceOtherDesc => i.incomeSourceOtherDesc;
  static String get incomeSourcePossession => i.incomeSourcePossession;
  static String get incomeSourcePossessionDesc => i.incomeSourcePossessionDesc;
  static String get incomeSourceProfession => i.incomeSourceProfession;
  static String get incomeSourceProfessionDesc => i.incomeSourceProfessionDesc;
  static String get incomeSourceTypeSheetSubtitle =>
      i.incomeSourceTypeSheetSubtitle;
  static String get incomeSourceTypeSheetTitle => i.incomeSourceTypeSheetTitle;
  static String get incomeStreamAcquisitionValue =>
      i.incomeStreamAcquisitionValue;
  static String get incomeStreamAsset => i.incomeStreamAsset;
  static String get incomeStreamBalance => i.incomeStreamBalance;
  static String get incomeStreamCurrentValue => i.incomeStreamCurrentValue;
  static String get incomeStreamDatePrefix => i.incomeStreamDatePrefix;
  static String get incomeStreamExpense => i.incomeStreamExpense;
  static String get incomeStreamExpenseCategory =>
      i.incomeStreamExpenseCategory;
  static String get incomeStreamLoadError => i.incomeStreamLoadError;
  static String get incomeStreamNoData => i.incomeStreamNoData;
  static String get incomeStreamPerHour => i.incomeStreamPerHour;
  static String get incomeStreamPossession => i.incomeStreamPossession;
  static String get incomeStreamProfession => i.incomeStreamProfession;
  static String get incomeStreamProfessionField =>
      i.incomeStreamProfessionField;
  static String get incomeStreamPurchasePrice => i.incomeStreamPurchasePrice;
  static String get incomeStreamTotalEarned => i.incomeStreamTotalEarned;
  static String get incomeStreamTotalYield => i.incomeStreamTotalYield;
  static String get incomeStreamTracker => i.incomeStreamTracker;
  static String get incomeStreamsAddExpense => i.incomeStreamsAddExpense;
  static String get incomeStreamsAddSource => i.incomeStreamsAddSource;
  static String get incomeStreamsEmpty => i.incomeStreamsEmpty;
  static String get incomeStreamsTabExpenses => i.incomeStreamsTabExpenses;
  static String get incomeStreamsTabIncome => i.incomeStreamsTabIncome;
  static String get incomeStreamsTabPossessions =>
      i.incomeStreamsTabPossessions;
  static String get incomeStreamsTitle => i.incomeStreamsTitle;
  static String get incoming => i.incoming;
  static String get incomingBondSync => i.incomingBondSync;
  static String get incomingTransfer => i.incomingTransfer;
  static String get incomingTransfer1 => i.incomingTransfer1;
  static String get india => i.india;
  static String get indonesia => i.indonesia;
  static String get intermediateConversionTriple =>
      i.intermediateConversionTriple;
  static String get internalVoucherCategoryRequired =>
      i.internalVoucherCategoryRequired;
  static String get internalVoucherFundAccount => i.internalVoucherFundAccount;
  static String get internalVoucherFundError => i.internalVoucherFundError;
  static String get internalVoucherPaymentLabel =>
      i.internalVoucherPaymentLabel;
  static String get internalVoucherPickExpense => i.internalVoucherPickExpense;
  static String get internalVoucherPickRevenue => i.internalVoucherPickRevenue;
  static String get internalVoucherReceiptLabel =>
      i.internalVoucherReceiptLabel;
  static String get internalVoucherSuccess => i.internalVoucherSuccess;
  static String get internalVoucherTypePayment => i.internalVoucherTypePayment;
  static String get internalVoucherTypeReceipt => i.internalVoucherTypeReceipt;
  static String get internalVouchersTitle => i.internalVouchersTitle;
  static String get internetConnectionFailed => i.internetConnectionFailed;
  static String get internetConnectionFailedPlease =>
      i.internetConnectionFailedPlease;
  static String get invalidData => i.invalidData;
  static String get invalidDataCheckThe => i.invalidDataCheckThe;
  static String get invalidDateRange => i.invalidDateRange;
  static String get invalidEmail => i.invalidEmail;
  static String get invalidResponseNoAuthentication =>
      i.invalidResponseNoAuthentication;
  static String get investmentsAndProjects => i.investmentsAndProjects;
  static String get ipDiscoveringNetwork => i.ipDiscoveringNetwork;
  static String get iran => i.iran;
  static String get iraq => i.iraq;
  static String get ireland => i.ireland;
  static String get issued => i.issued;
  static String get itAllowsAnyoneWith => i.itAllowsAnyoneWith;
  static String get itIsNotPossible => i.itIsNotPossible;
  static String get itPreventsEveryoneFrom => i.itPreventsEveryoneFrom;
  static String get itWasNotPossible => i.itWasNotPossible;
  static String get itWasNotPossible1 => i.itWasNotPossible1;
  static String get italy => i.italy;
  static String get jamaica => i.jamaica;
  static String get january => i.january;
  static String get japan => i.japan;
  static String get jersey => i.jersey;
  static String get jm => i.jm;
  static String get jordan => i.jordan;
  static String get jordanianDinar => i.jordanianDinar;
  static String get july => i.july;
  static String get june => i.june;
  static String get kazakhstan => i.kazakhstan;
  static String get kenya => i.kenya;
  static String get keypkpublickeyssafaf0932128 =>
      i.keypkpublickeyssafaf0932128;
  static String get khaledWalidAlamiri => i.khaledWalidAlamiri;
  static String get kingdomOfSaudiArabia => i.kingdomOfSaudiArabia;
  static String get kiribati => i.kiribati;
  static String get kosovo => i.kosovo;
  static String get kuwait => i.kuwait;
  static String get kuwaitiDinar => i.kuwaitiDinar;
  static String get kwd => i.kwd;
  static String get kyrgyzstan => i.kyrgyzstan;
  static String get labelTheDateField => i.labelTheDateField;
  static String get labelTheNumberField => i.labelTheNumberField;
  static String get landIslands => i.landIslands;
  static String get langArabic => i.langArabic;
  static String get langEnglish => i.langEnglish;
  static String get laos => i.laos;
  static String get latvia => i.latvia;
  static String get lebanon => i.lebanon;
  static String get ledgerEntriesCouldNot => i.ledgerEntriesCouldNot;
  static String get ledgerEntries => i.ledgerEntries;
  static String get ledgerEntry => i.ledgerEntry;
  static String get ledgerMovement => i.ledgerMovement;
  static String get lesotho => i.lesotho;
  static String get liabilities => i.liabilities;
  static String get liabilitiesLabel => i.liabilitiesLabel;
  static String get liberia => i.liberia;
  static String get libya => i.libya;
  static String get liechtenstein => i.liechtenstein;
  static String get linkToRootAccount => i.linkToRootAccount;
  static String get linkedBonds => i.linkedBonds;
  static String get liquidateOfferForSale => i.liquidateOfferForSale;
  static String get liquidationOfMortgage => i.liquidationOfMortgage;
  static String get liquidationOfMortgage1 => i.liquidationOfMortgage1;
  static String get listOfBondsTo => i.listOfBondsTo;
  static String get lithuania => i.lithuania;
  static String get loading => i.loading;
  static String get loadingLabel => i.loadingLabel;
  static String get localCopyOnThe => i.localCopyOnThe;
  static String get localRecord => i.localRecord;
  static String get lockScreenSubtitle => i.lockScreenSubtitle;
  static String get lockScreenTitle => i.lockScreenTitle;
  static String get loginAction => i.loginAction;
  static String get loginDataIsIncorrect => i.loginDataIsIncorrect;
  static String get loginSubtitle => i.loginSubtitle;
  static String get loginTitle => i.loginTitle;
  static String get logoutAction => i.logoutAction;
  static String get logoutConfirmBody => i.logoutConfirmBody;
  static String get logoutConfirmTitle => i.logoutConfirmTitle;
  static String get luxembourg => i.luxembourg;
  static String get macauSpecialAdministrativeRegions =>
      i.macauSpecialAdministrativeRegions;
  static String get macedonia => i.macedonia;
  static String get madagascar => i.madagascar;
  static String get madianMovement => i.madianMovement;
  static String get mainHeaderTitle => i.mainHeaderTitle;
  static String get makeAPaymentOn => i.makeAPaymentOn;
  static String get makeASettlement => i.makeASettlement;
  static String get malawi => i.malawi;
  static String get malaysia => i.malaysia;
  static String get maldives => i.maldives;
  static String get malta => i.malta;
  static String get manIsland => i.manIsland;
  static String get manageAutomaticTextsWhen => i.manageAutomaticTextsWhen;
  static String get manageBlockList => i.manageBlockList;
  static String get manageCurrenciesAndVirtual => i.manageCurrenciesAndVirtual;
  static String get manageTheAllowList => i.manageTheAllowList;
  static String get managementAddAssetFab => i.managementAddAssetFab;
  static String get managementAddExpenseFab => i.managementAddExpenseFab;
  static String get managementAddFlowFab => i.managementAddFlowFab;
  static String get managementAddRevenueFab => i.managementAddRevenueFab;
  static String get managementAssetLinkExpense => i.managementAssetLinkExpense;
  static String get managementAssetLinkRevenue => i.managementAssetLinkRevenue;
  static String get managementAssetValueLabel => i.managementAssetValueLabel;
  static String get managementAssetYieldLabel => i.managementAssetYieldLabel;
  static String get managementAssetsEmpty => i.managementAssetsEmpty;
  static String get managementExpensesEmpty => i.managementExpensesEmpty;
  static String get managementFilterAll => i.managementFilterAll;
  static String get managementInvestmentAssets => i.managementInvestmentAssets;
  static String get managementLabelExpenses => i.managementLabelExpenses;
  static String get managementLabelRevenues => i.managementLabelRevenues;
  static String get managementManageAccruals => i.managementManageAccruals;
  static String get managementPersonalPossessions =>
      i.managementPersonalPossessions;
  static String get managementSearchHint => i.managementSearchHint;
  static String get managementSearchNoResults => i.managementSearchNoResults;
  static String get managementSearchVouchersHint =>
      i.managementSearchVouchersHint;
  static String get managementTabAssets => i.managementTabAssets;
  static String get managementTabExpenses => i.managementTabExpenses;
  static String get managementTabFinancialRecords =>
      i.managementTabFinancialRecords;
  static String get managementTabFundFlows => i.managementTabFundFlows;
  static String get managementTabOutflowSources =>
      i.managementTabOutflowSources;
  static String get managementTabPersonalFlowAccounts =>
      i.managementTabPersonalFlowAccounts;
  static String get managementTabRevenues => i.managementTabRevenues;
  static String get managementTitle => i.managementTitle;
  static String get march => i.march;
  static String get marshallIslands => i.marshallIslands;
  static String get martinique => i.martinique;
  static String get matchingBondWouldYou => i.matchingBondWouldYou;
  static String get mauritania => i.mauritania;
  static String get mauritius => i.mauritius;
  static String get may => i.may;
  static String get mayotte => i.mayotte;
  static String get mergeAndConfirmLocal => i.mergeAndConfirmLocal;
  static String get messagingInboxTab => i.messagingInboxTab;
  static String get messagingTemplatesTab => i.messagingTemplatesTab;
  static String get mexico => i.mexico;
  static String get micronesia => i.micronesia;
  static String get missingBondInformationIn => i.missingBondInformationIn;
  static String get missingValidity => i.missingValidity;
  static String get modelLabel => i.modelLabel;
  static String get modificationDate => i.modificationDate;
  static String get modifyingTheClassificationOr =>
      i.modifyingTheClassificationOr;
  static String get moldova => i.moldova;
  static String get monaco => i.monaco;
  static String get mongolia => i.mongolia;
  static String get montenegro => i.montenegro;
  static String get monthly => i.monthly;
  static String get montserrat => i.montserrat;
  static String get more => i.more;
  static String get morocco => i.morocco;
  static String get mortgageDetails => i.mortgageDetails;
  static String get mortgageLiquidationSurplusHeld =>
      i.mortgageLiquidationSurplusHeld;
  static String get mortgagePictures => i.mortgagePictures;
  static String get movement => i.movement;
  static String get movements => i.movements;
  static String get mozambique => i.mozambique;
  static String get myAccountBroker => i.myAccountBroker;
  static String get myCity => i.myCity;
  static String get myConclusionIsIndebted => i.myConclusionIsIndebted;
  static String get myCreditors => i.myCreditors;
  static String get myEditorialIsIndebted => i.myEditorialIsIndebted;
  static String get myanmar => i.myanmar;
  static String get nTheAuthenticityOf => i.nTheAuthenticityOf;
  static String get name => i.name;
  static String get nameHint => i.nameHint;
  static String get nameOfOriginking => i.nameOfOriginking;
  static String get nameOfTheFinancial => i.nameOfTheFinancial;
  static String get nameOfTheOther => i.nameOfTheOther;
  static String get namibia => i.namibia;
  static String get nature => i.nature;
  static String get nature1 => i.nature1;
  static String get natureCreditShort => i.natureCreditShort;
  static String get natureDebitShort => i.natureDebitShort;
  static String get natureLabel => i.natureLabel;
  static String get natureOfAccount => i.natureOfAccount;
  static String get nauru => i.nauru;
  static String get nautomaticallyExportedAndDigitally =>
      i.nautomaticallyExportedAndDigitally;
  static String get navAccountsTab => i.navAccountsTab;
  static String get navCostCentersTab => i.navCostCentersTab;
  static String get navManagementTab => i.navManagementTab;
  static String get navMessagesTab => i.navMessagesTab;
  static String get navReportsTab => i.navReportsTab;
  static String get navTripartiteTab => i.navTripartiteTab;
  static String get navVouchersTab => i.navVouchersTab;
  static String get nepal => i.nepal;
  static String get netBalance => i.netBalance;
  static String get netClosingBalances => i.netClosingBalances;
  static String get netLiabilitiesAndEquityLabel =>
      i.netLiabilitiesAndEquityLabel;
  static String get neutral => i.neutral;
  static String get newAccount => i.newAccount;
  static String get newBond => i.newBond;
  static String get newBrokerageTransfer => i.newBrokerageTransfer;
  static String get newCaledonia => i.newCaledonia;
  static String get newChildAccountTitle => i.newChildAccountTitle;
  static String get newConversion => i.newConversion;
  static String get newCostCenterTitle => i.newCostCenterTitle;
  static String get newNotification => i.newNotification;
  static String get newRootAccountTitle => i.newRootAccountTitle;
  static String get newStatus => i.newStatus;
  static String get newStr => i.newStr;
  static String get newZealand => i.newZealand;
  static String get nextSteps => i.nextSteps;
  static String get nicaragua => i.nicaragua;
  static String get niger => i.niger;
  static String get nigeria => i.nigeria;
  static String get niue => i.niue;
  static String get nnautomaticallyExportedViaThe =>
      i.nnautomaticallyExportedViaThe;
  static String get noAccount => i.noAccount;
  static String get noAccountBalancesWere => i.noAccountBalancesWere;
  static String get noBackupFoundIn => i.noBackupFoundIn;
  static String get noBackupOnDrive => i.noBackupOnDrive;
  static String get noBondDataFound => i.noBondDataFound;
  static String get noCounterpartyDataFound => i.noCounterpartyDataFound;
  static String get noDraftReceiptMatching => i.noDraftReceiptMatching;
  static String get noFileWasFound => i.noFileWasFound;
  static String get noMatchingResultsFound => i.noMatchingResultsFound;
  static String get noPrivacyFound => i.noPrivacyFound;
  static String get noTermsFound => i.noTermsFound;
  static String get noValidDataRows => i.noValidDataRows;
  static String get norfolkIsland => i.norfolkIsland;
  static String get northKorea => i.northKorea;
  static String get northernMarianaIslands => i.northernMarianaIslands;
  static String get norway => i.norway;
  static String get notRegistered => i.notRegistered;
  static String get notes => i.notes;
  static String get notes1 => i.notes1;
  static String get notesLabel => i.notesLabel;
  static String get noticeOfAdditionTo => i.noticeOfAdditionTo;
  static String get noticeOfDeductionFrom => i.noticeOfDeductionFrom;
  static String get notifDirectCategories => i.notifDirectCategories;
  static String get notifMediaAlerts => i.notifMediaAlerts;
  static String get notifPeerActivityDesc => i.notifPeerActivityDesc;
  static String get notifPeerActivityTitle => i.notifPeerActivityTitle;
  static String get notifPermissionDeniedBody => i.notifPermissionDeniedBody;
  static String get notifPermissionDeniedTitle => i.notifPermissionDeniedTitle;
  static String get notifPermissionGranted => i.notifPermissionGranted;
  static String get notifPermissionGrantedBody => i.notifPermissionGrantedBody;
  static String get notifPermissionOpenSettings =>
      i.notifPermissionOpenSettings;
  static String get notifSelfActivityDesc => i.notifSelfActivityDesc;
  static String get notifSelfActivityTitle => i.notifSelfActivityTitle;
  static String get notifSoundDesc => i.notifSoundDesc;
  static String get notifSoundEnabled => i.notifSoundEnabled;
  static String get notifVibrationDesc => i.notifVibrationDesc;
  static String get notifVibrationEnabled => i.notifVibrationEnabled;
  static String get notificationIntentSms => i.notificationIntentSms;
  static String get notificationIntentWa => i.notificationIntentWa;
  static String get notificationMessageBody => i.notificationMessageBody;
  static String get notificationNoTemplates => i.notificationNoTemplates;
  static String get notificationPreviewTitle => i.notificationPreviewTitle;
  static String get notificationRecordNotFound => i.notificationRecordNotFound;
  static String get notificationSelectTemplate => i.notificationSelectTemplate;
  static String get notificationSendSms => i.notificationSendSms;
  static String get notificationSendWhatsApp => i.notificationSendWhatsApp;
  static String get notificationTemplatesTitle => i.notificationTemplatesTitle;
  static String get november => i.november;
  static String get numberOfDecimalDigits => i.numberOfDecimalDigits;
  static String get nutritionAndDailyConsumption =>
      i.nutritionAndDailyConsumption;
  static String get obligationsAndDebts => i.obligationsAndDebts;
  static String get obligationsAndDebts1 => i.obligationsAndDebts1;
  static String get occupiedPalestinianTerritories =>
      i.occupiedPalestinianTerritories;
  static String get october => i.october;
  static String get offerForSale => i.offerForSale;
  static String get oman => i.oman;
  static String get omani => i.omani;
  static String get onYou => i.onYou;
  static String get once => i.once;
  static String get onlyPeopleOnYour => i.onlyPeopleOnYour;
  static String get onlyUsersAllowedTo => i.onlyUsersAllowedTo;
  static String get onlyUsersSpecifiedIn => i.onlyUsersSpecifiedIn;
  static String get openEachDocumentVerify => i.openEachDocumentVerify;
  static String get openSettings => i.openSettings;
  static String get openToEveryone => i.openToEveryone;
  static String get openToMyAccounts => i.openToMyAccounts;
  static String get openWithBlocklist => i.openWithBlocklist;
  static String get openingBalance => i.openingBalance;
  static String get openingBalances => i.openingBalances;
  static String get oppositeParty => i.oppositeParty;
  static String get other => i.other;
  static String get otpSendError => i.otpSendError;
  static String get otpVerifyError => i.otpVerifyError;
  static String get outgoingTransfer => i.outgoingTransfer;
  static String get outgoingTransfer1 => i.outgoingTransfer1;
  static String get outgoingTransfer2 => i.outgoingTransfer2;
  static String get outlyingIslandsOfThe => i.outlyingIslandsOfThe;
  static String get oweToYou => i.oweToYou;
  static String get p2pScanSubtitle => i.p2pScanSubtitle;
  static String get p2pScanTitle => i.p2pScanTitle;
  static String get p2pSyncCodeSnapsync => i.p2pSyncCodeSnapsync;
  static String get p2pSyncFailed => i.p2pSyncFailed;
  static String get p2pSyncSuccess => i.p2pSyncSuccess;
  static String get pakistan => i.pakistan;
  static String get palau => i.palau;
  static String get panama => i.panama;
  static String get papuaNewGuinea => i.papuaNewGuinea;
  static String get paraguay => i.paraguay;
  static String get parentAccountLabel => i.parentAccountLabel;
  static String get parsingThePackage => i.parsingThePackage;
  static String get partial => i.partial;
  static String get partialMatch => i.partialMatch;
  static String get partyBankInfoLabel => i.partyBankInfoLabel;
  static String get partyDetailsSection => i.partyDetailsSection;
  static String get partyPhoneLabel => i.partyPhoneLabel;
  static String get partyTypeLabel => i.partyTypeLabel;
  static String get partyWhatsappLabel => i.partyWhatsappLabel;
  static String get passwordChangeError => i.passwordChangeError;
  static String get passwordMismatch => i.passwordMismatch;
  static String get passwordResetAction => i.passwordResetAction;
  static String get passwordResetConfirmAction => i.passwordResetConfirmAction;
  static String get passwordResetEmailSent => i.passwordResetEmailSent;
  static String get passwordResetError => i.passwordResetError;
  static String get passwordResetNewPassword => i.passwordResetNewPassword;
  static String get passwordResetSubtitle => i.passwordResetSubtitle;
  static String get passwordResetSuccess => i.passwordResetSuccess;
  static String get passwordResetTitle => i.passwordResetTitle;
  static String get passwordResetTokenHint => i.passwordResetTokenHint;
  static String get passwordTooShort => i.passwordTooShort;
  static String get perfectMatch => i.perfectMatch;
  static String get period => i.period;
  static String get periodMovement => i.periodMovement;
  static String get personalExpenses => i.personalExpenses;
  static String get personalLiving => i.personalLiving;
  static String get personalRevenue => i.personalRevenue;
  static String get peru => i.peru;
  static String get phone => i.phone;
  static String get phoneNumberRequired => i.phoneNumberRequired;
  static String get pickAccountTitle => i.pickAccountTitle;
  static String get pitcairnIsland => i.pitcairnIsland;
  static String get pleaseEnterACommit => i.pleaseEnterACommit;
  static String get pleaseEnterADimension => i.pleaseEnterADimension;
  static String get pleaseEnterAName => i.pleaseEnterAName;
  static String get pleaseEnterAValid => i.pleaseEnterAValid;
  static String get pleaseEnterTheCategory => i.pleaseEnterTheCategory;
  static String get pleaseEnterTheFull => i.pleaseEnterTheFull;
  static String get pleaseEnterTheName => i.pleaseEnterTheName;
  static String get pleaseEnterThePrimary => i.pleaseEnterThePrimary;
  static String get pleaseEnterTheSale => i.pleaseEnterTheSale;
  static String get pleaseEnterYourFacility => i.pleaseEnterYourFacility;
  static String get pleaseSelectASender => i.pleaseSelectASender;
  static String get pleaseSelectTheSource => i.pleaseSelectTheSource;
  static String get pleaseSignInTo => i.pleaseSignInTo;
  static String get poland => i.poland;
  static String get portugal => i.portugal;
  static String get possessionsEmpty => i.possessionsEmpty;
  static String get previewTheReceipt => i.previewTheReceipt;
  static String get previousCase => i.previousCase;
  static String get privacyLoadingError => i.privacyLoadingError;
  static String get privacyMode => i.privacyMode;
  static String get privacyPolicyHasBeen => i.privacyPolicyHasBeen;
  static String get privacyPolicyLabel => i.privacyPolicyLabel;
  static String get privacyProtected => i.privacyProtected;
  static String get privacyTermsHeader => i.privacyTermsHeader;
  static String get professionAccountNameHint => i.professionAccountNameHint;
  static String get professionAccountNameLabel => i.professionAccountNameLabel;
  static String get professionAccountNameRequired =>
      i.professionAccountNameRequired;
  static String get professionAddCostCenter => i.professionAddCostCenter;
  static String get professionHourlyRateLabel => i.professionHourlyRateLabel;
  static String get professionLicenseHint => i.professionLicenseHint;
  static String get professionLicenseLabel => i.professionLicenseLabel;
  static String get professionNameHint => i.professionNameHint;
  static String get professionNameLabel => i.professionNameLabel;
  static String get professionNameRequired => i.professionNameRequired;
  static String get professionNotesHint => i.professionNotesHint;
  static String get professionNotesLabel => i.professionNotesLabel;
  static String get professionStartDateHint => i.professionStartDateHint;
  static String get professionStartDateLabel => i.professionStartDateLabel;
  static String get professionSubmitButton => i.professionSubmitButton;
  static String get professionSubmitNote => i.professionSubmitNote;
  static String get professionWizardDesc => i.professionWizardDesc;
  static String get professionWizardRootError => i.professionWizardRootError;
  static String get professionWizardSuccess => i.professionWizardSuccess;
  static String get professionWizardTitle => i.professionWizardTitle;
  static String get profileDeleteAccountAction => i.profileDeleteAccountAction;
  static String get profileDeleteAccountConfirmLabel =>
      i.profileDeleteAccountConfirmLabel;
  static String get profileDeleteAccountExecute =>
      i.profileDeleteAccountExecute;
  static String get profileDeleteAccountSuccess =>
      i.profileDeleteAccountSuccess;
  static String get profileDeleteAccountWarningBody =>
      i.profileDeleteAccountWarningBody;
  static String get profileDeleteAccountWarningTitle =>
      i.profileDeleteAccountWarningTitle;
  static String get profileDetailsSection => i.profileDetailsSection;
  static String get profileEmailLabel => i.profileEmailLabel;
  static String get profileImageUpload => i.profileImageUpload;
  static String get profileLogoUpload => i.profileLogoUpload;
  static String get profileNameLabel => i.profileNameLabel;
  static String get profilePhoneLabel => i.profilePhoneLabel;
  static String get profileUpdateAction => i.profileUpdateAction;
  static String get profileUpdateSuccess => i.profileUpdateSuccess;
  static String get profileWhatsAppLabel => i.profileWhatsAppLabel;
  static String get propertyRights => i.propertyRights;
  static String get puertoRico => i.puertoRico;
  static String get purchaseDateLabel => i.purchaseDateLabel;
  static String get qatar => i.qatar;
  static String get qatari => i.qatari;
  static String get qayd => i.qayd;
  static String get quarterly => i.quarterly;
  static String get readyToSync => i.readyToSync;
  static String get realEstateStocksMoneymaking =>
      i.realEstateStocksMoneymaking;
  static String get reassessmentLog => i.reassessmentLog;
  static String get receiptNotice => i.receiptNotice;
  static String get receiptPublicKeyLabel => i.receiptPublicKeyLabel;
  static String get receiptSignatureSection => i.receiptSignatureSection;
  static String get receiptSignedBy => i.receiptSignedBy;
  static String get receiptVerifiedLabel => i.receiptVerifiedLabel;
  static String get receiptVoucher => i.receiptVoucher;
  static String get recipient => i.recipient;
  static String get recipientCreditedToHis => i.recipientCreditedToHis;
  static String get recordingDataCreditTo => i.recordingDataCreditTo;
  static String get recurringAmount => i.recurringAmount;
  static String get reevaluate => i.reevaluate;
  static String get reference => i.reference;
  static String get referenceDataOptional => i.referenceDataOptional;
  static String get referenceId => i.referenceId;
  static String get referenceNumber => i.referenceNumber;
  static String get referenceNumber1 => i.referenceNumber1;
  static String get refreshBalanceTooltip => i.refreshBalanceTooltip;
  static String get registerAction => i.registerAction;
  static String get registerSubtitle => i.registerSubtitle;
  static String get registerTitle => i.registerTitle;
  static String get registrationDataCreditTo => i.registrationDataCreditTo;
  static String get registrationDataDebitFrom => i.registrationDataDebitFrom;
  static String get registrationDataFromThe => i.registrationDataFromThe;
  static String get registrationDataToThe => i.registrationDataToThe;
  static String get registrationNumberLocationSpecifications =>
      i.registrationNumberLocationSpecifications;
  static String get regularbilateralBond => i.regularbilateralBond;
  static String get releaseDate => i.releaseDate;
  static String get released => i.released;
  static String get remittanceClearing => i.remittanceClearing;
  static String get replaceDatabaseUsingPrimary =>
      i.replaceDatabaseUsingPrimary;
  static String get reportAProblem => i.reportAProblem;
  static String get requestANewFeature => i.requestANewFeature;
  static String get requestToApproveA => i.requestToApproveA;
  static String get requestToCreateA => i.requestToCreateA;
  static String get requestToMakeA => i.requestToMakeA;
  static String get required => i.required;
  static String get resendAction => i.resendAction;
  static String get resendPrompt => i.resendPrompt;
  static String get resendTimerPrefix => i.resendTimerPrefix;
  static String get resendTimerSuffix => i.resendTimerSuffix;
  static String get resending => i.resending;
  static String get resolvingConflicts => i.resolvingConflicts;
  static String get restoration => i.restoration;
  static String get restoreAccountAction => i.restoreAccountAction;
  static String get restoreAccountConfirm => i.restoreAccountConfirm;
  static String get restoreAccountSuccess => i.restoreAccountSuccess;
  static String get restoreAccountTitle => i.restoreAccountTitle;
  static String get restoreNow => i.restoreNow;
  static String get restoreTheSelectedVersion => i.restoreTheSelectedVersion;
  static String get restrictedAllowListOnly => i.restrictedAllowListOnly;
  static String get restriction => i.restriction;
  static String get restrictionsCannotBeCreated =>
      i.restrictionsCannotBeCreated;
  static String get retainedSurplusForThe => i.retainedSurplusForThe;
  static String get retry => i.retry;
  static String get retryAction => i.retryAction;
  static String get returnToLogin => i.returnToLogin;
  static String get reunion => i.reunion;
  static String get revenuesAndGains => i.revenuesAndGains;
  static String get reviewAccountingEntries => i.reviewAccountingEntries;
  static String get reviewAndConfirm => i.reviewAndConfirm;
  static String get reviewAndEditThe => i.reviewAndEditThe;
  static String get reviewEachAccountAnd => i.reviewEachAccountAnd;
  static String get reviewOutstandingBonds => i.reviewOutstandingBonds;
  static String get reviewTheAttachedPictures => i.reviewTheAttachedPictures;
  static String get rightsAndEntitlements => i.rightsAndEntitlements;
  static String get romania => i.romania;
  static String get root => i.root;
  static String get rs => i.rs;
  static String get russia => i.russia;
  static String get rwanda => i.rwanda;
  static String get s0123456789 => i.s0123456789;
  static String get s1 => i.s1;
  static String get s2 => i.s2;
  static String get s3 => i.s3;
  static String get s4 => i.s4;
  static String get saintBarthelemy => i.saintBarthelemy;
  static String get saintHelena => i.saintHelena;
  static String get saintKittsAndNevis => i.saintKittsAndNevis;
  static String get saintLucia => i.saintLucia;
  static String get saintMartinFrenchPart => i.saintMartinFrenchPart;
  static String get saintVincentAndThe => i.saintVincentAndThe;
  static String get samoa => i.samoa;
  static String get sanMarino => i.sanMarino;
  static String get saoTomeAndPrincipe => i.saoTomeAndPrincipe;
  static String get sar => i.sar;
  static String get saudiRiyals => i.saudiRiyals;
  static String get save => i.save;
  static String get saveAccount => i.saveAccount;
  static String get saveAccountChanges => i.saveAccountChanges;
  static String get saveTheDoubleConversion => i.saveTheDoubleConversion;
  static String get saveTheMortgage => i.saveTheMortgage;
  static String get savingAndBuildingReserves => i.savingAndBuildingReserves;
  static String get scanThisCodeFrom => i.scanThisCodeFrom;
  static String get searchAccountsHint => i.searchAccountsHint;
  static String get searchCostCentersHint => i.searchCostCentersHint;
  static String get searchForConversionDetails => i.searchForConversionDetails;
  static String get searchForTheCountry => i.searchForTheCountry;
  static String get searchInGoogleDrive => i.searchInGoogleDrive;
  static String get secondClientSignature => i.secondClientSignature;
  static String get securityBiometricReason => i.securityBiometricReason;
  static String get securityBiometricTitle => i.securityBiometricTitle;
  static String get securityLockSubtitle => i.securityLockSubtitle;
  static String get securityLockTitle => i.securityLockTitle;
  static String get securityNeedPinFirst => i.securityNeedPinFirst;
  static String get securityPinDialogTitle => i.securityPinDialogTitle;
  static String get securityPinField => i.securityPinField;
  static String get securityPinLength => i.securityPinLength;
  static String get securityPinMismatch => i.securityPinMismatch;
  static String get securityPinRepeat => i.securityPinRepeat;
  static String get securityPinSaved => i.securityPinSaved;
  static String get securityPinWrong => i.securityPinWrong;
  static String get securitySetPinSubtitle => i.securitySetPinSubtitle;
  static String get securitySetPinTitle => i.securitySetPinTitle;
  static String get securityWarning => i.securityWarning;
  static String get seedBackupConfirmAction => i.seedBackupConfirmAction;
  static String get seedBackupConfirmBody => i.seedBackupConfirmBody;
  static String get seedBackupConfirmTitle => i.seedBackupConfirmTitle;
  static String get seedBackupConfirmed => i.seedBackupConfirmed;
  static String get seedBackupSkipAction => i.seedBackupSkipAction;
  static String get seedBackupWarning => i.seedBackupWarning;
  static String get seedRecoveryAction => i.seedRecoveryAction;
  static String get seedRecoveryBody => i.seedRecoveryBody;
  static String get seedRecoveryInvalid => i.seedRecoveryInvalid;
  static String get seedRecoverySuccess => i.seedRecoverySuccess;
  static String get seedRecoveryTitle => i.seedRecoveryTitle;
  static String get seedSetupBody => i.seedSetupBody;
  static String get seedSetupTitle => i.seedSetupTitle;
  static String get seedWordLabel => i.seedWordLabel;
  static String get selectAnyTextIn => i.selectAnyTextIn;
  static String get selectCostCenter => i.selectCostCenter;
  static String get selectCurrency => i.selectCurrency;
  static String get selectTheAppropriateTransfer =>
      i.selectTheAppropriateTransfer;
  static String get selectTheApprovedFinancial => i.selectTheApprovedFinancial;
  static String get selectTheCountry => i.selectTheCountry;
  static String get semiannually => i.semiannually;
  static String get send => i.send;
  static String get sender => i.sender;
  static String get sender1 => i.sender1;
  static String get senderDeductedFromHis => i.senderDeductedFromHis;
  static String get senegal => i.senegal;
  static String get sent => i.sent;
  static String get sent1 => i.sent1;
  static String get september => i.september;
  static String get serbia => i.serbia;
  static String get serialNumberLabel => i.serialNumberLabel;
  static String get serialNumberOrPlateLabel => i.serialNumberOrPlateLabel;
  static String get serverConnectionError => i.serverConnectionError;
  static String get serverErrorPleaseTry => i.serverErrorPleaseTry;
  static String get settingsAppearanceSubtitle => i.settingsAppearanceSubtitle;
  static String get settingsBackupConfirmBody => i.settingsBackupConfirmBody;
  static String get settingsBackupConfirmTitle => i.settingsBackupConfirmTitle;
  static String get settingsBackupSaveSubtitle => i.settingsBackupSaveSubtitle;
  static String get settingsBackupSaveTitle => i.settingsBackupSaveTitle;
  static String get settingsBackupSaved => i.settingsBackupSaved;
  static String get settingsBackupShareSubtitle =>
      i.settingsBackupShareSubtitle;
  static String get settingsBackupShareTitle => i.settingsBackupShareTitle;
  static String get settingsBackupSubtitle => i.settingsBackupSubtitle;
  static String get settingsContactSupport => i.settingsContactSupport;
  static String get settingsCsvDefaultClassification =>
      i.settingsCsvDefaultClassification;
  static String get settingsCsvImportConfirmTitle =>
      i.settingsCsvImportConfirmTitle;
  static String get settingsCsvImportExecute => i.settingsCsvImportExecute;
  static String get settingsCsvImportSubtitle => i.settingsCsvImportSubtitle;
  static String get settingsCsvImportTitle => i.settingsCsvImportTitle;
  static String get settingsCsvPreviewTitle => i.settingsCsvPreviewTitle;
  static String get settingsExportAllSubtitle => i.settingsExportAllSubtitle;
  static String get settingsExportAllTitle => i.settingsExportAllTitle;
  static String get settingsExportConfirmBody => i.settingsExportConfirmBody;
  static String get settingsExportConfirmTitle => i.settingsExportConfirmTitle;
  static String get settingsExportStatementPickTitle =>
      i.settingsExportStatementPickTitle;
  static String get settingsExportStatementSubtitle =>
      i.settingsExportStatementSubtitle;
  static String get settingsExportStatementTitle =>
      i.settingsExportStatementTitle;
  static String get settingsExportVouchersTitle =>
      i.settingsExportVouchersTitle;
  static String get settingsFaqs => i.settingsFaqs;
  static String get settingsGroupAppearance => i.settingsGroupAppearance;
  static String get settingsGroupBackup => i.settingsGroupBackup;
  static String get settingsGroupCurrency => i.settingsGroupCurrency;
  static String get settingsFiscalPeriodsSubtitle =>
      i.settingsFiscalPeriodsSubtitle;
  static String get settingsFiscalPeriodsTitle => i.settingsFiscalPeriodsTitle;
  static String get settingsGroupNotifications => i.settingsGroupNotifications;
  static String get settingsGroupProfile => i.settingsGroupProfile;
  static String get settingsGroupSecurity => i.settingsGroupSecurity;
  static String get settingsGroupSupport => i.settingsGroupSupport;
  static String get settingsGroupTemplates => i.settingsGroupTemplates;
  static String get settingsNotificationsSubtitle =>
      i.settingsNotificationsSubtitle;
  static String get settingsPrivacyPolicy => i.settingsPrivacyPolicy;
  static String get settingsProceed => i.settingsProceed;
  static String get settingsReportIssue => i.settingsReportIssue;
  static String get settingsRestoreConfirm => i.settingsRestoreConfirm;
  static String get settingsRestoreDone => i.settingsRestoreDone;
  static String get settingsRestoreError => i.settingsRestoreError;
  static String get settingsRestoreSubtitle => i.settingsRestoreSubtitle;
  static String get settingsRestoreTitle => i.settingsRestoreTitle;
  static String get settingsRestoreWarningBody => i.settingsRestoreWarningBody;
  static String get settingsRestoreWarningTitle =>
      i.settingsRestoreWarningTitle;
  static String get settingsSectionAutoBackup => i.settingsSectionAutoBackup;
  static String get settingsSectionBackup => i.settingsSectionBackup;
  static String get settingsSectionCurrency => i.settingsSectionCurrency;
  static String get settingsSectionCustomization =>
      i.settingsSectionCustomization;
  static String get settingsSectionDataSync => i.settingsSectionDataSync;
  static String get settingsSectionDraft => i.settingsSectionDraft;
  static String get settingsSectionDriveBackup => i.settingsSectionDriveBackup;
  static String get settingsSectionExport => i.settingsSectionExport;
  static String get settingsSectionSecurity => i.settingsSectionSecurity;
  static String get settingsSectionSecurityNotifications =>
      i.settingsSectionSecurityNotifications;
  static String get settingsSectionSupport => i.settingsSectionSupport;
  static String get settingsSecuritySubtitle => i.settingsSecuritySubtitle;
  static String get settingsSupportSubtitle => i.settingsSupportSubtitle;
  static String get settingsSyncPrivacySubtitle =>
      i.settingsSyncPrivacySubtitle;
  static String get settingsSyncPrivacyTitle => i.settingsSyncPrivacyTitle;
  static String get settingsSystemTitle => i.settingsSystemTitle;
  static String get settingsTemplatesSubtitle => i.settingsTemplatesSubtitle;
  static String get settingsTermsOfUse => i.settingsTermsOfUse;
  static String get settingsTitle => i.settingsTitle;
  static String get settingsUnderstood => i.settingsUnderstood;
  static String get settingsVersionInfo => i.settingsVersionInfo;
  static String get settled => i.settled;
  static String get settlementType => i.settlementType;
  static String get seychelles => i.seychelles;
  static String get shareAsImage => i.shareAsImage;
  static String get shareAsImageTooltip => i.shareAsImageTooltip;
  static String get shareAsPdf => i.shareAsPdf;
  static String get shareAsQr => i.shareAsQr;
  static String get shareAsSms => i.shareAsSms;
  static String get shareAsTextTooltip => i.shareAsTextTooltip;
  static String get shareReceiptTitle => i.shareReceiptTitle;
  static String get shareViaWhatsApp => i.shareViaWhatsApp;
  static String get sharingAcrossTheSystem => i.sharingAcrossTheSystem;
  static String get sharingOptions => i.sharingOptions;
  static String get showSuspendedLabel => i.showSuspendedLabel;
  static String get showTheReceiptDocument => i.showTheReceiptDocument;
  static String get sierraLeone => i.sierraLeone;
  static String get signInWithYour => i.signInWithYour;
  static String get signatureAgreement => i.signatureAgreement;
  static String get signatureOfReceivingClient => i.signatureOfReceivingClient;
  static String get signatureOfSendingClient => i.signatureOfSendingClient;
  static String get signatureOfTheBond => i.signatureOfTheBond;
  static String get signatureOfTheOpposite => i.signatureOfTheOpposite;
  static String get signatureOfTheReceiving => i.signatureOfTheReceiving;
  static String get signatureOfTheSending => i.signatureOfTheSending;
  static String get signatureStatus => i.signatureStatus;
  static String get singapore => i.singapore;
  static String get sintMaartenDutchPart => i.sintMaartenDutchPart;
  static String get skip => i.skip;
  static String get skipAndStartWith => i.skipAndStartWith;
  static String get skippedMovements => i.skippedMovements;
  static String get slovakia => i.slovakia;
  static String get slovenia => i.slovenia;
  static String get smartSuggestionAccept => i.smartSuggestionAccept;
  static String get smartSuggestionAmount => i.smartSuggestionAmount;
  static String get smartSuggestionDate => i.smartSuggestionDate;
  static String get smartSuggestionType => i.smartSuggestionType;
  static String get smartSuggestionsTitle => i.smartSuggestionsTitle;
  static String get statusDraft => i.statusDraft;
  static String get statusConfirmed => i.statusConfirmed;
  static String get statusSettled => i.statusSettled;
  static String get statusVoided => i.statusVoided;
  static String get statusPending => i.statusPending;
  static String get snapsync => i.snapsync;
  static String get solomonIslands => i.solomonIslands;
  static String get somalia => i.somalia;
  static String get someDataCannotBe => i.someDataCannotBe;
  static String get sourceQaidPersonalAccounting =>
      i.sourceQaidPersonalAccounting;
  static String get southAfrica => i.southAfrica;
  static String get southGeorgia => i.southGeorgia;
  static String get southKorea => i.southKorea;
  static String get southSudan => i.southSudan;
  static String get southernRegionsOfFrance => i.southernRegionsOfFrance;
  static String get spain => i.spain;
  static String get sriLanka => i.sriLanka;
  static String get stPierreAndMicolon => i.stPierreAndMicolon;
  static String get standardClassificationTab => i.standardClassificationTab;
  static String get startByAddingYour => i.startByAddingYour;
  static String get startByAddingYour1 => i.startByAddingYour1;
  static String get startImport => i.startImport;
  static String get statement => i.statement;
  static String get statement1 => i.statement1;
  static String get statementBalanceAgainstYou => i.statementBalanceAgainstYou;
  static String get statementBalanceForYou => i.statementBalanceForYou;
  static String get statementBalanceSettled => i.statementBalanceSettled;
  static String get statementBroughtForward => i.statementBroughtForward;
  static String get statementChatAccept => i.statementChatAccept;
  static String get statementChatEmpty => i.statementChatEmpty;
  static String get statementChatEmptyFiltered => i.statementChatEmptyFiltered;
  static String get statementChatReject => i.statementChatReject;
  static String get statementChatResubmit => i.statementChatResubmit;
  static String get statementChatSearchHint => i.statementChatSearchHint;
  static String get statementSettlementMilestone =>
      i.statementSettlementMilestone;
  static String get statementChatTitle => i.statementChatTitle;
  static String get statementChatWithdraw => i.statementChatWithdraw;
  static String get statementDateLastQuarter => i.statementDateLastQuarter;
  static String get statementDateThisMonth => i.statementDateThisMonth;
  static String get statementDateThisYear => i.statementDateThisYear;
  static String get statementFeePrefix => i.statementFeePrefix;
  static String get statementFieldName => i.statementFieldName;
  static String get statementFilterStatusSection =>
      i.statementFilterStatusSection;
  static String get statementFilterTitle => i.statementFilterTitle;
  static String get statementFinalBalance => i.statementFinalBalance;
  static String get statementIncludePreviousBalance =>
      i.statementIncludePreviousBalance;
  static String get statementIncludePreviousBalanceHint =>
      i.statementIncludePreviousBalanceHint;
  static String get statementMediatorPrefix => i.statementMediatorPrefix;
  static String get statementRunningBalance => i.statementRunningBalance;
  static String get statementStatusConfirmed => i.statementStatusConfirmed;
  static String get statementStatusPending => i.statementStatusPending;
  static String get statementStatusReceipt => i.statementStatusReceipt;
  static String get statementStatusRejected => i.statementStatusRejected;
  static String get statementUnifiedTitle => i.statementUnifiedTitle;
  static String get statementUnreadMessages => i.statementUnreadMessages;
  static String get statementViewModeMy => i.statementViewModeMy;
  static String get statementViewModeOther => i.statementViewModeOther;
  static String get statementVoucherCount => i.statementVoucherCount;
  static String get statusActive => i.statusActive;
  static String get statusActiveEn => i.statusActiveEn;
  static String get statusInactive => i.statusInactive;
  static String get statusInactiveEn => i.statusInactiveEn;
  static String get statusLabel => i.statusLabel;
  static String get statusRejected => i.statusRejected;
  static String get str1 => i.str1;
  static String get submitTheRequest => i.submitTheRequest;
  static String get subscriptionHasExpiredPlease =>
      i.subscriptionHasExpiredPlease;
  static String get sudan => i.sudan;
  static String get suggestionClaim => i.suggestionClaim;
  static String get suggestionRecurring => i.suggestionRecurring;
  static String get suriname => i.suriname;
  static String get svalbardAndJanMayen => i.svalbardAndJanMayen;
  static String get swaziland => i.swaziland;
  static String get sweden => i.sweden;
  static String get switzerland => i.switzerland;
  static String get syncAcceptanceBody => i.syncAcceptanceBody;
  static String get syncAcceptanceTitle => i.syncAcceptanceTitle;
  static String get syncClaimBody => i.syncClaimBody;
  static String get syncClaimTitle => i.syncClaimTitle;
  static String get syncPrivacy => i.syncPrivacy;
  static String get synchronizationControl => i.synchronizationControl;
  static String get syncingViaDirectQr => i.syncingViaDirectQr;
  static String get syria => i.syria;
  static String get taiwan => i.taiwan;
  static String get tajikistan => i.tajikistan;
  static String get tanzania => i.tanzania;
  static String get templateAddFab => i.templateAddFab;
  static String get templateAddTitle => i.templateAddTitle;
  static String get templateBodyLabel => i.templateBodyLabel;
  static String get templateDeleteConfirm => i.templateDeleteConfirm;
  static String get templateDeleteMessage => i.templateDeleteMessage;
  static String get templateDeleteTitle => i.templateDeleteTitle;
  static String get templateEditCancel => i.templateEditCancel;
  static String get templateEditSave => i.templateEditSave;
  static String get templateEditTitle => i.templateEditTitle;
  static String get templateKindAccount => i.templateKindAccount;
  static String get templateKindPayment => i.templateKindPayment;
  static String get templateKindPickerLabel => i.templateKindPickerLabel;
  static String get templateKindReceipt => i.templateKindReceipt;
  static String get templateNameLabel => i.templateNameLabel;
  static String get templateNotFound => i.templateNotFound;
  static String get termsLoadingError => i.termsLoadingError;
  static String get termsOfUseLabel => i.termsOfUseLabel;
  static String get thailand => i.thailand;
  static String get thankYouForDealing => i.thankYouForDealing;
  static String get theAccount => i.theAccount;
  static String get theAccountCannotBe => i.theAccountCannotBe;
  static String get theAccountCouldNot => i.theAccountCouldNot;
  static String get theAccountCouldNot1 => i.theAccountCouldNot1;
  static String get theAccountDoesNot => i.theAccountDoesNot;
  static String get theAccountDoesNot1 => i.theAccountDoesNot1;
  static String get theAccountHasBeen => i.theAccountHasBeen;
  static String get theAccountHasBeen1 => i.theAccountHasBeen1;
  static String get theAccountIsTemporarily => i.theAccountIsTemporarily;
  static String get theAccountStatusHas => i.theAccountStatusHas;
  static String get theAccounts => i.theAccounts;
  static String get theAffectedPartyAnd => i.theAffectedPartyAnd;
  static String get theAmountCannotBe => i.theAmountCannotBe;
  static String get theAmountMustBe => i.theAmountMustBe;
  static String get theApplicationIsIn => i.theApplicationIsIn;
  static String get theAssetHasBeen => i.theAssetHasBeen;
  static String get theAttachmentDoesNot => i.theAttachmentDoesNot;
  static String get theAttachmentNotDownloaded => i.theAttachmentNotDownloaded;
  static String get theAutomaticBackupCould => i.theAutomaticBackupCould;
  static String get theBackupCouldNot => i.theBackupCouldNot;
  static String get theBackupCouldNot1 => i.theBackupCouldNot1;
  static String get theBondAmountMust => i.theBondAmountMust;
  static String get theBondCanBe => i.theBondCanBe;
  static String get theBondCanOnly => i.theBondCanOnly;
  static String get theBondCannotBe => i.theBondCannotBe;
  static String get theBondCannotBe1 => i.theBondCannotBe1;
  static String get theBondCouldNot => i.theBondCouldNot;
  static String get theBondCouldNot1 => i.theBondCouldNot1;
  static String get theBondCouldNot2 => i.theBondCouldNot2;
  static String get theBondDoesNot => i.theBondDoesNot;
  static String get theBondEntriesCould => i.theBondEntriesCould;
  static String get theBondHasBeen => i.theBondHasBeen;
  static String get theBondHasBeen1 => i.theBondHasBeen1;
  static String get theBondHasBeen2 => i.theBondHasBeen2;
  static String get theBondHasBeen3 => i.theBondHasBeen3;
  static String get theBondIsApproved => i.theBondIsApproved;
  static String get theBondIsPreaccepted => i.theBondIsPreaccepted;
  static String get theBondIsWithdrawn => i.theBondIsWithdrawn;
  static String get theBox => i.theBox;
  static String get theCategoryCouldNot => i.theCategoryCouldNot;
  static String get theCodeDoesNot => i.theCodeDoesNot;
  static String get theCondition => i.theCondition;
  static String get theConflictWasSuccessfully => i.theConflictWasSuccessfully;
  static String get theConnectionTimedOut => i.theConnectionTimedOut;
  static String get theConsolidatedBackupCould => i.theConsolidatedBackupCould;
  static String get theCostCenterCould => i.theCostCenterCould;
  static String get theCostCenterCould1 => i.theCostCenterCould1;
  static String get theCounterpartyHasRestricted =>
      i.theCounterpartyHasRestricted;
  static String get theCounterpartysPublicKey => i.theCounterpartysPublicKey;
  static String get theDataHasBeen => i.theDataHasBeen;
  static String get theDatabaseDoesNot => i.theDatabaseDoesNot;
  static String get theDatabaseFileCould => i.theDatabaseFileCould;
  static String get theDatabaseVersionIs => i.theDatabaseVersionIs;
  static String get theDate => i.theDate;
  static String get theDate1 => i.theDate1;
  static String get theDefaultAccountCannot => i.theDefaultAccountCannot;
  static String get theDefaultAccountCannot1 => i.theDefaultAccountCannot1;
  static String get theDefaultAccountCannot2 => i.theDefaultAccountCannot2;
  static String get theDefaultCostCenter => i.theDefaultCostCenter;
  static String get theDefaultCostCenter1 => i.theDefaultCostCenter1;
  static String get theDefaultCostCenter2 => i.theDefaultCostCenter2;
  static String get theDefaultCostCenters => i.theDefaultCostCenters;
  static String get theDefaultTemplateCannot => i.theDefaultTemplateCannot;
  static String get theDimensionCouldNot => i.theDimensionCouldNot;
  static String get theDimensionCouldNot1 => i.theDimensionCouldNot1;
  static String get theDimensionsOfThe => i.theDimensionsOfThe;
  static String get theDocumentCannotBe => i.theDocumentCannotBe;
  static String get theDocumentCouldNot => i.theDocumentCouldNot;
  static String get theDoubleConversionFeature => i.theDoubleConversionFeature;
  static String get theDoubleConversionWas => i.theDoubleConversionWas;
  static String get theDrawingObjectCould => i.theDrawingObjectCould;
  static String get theEntitlementCouldNot => i.theEntitlementCouldNot;
  static String get theEntitlementCouldNot1 => i.theEntitlementCouldNot1;
  static String get theEntitlementCouldNot2 => i.theEntitlementCouldNot2;
  static String get theEntityOriginatingThe => i.theEntityOriginatingThe;
  static String get theEntryAmountMust => i.theEntryAmountMust;
  static String get theEntryCouldNot => i.theEntryCouldNot;
  static String get theFileCouldNot => i.theFileCouldNot;
  static String get theFileCouldNot1 => i.theFileCouldNot1;
  static String get theFileDoesNot => i.theFileDoesNot;
  static String get theFileDoesNot1 => i.theFileDoesNot1;
  static String get theFileDoesNot2 => i.theFileDoesNot2;
  static String get theFileIsEmpty => i.theFileIsEmpty;
  static String get theFirstRowMust => i.theFirstRowMust;
  static String get theFreeTrialPeriod => i.theFreeTrialPeriod;
  static String get theFundAccountMust => i.theFundAccountMust;
  static String get theFundAccountWas => i.theFundAccountWas;
  static String get theHistoryOfAll => i.theHistoryOfAll;
  static String get theInstrumentCannotBe => i.theInstrumentCannotBe;
  static String get theIntermediateAccountMust => i.theIntermediateAccountMust;
  static String get theInternalTransactionWas => i.theInternalTransactionWas;
  static String get theLastOpenDocument => i.theLastOpenDocument;
  static String get theLedgerCouldNot => i.theLedgerCouldNot;
  static String get theListHasBeen => i.theListHasBeen;
  static String get theListIsEmpty => i.theListIsEmpty;
  static String get theMainFundAccount => i.theMainFundAccount;
  static String get theMediator => i.theMediator;
  static String get theMortgageDoesNot => i.theMortgageDoesNot;
  static String get theMortgageHasBeen => i.theMortgageHasBeen;
  static String get theName => i.theName;
  static String get theNameOfThe => i.theNameOfThe;
  static String get theNameOfThe1 => i.theNameOfThe1;
  static String get theNext => i.theNext;
  static String get theOtherParty => i.theOtherParty;
  static String get theOutboxCouldNot => i.theOutboxCouldNot;
  static String get thePartyDataCould => i.thePartyDataCould;
  static String get thePartyDataCould1 => i.thePartyDataCould1;
  static String get thePartyOriginatingThe => i.thePartyOriginatingThe;
  static String get thePartysOutboxCould => i.thePartysOutboxCould;
  static String get thePhilippines => i.thePhilippines;
  static String get thePictures => i.thePictures;
  static String get thePrimaryKeyIs => i.thePrimaryKeyIs;
  static String get thePrivacyPolicyCould => i.thePrivacyPolicyCould;
  static String get theRequestHasBeen => i.theRequestHasBeen;
  static String get theRestoreOperationFailed => i.theRestoreOperationFailed;
  static String get theRootAccountFor => i.theRootAccountFor;
  static String get theSelectedCurrencyIs => i.theSelectedCurrencyIs;
  static String get theSenderAndRecipient => i.theSenderAndRecipient;
  static String get theSenderAndRecipient1 => i.theSenderAndRecipient1;
  static String get theSendingAttemptCould => i.theSendingAttemptCould;
  static String get theSignatureDoesNot => i.theSignatureDoesNot;
  static String get theSourceAndDestination => i.theSourceAndDestination;
  static String get theSyncTagCould => i.theSyncTagCould;
  static String get theSynchronizationTableCould =>
      i.theSynchronizationTableCould;
  static String get theSystemWillAutomatically => i.theSystemWillAutomatically;
  static String get theSystemWillCancel => i.theSystemWillCancel;
  static String get theTemplateCouldNot => i.theTemplateCouldNot;
  static String get theTemplateCouldNot1 => i.theTemplateCouldNot1;
  static String get theTemplateCouldNot2 => i.theTemplateCouldNot2;
  static String get theTransferHasBeen => i.theTransferHasBeen;
  static String get theTransferHasBeen1 => i.theTransferHasBeen1;
  static String get theTransferHasBeen2 => i.theTransferHasBeen2;
  static String get theTransferRequestHas => i.theTransferRequestHas;
  static String get theTransferWasRejected => i.theTransferWasRejected;
  static String get theTripleTransferVouchers => i.theTripleTransferVouchers;
  static String get theUserCouldNot => i.theUserCouldNot;
  static String get theUserHasBeen => i.theUserHasBeen;
  static String get theUserHasBeen1 => i.theUserHasBeen1;
  static String get theVoucherCouldNot => i.theVoucherCouldNot;
  static String get themeDark => i.themeDark;
  static String get themeLight => i.themeLight;
  static String get themeSystem => i.themeSystem;
  static String get thereAreNoNew => i.thereAreNoNew;
  static String get thereAreNoTransactions => i.thereAreNoTransactions;
  static String get thereAreNoTransfers => i.thereAreNoTransfers;
  static String get thereIsAPrevious => i.thereIsAPrevious;
  static String get thereIsAlreadyAn => i.thereIsAlreadyAn;
  static String get thereIsAnAccount => i.thereIsAnAccount;
  static String get thereIsNoAccount => i.thereIsNoAccount;
  static String get thereIsNoContent => i.thereIsNoContent;
  static String get thereIsNoDatabase => i.thereIsNoDatabase;
  static String get thereIsNoDebt => i.thereIsNoDebt;
  static String get thisActionCannotBe => i.thisActionCannotBe;
  static String get thisBondHasBeen => i.thisBondHasBeen;
  static String get thisMortgageCannotBe => i.thisMortgageCannotBe;
  static String get thisNoticeIsConsidered => i.thisNoticeIsConsidered;
  static String get thisNoticeIsConsidered1 => i.thisNoticeIsConsidered1;
  static String get thisReportWasGenerated => i.thisReportWasGenerated;
  static String get thisStatementWasGenerated => i.thisStatementWasGenerated;
  static String get toBeSure => i.toBeSure;
  static String get toConnectTwoDevices => i.toConnectTwoDevices;
  static String get toMe => i.toMe;
  static String get toMerge => i.toMerge;
  static String get toRequest => i.toRequest;
  static String get toTreat => i.toTreat;
  static String get toWithdraw => i.toWithdraw;
  static String get togo => i.togo;
  static String get tokelau => i.tokelau;
  static String get tonga => i.tonga;
  static String get total => i.total;
  static String get totalAssets => i.totalAssets;
  static String get totalAssetsLabel => i.totalAssetsLabel;
  static String get totalBalance => i.totalBalance;
  static String get totalBalance1 => i.totalBalance1;
  static String get totalBalance2 => i.totalBalance2;
  static String get totalCredit => i.totalCredit;
  static String get totalDebit => i.totalDebit;
  static String get totalLiabilities => i.totalLiabilities;
  static String get totalLiabilitiesLabel => i.totalLiabilitiesLabel;
  static String get totalsSummaryPrefix => i.totalsSummaryPrefix;
  static String get transactionVouchersAreCreated =>
      i.transactionVouchersAreCreated;
  static String get transferAmount => i.transferAmount;
  static String get transferFeeActionEdit => i.transferFeeActionEdit;
  static String get transferFeeActionSave => i.transferFeeActionSave;
  static String get transferFeeAmountLabel => i.transferFeeAmountLabel;
  static String get transferFeeErrorInvalidAmount =>
      i.transferFeeErrorInvalidAmount;
  static String get transferFeeIncome => i.transferFeeIncome;
  static String get transferFeeSaveSuccess => i.transferFeeSaveSuccess;
  static String get transferFeeToggleSubtitle => i.transferFeeToggleSubtitle;
  static String get transferFeeToggleTitle => i.transferFeeToggleTitle;
  static String get transferFees => i.transferFees;
  static String get transportationAndMobility => i.transportationAndMobility;
  static String get trialBalance => i.trialBalance;
  static String get trialBalanceARecording => i.trialBalanceARecording;
  static String get trialBalanceBalanced => i.trialBalanceBalanced;
  static String get trialBalanceColAccount => i.trialBalanceColAccount;
  static String get trialBalanceColCredit => i.trialBalanceColCredit;
  static String get trialBalanceColDebit => i.trialBalanceColDebit;
  static String get trialBalanceCryptocurrencySystem =>
      i.trialBalanceCryptocurrencySystem;
  static String get trialBalanceEmpty => i.trialBalanceEmpty;
  static String get trialBalanceGrandTotal => i.trialBalanceGrandTotal;
  static String get trialBalanceImbalanceLabel => i.trialBalanceImbalanceLabel;
  static String get trialBalanceNotBalanced => i.trialBalanceNotBalanced;
  static String get trialBalanceTitle => i.trialBalanceTitle;
  static String get trinidadAndTobago => i.trinidadAndTobago;
  static String get tripartiteAffectedLabel => i.tripartiteAffectedLabel;
  static String get tripartiteBridgeTooltip => i.tripartiteBridgeTooltip;
  static String get tripartiteContingentBadge => i.tripartiteContingentBadge;
  static String get tripartiteContingentHint => i.tripartiteContingentHint;
  static String get tripartiteCreatedSuccess => i.tripartiteCreatedSuccess;
  static String get tripartiteDestinationLabel => i.tripartiteDestinationLabel;
  static String get tripartiteDisabledDialogContent =>
      i.tripartiteDisabledDialogContent;
  static String get tripartiteDisabledDialogTitle =>
      i.tripartiteDisabledDialogTitle;
  static String get tripartiteDisabledError => i.tripartiteDisabledError;
  static String get tripartiteDraftSaved => i.tripartiteDraftSaved;
  static String get tripartiteFlowDestination => i.tripartiteFlowDestination;
  static String get tripartiteFlowMediator => i.tripartiteFlowMediator;
  static String get tripartiteFlowSource => i.tripartiteFlowSource;
  static String get tripartiteFlowTitle => i.tripartiteFlowTitle;
  static String get tripartiteGoToSettings => i.tripartiteGoToSettings;
  static String get tripartiteGroupLabel => i.tripartiteGroupLabel;
  static String get tripartiteMediatorLabel => i.tripartiteMediatorLabel;
  static String get tripartiteNewTitle => i.tripartiteNewTitle;
  static String get tripartiteNoClearingAccount =>
      i.tripartiteNoClearingAccount;
  static String get tripartitePaymentLeg => i.tripartitePaymentLeg;
  static String get tripartitePickAffectedHint => i.tripartitePickAffectedHint;
  static String get tripartitePickDestHint => i.tripartitePickDestHint;
  static String get tripartitePickSourceHint => i.tripartitePickSourceHint;
  static String get tripartiteReceiptLeg => i.tripartiteReceiptLeg;
  static String get tripartiteReleasedInfo => i.tripartiteReleasedInfo;
  static String get tripartiteRequestFunds => i.tripartiteRequestFunds;
  static String get transferRequestCurrencyLabel =>
      i.transferRequestCurrencyLabel;
  static String get transferRequestNotesLabel => i.transferRequestNotesLabel;
  static String get transferRequestNotesHint => i.transferRequestNotesHint;
  static String get transferRequestOpenTransfers =>
      i.transferRequestOpenTransfers;
  static String get transferRequestReceivedTitle =>
      i.transferRequestReceivedTitle;
  static String get tripartiteSelectAccountHint =>
      i.tripartiteSelectAccountHint;
  static String get tripartiteSelectAccounts => i.tripartiteSelectAccounts;
  static String get tripartiteSourceLabel => i.tripartiteSourceLabel;
  static String get tripartiteToggleLabel => i.tripartiteToggleLabel;
  static String get tripartiteToggleSubtitle => i.tripartiteToggleSubtitle;
  static String get tripleConversion => i.tripleConversion;
  static String get tripleTransferDeedNotice => i.tripleTransferDeedNotice;
  static String get trkiye => i.trkiye;
  static String get tryChangingTheFilters => i.tryChangingTheFilters;
  static String get trySearchingWithOther => i.trySearchingWithOther;
  static String get trySearchingWithOther1 => i.trySearchingWithOther1;
  static String get trySearchingWithOther2 => i.trySearchingWithOther2;
  static String get tunisia => i.tunisia;
  static String get turkishLira => i.turkishLira;
  static String get turkmenistan => i.turkmenistan;
  static String get turksAndCaicosIslands => i.turksAndCaicosIslands;
  static String get tuvalu => i.tuvalu;
  static String get twoOrdinaryBondsAffect => i.twoOrdinaryBondsAffect;
  static String get twoVouchersWillBe => i.twoVouchersWillBe;
  static String get type => i.type;
  static String get typeDebitcredit => i.typeDebitcredit;
  static String get typeOfFinancialTransaction => i.typeOfFinancialTransaction;
  static String get uganda => i.uganda;
  static String get uk => i.uk;
  static String get ukraine => i.ukraine;
  static String get unableToCalculateCost => i.unableToCalculateCost;
  static String get unableToCheckLicense => i.unableToCheckLicense;
  static String get unableToConnectTo => i.unableToConnectTo;
  static String get unableToConnectTo1 => i.unableToConnectTo1;
  static String get unableToCreateAccount => i.unableToCreateAccount;
  static String get unableToCreateOr => i.unableToCreateOr;
  static String get unableToDeleteAccount => i.unableToDeleteAccount;
  static String get unableToDeleteAccount1 => i.unableToDeleteAccount1;
  static String get unableToDeleteCost => i.unableToDeleteCost;
  static String get unableToDeleteCost1 => i.unableToDeleteCost1;
  static String get unableToDeleteUser => i.unableToDeleteUser;
  static String get unableToExtractImage => i.unableToExtractImage;
  static String get unableToLoadComparison => i.unableToLoadComparison;
  static String get unableToLoadContent => i.unableToLoadContent;
  static String get unableToLoadInbox => i.unableToLoadInbox;
  static String get unableToLoadNotification => i.unableToLoadNotification;
  static String get unableToLoadPrivacy => i.unableToLoadPrivacy;
  static String get unableToOpenWhatsapp => i.unableToOpenWhatsapp;
  static String get unableToReadAccrued => i.unableToReadAccrued;
  static String get unableToReadArchived => i.unableToReadArchived;
  static String get unableToReadConversion => i.unableToReadConversion;
  static String get unableToReadCost => i.unableToReadCost;
  static String get unableToReadCost1 => i.unableToReadCost1;
  static String get unableToReadDependent => i.unableToReadDependent;
  static String get unableToReadDimension => i.unableToReadDimension;
  static String get unableToReadDimensions => i.unableToReadDimensions;
  static String get unableToReadDouble => i.unableToReadDouble;
  static String get unableToReadLabels => i.unableToReadLabels;
  static String get unableToReadMessage => i.unableToReadMessage;
  static String get unableToReadMonthly => i.unableToReadMonthly;
  static String get unableToReadParty => i.unableToReadParty;
  static String get unableToReadPosition => i.unableToReadPosition;
  static String get unableToReadRecent => i.unableToReadRecent;
  static String get unableToReadReturns => i.unableToReadReturns;
  static String get unableToReadSubaccounts => i.unableToReadSubaccounts;
  static String get unableToReadTemplates => i.unableToReadTemplates;
  static String get unableToReadThe => i.unableToReadThe;
  static String get unableToReadVouchers => i.unableToReadVouchers;
  static String get unableToRestoreAccount => i.unableToRestoreAccount;
  static String get unableToSaveAccount => i.unableToSaveAccount;
  static String get unableToSaveAnd => i.unableToSaveAnd;
  static String get unableToSaveNotification => i.unableToSaveNotification;
  static String get unableToSaveThe => i.unableToSaveThe;
  static String get unableToSearchBonds => i.unableToSearchBonds;
  static String get unableToSearchBy => i.unableToSearchBy;
  static String get unableToSearchBy1 => i.unableToSearchBy1;
  static String get unableToSearchBy2 => i.unableToSearchBy2;
  static String get unableToSearchFor => i.unableToSearchFor;
  static String get unableToUpdateDelivery => i.unableToUpdateDelivery;
  static String get unableToUpdateNotification => i.unableToUpdateNotification;
  static String get unableToUpdateSync => i.unableToUpdateSync;
  static String get unableToVerifyAccount => i.unableToVerifyAccount;
  static String get unacceptable => i.unacceptable;
  static String get unavailable => i.unavailable;
  static String get unbalanced => i.unbalanced;
  static String get unbalancedLabel => i.unbalancedLabel;
  static String get uncertain => i.uncertain;
  static String get undefined => i.undefined;
  static String get unexpectedErrorTryAgain => i.unexpectedErrorTryAgain;
  static String get unitedArabEmirates => i.unitedArabEmirates;
  static String get unknown => i.unknown;
  static String get unknownAccount => i.unknownAccount;
  static String get unlockAction => i.unlockAction;
  static String get updateAccountStatus => i.updateAccountStatus;
  static String get updateError => i.updateError;
  static String get appUpdateAvailableTitle => i.appUpdateAvailableTitle;
  static String get appUpdateAvailableBody => i.appUpdateAvailableBody;
  static String get appUpdateInstallAction => i.appUpdateInstallAction;
  static String get appUpdateRestartBody => i.appUpdateRestartBody;
  static String get appUpdateInstalling => i.appUpdateInstalling;
  static String get updateOnTheBond => i.updateOnTheBond;
  static String get updateOnTheTransfer => i.updateOnTheTransfer;
  static String get uruguay => i.uruguay;
  static String get us => i.us;
  static String get usDollars => i.usDollars;
  static String get usVirginIslands => i.usVirginIslands;
  static String get usersBlockedFromSyncing => i.usersBlockedFromSyncing;
  static String get uzbekistan => i.uzbekistan;
  static String get vanuatu => i.vanuatu;
  static String get vatican => i.vatican;
  static String get vaultActivateAction => i.vaultActivateAction;
  static String get vaultClockTamperedBody => i.vaultClockTamperedBody;
  static String get vaultClockTamperedTitle => i.vaultClockTamperedTitle;
  static String get vaultContactSupport => i.vaultContactSupport;
  static String get vaultDeviceUnboundBody => i.vaultDeviceUnboundBody;
  static String get vaultDeviceUnboundTitle => i.vaultDeviceUnboundTitle;
  static String get vaultEmailHint => i.vaultEmailHint;
  static String get vaultPasswordHint => i.vaultPasswordHint;
  static String get vaultPendingBody => i.vaultPendingBody;
  static String get vaultPendingTitle => i.vaultPendingTitle;
  static String get vaultRevokedBody => i.vaultRevokedBody;
  static String get vaultRevokedTitle => i.vaultRevokedTitle;
  static String get vaultTrialDaysRemaining => i.vaultTrialDaysRemaining;
  static String get vaultTrialExpiredBody => i.vaultTrialExpiredBody;
  static String get vaultTrialExpiredTitle => i.vaultTrialExpiredTitle;
  static String get venezuela => i.venezuela;
  static String get verificationMethodEmailSubtitle =>
      i.verificationMethodEmailSubtitle;
  static String get verificationMethodEmailTitle =>
      i.verificationMethodEmailTitle;
  static String get verificationMethodPhoneSubtitle =>
      i.verificationMethodPhoneSubtitle;
  static String get verificationMethodPhoneTitle =>
      i.verificationMethodPhoneTitle;
  static String get verificationMethodSelectorTitle =>
      i.verificationMethodSelectorTitle;
  static String get verificationSubtitle => i.verificationSubtitle;
  static String get verificationTitle => i.verificationTitle;
  static String get verifyAction => i.verifyAction;
  static String get video => i.video;
  static String get vietnam => i.vietnam;
  static String get viewDetails => i.viewDetails;
  static String get virtualCostCenters => i.virtualCostCenters;
  static String get voucherAcceptedSuccess => i.voucherAcceptedSuccess;
  static String get voucherAddCollateral => i.voucherAddCollateral;
  static String get voucherAffectedAccountHint => i.voucherAffectedAccountHint;
  static String get voucherAffectedAccountLabel =>
      i.voucherAffectedAccountLabel;
  static String get voucherAffectedAccountParty =>
      i.voucherAffectedAccountParty;
  static String get voucherAffectedAccountPaymentTitle =>
      i.voucherAffectedAccountPaymentTitle;
  static String get voucherAffectedAccountReceiptTitle =>
      i.voucherAffectedAccountReceiptTitle;
  static String get voucherAmountLabel => i.voucherAmountLabel;
  static String get voucherAmountRequired => i.voucherAmountRequired;
  static String get voucherAttachImages => i.voucherAttachImages;
  static String get voucherAttachmentSizeLabel => i.voucherAttachmentSizeLabel;
  static String get voucherAttachmentsSection => i.voucherAttachmentsSection;
  static String get voucherClearAllFiltersChip => i.voucherClearAllFiltersChip;
  static String get voucherCollateralExpiryLabel =>
      i.voucherCollateralExpiryLabel;
  static String get voucherCollateralSection => i.voucherCollateralSection;
  static String get voucherCollateralSettlementsTitle =>
      i.voucherCollateralSettlementsTitle;
  static String get voucherCollateralStatusLabel =>
      i.voucherCollateralStatusLabel;
  static String get voucherCollateralValueLabel =>
      i.voucherCollateralValueLabel;
  static String get voucherCollateralValuePrefix =>
      i.voucherCollateralValuePrefix;
  static String get voucherConfirmAction => i.voucherConfirmAction;
  static String get voucherConfirmAndSend => i.voucherConfirmAndSend;
  static String get voucherConfirmedAndSentSuccess =>
      i.voucherConfirmedAndSentSuccess;
  static String get voucherConfirmedAtLabel => i.voucherConfirmedAtLabel;
  static String get voucherConfirmedSuccess => i.voucherConfirmedSuccess;
  static String get voucherCostCenterTypeCost => i.voucherCostCenterTypeCost;
  static String get voucherCostCenterTypeProfit =>
      i.voucherCostCenterTypeProfit;
  static String get voucherCostCentersSection => i.voucherCostCentersSection;
  static String get voucherCounterpartyLabel => i.voucherCounterpartyLabel;
  static String get voucherCreateReversal => i.voucherCreateReversal;
  static String get voucherCreateSettlement => i.voucherCreateSettlement;
  static String get voucherCreatedDraft => i.voucherCreatedDraft;
  static String get voucherCurrencyLabel => i.voucherCurrencyLabel;
  static String get voucherDateLabel => i.voucherDateLabel;
  static String get voucherDeleteOrWithdraw => i.voucherDeleteOrWithdraw;
  static String get voucherDescriptionLabel => i.voucherDescriptionLabel;
  static String get voucherDetailTitle => i.voucherDetailTitle;
  static String get voucherDifferentAccounts => i.voucherDifferentAccounts;
  static String get voucherEditAction => i.voucherEditAction;
  static String get voucherEditDateOrPartyWarning =>
      i.voucherEditDateOrPartyWarning;
  static String get voucherFilterAccountsSection =>
      i.voucherFilterAccountsSection;
  static String get voucherFilterApply => i.voucherFilterApply;
  static String get voucherFilterChipSearchPrefix =>
      i.voucherFilterChipSearchPrefix;
  static String get voucherFilterClearFields => i.voucherFilterClearFields;
  static String get voucherFilterDateFrom => i.voucherFilterDateFrom;
  static String get voucherFilterDateNotSet => i.voucherFilterDateNotSet;
  static String get voucherFilterDateSection => i.voucherFilterDateSection;
  static String get voucherFilterDateTo => i.voucherFilterDateTo;
  static String get voucherFilterNotSelected => i.voucherFilterNotSelected;
  static String get voucherFilterSheetTitle => i.voucherFilterSheetTitle;
  static String get voucherFilterStateAny => i.voucherFilterStateAny;
  static String get voucherFilterStateSection => i.voucherFilterStateSection;
  static String get voucherFilterTypeAny => i.voucherFilterTypeAny;
  static String get voucherFilterTypeSection => i.voucherFilterTypeSection;
  static String get voucherJumpHeader => i.voucherJumpHeader;
  static String get voucherDateInClosedPeriod => i.voucherDateInClosedPeriod;
  static String get voucherListTitle => i.voucherListTitle;
  static String get voucherMergeAction => i.voucherMergeAction;
  static String get voucherNewTitle => i.voucherNewTitle;
  static String get voucherNotesLabel => i.voucherNotesLabel;
  static String get voucherOriginDocumentButton =>
      i.voucherOriginDocumentButton;
  static String get voucherOriginLabel => i.voucherOriginLabel;
  static String get voucherPickAffectedHint => i.voucherPickAffectedHint;
  static String get voucherPickCounterpartyHint =>
      i.voucherPickCounterpartyHint;
  static String get voucherPickCounterpartyHint2 =>
      i.voucherPickCounterpartyHint2;
  static String get voucherPreviewCardTitle => i.voucherPreviewCardTitle;
  static String get voucherReceiverLabel => i.voucherReceiverLabel;
  static String get voucherReciprocalMatchBody => i.voucherReciprocalMatchBody;
  static String get voucherReciprocalMatchTitle =>
      i.voucherReciprocalMatchTitle;
  static String get voucherRedirectToOthers => i.voucherRedirectToOthers;
  static String get voucherReferenceLabel => i.voucherReferenceLabel;
  static String get voucherRejectedSuccess => i.voucherRejectedSuccess;
  static String get voucherRejectionReasonLabel =>
      i.voucherRejectionReasonLabel;
  static String get voucherReplyHeader => i.voucherReplyHeader;
  static String get voucherReversalIndicator => i.voucherReversalIndicator;
  static String get voucherSaveDraft => i.voucherSaveDraft;
  static String get voucherSearchHint => i.voucherSearchHint;
  static String get voucherSelectBothAccounts => i.voucherSelectBothAccounts;
  static String get voucherSendMessageTooltip => i.voucherSendMessageTooltip;
  static String get voucherSenderLabel => i.voucherSenderLabel;
  static String get voucherSettledAtLabel => i.voucherSettledAtLabel;
  static String get voucherSettlementIndicator => i.voucherSettlementIndicator;
  static String get voucherSignatureStatusLabel =>
      i.voucherSignatureStatusLabel;
  static String get voucherSignatureMatchesData =>
      i.voucherSignatureMatchesData;
  static String get voucherSignatureMismatchData =>
      i.voucherSignatureMismatchData;
  static String get voucherSignaturePendingCounterparty =>
      i.voucherSignaturePendingCounterparty;
  static String get voucherStateConfirmed => i.voucherStateConfirmed;
  static String get voucherStateDraft => i.voucherStateDraft;
  static String get voucherStateSent => i.voucherStateSent;
  static String get voucherStateSettled => i.voucherStateSettled;
  static String get voucherStateWithdrawn => i.voucherStateWithdrawn;
  static String get voucherTypePayment => i.voucherTypePayment;
  static String get voucherTypeReceipt => i.voucherTypeReceipt;
  static String get voucherWithdrawAction => i.voucherWithdrawAction;
  static String get voucherWithdrawConfirmBody => i.voucherWithdrawConfirmBody;
  static String get voucherWithdrawConfirmTitle =>
      i.voucherWithdrawConfirmTitle;
  static String get voucherWithdrawalSuccess => i.voucherWithdrawalSuccess;
  static String get voucherWithdrawnSuccess => i.voucherWithdrawnSuccess;
  static String get vouchersEmpty => i.vouchersEmpty;
  static String get vouchersEmptyFiltered => i.vouchersEmptyFiltered;
  static String get waiting => i.waiting;
  static String get waitingForApproval => i.waitingForApproval;
  static String get waitingForTheOther => i.waitingForTheOther;
  static String get wallisAndFutuna => i.wallisAndFutuna;
  static String get warningImportant => i.warningImportant;
  static String get watts => i.watts;
  static String get weFoundABackup => i.weFoundABackup;
  static String get weFoundALocal => i.weFoundALocal;
  static String get weekly => i.weekly;
  static String get westernSahara => i.westernSahara;
  static String get whatsapp => i.whatsapp;
  static String get whatsappAndSmsMessage => i.whatsappAndSmsMessage;
  static String get whatsappBusiness => i.whatsappBusiness;
  static String get whatsappIsNotInstalled => i.whatsappIsNotInstalled;
  static String get withdrawdelete => i.withdrawdelete;
  static String get withoutDescription => i.withoutDescription;
  static String get writeMessageDetailsHere => i.writeMessageDetailsHere;
  static String get yemen => i.yemen;
  static String get yemeni => i.yemeni;
  static String get youHaveNotAdded => i.youHaveNotAdded;
  static String get youHaveNotAdded1 => i.youHaveNotAdded1;
  static String get youMustChooseA => i.youMustChooseA;
  static String get youMustSelectThe => i.youMustSelectThe;
  static String get your => i.your;
  static String get yourBondHasBeen => i.yourBondHasBeen;
  static String get yourGoogleAccountSignin => i.yourGoogleAccountSignin;
  static String get yourLocalRecordDraft => i.yourLocalRecordDraft;
  static String get yourLoginHasBeen => i.yourLoginHasBeen;
  static String get zambia => i.zambia;
  static String get zimbabwe => i.zimbabwe;
  static String get identityQrScanHint => i.identityQrScanHint;
  static String get identityQrScanTitle => i.identityQrScanTitle;
  static String get identityQrShowSubtitle => i.identityQrShowSubtitle;
  static String get identityQrShowTitle => i.identityQrShowTitle;
  static String get permissionCameraMissingBodyQr =>
      i.permissionCameraMissingBodyQr;
  static String get permissionCameraMissingTitle =>
      i.permissionCameraMissingTitle;
  static String get qrCloseAction => i.qrCloseAction;
  static String get qrCodeDisplayTitle => i.qrCodeDisplayTitle;
  static String get qrCodeShowTooltip => i.qrCodeShowTooltip;
  static String get qrScannerHint => i.qrScannerHint;
  static String get qrScannerTitle => i.qrScannerTitle;
  static String accrualProcessConfirmBody(double amount, String currency) =>
      i.accrualProcessConfirmBody(amount, currency);
  static String costCenterDimensionsTitle(String name) =>
      i.costCenterDimensionsTitle(name);
  static String costCenterRemoveConfirmBody(String name) =>
      i.costCenterRemoveConfirmBody(name);
  static String liquidationCoverTotalDebt(String amount, String currency) =>
      i.liquidationCoverTotalDebt(amount, currency);
  static String liquidationCoverVoucherAmount(String amount, String currency) =>
      i.liquidationCoverVoucherAmount(amount, currency);
  static String liquidationEntryCash(String amount) =>
      i.liquidationEntryCash(amount);
  static String liquidationEntryCounterparty(String amount) =>
      i.liquidationEntryCounterparty(amount);
  static String liquidationEntryCredit(String amount) =>
      i.liquidationEntryCredit(amount);
  static String liquidationEntryDebit(String amount) =>
      i.liquidationEntryDebit(amount);
  static String liquidationEntrySurplus(String amount) =>
      i.liquidationEntrySurplus(amount);
  static String liquidationSaleValueLabel(String currency) =>
      i.liquidationSaleValueLabel(currency);
  static String liquidationSaleValuePrompt(String description) =>
      i.liquidationSaleValuePrompt(description);
  static String restoreAccountWarning(String accountName) =>
      i.restoreAccountWarning(accountName);
  static String settingsCsvImportConfirmBody(int count) =>
      i.settingsCsvImportConfirmBody(count);
  static String settingsCsvImportDone(int ok, int fail) =>
      i.settingsCsvImportDone(ok, fail);
  static String settingsCsvPreviewBody(int rowCount) =>
      i.settingsCsvPreviewBody(rowCount);
  static String syncAcceptanceInboxBody(String shortId) =>
      i.syncAcceptanceInboxBody(shortId);
  static String get transferFeeBoxMediatedTitle =>
      i.transferFeeBoxMediatedTitle;
  static String get transferFeeBoxMediatedSubtitle =>
      i.transferFeeBoxMediatedSubtitle;
  static String get transferFeeTripartiteTitle => i.transferFeeTripartiteTitle;
  static String get transferFeeTripartiteSubtitle =>
      i.transferFeeTripartiteSubtitle;
  static String get transferFeeValidationPositiveValue =>
      i.transferFeeValidationPositiveValue;
  static String get transferFeeSaveFailure => i.transferFeeSaveFailure;
  static String get transferFeeCalculationTypeLabel =>
      i.transferFeeCalculationTypeLabel;
  static String get transferFeeFixedOption => i.transferFeeFixedOption;
  static String get transferFeePercentageOption =>
      i.transferFeePercentageOption;
  static String get transferFeePercentageLabel => i.transferFeePercentageLabel;
  static String get transferFeeLabelWithColon => i.transferFeeLabelWithColon;
  static String get transferGroupIdLabelWithColon =>
      i.transferGroupIdLabelWithColon;
  static String get transferFeeLoading => i.transferFeeLoading;

  static String get transferFeesLabel => i.transferFeesLabel;
  static String get transferFeeNetToRecipient => i.transferFeeNetToRecipient;
  static String get transferFeeEditAmountTitle => i.transferFeeEditAmountTitle;
  static String get transferFeeEditPercentageTitle =>
      i.transferFeeEditPercentageTitle;

  static String tripartiteRequestFor(String name) =>
      i.tripartiteRequestFor(name);
  static String voucherAttachmentCountLabel(int count) =>
      i.voucherAttachmentCountLabel(count);
  static String voucherCollateralSettlementLink(int index) =>
      i.voucherCollateralSettlementLink(index);
  static String standardClassificationLabel(String kind) =>
      i.standardClassificationLabel(kind);
  static String tripartiteNoticeDesc(String sender, String receiver) =>
      i.tripartiteNoticeDesc(sender, receiver);
  static String tripartiteDoubleTransferDesc(String sender, String receiver) =>
      i.tripartiteDoubleTransferDesc(sender, receiver);
  static String tripartiteCreditDesc(String receiver, String sender) =>
      i.tripartiteCreditDesc(receiver, sender);
  static String couldNotShareReceiptAsImage(String error) =>
      i.couldNotShareReceiptAsImage(error);

  static String couldNotLoadAttachment(String error) =>
      i.couldNotLoadAttachment(error);

  static String get attachmentNotDownloadedYet => i.attachmentNotDownloadedYet;

  static String errorOpeningFile(String error) => i.errorOpeningFile(error);

  // ---------------------------------------------------------------------------
  // Audit Log — Entity Names (missing entities)
  // ---------------------------------------------------------------------------
  static String get auditEntityCurrency => i.auditEntityCurrency;
  static String get auditEntityCurrencies => i.auditEntityCurrencies;
  static String get auditEntityAccrual => i.auditEntityAccrual;
  static String get auditEntityAccruals => i.auditEntityAccruals;
  static String get auditEntityMessageTemplate => i.auditEntityMessageTemplate;
  static String get auditEntityMessageTemplates =>
      i.auditEntityMessageTemplates;
  static String get auditEntityCostCenterDimension =>
      i.auditEntityCostCenterDimension;
  static String get auditEntityCostCenterDimensions =>
      i.auditEntityCostCenterDimensions;
  static String get auditEntityTransactionFee => i.auditEntityTransactionFee;
  static String get auditEntityTransactionFees => i.auditEntityTransactionFees;
  static String get auditEntityPartyDetails => i.auditEntityPartyDetails;

  // ---------------------------------------------------------------------------
  // Audit Log — Field (Key) Translations
  // ---------------------------------------------------------------------------
  static String get auditFieldCode => i.auditFieldCode;
  static String get auditFieldSymbol => i.auditFieldSymbol;
  static String get auditFieldDecimalPlaces => i.auditFieldDecimalPlaces;
  static String get auditFieldExchangeRate => i.auditFieldExchangeRate;
  static String get auditFieldIsBase => i.auditFieldIsBase;
  static String get auditFieldIsActive => i.auditFieldIsActive;
  static String get auditFieldTotalAmountMinor => i.auditFieldTotalAmountMinor;
  static String get auditFieldFrequency => i.auditFieldFrequency;
  static String get auditFieldStartDate => i.auditFieldStartDate;
  static String get auditFieldNextDueDate => i.auditFieldNextDueDate;
  static String get auditFieldSourceAccountId => i.auditFieldSourceAccountId;
  static String get auditFieldDestinationAccountId =>
      i.auditFieldDestinationAccountId;
  static String get auditFieldCategoryId => i.auditFieldCategoryId;
  static String get auditFieldCostCenterId => i.auditFieldCostCenterId;
  static String get auditFieldKind => i.auditFieldKind;
  static String get auditFieldBody => i.auditFieldBody;
  static String get auditFieldIsSystem => i.auditFieldIsSystem;
  static String get auditFieldSortOrder => i.auditFieldSortOrder;
  static String get auditFieldCollateralValueMinor =>
      i.auditFieldCollateralValueMinor;
  static String get auditFieldRevaluationDate => i.auditFieldRevaluationDate;
  static String get auditFieldVoucherId => i.auditFieldVoucherId;
  static String get auditFieldSettledAt => i.auditFieldSettledAt;
  static String get auditFieldDueDate => i.auditFieldDueDate;
  static String get auditFieldCollateralType => i.auditFieldCollateralType;
  static String get auditFieldBudgetMinorUnits => i.auditFieldBudgetMinorUnits;
  static String get auditFieldCenterType => i.auditFieldCenterType;
  static String get auditFieldDebitMinor => i.auditFieldDebitMinor;
  static String get auditFieldCreditMinor => i.auditFieldCreditMinor;
  static String get auditFieldLedgerId => i.auditFieldLedgerId;
  static String get auditFieldEntryDate => i.auditFieldEntryDate;
  static String get auditFieldVoucherEntryId => i.auditFieldVoucherEntryId;
  static String get auditFieldValue => i.auditFieldValue;
  static String get auditFieldCalculationType => i.auditFieldCalculationType;
  static String get auditFrequencyDaily => i.auditFrequencyDaily;
  static String get auditFrequencyWeekly => i.auditFrequencyWeekly;
  static String get auditFrequencyMonthly => i.auditFrequencyMonthly;
  static String get auditFrequencyQuarterly => i.auditFrequencyQuarterly;
  static String get auditFrequencySemiAnnually => i.auditFrequencySemiAnnually;
  static String get auditFrequencyYearly => i.auditFrequencyYearly;
  static String get auditFrequencyOnce => i.auditFrequencyOnce;
  static String get auditCalcTypeFixed => i.auditCalcTypeFixed;
  static String get auditCalcTypePercentage => i.auditCalcTypePercentage;

  // Revert single
  static String get auditRevertSingle => i.auditRevertSingle;
  static String get auditRevertSingleTitle => i.auditRevertSingleTitle;
  static String get auditRevertSingleBody => i.auditRevertSingleBody;
  static String get auditRevertSingleConfirm => i.auditRevertSingleConfirm;

  // Impact warning
  static String get auditImpactWarningTitle => i.auditImpactWarningTitle;
  static String get auditImpactWarningBody => i.auditImpactWarningBody;
  static String get auditImpactWarningProceed => i.auditImpactWarningProceed;
  static String get auditImpactAffectedCount => i.auditImpactAffectedCount;

  // Severity
  static String get auditSeverityInfo => i.auditSeverityInfo;
  static String get auditSeverityWarning => i.auditSeverityWarning;
  static String get auditSeverityCritical => i.auditSeverityCritical;

  // Search & filter
  static String get auditSearchHint => i.auditSearchHint;
  static String get auditFilterSeverity => i.auditFilterSeverity;
  static String get auditNoMatchesForFilter => i.auditNoMatchesForFilter;

  static String get vaultBannedTitle => i.vaultBannedTitle;
  static String get vaultBannedBody => i.vaultBannedBody;
  static String get vaultUpdateRequiredTitle => i.vaultUpdateRequiredTitle;
  static String get vaultUpdateRequiredBody => i.vaultUpdateRequiredBody;
  static String get vaultUpdateAction => i.vaultUpdateAction;
  static String get pleaseWaitAFewMinutes => i.pleaseWaitAFewMinutes;
  static String get deviceManagement => i.deviceManagement;
  static String get pairedDevices => i.pairedDevices;
  static String get lastSyncSeq => i.lastSyncSeq;
  static String get revoke => i.revoke;
  static String get revoked => i.revoked;

  static String get devicePairingQrOnlyTitle => i.devicePairingQrOnlyTitle;
  static String get devicePairingQrOnlyDesc => i.devicePairingQrOnlyDesc;
  static String get devicePairingShowMyQr => i.devicePairingShowMyQr;
  static String get devicePairingScanQr => i.devicePairingScanQr;
  static String get devicePairingRefresh => i.devicePairingRefresh;
  static String get devicePairingPublicKeysAuto =>
      i.devicePairingPublicKeysAuto;
  static String get devicePairingNoDevicesYet => i.devicePairingNoDevicesYet;
  static String get devicePairingThisDeviceSuffix =>
      i.devicePairingThisDeviceSuffix;
  static String get devicePairingDialogTitle => i.devicePairingDialogTitle;
  static String get deviceDefaultName => i.deviceDefaultName;
  static String get deviceManagementSubtitle => i.deviceManagementSubtitle;
  static String get deviceLoadError => i.deviceLoadError;
  static String get devicePairedSuccess => i.devicePairedSuccess;
  static String get devicePairError => i.devicePairError;
  static String get deviceRevokedSuccess => i.deviceRevokedSuccess;
  static String get deviceRevokeError => i.deviceRevokeError;

  static String get companionBootstrapSentSuccess =>
      i.companionBootstrapSentSuccess;
  static String get companionBootstrapSentSuccessDesc =>
      i.companionBootstrapSentSuccessDesc;
  static String get companionBootstrapSentError =>
      i.companionBootstrapSentError;
  static String get companionCredentialsFailed => i.companionCredentialsFailed;
  static String get linkAsCompanionDevice => i.linkAsCompanionDevice;
  static String get scanCompanionQrInstruction => i.scanCompanionQrInstruction;
  static String get linkNewCompanionDevicePrompt =>
      i.linkNewCompanionDevicePrompt;
  static String get linkNewCompanionDeviceDesc => i.linkNewCompanionDeviceDesc;
  static String get scanCompanionQr => i.scanCompanionQr;
  static String get companionDeviceRestriction => i.companionDeviceRestriction;
  static String get deviceAuthorizationRevoked => i.deviceAuthorizationRevoked;
  static String get logoutPrimaryHandoverTitle => i.logoutPrimaryHandoverTitle;
  static String logoutPrimaryHandoverTemplate(String deviceName) =>
      i.logoutPrimaryHandoverTemplate(deviceName);
  static String get deviceRolePrimaryLabel => i.deviceRolePrimaryLabel;
  static String get actionApprove => i.actionApprove;
  static String get migratingData => i.migratingData;
  static String get migratingDataSubtitle => i.migratingDataSubtitle;
  static String get regenerateQrCode => i.regenerateQrCode;
  static String migratingFinancialLedger(String progress) =>
      i.migratingFinancialLedger(progress);
  static String newVoucherClaim(String amount, String currency) =>
      i.newVoucherClaim(amount, currency);
  static String voucherRejectedWithReason(String reason) =>
      i.voucherRejectedWithReason(reason);
  static String newTripartiteRequestFrom(String name) =>
      i.newTripartiteRequestFrom(name);

  static String estimatedValueWithCurrency(String currency) =>
      i.estimatedValueWithCurrency(currency);
  static String permissionDeniedMessage(String service) =>
      i.permissionDeniedMessage(service);
  static String voucherNotice(String type) => i.voucherNotice(type);
  static String bondConflictsFound(int count) => i.bondConflictsFound(count);
  static String errorExportingPdf(String reportName, String error) =>
      i.errorExportingPdf(reportName, error);
  static String errorExportingExcel(String reportName, String error) =>
      i.errorExportingExcel(reportName, error);

  static String accountNotFoundPrompt(String name) =>
      i.accountNotFoundPrompt(name);
  static String dualTransferNoticeRecipient(String name) =>
      i.dualTransferNoticeRecipient(name);
  static String dualTransferNoticeSender(String name) =>
      i.dualTransferNoticeSender(name);

  static String get currentStatus => i.currentStatus;
  static String get restoreOnlyThis => i.restoreOnlyThis;
  static String get restoreAll => i.restoreAll;
  static String redoImpactWarning(String items) => i.redoImpactWarning(items);
  static String versionWithNumber(String number) => i.versionWithNumber(number);
  static String waitSecondsBeforeRetry(int seconds) =>
      i.waitSecondsBeforeRetry(seconds);

  static String appInvitationMessage(String name) =>
      i.appInvitationMessage(name);
  static String skippedAccountsNoPhone(int count) =>
      i.skippedAccountsNoPhone(count);
  static String currencySymbolExample(String symbol) =>
      i.currencySymbolExample(symbol);
  static String get pdfShowHideBalance => i.pdfShowHideBalance;
  static String accountBalanceGreeting(String name) =>
      i.accountBalanceGreeting(name);
  static String matchedInQayd(String target) => i.matchedInQayd(target);
  static String get millionSuffix => i.millionSuffix;
  static String get thousandSuffix => i.thousandSuffix;
  static String onDate(String date) => i.onDate(date);
  static String editingWithLabel(String label) => i.editingWithLabel(label);
  static String showLabelInBonds(String label) => i.showLabelInBonds(label);
  static String searchBondsForStatus(String status) =>
      i.searchBondsForStatus(status);
  static String settledWithSurplus(String amount, String currency) =>
      i.settledWithSurplus(amount, currency);

  // ── Manual Device Linking (WhatsApp-style) ─────────────────────────────────
  static String get manualCodeLinkButton => i.manualCodeLinkButton;
  static String get manualCodeDisplayTitle => i.manualCodeDisplayTitle;
  static String get manualCodeDisplayInstruction =>
      i.manualCodeDisplayInstruction;
  static String get manualCodeCopied => i.manualCodeCopied;
  static String get manualCodeWaitingForCompanion =>
      i.manualCodeWaitingForCompanion;
  static String get manualCodeExpired => i.manualCodeExpired;
  static String get manualCodeDividerLabel => i.manualCodeDividerLabel;
  static String get manualCodeInputButton => i.manualCodeInputButton;
  static String get manualCodeInputTitle => i.manualCodeInputTitle;
  static String get manualCodeInputInstruction => i.manualCodeInputInstruction;
  static String get manualCodeInputHint => i.manualCodeInputHint;
  static String get manualCodeSubmit => i.manualCodeSubmit;
  static String get manualCodeSubmitting => i.manualCodeSubmitting;
  static String get manualCodeInvalidOrExpired => i.manualCodeInvalidOrExpired;
  static String get manualCodeTooManyAttempts => i.manualCodeTooManyAttempts;
  static String get manualCodeExpiredDesc => i.manualCodeExpiredDesc;

  static String get counterpartyOnboardingRequestTitle =>
      i.counterpartyOnboardingRequestTitle;
  static String counterpartyOnboardingRequestFrom(String identifier) =>
      i.counterpartyOnboardingRequestFrom(identifier);
  static String get counterpartyOnboardingAcceptButton =>
      i.counterpartyOnboardingAcceptButton;

  static String get posQuantityCannotBeNegative =>
      i.posQuantityCannotBeNegative;
  static String get posQuantityMustBePositive => i.posQuantityMustBePositive;
  static String get posQuantityScaleInvalid => i.posQuantityScaleInvalid;
  static String get posQuantityScaleMismatch => i.posQuantityScaleMismatch;
  static String get posQuantityWouldBeNegative => i.posQuantityWouldBeNegative;
  static String get posDocumentTransitionInvalid =>
      i.posDocumentTransitionInvalid;
  static String get posActivationFailed => i.posActivationFailed;
  static String get posFeatureStateReadFailed => i.posFeatureStateReadFailed;
  static String get posFeatureDisableFailed => i.posFeatureDisableFailed;
  static String get posTemplateConflict => i.posTemplateConflict;
  static String get posFeatureTitle => i.posFeatureTitle;
  static String get posFeatureSubtitle => i.posFeatureSubtitle;
  static String get posFeaturePageTitle => i.posFeaturePageTitle;
  static String get posFeaturePageDescription => i.posFeaturePageDescription;
  static String get posFeatureEnabled => i.posFeatureEnabled;
  static String get posFeatureDisabled => i.posFeatureDisabled;
  static String get posFeatureActivate => i.posFeatureActivate;
  static String get posFeatureDisable => i.posFeatureDisable;
  static String get posFeatureActivationWarning =>
      i.posFeatureActivationWarning;
  static String get posFeatureActivationSuccess =>
      i.posFeatureActivationSuccess;
  static String get posFeatureDisableSuccess => i.posFeatureDisableSuccess;
  static String get posFeatureCancel => i.posFeatureCancel;
  static String get posFeatureConfirm => i.posFeatureConfirm;
  static String get posBarcodeInvalid => i.posBarcodeInvalid;
  static String get posProductIdRequired => i.posProductIdRequired;
  static String get posProductNameRequired => i.posProductNameRequired;
  static String get posProductSkuRequired => i.posProductSkuRequired;
  static String get posProductUnitRequired => i.posProductUnitRequired;
  static String get posProductPriceInvalid => i.posProductPriceInvalid;
  static String get posProductCurrencyMismatch => i.posProductCurrencyMismatch;
  static String get posProductCurrencyNotFound => i.posProductCurrencyNotFound;
  static String get posProductScaleInvalid => i.posProductScaleInvalid;
  static String get posProductThresholdInvalid => i.posProductThresholdInvalid;
  static String get posProductNotFound => i.posProductNotFound;
  static String get posProductReadFailed => i.posProductReadFailed;
  static String get posProductSaveFailed => i.posProductSaveFailed;
  static String get posProductBarcodeExists => i.posProductBarcodeExists;
  static String get posWorkspaceTitle => i.posWorkspaceTitle;
  static String get posWorkspaceWelcome => i.posWorkspaceWelcome;
  static String get posWorkspaceDescription => i.posWorkspaceDescription;
  static String get posWorkspaceDisabled => i.posWorkspaceDisabled;
  static String get posWorkspaceEnableFromSettings =>
      i.posWorkspaceEnableFromSettings;
  static String get posWorkspaceCatalogSubtitle =>
      i.posWorkspaceCatalogSubtitle;
  static String get posWorkspacePurchaseSubtitle =>
      i.posWorkspacePurchaseSubtitle;
  static String get posWorkspaceSalesTitle => i.posWorkspaceSalesTitle;
  static String get posWorkspaceComingSoon => i.posWorkspaceComingSoon;
  static String get posPurchaseTitle => i.posPurchaseTitle;
  static String get posPurchaseDescription => i.posPurchaseDescription;
  static String get posPurchaseSupplier => i.posPurchaseSupplier;
  static String get posPurchaseSelectSupplier => i.posPurchaseSelectSupplier;
  static String get posPurchaseProducts => i.posPurchaseProducts;
  static String get posPurchaseNoProducts => i.posPurchaseNoProducts;
  static String get posPurchaseAddProduct => i.posPurchaseAddProduct;
  static String get posPurchaseAlreadyAdded => i.posPurchaseAlreadyAdded;
  static String get posPurchaseQuantity => i.posPurchaseQuantity;
  static String get posPurchaseUnitCost => i.posPurchaseUnitCost;
  static String get posPurchaseSourceUnitPrice => i.posPurchaseSourceUnitPrice;
  static String get posPurchaseCurrencyLocked => i.posPurchaseCurrencyLocked;
  static String get posPurchaseInventoryCost => i.posPurchaseInventoryCost;
  static String get posPurchaseProposedSalePrice =>
      i.posPurchaseProposedSalePrice;
  static String get posPurchaseCurrentCatalogSalePrice =>
      i.posPurchaseCurrentCatalogSalePrice;
  static String get posPurchaseApplyProposedSalePrice =>
      i.posPurchaseApplyProposedSalePrice;
  static String get posPurchaseEnterCostForCurrency =>
      i.posPurchaseEnterCostForCurrency;
  static String get posProfitMarginTitle => i.posProfitMarginTitle;
  static String get posProfitMarginPercentage => i.posProfitMarginPercentage;
  static String get posProfitMarginFixedAmount => i.posProfitMarginFixedAmount;
  static String get posProfitMarginAmount => i.posProfitMarginAmount;
  static String get posProfitMarginHint => i.posProfitMarginHint;
  static String get posCurrencyRatesTitle => i.posCurrencyRatesTitle;
  static String get posCurrencyRatesDescription =>
      i.posCurrencyRatesDescription;
  static String get posCurrencyRateFrom => i.posCurrencyRateFrom;
  static String get posCurrencyRateTo => i.posCurrencyRateTo;
  static String get posCurrencyRateValue => i.posCurrencyRateValue;
  static String get posCurrencyRateNote => i.posCurrencyRateNote;
  static String get posCurrencyRateSave => i.posCurrencyRateSave;
  static String get posCurrencyRateSaved => i.posCurrencyRateSaved;
  static String get posCurrencyRateHistory => i.posCurrencyRateHistory;
  static String get posCurrencyRateNoHistory => i.posCurrencyRateNoHistory;
  static String get posCurrencyRateInvalid => i.posCurrencyRateInvalid;
  static String get posCurrencyRateHistoryLoadFailed =>
      i.posCurrencyRateHistoryLoadFailed;
  static String get posCheckoutRateSnapshotLabel =>
      i.posCheckoutRateSnapshotLabel;
  static String get posCheckoutRateReverseApplied =>
      i.posCheckoutRateReverseApplied;
  static String get posPurchasePaymentMethod => i.posPurchasePaymentMethod;
  static String get posPurchaseCredit => i.posPurchaseCredit;
  static String get posPurchaseCash => i.posPurchaseCash;
  static String get posPurchaseTotal => i.posPurchaseTotal;
  static String get posPurchaseSubmit => i.posPurchaseSubmit;
  static String get posPurchaseSaved => i.posPurchaseSaved;
  static String get posPurchaseAcknowledgeFailed =>
      i.posPurchaseAcknowledgeFailed;
  static String get posPurchaseSnapshotRestored =>
      i.posPurchaseSnapshotRestored;
  static String get posPurchaseSnapshotRestoreFailed =>
      i.posPurchaseSnapshotRestoreFailed;
  static String get posPurchaseCartEmpty => i.posPurchaseCartEmpty;
  static String get posPurchaseExpiryNotice => i.posPurchaseExpiryNotice;
  static String get posPurchaseLoadFailed => i.posPurchaseLoadFailed;
  static String get posPurchaseSubmitFailed => i.posPurchaseSubmitFailed;
  static String get posCheckoutTitle => i.posCheckoutTitle;
  static String get posCheckoutInputHint => i.posCheckoutInputHint;
  static String get posCheckoutSearchResults => i.posCheckoutSearchResults;
  static String get posCheckoutCartEmpty => i.posCheckoutCartEmpty;
  static String get posCheckoutCurrencyLabel => i.posCheckoutCurrencyLabel;
  static String get posCheckoutPricePerUnit => i.posCheckoutPricePerUnit;
  static String get posCheckoutCatalogReference =>
      i.posCheckoutCatalogReference;
  static String get posCheckoutPriceRequired => i.posCheckoutPriceRequired;
  static String get posCheckoutSubtotal => i.posCheckoutSubtotal;
  static String get posCheckoutClearCart => i.posCheckoutClearCart;
  static String get posCheckoutCameraActive => i.posCheckoutCameraActive;
  static String get posCheckoutPostingPending => i.posCheckoutPostingPending;
  static String get posCheckoutAdvance => i.posCheckoutAdvance;
  static String get posCheckoutCustomerAccount => i.posCheckoutCustomerAccount;
  static String get posCheckoutPaymentAccount => i.posCheckoutPaymentAccount;
  static String get posCheckoutPaymentMethod => i.posCheckoutPaymentMethod;
  static String get posCheckoutCash => i.posCheckoutCash;
  static String get posCheckoutBank => i.posCheckoutBank;
  static String get posCheckoutCredit => i.posCheckoutCredit;
  static String get posCheckoutOther => i.posCheckoutOther;
  static String get posCheckoutComplete => i.posCheckoutComplete;
  static String get posCheckoutCompleted => i.posCheckoutCompleted;
  static String get posInvoiceHistoryTitle => i.posInvoiceHistoryTitle;
  static String get posInvoiceHistoryEmpty => i.posInvoiceHistoryEmpty;
  static String get posInvoiceDetailTitle => i.posInvoiceDetailTitle;
  static String get posInvoiceNotFound => i.posInvoiceNotFound;
  static String get posInvoiceDueLabel => i.posInvoiceDueLabel;
  static String get posInvoiceExportPdf => i.posInvoiceExportPdf;
  static String get posInvoicePdfFailed => i.posInvoicePdfFailed;
  static String get posSalesReturnAction => i.posSalesReturnAction;
  static String get posSalesReturnTitle => i.posSalesReturnTitle;
  static String get posSalesReturnDescription => i.posSalesReturnDescription;
  static String get posSalesReturnQuantity => i.posSalesReturnQuantity;
  static String get posSalesReturnMaximum => i.posSalesReturnMaximum;
  static String get posSalesReturnReason => i.posSalesReturnReason;
  static String get posSalesReturnSubmit => i.posSalesReturnSubmit;
  static String get posSalesReturnSucceeded => i.posSalesReturnSucceeded;
  static String get posSalesReturnFailed => i.posSalesReturnFailed;
  static String get posSalesReturnQuantityInvalid =>
      i.posSalesReturnQuantityInvalid;
  static String get posSalesReturnNothingSelected =>
      i.posSalesReturnNothingSelected;
  static String get posSalesReturnUnavailable => i.posSalesReturnUnavailable;
  static String get posSalesVoidAction => i.posSalesVoidAction;
  static String get posSalesVoidConfirm => i.posSalesVoidConfirm;
  static String get posSalesVoidSucceeded => i.posSalesVoidSucceeded;
  static String get posSalesVoidFailed => i.posSalesVoidFailed;
  static String get posDailySalesReportTitle => i.posDailySalesReportTitle;
  static String get posDailySalesReportFailed => i.posDailySalesReportFailed;
  static String get posDailySalesInvoiceCount => i.posDailySalesInvoiceCount;
  static String get posDailySalesOtherCurrenciesExcluded =>
      i.posDailySalesOtherCurrenciesExcluded;
  static String get posDailySalesGross => i.posDailySalesGross;
  static String get posDailySalesPaid => i.posDailySalesPaid;
  static String get posDailySalesDue => i.posDailySalesDue;
  static String get posWorkspaceLoadFailed => i.posWorkspaceLoadFailed;
  static String get posWorkspaceCurrencyUnavailable =>
      i.posWorkspaceCurrencyUnavailable;
  static String get posStockIdRequired => i.posStockIdRequired;
  static String get posStockProductIdRequired => i.posStockProductIdRequired;
  static String get posStockWarehouseIdRequired =>
      i.posStockWarehouseIdRequired;
  static String get posStockIdempotencyRequired =>
      i.posStockIdempotencyRequired;
  static String get posStockDirectionRequired => i.posStockDirectionRequired;
  static String get posStockScaleMismatch => i.posStockScaleMismatch;
  static String get posStockCurrencyMismatch => i.posStockCurrencyMismatch;
  static String get posStockInsufficient => i.posStockInsufficient;
  static String get posStockNegativeResult => i.posStockNegativeResult;
  static String get posStockIdempotencyExists => i.posStockIdempotencyExists;
  static String get posStockInvalidMovement => i.posStockInvalidMovement;
  static String get posStockReadFailed => i.posStockReadFailed;
  static String get posStockAppendFailed => i.posStockAppendFailed;
  static String get posStockProductInactive => i.posStockProductInactive;
  static String get posStockMovementsTitle => i.posStockMovementsTitle;
  static String get posStockMovementsDescription =>
      i.posStockMovementsDescription;
  static String get posStockMovementsEmpty => i.posStockMovementsEmpty;
  static String get posStockMovementsLoadMore => i.posStockMovementsLoadMore;
  static String get posStockMovementAllProducts =>
      i.posStockMovementAllProducts;
  static String get posStockMovementAllTypes => i.posStockMovementAllTypes;
  static String posStockMovementTypeLabel(String type) =>
      i.posStockMovementTypeLabel(type);
  static String get posStockMovementInbound => i.posStockMovementInbound;
  static String get posStockMovementOutbound => i.posStockMovementOutbound;
  static String get posStockAdjustmentTitle => i.posStockAdjustmentTitle;
  static String get posStockAdjustmentDescription =>
      i.posStockAdjustmentDescription;
  static String get posStockAdjustmentDirection =>
      i.posStockAdjustmentDirection;
  static String get posStockAdjustmentIncrease => i.posStockAdjustmentIncrease;
  static String get posStockAdjustmentDecrease => i.posStockAdjustmentDecrease;
  static String get posStockAdjustmentQuantity => i.posStockAdjustmentQuantity;
  static String get posStockAdjustmentUnitCost => i.posStockAdjustmentUnitCost;
  static String get posStockAdjustmentCounterAccount =>
      i.posStockAdjustmentCounterAccount;
  static String get posStockAdjustmentSelectAccount =>
      i.posStockAdjustmentSelectAccount;
  static String get posStockAdjustmentReason => i.posStockAdjustmentReason;
  static String get posStockAdjustmentReasonRequired =>
      i.posStockAdjustmentReasonRequired;
  static String get posStockAdjustmentValueRequired =>
      i.posStockAdjustmentValueRequired;
  static String get posStockAdjustmentSave => i.posStockAdjustmentSave;
  static String get posStockAdjustmentSaved => i.posStockAdjustmentSaved;
  static String posStockAdjustmentVoucherDescription(String reason) =>
      i.posStockAdjustmentVoucherDescription(reason);
  static String get posWorkspaceInventorySection =>
      i.posWorkspaceInventorySection;
  static String get posWorkspaceSalesSection => i.posWorkspaceSalesSection;
  static String get posWorkspaceOpenSettings => i.posWorkspaceOpenSettings;
  static String get posCatalogManageCategories => i.posCatalogManageCategories;
  static String get posOpeningBalanceTitle => i.posOpeningBalanceTitle;
  static String get posOpeningBalanceDescription =>
      i.posOpeningBalanceDescription;
  static String get posOpeningBalanceProduct => i.posOpeningBalanceProduct;
  static String get posOpeningBalanceSelectProduct =>
      i.posOpeningBalanceSelectProduct;
  static String get posOpeningBalanceNoProducts =>
      i.posOpeningBalanceNoProducts;
  static String get posOpeningBalanceQuantity => i.posOpeningBalanceQuantity;
  static String posOpeningBalanceQuantityHint(int scale) =>
      i.posOpeningBalanceQuantityHint(scale);
  static String get posOpeningBalanceUnitCost => i.posOpeningBalanceUnitCost;
  static String posOpeningBalanceCostHint(String currency) =>
      i.posOpeningBalanceCostHint(currency);
  static String get posOpeningBalancePositiveInteger =>
      i.posOpeningBalancePositiveInteger;
  static String get posOpeningBalanceNonNegativeInteger =>
      i.posOpeningBalanceNonNegativeInteger;
  static String get posOpeningBalanceSave => i.posOpeningBalanceSave;
  static String get posOpeningBalanceSaved => i.posOpeningBalanceSaved;
  static String get posOpeningBalanceCurrent => i.posOpeningBalanceCurrent;
  static String get posWarehouseUnavailable => i.posWarehouseUnavailable;
  static String get posAccountingSourceRequired =>
      i.posAccountingSourceRequired;
  static String get posAccountingAccountsRequired =>
      i.posAccountingAccountsRequired;
  static String get posAccountingAccountsDistinct =>
      i.posAccountingAccountsDistinct;
  static String get posOpeningBalanceAccountingDescription =>
      i.posOpeningBalanceAccountingDescription;
  static String get posAccountingEntriesRequired =>
      i.posAccountingEntriesRequired;
  static String get posAccountingDateMismatch => i.posAccountingDateMismatch;
  static String get posAccountingSourceMismatch =>
      i.posAccountingSourceMismatch;
  static String get posAccountingDuplicateSource =>
      i.posAccountingDuplicateSource;
  static String get posAccountingTransactionFailed =>
      i.posAccountingTransactionFailed;
  static String get posAccountingPartialState => i.posAccountingPartialState;
  static String get posInvoiceInvalid => i.posInvoiceInvalid;
  static String get posInvoiceLinesRequired => i.posInvoiceLinesRequired;
  static String get posInvoiceLineInvalid => i.posInvoiceLineInvalid;
  static String get posInvoiceTotalsInvalid => i.posInvoiceTotalsInvalid;
  static String get posInvoicePaymentInvalid => i.posInvoicePaymentInvalid;
  static String get posInvoiceTransitionInvalid =>
      i.posInvoiceTransitionInvalid;
  static String get posInvoiceSignatureInvalid => i.posInvoiceSignatureInvalid;
  static String get posInvoiceNotPosted => i.posInvoiceNotPosted;
  static String get posInvoiceFiscalPeriodClosed =>
      i.posInvoiceFiscalPeriodClosed;
  static String get posCatalogTitle => i.posCatalogTitle;
  static String get posCatalogSearchHint => i.posCatalogSearchHint;
  static String get posCatalogAddProduct => i.posCatalogAddProduct;
  static String get posCatalogCreateTitle => i.posCatalogCreateTitle;
  static String get posCatalogEmpty => i.posCatalogEmpty;
  static String get posCatalogNoResults => i.posCatalogNoResults;
  static String get posCatalogName => i.posCatalogName;
  static String get posCatalogSku => i.posCatalogSku;
  static String get posCatalogSalePrice => i.posCatalogSalePrice;
  static String get posCatalogSalePriceMinor => i.posCatalogSalePriceMinor;
  static String get posCatalogPurchasePrice => i.posCatalogPurchasePrice;
  static String get posCatalogPurchasePriceMinor =>
      i.posCatalogPurchasePriceMinor;
  static String get posCatalogUnit => i.posCatalogUnit;
  static String get posCatalogCategory => i.posCatalogCategory;
  static String get posCatalogNoCategory => i.posCatalogNoCategory;
  static String get posCatalogAddCategory => i.posCatalogAddCategory;
  static String get posCatalogCreateCategory => i.posCatalogCreateCategory;
  static String get posCatalogEditCategory => i.posCatalogEditCategory;
  static String get posCatalogCategoryName => i.posCatalogCategoryName;
  static String get posCatalogCategoryCode => i.posCatalogCategoryCode;
  static String get posCatalogCategoryNameRequired =>
      i.posCatalogCategoryNameRequired;
  static String get posCatalogCategoryCodeRequired =>
      i.posCatalogCategoryCodeRequired;
  static String get posProductCategoryInUse => i.posProductCategoryInUse;
  static String get posCatalogQuantityScale => i.posCatalogQuantityScale;
  static String get posCatalogReorderLevel => i.posCatalogReorderLevel;
  static String get posCatalogBarcode => i.posCatalogBarcode;
  static String get posCatalogDescription => i.posCatalogDescription;
  static String get posCatalogExpiryTracking => i.posCatalogExpiryTracking;
  static String get posCatalogDeactivateTitle => i.posCatalogDeactivateTitle;
  static String get posCatalogDeactivateMessage =>
      i.posCatalogDeactivateMessage;
  static String get posCatalogDeactivate => i.posCatalogDeactivate;
  static String get posCatalogReactivate => i.posCatalogReactivate;
  static String get posCatalogBarcodesHint => i.posCatalogBarcodesHint;
  static String get posProductScaleImmutable => i.posProductScaleImmutable;
  static String get posCatalogShowInactive => i.posCatalogShowInactive;
  static String get posCatalogNoCategories => i.posCatalogNoCategories;
  static String get posCatalogEditTitle => i.posCatalogEditTitle;
  static String get posCatalogEditCategoryTitle =>
      i.posCatalogEditCategoryTitle;
  static String get posCatalogDeactivateCategoryMessage =>
      i.posCatalogDeactivateCategoryMessage;
  static String get posCatalogCategoryDeactivateTitle =>
      i.posCatalogCategoryDeactivateTitle;
  static String get posCatalogCategoryDeactivate =>
      i.posCatalogCategoryDeactivate;
  static String get posCatalogCategoryReactivate =>
      i.posCatalogCategoryReactivate;
  static String get posCatalogQuantityScaleReadOnly =>
      i.posCatalogQuantityScaleReadOnly;
  static String get posCatalogEditValidationFailed =>
      i.posCatalogEditValidationFailed;
}
