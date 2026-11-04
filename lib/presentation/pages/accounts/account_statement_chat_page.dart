import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qayd/core/result/result.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:qayd/application/pos/pos_credit_invoice_chat_protocol.dart';
import 'package:qayd/application/accounts/dtos/account_statement_chat_message_dto.dart';
import 'package:qayd/application/vouchers/dtos/confirm_voucher_input.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/domain/value_objects/voucher_state.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/domain/entities/pos_credit_invoice_chat_snapshot.dart';
import 'package:qayd/di/injection_container.dart';
import 'package:qayd/presentation/components/atomic/qayd_badge.dart';
import 'package:qayd/presentation/components/atomic/qayd_dialog.dart';
import 'package:qayd/presentation/components/atomic/qayd_money_display.dart';
import 'package:qayd/presentation/components/atomic/qayd_text.dart';
import 'package:qayd/presentation/components/atomic/qayd_snackbar.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';
import 'package:qayd/presentation/navigation/qayd_page_route.dart';
import 'package:qayd/presentation/pages/accounts/account_detail_cubit.dart';
import 'package:qayd/presentation/pages/accounts/account_detail_page.dart';
import 'package:qayd/presentation/pages/accounts/statement_chat_cubit.dart';
import 'package:qayd/presentation/pages/accounts/statement_chat_filter_sheet.dart';
import 'package:qayd/presentation/pages/accounts/statement_chat_state.dart';
import 'package:qayd/presentation/pages/vouchers/tripartite_create_page.dart';
import 'package:qayd/presentation/pages/vouchers/voucher_create_page.dart';
import 'package:qayd/presentation/pages/vouchers/voucher_create_cubit.dart';
import 'package:qayd/presentation/pages/vouchers/voucher_suggestions_cubit.dart';
import 'package:qayd/presentation/widgets/request_tripartite_sheet.dart';
import 'package:qayd/presentation/pages/vouchers/voucher_detail_page.dart';
import 'package:qayd/presentation/theme/color_tokens.dart';
import 'package:qayd/presentation/theme/qayd_theme_extensions.dart';
import 'package:qayd/presentation/theme/radius_tokens.dart';
import 'package:qayd/presentation/theme/spacing_tokens.dart';
import 'package:qayd/presentation/utils/numerical_styling.dart';
import 'package:qayd/presentation/utils/statement_chat_export.dart';
import 'package:qayd/application/accounts/dtos/statement_chat_filter_input.dart';
import 'package:qayd/presentation/utils/whatsapp_flavor_picker.dart';
import 'package:qayd/core/utils/currency_util.dart';
import 'package:qayd/presentation/utils/share_pdf_bytes.dart';

/// Chat-style "Statement of Account" between two parties (accounts).
///
/// Full implementation with:
/// - BLoC-powered state management
/// - Search bar with debounce
/// - Advanced filtering (agreement status, type, date range, brought-forward)
/// - Color-coded bubbles (Green/Blue/Orange/Red)
/// - Running balance on each bubble
/// - Summary footer with net balance
/// - Accept / Reject / Resubmit interactive actions
final class AccountStatementChatPage extends StatefulWidget {
  const AccountStatementChatPage({
    super.key,
    required this.counterpartyAccountId,
    this.myAccountId,
    this.isEmbedded = false,
  });

  final String counterpartyAccountId;
  final String? myAccountId;
  final bool isEmbedded;

  @override
  State<AccountStatementChatPage> createState() =>
      _AccountStatementChatPageState();
}

class _AccountStatementChatPageState extends State<AccountStatementChatPage> {
  bool _mutating = false;
  bool _showSearch = false;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Actions ──

  Future<void> _acceptVoucher(BuildContext context, String voucherId) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      final r = await InjectionContainer.confirmVoucherUseCase.call(
        ConfirmVoucherInput(voucherId: voucherId),
      );
      if (r.isFailure && mounted) {
        QaydSnackBar.show(
          context,
          r.failureOrNull!.messageAr,
          type: QaydSnackBarType.error,
        );
        return;
      }
      if (mounted) {
        QaydSnackBar.show(
          context,
          AppStrings.voucherAcceptedSuccess,
          type: QaydSnackBarType.success,
        );
        context.read<StatementChatCubit>().reload();
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _rejectVoucher(BuildContext context, String voucherId) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      final r = await InjectionContainer.rejectVoucherUseCase.call(
        voucherId: voucherId,
      );
      if (r.isFailure && mounted) {
        QaydSnackBar.show(
          context,
          r.failureOrNull!.messageAr,
          type: QaydSnackBarType.error,
        );
        return;
      }
      if (mounted) {
        QaydSnackBar.show(
          context,
          AppStrings.voucherRejectedSuccess,
          type: QaydSnackBarType.success,
        );
        context.read<StatementChatCubit>().reload();
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _resubmitVoucher(BuildContext context, String voucherId) async {
    // Instead of resubmit usecase, we now navigate to create page to allow edits
    // as per Protocol v1.4 (Corrective Resubmission).
    final cubit = context.read<StatementChatCubit>();
    final state = cubit.state;
    if (state is! StatementChatReady) return;

    final msg = state.messages.firstWhere((m) => m.voucherId == voucherId);

    Navigator.of(context)
        .push(
          QaydPageRoute.slideFromStart(
            builder: (ctx) => MultiBlocProvider(
              providers: [
                BlocProvider<VoucherCreateCubit>(
                  create: (_) => VoucherCreateCubit(
                    InjectionContainer.createVoucherUseCase,
                    InjectionContainer.createTripartiteTransferUseCase,
                  ),
                ),
                BlocProvider<VoucherSuggestionsCubit>(
                  create: (_) => VoucherSuggestionsCubit(
                    InjectionContainer.getAutoSuggestionsUseCase,
                    InjectionContainer.markNotificationMessageProcessedUseCase,
                  ),
                ),
              ],
              child: VoucherCreatePage(
                initialQrData: {
                  'type': msg.typeCode == 'payment'
                      ? VoucherType.payment
                      : VoucherType.receipt,
                  'date': DateTime.parse(msg.dateIso),
                  'amountMinorUnits': msg.amountMinorUnits,
                  'description': msg.description,
                  'counterpartyAccountId': msg.otherPartyId,
                  'currencyCode': msg.currencyCode,
                  'editingVoucherId': msg.voucherId,
                },
              ),
            ),
          ),
        )
        .then((_) => cubit.reload());
  }

  Future<void> _createReversalVoucher(
    BuildContext context,
    AccountStatementChatMessageDto msg,
  ) async {
    final cubit = context.read<StatementChatCubit>();

    final action = await QaydDialog.show<String>(
      context: context,
      icon: Icons.published_with_changes_rounded,
      title: AppStrings.confirmSystematicReversal,
      content: AppStrings.systematicReversalExplainer,
      primaryActionLabel: AppStrings.voucherCreateReversal,
      onPrimaryAction: () => Navigator.pop(context, 'full'),
      secondaryActionLabel: AppStrings.correctionAndRedirection,
      onSecondaryAction: () => Navigator.pop(context, 'partial'),
      tertiaryActionLabel: AppStrings.templateEditCancel,
      onTertiaryAction: () => Navigator.pop(context, 'cancel'),
    );

    if (action == 'full') {
      if (_mutating) return;
      setState(() => _mutating = true);
      final result = await InjectionContainer.createReversalVoucherUseCase.call(
        originVoucherId: msg.voucherId,
      );
      setState(() => _mutating = false);
      if (!mounted) return;
      result.fold(
        (f) => QaydSnackBar.show(
          context,
          f.messageAr,
          type: QaydSnackBarType.error,
        ),
        (_) {
          QaydSnackBar.show(
            context,
            AppStrings.voucherCreatedDraft,
            type: QaydSnackBarType.success,
          );
          cubit.reload();
        },
      );
    } else if (action == 'partial') {
      final reversalType = msg.typeCode == VoucherType.payment.name
          ? VoucherType.receipt
          : VoucherType.payment;
      Navigator.of(context)
          .push(
            QaydPageRoute.slideFromStart(
              builder: (ctx) => MultiBlocProvider(
                providers: [
                  BlocProvider<VoucherCreateCubit>(
                    create: (_) => VoucherCreateCubit(
                      InjectionContainer.createVoucherUseCase,
                      InjectionContainer.createTripartiteTransferUseCase,
                    ),
                  ),
                  BlocProvider<VoucherSuggestionsCubit>(
                    create: (_) => VoucherSuggestionsCubit(
                      InjectionContainer.getAutoSuggestionsUseCase,
                      InjectionContainer
                          .markNotificationMessageProcessedUseCase,
                    ),
                  ),
                ],
                child: VoucherCreatePage(
                  initialQrData: {
                    'type': reversalType,
                    'date': DateTime.now(),
                    'amountMinorUnits': msg.amountMinorUnits,
                    'description':
                        '${AppStrings.voucherReversalIndicator} — ${msg.description}',
                    'counterpartyAccountId': msg.otherPartyId,
                    'currencyCode': msg.currencyCode,
                    'originVoucherId': msg.voucherId,
                  },
                ),
              ),
            ),
          )
          .then((_) => cubit.reload());
    }
  }

  Future<void> _withdrawVoucher(BuildContext context, String voucherId) async {
    final cubit = context.read<StatementChatCubit>();
    final state = cubit.state;
    if (state is! StatementChatReady) return;
    final msg = state.messages.firstWhere((m) => m.voucherId == voucherId);

    final action = await QaydDialog.show<String>(
      context: context,
      icon: Icons.warning_amber_rounded,
      iconColor: Theme.of(context).colorScheme.error,
      title: AppStrings.voucherWithdrawConfirmTitle,
      content: AppStrings.voucherWithdrawConfirmBody,
      primaryActionLabel: AppStrings.voucherRedirectToOthers,
      onPrimaryAction: () => Navigator.pop(context, 'edit_others'),
      secondaryActionLabel: AppStrings.voucherDeleteOrWithdraw,
      onSecondaryAction: () => Navigator.pop(context, 'withdraw'),
      tertiaryActionLabel: AppStrings.templateEditCancel,
      onTertiaryAction: () => Navigator.pop(context, 'cancel'),
    );

    if (action == 'withdraw') {
      setState(() => _mutating = true);
      final result = await InjectionContainer.withdrawVoucherUseCase.call(
        voucherId: voucherId,
      );
      setState(() => _mutating = false);

      result.fold(
        (f) => QaydSnackBar.show(
          context,
          f.messageAr,
          type: QaydSnackBarType.error,
        ),
        (_) {
          QaydSnackBar.show(
            context,
            AppStrings.voucherWithdrawalSuccess,
            type: QaydSnackBarType.success,
          );
          cubit.reload();
        },
      );
    } else if (action == 'edit_others') {
      Navigator.of(context)
          .push(
            QaydPageRoute.slideFromStart(
              builder: (ctx) => MultiBlocProvider(
                providers: [
                  BlocProvider<VoucherCreateCubit>(
                    create: (_) => VoucherCreateCubit(
                      InjectionContainer.createVoucherUseCase,
                      InjectionContainer.createTripartiteTransferUseCase,
                    ),
                  ),
                  BlocProvider<VoucherSuggestionsCubit>(
                    create: (_) => VoucherSuggestionsCubit(
                      InjectionContainer.getAutoSuggestionsUseCase,
                      InjectionContainer
                          .markNotificationMessageProcessedUseCase,
                    ),
                  ),
                ],
                child: VoucherCreatePage(
                  initialQrData: {
                    'type': msg.typeCode == 'payment'
                        ? VoucherType.payment
                        : VoucherType.receipt,
                    'date': DateTime.parse(msg.dateIso),
                    'amountMinorUnits': msg.amountMinorUnits,
                    'description': msg.description,
                    'counterpartyAccountId': msg.otherPartyId,
                    'currencyCode': msg.currencyCode,
                    'editingVoucherId': msg.voucherId,
                  },
                ),
              ),
            ),
          )
          .then((_) => cubit.reload());
    }
  }

  void _scrollToMessage(String voucherId) {
    final key = _messageKeys[voucherId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> _openAccountProfile(String accountId) async {
    await Navigator.of(context).push<void>(
      QaydPageRoute.slideFromStart<void>(
        builder: (ctx) => BlocProvider(
          create: (_) =>
              AccountDetailCubit(InjectionContainer.getAccountDetailsUseCase)
                ..load(accountId),
          child: const AccountDetailPage(),
        ),
      ),
    );
  }

  Future<void> _navigateToCounterpartyChat(
    BuildContext context,
    String cpAccountId,
    String myAccountId,
  ) async {
    // Navigate to the individual chat with that specific party
    await Navigator.of(context).push<void>(
      QaydPageRoute.slideFromStart<void>(
        builder: (ctx) => BlocProvider(
          create: (_) => StatementChatCubit(
            listStatement: InjectionContainer.listAccountStatementChatUseCase,
            listAccounts: InjectionContainer.listAccountsUseCase,
            getCostCenterDetails:
                InjectionContainer.getCostCenterDetailsUseCase,
            counterpartyAccountId: cpAccountId,
            syncCoordinatorService: InjectionContainer.syncCoordinatorService,
            myAccountId: myAccountId,
          )..load(),
          child: AccountStatementChatPage(
            counterpartyAccountId: cpAccountId,
            myAccountId: myAccountId,
          ),
        ),
      ),
    );
  }

  Future<void> _createNewVoucher(StatementChatCubit cubit) async {
    Navigator.of(context)
        .push(
          QaydPageRoute.slideFromStart(
            builder: (ctx) => MultiBlocProvider(
              providers: [
                BlocProvider<VoucherCreateCubit>(
                  create: (_) => VoucherCreateCubit(
                    InjectionContainer.createVoucherUseCase,
                    InjectionContainer.createTripartiteTransferUseCase,
                  ),
                ),
                BlocProvider<VoucherSuggestionsCubit>(
                  create: (_) => VoucherSuggestionsCubit(
                    InjectionContainer.getAutoSuggestionsUseCase,
                    InjectionContainer.markNotificationMessageProcessedUseCase,
                  ),
                ),
              ],
              child: VoucherCreatePage(
                initialQrData: {
                  'counterpartyAccountId': widget.counterpartyAccountId,
                  'lockCounterparty': true,
                },
              ),
            ),
          ),
        )
        .then((_) => cubit.reload());
  }

  Future<void> _openFilterSheet(StatementChatCubit cubit) async {
    final result = await showStatementChatFilterSheet(
      context,
      initial: cubit.filter,
    );
    if (result != null && mounted) {
      cubit.setFilter(result);
    }
  }

  Future<void> _respondToPosCreditInvoice(
    String notificationId,
    bool accepted,
  ) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      final result =
          await InjectionContainer.respondToPosCreditInvoiceInChatUseCase(
            notificationId: notificationId,
            accepted: accepted,
          );
      if (!mounted) return;
      if (result.isFailure) {
        QaydSnackBar.show(
          context,
          result.failureOrNull!.messageAr,
          type: QaydSnackBarType.error,
        );
      } else {
        QaydSnackBar.show(
          context,
          AppStrings.posCreditInvoiceResponseSent,
          type: QaydSnackBarType.success,
        );
      }
      await context.read<StatementChatCubit>().reload();
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _retryPosCreditInvoice({
    required String notificationId,
    required bool retryAcknowledgment,
    bool accepted = true,
  }) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      final result = retryAcknowledgment
          ? await InjectionContainer.respondToPosCreditInvoiceInChatUseCase(
              notificationId: notificationId,
              accepted: accepted,
            )
          : await InjectionContainer.sendPosCreditInvoiceToChatUseCase.retry(
              notificationId,
            );
      if (!mounted) return;
      if (result.isFailure) {
        QaydSnackBar.show(
          context,
          result.failureOrNull!.messageAr,
          type: QaydSnackBarType.error,
        );
      } else {
        QaydSnackBar.show(
          context,
          retryAcknowledgment
              ? AppStrings.posCreditInvoiceResponseSent
              : AppStrings.posCreditInvoiceAwaiting,
          type: QaydSnackBarType.success,
        );
      }
      await context.read<StatementChatCubit>().reload();
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _openPosCreditInvoiceDetails(AccountStatementChatMessageDto msg) {
    try {
      final notificationId = msg.posInvoiceMessageId;
      if (notificationId == null) {
        throw const FormatException('Missing invoice message id.');
      }
      final payload = PosCreditInvoiceChatProtocol.decodePayload(
        msg.posInvoicePayloadJson,
      );
      final snapshot = PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
        payload,
        expectedNodeId: notificationId,
      );
      final pdfBytes = PosCreditInvoiceChatProtocol.pdfBytesFromEventPayload(
        payload,
        expectedInvoiceFingerprint: snapshot.fingerprint,
      );
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _PosCreditInvoiceDetailsSheet(
          snapshot: snapshot,
          onExportPdf: () async {
            await sharePdfBytes(
              pdfBytes,
              'pos-credit-invoice-${snapshot.fingerprint.substring(0, 12)}.pdf',
            );
          },
        ),
      );
    } on FormatException {
      QaydSnackBar.show(
        context,
        AppStrings.posInvoiceNotFound,
        type: QaydSnackBarType.error,
      );
    }
  }

  void _showVoucherActions(
    BuildContext context,
    AccountStatementChatMessageDto msg,
  ) {
    final custom = Theme.of(context).extension<QaydCustomColors>()!;

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(RadiusTokens.lg),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: SpacingTokens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: custom.subtleBorder.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(RadiusTokens.pill),
              ),
            ),
            SizedBox(height: SpacingTokens.lg),

            // Interaction buttons like "same movement of reaction buttons"
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
              child: Row(
                children: [
                  if (msg.isCreator &&
                      msg.signatureStatusCode == AgreementStatus.rejected.name)
                    _ActionButton(
                      icon: Icons.edit_rounded,
                      label: AppStrings.voucherEditAction,
                      onTap: () {
                        Navigator.pop(ctx);
                        _resubmitVoucher(context, msg.voucherId);
                      },
                    ),
                  if (msg.isCreator &&
                      !AgreementStatus.values
                          .byName(msg.signatureStatusCode)
                          .isAccepted)
                    _ActionButton(
                      icon: Icons.u_turn_right_rounded,
                      label: AppStrings.statementChatWithdraw,
                      color: ColorTokens.errorDeep,
                      onTap: () {
                        Navigator.pop(ctx);
                        _withdrawVoucher(context, msg.voucherId);
                      },
                    ),
                  if (AgreementStatus.values
                      .byName(msg.signatureStatusCode)
                      .isAccepted)
                    _ActionButton(
                      icon: Icons.published_with_changes_rounded,
                      label: AppStrings.voucherCreateReversal,
                      color: Theme.of(
                        context,
                      ).extension<QaydCustomColors>()!.goldAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        _createReversalVoucher(context, msg);
                      },
                    ),
                  _ActionButton(
                    icon: Icons.description_outlined,
                    label: AppStrings.actionDetails,
                    onTap: () {
                      Navigator.pop(ctx);
                      VoucherDetailPage.show(context, msg.voucherId);
                    },
                  ),
                  if (msg.mediatorAccountId != null)
                    _ActionButton(
                      icon: Icons.support_agent_rounded,
                      label: AppStrings.tripartiteMediatorLabel,
                      color: custom.goldAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        _navigateToCounterpartyChat(
                          context,
                          msg.mediatorAccountId!,
                          widget.myAccountId ?? widget.counterpartyAccountId,
                        );
                      },
                    ),
                  _ActionButton(
                    icon: Icons.copy_rounded,
                    label: AppStrings.actionCopy,
                    onTap: () {
                      Navigator.pop(ctx);
                      // Add copy logic
                    },
                  ),
                  _ActionButton(
                    icon: Icons.share_rounded,
                    label: AppStrings.actionShare,
                    onTap: () {
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<List<_BalanceSnapshot>> _calculateAllRollingSnapshots(
    List<AccountStatementChatMessageDto> historyReversed,
    Map<String, int> initialBalances,
  ) {
    final List<AccountStatementChatMessageDto> history = historyReversed
        .reversed
        .toList();
    final List<List<_BalanceSnapshot>> snapshotsList = [];
    final Map<String, _BalanceSnapshot> currentBalances = {};

    // Collect symbols from history to use for initial balances
    final Map<String, AccountStatementChatMessageDto> symbolLookup = {};
    for (final m in history) {
      symbolLookup.putIfAbsent(m.currencyCode, () => m);
    }

    initialBalances.forEach((code, amount) {
      final dto = symbolLookup[code];
      currentBalances[code] = _BalanceSnapshot(
        code: code,
        symbol: CurrencyUtil.getLocalizedName(code),
        digits: dto?.currencyDigits ?? 2,
        amount: amount,
      );
    });

    for (final m in history) {
      if (m.isSettlementMilestone) {
        snapshotsList.add(currentBalances.values.toList());
        continue;
      }
      final current =
          currentBalances[m.currencyCode] ??
          _BalanceSnapshot(
            code: m.currencyCode,
            symbol: CurrencyUtil.getLocalizedName(m.currencyCode),
            digits: m.currencyDigits,
            amount: 0,
          );

      final affectsBalance =
          m.voucherStateCode == 'confirmed' || m.voucherStateCode == 'settled';

      if (affectsBalance) {
        int impact = m.amountMinorUnits;
        if (m.direction == 'outgoing') impact = -impact;

        currentBalances[m.currencyCode] = current.copyWith(
          amount: current.amount + impact,
        );
      }
      snapshotsList.add(currentBalances.values.toList());
    }

    return snapshotsList.reversed.toList();
  }

  List<_BalanceSnapshot> _calculateInitialSnapshots(
    Map<String, int> initialBalances,
    List<AccountStatementChatMessageDto> history,
  ) {
    final Map<String, AccountStatementChatMessageDto> symbolLookup = {};
    for (final m in history) {
      symbolLookup.putIfAbsent(m.currencyCode, () => m);
    }

    return initialBalances.entries.map((e) {
      final dto = symbolLookup[e.key];
      return _BalanceSnapshot(
        code: e.key,
        symbol: CurrencyUtil.getLocalizedName(e.key),
        digits: dto?.currencyDigits ?? 2,
        amount: e.value,
      );
    }).toList();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StatementChatCubit, StatementChatState>(
      builder: (context, state) {
        if (state is StatementChatInitial || state is StatementChatLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state is StatementChatFailure) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QaydText(
                      state.failure.messageAr,
                      slot: QaydTextStyleSlot.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: SpacingTokens.md),
                    FilledButton(
                      onPressed: () =>
                          context.read<StatementChatCubit>().load(),
                      child: Text(AppStrings.retryAction),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final data = state as StatementChatReady;
        final cubit = context.read<StatementChatCubit>();
        final custom = Theme.of(context).extension<QaydCustomColors>()!;
        final voucherCount = data.messages
            .where((m) => !m.isSettlementMilestone && !m.isPosCreditInvoice)
            .length;

        final int firstUnreadIndex = data.messages.lastIndexWhere(
          (m) =>
              m.direction == 'incoming' &&
              m.signatureStatusCode == 'underRequest',
        );

        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () => _createNewVoucher(cubit),
            backgroundColor: custom.goldAccent,
            foregroundColor: Colors.white,
            mini: true,
            child: const Icon(Icons.add_rounded),
          ),
          body: Column(
            children: [
              // ── Header ──
              if (!widget.isEmbedded)
                _ChatHeader(
                  counterpartyName: data.counterpartyName,
                  counterpartyAccountId: data.counterpartyAccountId,
                  messageCount: voucherCount,
                  hasFilters: data.hasActiveFilters,
                  showSearch: _showSearch,
                  isUnified: data.isUnified,
                  onProfileTap: () =>
                      _openAccountProfile(data.counterpartyAccountId),
                  onRequestFunds: () {
                    RequestTripartiteSheet.show(
                      context,
                      destinationAccountId: data.counterpartyAccountId,
                      destinationName: data.counterpartyName,
                    );
                  },
                  onSearchToggle: () {
                    setState(() {
                      _showSearch = !_showSearch;
                      if (!_showSearch) {
                        _searchController.clear();
                        cubit.clearSearch();
                      }
                    });
                  },
                  onFilterTap: () => _openFilterSheet(cubit),
                  onExportPdf: () => shareStatementChatAsPdf(
                    context,
                    accountId: data.counterpartyAccountId,
                    accountName: data.counterpartyName,
                    filter: data.filter,
                    messages: data.messages,
                    broughtForwardByCurrency: data.broughtForwardByCurrency,
                    finalBalanceByCurrency: data.finalBalanceByCurrency,
                  ),
                  onShareWhatsapp: () async {
                    final method = await ShareMethodPicker.show(context);
                    if (method == null || method == ShareMethod.system) return;
                    if (!context.mounted) return;
                    shareStatementChatAsPdf(
                      context,
                      accountId: data.counterpartyAccountId,
                      accountName: data.counterpartyName,
                      filter: data.filter,
                      messages: data.messages,
                      broughtForwardByCurrency: data.broughtForwardByCurrency,
                      finalBalanceByCurrency: data.finalBalanceByCurrency,
                      shareMethod: method,
                    );
                  },
                  onExportExcel: () => shareStatementChatAsExcel(
                    context,
                    accountId: data.counterpartyAccountId,
                    accountName: data.counterpartyName,
                    filter: data.filter,
                    messages: data.messages,
                    broughtForwardByCurrency: data.broughtForwardByCurrency,
                    currencyDigits: data.currencyDigits,
                  ),
                ),

              // ── Search bar ──
              if (_showSearch)
                _SearchBar(
                  controller: _searchController,
                  onChanged: (text) => cubit.setSearchText(text),
                  onClear: () {
                    _searchController.clear();
                    cubit.clearSearch();
                  },
                ),

              // ── Filter chips ──
              if (data.hasActiveFilters)
                _ActiveFilterChips(
                  data: data,
                  onClearAll: () {
                    _searchController.clear();
                    cubit.clearAllFiltersAndSearch();
                  },
                ),

              // ── View Mode Toggle ──
              _ViewModeToggle(
                mode: data.filter.viewMode,
                onChanged: (m) => cubit.setViewMode(m),
              ),

              // ── Messages list ──
              Expanded(
                child: data.messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(SpacingTokens.lg),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 56,
                                color: custom.subtleBorder,
                              ),
                              SizedBox(height: SpacingTokens.md),
                              QaydText(
                                data.hasActiveFilters
                                    ? AppStrings.statementChatEmptyFiltered
                                    : AppStrings.statementChatEmpty,
                                slot: QaydTextStyleSlot.bodyLarge,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => cubit.reload(),
                        child: Builder(
                          builder: (context) {
                            // Pre-calculate all chronology snapshots in one go (O(N))
                            final allSnapshots = _calculateAllRollingSnapshots(
                              data.messages,
                              data.broughtForwardByCurrency,
                            );
                            final showBF =
                                data.filter.includePreviousBalance &&
                                data.broughtForwardByCurrency.values.any(
                                  (v) => v != 0,
                                );

                            return ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              padding: const EdgeInsets.only(
                                left: SpacingTokens.sm,
                                right: SpacingTokens.sm,
                                top: 110.0,
                                bottom: SpacingTokens.sm,
                              ),
                              itemCount:
                                  data.messages.length + (showBF ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (showBF && i == data.messages.length) {
                                  return _BroughtForwardCard(
                                    balances: allSnapshots.isEmpty
                                        ? []
                                        : _calculateInitialSnapshots(
                                            data.broughtForwardByCurrency,
                                            data.messages,
                                          ),
                                  );
                                }
                                final msgIdx = i;
                                final msg = data.messages[msgIdx];
                                final key = _messageKeys.putIfAbsent(
                                  msg.voucherId,
                                  () => GlobalKey(),
                                );
                                final balances = allSnapshots[msgIdx];

                                // Find child reversal voucher (if any) for bidirectional navigation
                                String? childReversalId;
                                if (!msg.isSettlementMilestone &&
                                    msg.reversalCount > 0) {
                                  for (final m in data.messages) {
                                    if (m.originVoucherId == msg.voucherId) {
                                      childReversalId = m.voucherId;
                                      break;
                                    }
                                  }
                                }

                                final msgWidget = msg.isSettlementMilestone
                                    ? _SettlementMilestoneCard(msg: msg)
                                    : msg.isTransferRequest
                                    ? _TransferRequestBubble(
                                        msg: msg,
                                        onTap: () {
                                          if (!msg.isCreator) {
                                            final uri = Uri.parse(
                                              '/tripartite/create?sourceAccountId=${msg.otherPartyId}&destAccountId=${msg.otherPartyId}&amount=${msg.amountMinorUnits}&currency=${msg.currencyCode}&notes=${Uri.encodeComponent(msg.description)}',
                                            );
                                            Navigator.of(context).push(
                                              QaydPageRoute.slideFromStart(
                                                builder: (ctx) => MultiBlocProvider(
                                                  providers: [
                                                    BlocProvider<
                                                      VoucherCreateCubit
                                                    >(
                                                      create: (_) => VoucherCreateCubit(
                                                        InjectionContainer
                                                            .createVoucherUseCase,
                                                        InjectionContainer
                                                            .createTripartiteTransferUseCase,
                                                      ),
                                                    ),
                                                  ],
                                                  child: TripartiteCreatePage(
                                                    initialQrData: {
                                                      'amountMinorUnits':
                                                          int.tryParse(
                                                            uri.queryParameters['amount'] ??
                                                                '0',
                                                          ),
                                                      'currencyCode': uri
                                                          .queryParameters['currency'],
                                                      'sourceAccountId': uri
                                                          .queryParameters['sourceAccountId'],
                                                      'destAccountId': uri
                                                          .queryParameters['destAccountId'],
                                                      'notes': uri
                                                          .queryParameters['notes'],
                                                    },
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                      )
                                    : msg.isPosCreditInvoice
                                    ? _PosCreditInvoiceBubble(
                                        msg: msg,
                                        mutating: _mutating,
                                        onAccept: () =>
                                            _respondToPosCreditInvoice(
                                              msg.posInvoiceMessageId!,
                                              true,
                                            ),
                                        onReject: () =>
                                            _respondToPosCreditInvoice(
                                              msg.posInvoiceMessageId!,
                                              false,
                                            ),
                                        onRetrySend: () =>
                                            _retryPosCreditInvoice(
                                              notificationId:
                                                  msg.posInvoiceMessageId!,
                                              retryAcknowledgment: false,
                                            ),
                                        onRetryAcknowledgment: (accepted) =>
                                            _retryPosCreditInvoice(
                                              notificationId:
                                                  msg.posInvoiceMessageId!,
                                              retryAcknowledgment: true,
                                              accepted: accepted,
                                            ),
                                        onTap: () =>
                                            _openPosCreditInvoiceDetails(msg),
                                      )
                                    : _MessageBubble(
                                        msg: msg,
                                        mutating: _mutating,
                                        isUnified: data.isUnified,
                                        onAccept: (id) =>
                                            _acceptVoucher(context, id),
                                        onReject: (id) =>
                                            _rejectVoucher(context, id),
                                        onWithdraw: (id) =>
                                            _withdrawVoucher(context, id),
                                        onResubmit: (id) =>
                                            _resubmitVoucher(context, id),
                                        onOriginTap: _scrollToMessage,
                                        onReversalTap: childReversalId != null
                                            ? () => _scrollToMessage(
                                                childReversalId!,
                                              )
                                            : null,
                                        onTap: () => data.isUnified
                                            ? _navigateToCounterpartyChat(
                                                context,
                                                msg.otherPartyId,
                                                data.counterpartyAccountId,
                                              )
                                            : VoucherDetailPage.show(
                                                context,
                                                msg.voucherId,
                                              ),
                                        onLongPress: () =>
                                            _showVoucherActions(context, msg),
                                      );

                                final itemWidget = Column(
                                  key: key,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (i == firstUnreadIndex)
                                      const _UnreadSessionDivider(),

                                    msgWidget,

                                    // Centered balance summary table
                                    if (msg.voucherStateCode == 'confirmed' ||
                                        msg.voucherStateCode == 'settled')
                                      _ChronologySummaryTable(
                                        balances: balances,
                                      ),

                                    SizedBox(height: SpacingTokens.sm),
                                  ],
                                );

                                return itemWidget;
                              },
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
          bottomNavigationBar: data.messages.isNotEmpty
              ? _SummaryFooter(
                  finalBalancesByCurrency: data.finalBalanceByCurrency,
                  messageCount: voucherCount,
                )
              : null,
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Chat Header ──────────────────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.counterpartyName,
    required this.counterpartyAccountId,
    required this.messageCount,
    required this.hasFilters,
    required this.showSearch,
    required this.isUnified,
    required this.onProfileTap,
    required this.onSearchToggle,
    required this.onFilterTap,
    required this.onExportPdf,
    required this.onShareWhatsapp,
    required this.onExportExcel,
    this.onRequestFunds,
  });

  final String counterpartyName;
  final String counterpartyAccountId;
  final int messageCount;
  final bool hasFilters;
  final bool showSearch;
  final bool isUnified;
  final VoidCallback onProfileTap;
  final VoidCallback onSearchToggle;
  final VoidCallback onFilterTap;
  final VoidCallback onExportPdf;
  final VoidCallback onShareWhatsapp;
  final VoidCallback onExportExcel;
  final VoidCallback? onRequestFunds;

  @override
  Widget build(BuildContext context) {
    final custom = Theme.of(context).extension<QaydCustomColors>()!;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 2,
      shadowColor: scheme.shadow.withValues(alpha: 0.08),
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.xs,
            vertical: SpacingTokens.xs,
          ),
          child: Row(
            children: [
              // Back button
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: AppStrings.back,
              ),
              // Avatar + Name
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(RadiusTokens.md),
                  onTap: onProfileTap,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        child: Text(
                          counterpartyName.isNotEmpty
                              ? counterpartyName.trim().substring(0, 1)
                              : '?',
                          textDirection: Directionality.of(context),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      SizedBox(width: SpacingTokens.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              counterpartyName,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              isUnified
                                  ? AppStrings.statementUnifiedTitle
                                  : '$messageCount ${AppStrings.statementVoucherCount}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Search toggle
              IconButton(
                icon: Icon(
                  showSearch ? Icons.search_off_rounded : Icons.search_rounded,
                  size: 22,
                ),
                onPressed: onSearchToggle,
              ),
              // Filter
              Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.tune_rounded, size: 22),
                    onPressed: onFilterTap,
                  ),
                  if (hasFilters)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: custom.goldAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              // Options Menu
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 22),
                onSelected: (val) {
                  if (val == 'pdf') onExportPdf();
                  if (val == 'whatsapp') onShareWhatsapp();
                  if (val == 'excel') onExportExcel();
                  if (val == 'request_funds') onRequestFunds?.call();
                },
                itemBuilder: (context) => [
                  if (onRequestFunds != null)
                    PopupMenuItem(
                      value: 'request_funds',
                      child: Row(
                        children: [
                          Icon(
                            Icons.send_rounded,
                            size: 20,
                            color: custom.goldAccent,
                          ),
                          SizedBox(width: SpacingTokens.sm),
                          Text(AppStrings.tripartiteRequestFunds),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'excel',
                    child: Row(
                      children: [
                        Icon(Icons.table_view_outlined, size: 20),
                        SizedBox(width: SpacingTokens.sm),
                        Text(AppStrings.settingsExportStatementTitle),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'pdf',
                    child: Row(
                      children: [
                        Icon(Icons.picture_as_pdf_outlined, size: 20),
                        SizedBox(width: SpacingTokens.sm),
                        Text(AppStrings.accountStatementExportPdfTooltip),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Search Bar ───────────────────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      padding: EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.sm,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textDirection: Directionality.of(context),
        decoration: InputDecoration(
          hintText: AppStrings.statementChatSearchHint,
          prefixIcon: Icon(Icons.search_rounded, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, size: 18),
                  onPressed: onClear,
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.md,
            vertical: SpacingTokens.sm,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RadiusTokens.pill),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Active Filter Chips ──────────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({required this.data, required this.onClearAll});

  final StatementChatReady data;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final custom = Theme.of(context).extension<QaydCustomColors>()!;
    final chips = <Widget>[];

    if (data.searchQuery.trim().isNotEmpty) {
      chips.add(
        InputChip(
          label: Text(
            '${AppStrings.voucherFilterChipSearchPrefix}${data.searchQuery}',
          ),
          onDeleted: () => context.read<StatementChatCubit>().clearSearch(),
          deleteIconColor: custom.goldAccent,
        ),
      );
    }

    if (data.filter.agreementStatus != null) {
      final label = switch (data.filter.agreementStatus!) {
        AgreementStatus.accepted => AppStrings.statementStatusConfirmed,
        AgreementStatus.underRequest => AppStrings.statementStatusPending,
        AgreementStatus.rejected => AppStrings.statementStatusRejected,
        AgreementStatus.unverified => AppStrings.agreementUnverified,
      };
      chips.add(
        InputChip(
          label: Text(label),
          onDeleted: () {
            final cubit = context.read<StatementChatCubit>();
            cubit.setFilter(cubit.filter.copyWith(clearAgreementStatus: true));
          },
          deleteIconColor: custom.goldAccent,
        ),
      );
    }

    if (data.filter.type != null) {
      final label = data.filter.type == VoucherType.receipt
          ? AppStrings.voucherTypeReceipt
          : AppStrings.voucherTypePayment;
      chips.add(
        InputChip(
          label: Text(label),
          onDeleted: () {
            final cubit = context.read<StatementChatCubit>();
            cubit.setFilter(cubit.filter.copyWith(clearType: true));
          },
          deleteIconColor: custom.goldAccent,
        ),
      );
    }

    if (data.filter.fromDate != null || data.filter.toDate != null) {
      final df = DateFormat.yMd('en');
      final from = data.filter.fromDate != null
          ? df.format(data.filter.fromDate!)
          : '…';
      final to = data.filter.toDate != null
          ? df.format(data.filter.toDate!)
          : '…';
      chips.add(
        InputChip(
          label: Text('$from → $to'),
          onDeleted: () {
            final cubit = context.read<StatementChatCubit>();
            cubit.setFilter(
              cubit.filter.copyWith(clearFromDate: true, clearToDate: true),
            );
          },
          deleteIconColor: custom.goldAccent,
        ),
      );
    }

    if (data.filter.costCenterId != null) {
      final name =
          data.costCenterNamesById[data.filter.costCenterId] ??
          data.filter.costCenterId;
      chips.add(
        InputChip(
          label: Text('${AppStrings.costCenter}: $name'),
          onDeleted: () {
            final cubit = context.read<StatementChatCubit>();
            cubit.setFilter(cubit.filter.copyWith(clearCostCenter: true));
          },
          deleteIconColor: custom.goldAccent,
        ),
      );
    }

    chips.add(
      ActionChip(
        label: Text(AppStrings.voucherClearAllFiltersChip),
        onPressed: onClearAll,
        avatar: Icon(
          Icons.clear_all_rounded,
          size: 16,
          color: custom.goldAccent,
        ),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.xs,
      ),
      child: Wrap(
        spacing: SpacingTokens.sm,
        runSpacing: SpacingTokens.xs,
        children: chips,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Brought Forward Card ─────────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _BroughtForwardCard extends StatelessWidget {
  const _BroughtForwardCard({required this.balances});

  final List<_BalanceSnapshot> balances;

  @override
  Widget build(BuildContext context) {
    final custom = Theme.of(context).extension<QaydCustomColors>()!;
    final color = custom.confirmedState;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.sm,
      ),
      padding: const EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(RadiusTokens.md),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          if (balances.isNotEmpty) ...[
            ...balances.map(
              (b) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text(
                      b.code,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    _BalanceAmountText(
                      minorUnits: b.amount,
                      currencySymbol: b.symbol,
                      currencyDigits: b.digits,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Unread Session Divider ───────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _UnreadSessionDivider extends StatelessWidget {
  const _UnreadSessionDivider();

  @override
  Widget build(BuildContext context) {
    final custom = Theme.of(context).extension<QaydCustomColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: custom.goldAccent.withValues(alpha: 0.5),
              thickness: 1,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: custom.goldAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(RadiusTokens.pill),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.mark_chat_unread_rounded,
                  size: 14,
                  color: custom.goldAccent,
                ),
                SizedBox(width: 4),
                Text(
                  AppStrings.statementUnreadMessages,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: custom.goldAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Divider(
              color: custom.goldAccent.withValues(alpha: 0.5),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Summary Footer ───────────────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _SummaryFooter extends StatelessWidget {
  const _SummaryFooter({
    required this.finalBalancesByCurrency,
    required this.messageCount,
  });

  final Map<String, int> finalBalancesByCurrency;
  final int messageCount;

  @override
  Widget build(BuildContext context) {
    final custom = Theme.of(context).extension<QaydCustomColors>()!;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      padding: EdgeInsets.only(
        left: SpacingTokens.md,
        right: SpacingTokens.md,
        top: SpacingTokens.sm,
        bottom: MediaQuery.paddingOf(context).bottom + SpacingTokens.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compact Header
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.statementFinalBalance,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  '$messageCount ${AppStrings.statementVoucherCount}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),

          // Modern Data Table
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RadiusTokens.sm),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(2.2), // Icon + Status
                1: FlexColumnWidth(1.2), // Currency
                2: IntrinsicColumnWidth(), // Amount
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.2),
                ),
                verticalInside: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              children: finalBalancesByCurrency.entries.map((e) {
                final isPositive = e.value > 0;
                final isNegative = e.value < 0;
                final statusLabel = isPositive
                    ? AppStrings.statementBalanceAgainstYou
                    : isNegative
                    ? AppStrings.statementBalanceForYou
                    : AppStrings.statementBalanceSettled;
                final statusColor = isPositive
                    ? ColorTokens.goldAccent
                    : isNegative
                    ? custom.credit
                    : custom.confirmedState;
                final statusIcon = isPositive
                    ? Icons.trending_up_rounded
                    : isNegative
                    ? Icons.trending_down_rounded
                    : Icons.check_circle_outline_rounded;

                return TableRow(
                  children: [
                    // Col 1: Icon + Status Label
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, color: statusColor, size: 12),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 9.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Col 3: Amount
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: _BalanceAmountText(
                        minorUnits: e.value,
                        currencySymbol: CurrencyUtil.getLocalizedName(e.key),
                        currencyDigits: 2,
                        fontSize: 11,
                        withCurrencySymbol: false,
                      ),
                    ),
                    // Col 2: Currency Name
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Text(
                        CurrencyUtil.getLocalizedName(e.key),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceSnapshot {
  const _BalanceSnapshot({
    required this.code,
    required this.symbol,
    required this.digits,
    required this.amount,
  });

  final String code;
  final String symbol;
  final int digits;
  final int amount;

  _BalanceSnapshot copyWith({int? amount}) {
    return _BalanceSnapshot(
      code: code,
      symbol: symbol,
      digits: digits,
      amount: amount ?? this.amount,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectColor = color ?? scheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RadiusTokens.md),
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(SpacingTokens.sm),
              decoration: BoxDecoration(
                color: effectColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: effectColor, size: 24),
            ),
            SizedBox(height: SpacingTokens.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChronologySummaryTable extends StatelessWidget {
  const _ChronologySummaryTable({required this.balances});

  final List<_BalanceSnapshot> balances;

  @override
  Widget build(BuildContext context) {
    if (balances.isEmpty) return const SizedBox.shrink();

    final custom = Theme.of(context).extension<QaydCustomColors>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: balances.map((b) {
              final isPositive = b.amount > 0;
              final isNegative = b.amount < 0;
              final color = isPositive
                  ? ColorTokens.goldAccent
                  : isNegative
                  ? custom.credit
                  : custom.confirmedState;

              final label = isPositive
                  ? AppStrings.creditorToYou
                  : isNegative
                  ? AppStrings.oweToYou
                  : AppStrings.neutral;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(RadiusTokens.sm),
                  border: Border.all(color: color.withValues(alpha: 0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    SizedBox(width: 4),
                    _BalanceAmountText(
                      minorUnits: b.amount,
                      currencySymbol: b.symbol,
                      currencyDigits: b.digits,
                      fontSize: 11,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Message Bubble ───────────────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _SettlementMilestoneCard extends StatelessWidget {
  const _SettlementMilestoneCard({required this.msg});

  final AccountStatementChatMessageDto msg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final custom = Theme.of(context).extension<QaydCustomColors>()!;
    final balance = msg.settlementBalanceMinorUnits ?? 0;
    final currency = CurrencyCode(
      code: msg.currencyCode,
      nameAr: CurrencyUtil.getLocalizedName(msg.currencyCode),
      symbol: msg.currencySymbol,
      fractionalDigits: msg.currencyDigits,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: SpacingTokens.sm,
        horizontal: SpacingTokens.sm,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(SpacingTokens.md),
        decoration: BoxDecoration(
          color: custom.confirmedState.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(RadiusTokens.md),
          border: Border.all(
            color: custom.confirmedState.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.flag_circle_rounded, color: custom.confirmedState),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              msg.settlementLabel ?? AppStrings.statementSettlementMilestone,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: SpacingTokens.xs),
            QaydMoneyDisplay(
              money: Money.fromMinorUnits(balance, currency),
              size: QaydMoneyDisplaySize.medium,
              displayNegative: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferRequestBubble extends StatelessWidget {
  const _TransferRequestBubble({required this.msg, required this.onTap});

  final AccountStatementChatMessageDto msg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final custom = Theme.of(context).extension<QaydCustomColors>()!;
    final isMe = msg.isCreator;

    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 64 : 0,
        right: isMe ? 0 : 64,
        bottom: SpacingTokens.xs,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isMe
                ? custom.goldAccent.withValues(alpha: 0.1)
                : scheme.secondaryContainer.withValues(alpha: 0.8),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(RadiusTokens.lg),
              topRight: const Radius.circular(RadiusTokens.lg),
              bottomLeft: isMe
                  ? const Radius.circular(RadiusTokens.lg)
                  : Radius.zero,
              bottomRight: isMe
                  ? Radius.zero
                  : const Radius.circular(RadiusTokens.lg),
            ),
            border: Border.all(
              color: isMe
                  ? custom.goldAccent.withValues(alpha: 0.3)
                  : scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.call_split_rounded,
                    size: 16,
                    color: isMe
                        ? custom.goldAccent
                        : scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  Expanded(
                    child: Text(
                      isMe
                          ? AppStrings.requestToMakeA
                          : AppStrings.transferRequestReceivedTitle,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: isMe
                            ? custom.goldAccent
                            : scheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SpacingTokens.sm),
              QaydMoneyDisplay(
                money: Money.fromMinorUnits(
                  msg.amountMinorUnits,
                  CurrencyCode(
                    code: msg.currencyCode,
                    nameAr: CurrencyUtil.getLocalizedName(msg.currencyCode),
                    symbol: msg.currencySymbol,
                    fractionalDigits: msg.currencyDigits,
                  ),
                ),
                size: QaydMoneyDisplaySize.medium,
                displayNegative: false,
              ),
              if (msg.description.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  msg.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (!isMe) ...[
                const SizedBox(height: SpacingTokens.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: custom.goldAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(RadiusTokens.sm),
                  ),
                  child: Text(
                    AppStrings.transferRequestOpenTransfers,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: custom.goldAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.msg,
    required this.mutating,
    required this.isUnified,
    required this.onAccept,
    required this.onReject,
    required this.onWithdraw,
    required this.onResubmit,
    required this.onTap,
    required this.onLongPress,
    this.onOriginTap,
    this.onReversalTap,
  });

  final AccountStatementChatMessageDto msg;
  final bool mutating;
  final bool isUnified;
  final Future<void> Function(String voucherId) onAccept;
  final Future<void> Function(String voucherId) onReject;
  final Future<void> Function(String voucherId) onWithdraw;
  final Future<void> Function(String voucherId) onResubmit;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final void Function(String originId)? onOriginTap;
  final VoidCallback? onReversalTap;

  bool get _isIncoming => msg.direction == 'incoming';
  bool get _isOutgoing => msg.direction == 'outgoing';

  // ── Color-coded status system ──
  // 🟢 Green  = Confirmed (accepted)
  // 🔵 Blue   = Receipt voucher
  // 🟠 Orange = Pending (underRequest)
  // 🔴 Red    = Rejected

  Color _statusColor(BuildContext context) {
    final custom = Theme.of(context).extension<QaydCustomColors>()!;
    final agreement = AgreementStatus.values.byName(msg.signatureStatusCode);
    if (agreement.isRejected) return ColorTokens.errorDeep;
    if (agreement.isAccepted) return custom.confirmedState;
    if (msg.typeCode == VoucherType.receipt.name) return custom.debit;
    return custom.draftState;
  }

  String _typeLabel() {
    return msg.typeCode == VoucherType.receipt.name
        ? AppStrings.voucherTypeReceipt
        : AppStrings.voucherTypePayment;
  }

  IconData _typeIcon() {
    return msg.typeCode == VoucherType.receipt.name
        ? Icons.south_west_rounded
        : Icons.north_east_rounded;
  }

  IconData _ticksIcon() {
    final agreement = AgreementStatus.values.byName(msg.signatureStatusCode);
    if (agreement.isRejected) return Icons.close_rounded;
    if (agreement.isAccepted) return Icons.done_all_rounded;
    if (agreement.isUnderRequest) return Icons.check_rounded;
    return Icons.schedule_rounded;
  }

  Widget _stateWidget(BuildContext context) {
    final status = AgreementStatus.values.byName(msg.signatureStatusCode);
    if (status.isRejected) {
      return QaydBadge.agreement(
        status: AgreementStatus.rejected,
        context: context,
      );
    }
    if (status.isAccepted) {
      return QaydBadge.agreement(
        status: AgreementStatus.accepted,
        context: context,
      );
    }
    final state = VoucherState.values.byName(msg.voucherStateCode);
    return QaydBadge(state: state, context: context);
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat.yMMMd('en').format(DateTime.parse(msg.dateIso));
    final statusColor = _statusColor(context);
    final scheme = Theme.of(context).colorScheme;
    final custom = Theme.of(context).extension<QaydCustomColors>()!;

    final currency = CurrencyCode(
      code: msg.currencyCode,
      nameAr: CurrencyUtil.getLocalizedName(msg.currencyCode),
      symbol: msg.currencySymbol,
      fractionalDigits: msg.currencyDigits,
    );
    final money = Money.fromMinorUnits(msg.amountMinorUnits, currency);

    final alignment = _isIncoming
        ? AlignmentDirectional.centerStart
        : AlignmentDirectional.centerEnd;

    return Align(
      alignment: alignment,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: SpacingTokens.xs),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(RadiusTokens.lg),
                topEnd: const Radius.circular(RadiusTokens.lg),
                bottomStart: _isIncoming
                    ? const Radius.circular(RadiusTokens.xs)
                    : const Radius.circular(RadiusTokens.lg),
                bottomEnd: _isOutgoing
                    ? const Radius.circular(RadiusTokens.xs)
                    : const Radius.circular(RadiusTokens.lg),
              ),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Colored accent strip ──
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          statusColor,
                          statusColor.withValues(alpha: 0.40),
                        ],
                      ),
                    ),
                  ),

                  // ── Card content ──
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (msg.originVoucherId != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              SpacingTokens.md,
                              SpacingTokens.xs,
                              SpacingTokens.md,
                              0,
                            ),
                            child: InkWell(
                              onTap: () =>
                                  onOriginTap?.call(msg.originVoucherId!),
                              borderRadius: BorderRadius.circular(
                                RadiusTokens.sm,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.reply_rounded,
                                    size: 14,
                                    color: statusColor,
                                  ),
                                  SizedBox(width: SpacingTokens.xs),
                                  Expanded(
                                    child: Text(
                                      AppStrings.voucherReplyHeader,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: statusColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // ──── Header: type + badge + ticks ────
                        Container(
                          padding: const EdgeInsets.fromLTRB(
                            SpacingTokens.md,
                            SpacingTokens.sm + 2,
                            SpacingTokens.md,
                            SpacingTokens.sm,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.06),
                            border: Border(
                              bottom: BorderSide(
                                color: statusColor.withValues(alpha: 0.12),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Type icon in circle
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _typeIcon(),
                                  size: 14,
                                  color: statusColor,
                                ),
                              ),
                              SizedBox(width: SpacingTokens.sm),
                              // Type label & Other Party
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _typeLabel(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            color: statusColor,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.3,
                                          ),
                                    ),
                                    if (isUnified)
                                      Text(
                                        msg.otherPartyName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: statusColor.withValues(
                                                alpha: 0.7,
                                              ),
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              // Badge
                              _stateWidget(context),
                              SizedBox(width: SpacingTokens.xs),
                              // Ticks
                              Icon(
                                _ticksIcon(),
                                size: 15,
                                color: statusColor.withValues(alpha: 0.7),
                              ),
                            ],
                          ),
                        ),

                        // ──── Amount display ────
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SpacingTokens.md,
                            vertical: SpacingTokens.sm + 2,
                          ),
                          child: Row(
                            children: [
                              // Amount
                              Expanded(
                                child: QaydMoneyDisplay(
                                  money: money,
                                  size: QaydMoneyDisplaySize.large,
                                  displayNegative: false,
                                ),
                              ),
                              // Currency code chip
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: SpacingTokens.sm,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(
                                    RadiusTokens.xs,
                                  ),
                                ),
                                child: Text(
                                  CurrencyUtil.getLocalizedName(
                                    msg.currencyCode,
                                  ),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: statusColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ──── Description ────
                        if (msg.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              SpacingTokens.md,
                              0,
                              SpacingTokens.md,
                              SpacingTokens.sm,
                            ),
                            child: Text(
                              msg.description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                            ),
                          ),

                        // ──── Remittance Meta ────
                        if (msg.mediatorName != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              SpacingTokens.md,
                              0,
                              SpacingTokens.md,
                              SpacingTokens.sm,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: SpacingTokens.sm,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.tertiaryContainer.withValues(
                                  alpha: 0.3,
                                ),
                                borderRadius: BorderRadius.circular(
                                  RadiusTokens.sm,
                                ),
                                border: Border.all(
                                  color: scheme.tertiary.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.handshake_rounded,
                                    size: 14,
                                    color: scheme.tertiary,
                                  ),
                                  SizedBox(width: SpacingTokens.xs),
                                  Expanded(
                                    child: Text(
                                      '${AppStrings.statementMediatorPrefix}${msg.mediatorName}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onTertiaryContainer,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  if (msg.feeAmountMinorUnits != null &&
                                      msg.feeAmountMinorUnits! > 0) ...[
                                    Container(
                                      width: 1,
                                      height: 12,
                                      color: scheme.tertiary.withValues(
                                        alpha: 0.3,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: SpacingTokens.xs,
                                      ),
                                    ),
                                    Text(
                                      AppStrings.statementFeePrefix,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.tertiary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    QaydMoneyDisplay(
                                      money: Money.fromMinorUnits(
                                        msg.feeAmountMinorUnits!,
                                        currency,
                                      ),
                                      size: QaydMoneyDisplaySize.small,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                        // ──── Reversal indicator (shown when a corrective entry exists) ────
                        if (msg.reversalCount > 0)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              SpacingTokens.md,
                              0,
                              SpacingTokens.md,
                              SpacingTokens.xs,
                            ),
                            child: InkWell(
                              onTap: onReversalTap,
                              borderRadius: BorderRadius.circular(
                                RadiusTokens.sm,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: SpacingTokens.sm,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: ColorTokens.errorDeep.withValues(
                                    alpha: 0.06,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    RadiusTokens.sm,
                                  ),
                                  border: Border.all(
                                    color: ColorTokens.errorDeep.withValues(
                                      alpha: 0.22,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.published_with_changes_rounded,
                                      size: 13,
                                      color: ColorTokens.errorDeep,
                                    ),
                                    SizedBox(width: SpacingTokens.xs),
                                    Text(
                                      AppStrings.voucherReversalIndicator,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: ColorTokens.errorDeep,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    if (msg.reversalCount > 1) ...[
                                      SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: ColorTokens.errorDeep
                                              .withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            RadiusTokens.pill,
                                          ),
                                        ),
                                        child: Text(
                                          '×${msg.reversalCount}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: ColorTokens.errorDeep,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 9,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // ──── Footer: date + running balance ────
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SpacingTokens.md,
                            vertical: SpacingTokens.xs + 2,
                          ),
                          decoration: BoxDecoration(
                            color: custom.surfaceElevated.withValues(
                              alpha: 0.5,
                            ),
                            border: Border(
                              top: BorderSide(
                                color: custom.subtleBorder.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Date
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 11,
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              SizedBox(width: 4),
                              Text(
                                dateStr,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontSize: 10,
                                    ),
                              ),
                              const Spacer(),
                              // Running balance
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 11,
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              SizedBox(width: 4),
                              Text(
                                '${AppStrings.statementRunningBalance}: ',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant.withValues(
                                        alpha: 0.5,
                                      ),
                                      fontSize: 10,
                                    ),
                              ),
                              _BalanceAmountText(
                                minorUnits: msg.runningBalanceMinorUnits,
                                currencySymbol: CurrencyUtil.getLocalizedName(
                                  msg.currencyCode,
                                ),
                                currencyDigits: msg.currencyDigits,
                                fontSize: 10,
                              ),
                            ],
                          ),
                        ),

                        // ──── Action buttons ────
                        _actionArea(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _isDraft => msg.voucherStateCode == VoucherState.draft.name;
  bool get _isRejected =>
      msg.signatureStatusCode == AgreementStatus.rejected.name;

  Widget _actionArea(BuildContext context) {
    final custom = Theme.of(context).extension<QaydCustomColors>()!;

    // Only the Receiver (Counterparty) can Accept or Reject a pending voucher
    final showAcceptReject = !msg.isCreator && _isDraft && !_isRejected;

    // The Creator can withdraw their voucher as long as it is still a draft
    // (meaning the counterparty hasn't accepted it yet)
    final showWithdraw = msg.isCreator && _isDraft;

    // The Creator can only run the Corrective Resubmission flow (Resubmit)
    // if the counterparty explicitly rejected it
    final showResubmit = msg.isCreator && _isDraft && _isRejected;

    if (isUnified) return const SizedBox.shrink();
    if (!showAcceptReject && !showWithdraw && !showResubmit) {
      return const SizedBox.shrink();
    }

    final statusColor = _statusColor(context);

    if (showAcceptReject) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md,
          vertical: SpacingTokens.sm,
        ),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.04),
          border: Border(
            top: BorderSide(color: statusColor.withValues(alpha: 0.15)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: mutating
                    ? null
                    : () async => onAccept(msg.voucherId),
                icon: Icon(Icons.check_rounded, size: 16),
                label: Text(AppStrings.statementChatAccept),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: SpacingTokens.sm,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RadiusTokens.sm),
                  ),
                ),
              ),
            ),
            SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: mutating
                    ? null
                    : () async => onReject(msg.voucherId),
                icon: Icon(Icons.close_rounded, size: 16),
                label: Text(AppStrings.statementChatReject),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: SpacingTokens.sm,
                  ),
                  side: BorderSide(
                    color: ColorTokens.errorDeep.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RadiusTokens.sm),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.sm,
      ),
      decoration: BoxDecoration(
        color: custom.draftState.withValues(alpha: 0.04),
        border: Border(
          top: BorderSide(color: custom.draftState.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          if (showResubmit)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: mutating
                    ? null
                    : () async => onResubmit(msg.voucherId),
                icon: Icon(Icons.refresh_rounded, size: 16),
                label: Text(AppStrings.statementChatResubmit),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: SpacingTokens.sm,
                  ),
                  side: BorderSide(
                    color: custom.confirmedState.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RadiusTokens.sm),
                  ),
                ),
              ),
            ),
          if (showResubmit && showWithdraw) SizedBox(width: SpacingTokens.sm),
          if (showWithdraw)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: mutating
                    ? null
                    : () async => onWithdraw(msg.voucherId),
                icon: Icon(Icons.u_turn_right_rounded, size: 16),
                label: Text(AppStrings.statementChatWithdraw),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: SpacingTokens.sm,
                  ),
                  side: BorderSide(
                    color: ColorTokens.errorDeep.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RadiusTokens.sm),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PosCreditInvoiceBubble extends StatelessWidget {
  const _PosCreditInvoiceBubble({
    required this.msg,
    required this.mutating,
    required this.onAccept,
    required this.onReject,
    required this.onRetrySend,
    required this.onRetryAcknowledgment,
    required this.onTap,
  });

  final AccountStatementChatMessageDto msg;
  final bool mutating;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;
  final Future<void> Function() onRetrySend;
  final Future<void> Function(bool accepted) onRetryAcknowledgment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isIncoming = msg.direction == 'incoming';
    final acknowledgement = msg.posInvoiceAcknowledgmentStatus ?? 'pending';
    final delivery = msg.posInvoiceDeliveryStatus ?? 'queued';
    final isPending = acknowledgement == 'pending';
    final isPendingSync = acknowledgement.endsWith('_pending_sync');
    final scheme = Theme.of(context).colorScheme;
    final custom = Theme.of(context).extension<QaydCustomColors>()!;
    final statusColor = acknowledgement == 'rejected'
        ? ColorTokens.errorDeep
        : acknowledgement == 'accepted'
        ? custom.confirmedState
        : delivery == 'failed'
        ? ColorTokens.errorDeep
        : custom.draftState;
    final statusText = switch (acknowledgement) {
      'accepted' => AppStrings.posCreditInvoiceAccepted,
      'rejected' => AppStrings.posCreditInvoiceRejected,
      _ when isPendingSync => AppStrings.posCreditInvoiceResponsePendingSync,
      _ when !isIncoming && delivery == 'failed' =>
        AppStrings.posCreditInvoiceDeliveryFailed,
      _ when isIncoming => AppStrings.posCreditInvoiceNeedsResponse,
      _ => AppStrings.posCreditInvoiceAwaiting,
    };

    Widget? actions;
    if (isIncoming && isPending) {
      actions = Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: mutating ? null : onAccept,
              icon: const Icon(Icons.check_rounded, size: 16),
              label: Text(AppStrings.statementChatAccept),
            ),
          ),
          const SizedBox(width: SpacingTokens.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: mutating ? null : onReject,
              icon: const Icon(Icons.close_rounded, size: 16),
              label: Text(AppStrings.statementChatReject),
            ),
          ),
        ],
      );
    } else if (isIncoming && isPendingSync) {
      final accepted = acknowledgement.startsWith('accepted_');
      actions = OutlinedButton.icon(
        onPressed: mutating ? null : () => onRetryAcknowledgment(accepted),
        icon: const Icon(Icons.sync_rounded),
        label: Text(AppStrings.posCreditInvoiceRetryAck),
      );
    } else if (!isIncoming &&
        isPending &&
        (delivery == 'failed' || delivery == 'pending')) {
      actions = OutlinedButton.icon(
        onPressed: mutating ? null : onRetrySend,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(AppStrings.posCreditInvoiceRetrySend),
      );
    }

    return Align(
      alignment: isIncoming
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        child: Card(
          clipBehavior: Clip.antiAlias,
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RadiusTokens.lg),
            side: BorderSide(color: statusColor.withValues(alpha: 0.35)),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long_rounded, color: statusColor),
                      const SizedBox(width: SpacingTokens.sm),
                      Expanded(
                        child: Text(
                          AppStrings.posCreditInvoiceChatTitle,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '#${msg.posInvoiceNumber ?? ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppStrings.posInvoiceDueLabel,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      _BalanceAmountText(
                        minorUnits: msg.posInvoiceDueMinorUnits ?? 0,
                        currencySymbol: msg.currencySymbol,
                        currencyDigits: msg.currencyDigits,
                        fontSize: 14,
                      ),
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    statusText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (actions != null) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    actions,
                  ],
                  const SizedBox(height: SpacingTokens.xs),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      AppStrings.posCreditInvoiceOpenDetails,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: scheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PosCreditInvoiceDetailsSheet extends StatelessWidget {
  const _PosCreditInvoiceDetailsSheet({
    required this.snapshot,
    required this.onExportPdf,
  });

  final PosCreditInvoiceChatSnapshot snapshot;
  final Future<void> Function() onExportPdf;

  @override
  Widget build(BuildContext context) {
    final currency = snapshot.currency;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(SpacingTokens.lg),
        children: [
          Text(
            AppStrings.posCreditInvoiceChatTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text('#${snapshot.invoiceNumber}'),
          Text(DateFormat.yMMMd('en').format(snapshot.invoiceDate)),
          const SizedBox(height: SpacingTokens.sm),
          Container(
            padding: const EdgeInsets.all(SpacingTokens.sm),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(RadiusTokens.md),
            ),
            child: Text(AppStrings.posCreditInvoiceAcknowledgmentOnly),
          ),
          const SizedBox(height: SpacingTokens.md),
          for (final line in snapshot.lines)
            Card(
              child: ListTile(
                title: Text(line.productName),
                subtitle: Text(
                  '${line.quantity.toExactString()} × '
                  '${_displayMinor(line.unitPriceMinorUnits, currency)}',
                ),
                trailing: _BalanceAmountText(
                  minorUnits: line.lineTotalMinorUnits,
                  currencySymbol: currency.symbol,
                  currencyDigits: currency.fractionalDigits,
                  fontSize: 12,
                ),
              ),
            ),
          const Divider(),
          _invoiceAmountRow(
            context,
            AppStrings.posCheckoutSubtotal,
            snapshot.subtotalMinorUnits,
          ),
          _invoiceAmountRow(
            context,
            AppStrings.posCheckoutDiscountTotal,
            snapshot.discountMinorUnits,
          ),
          _invoiceAmountRow(
            context,
            AppStrings.posCreditInvoiceTaxLabel,
            snapshot.taxMinorUnits,
          ),
          _invoiceAmountRow(
            context,
            AppStrings.posCheckoutFinalTotal,
            snapshot.totalMinorUnits,
            strong: true,
          ),
          _invoiceAmountRow(
            context,
            AppStrings.posCreditInvoicePaidLabel,
            snapshot.paidMinorUnits,
          ),
          _invoiceAmountRow(
            context,
            AppStrings.posInvoiceDueLabel,
            snapshot.dueMinorUnits,
            strong: true,
          ),
          const SizedBox(height: SpacingTokens.md),
          FilledButton.icon(
            onPressed: onExportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(AppStrings.posInvoiceExportPdf),
          ),
        ],
      ),
    );
  }

  Widget _invoiceAmountRow(
    BuildContext context,
    String label,
    int amount, {
    bool strong = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong
                  ? Theme.of(context).textTheme.titleSmall
                  : Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          _BalanceAmountText(
            minorUnits: amount,
            currencySymbol: snapshot.currency.symbol,
            currencyDigits: snapshot.currency.fractionalDigits,
            fontSize: strong ? 14 : 12,
          ),
        ],
      ),
    );
  }

  String _displayMinor(int amount, CurrencyCode currency) {
    final digits = currency.fractionalDigits;
    final divisor = _powerOfTen(digits);
    return '${(amount / divisor).toStringAsFixed(digits)} ${currency.symbol}';
  }

  int _powerOfTen(int digits) {
    var value = 1;
    for (var index = 0; index < digits; index++) {
      value *= 10;
    }
    return value;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Shared Balance Amount Text ───────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _BalanceAmountText extends StatelessWidget {
  const _BalanceAmountText({
    required this.minorUnits,
    required this.currencySymbol,
    required this.currencyDigits,
    this.withCurrencySymbol = true,
    this.fontSize,
  });

  final int minorUnits;
  final String currencySymbol;
  final int currencyDigits;
  final bool withCurrencySymbol;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final custom = Theme.of(context).extension<QaydCustomColors>()!;
    final scheme = Theme.of(context).colorScheme;

    final isPositive = minorUnits > 0;
    final isNegative = minorUnits < 0;
    final color = isPositive
        ? ColorTokens.goldAccent
        : isNegative
        ? custom.credit
        : custom.confirmedState;

    num divisor = 1;
    for (var i = 0; i < currencyDigits; i++) {
      divisor *= 10;
    }
    final abs = minorUnits.abs();
    final major = abs / divisor;
    final formatted = major.toStringAsFixed(currencyDigits);

    final effectiveFontSize = fontSize ?? (12.0);
    return Text.rich(
      TextSpan(
        children: [
          buildNumericalScaledSpan(
            formatted,
            TextStyle(
              color: color,
              fontWeight: FontWeight.w800, //: FontWeight.w600,
              fontSize: effectiveFontSize,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (withCurrencySymbol)
            TextSpan(
              text: ' $currencySymbol',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
              // textAlign: TextAlign.center,
            ),
        ],
      ),
      // textDirection: TextDirection.ltr,
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.mode, required this.onChanged});

  final StatementChatViewMode mode;
  final ValueChanged<StatementChatViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.xs,
      ),
      child: SegmentedButton<StatementChatViewMode>(
        segments: [
          ButtonSegment<StatementChatViewMode>(
            value: StatementChatViewMode.myAccounts,
            label: Text(
              AppStrings.statementViewModeMy,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            icon: Icon(Icons.account_circle_outlined, size: 18),
          ),
          ButtonSegment<StatementChatViewMode>(
            value: StatementChatViewMode.otherPartyAccounts,
            label: Text(
              AppStrings.statementViewModeOther,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            icon: Icon(Icons.people_alt_outlined, size: 18),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (set) => onChanged(set.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: WidgetStateProperty.all(
            BorderSide(color: scheme.outline.withOpacity(0.2)),
          ),
        ),
      ),
    );
  }
}
