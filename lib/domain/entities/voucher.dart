import 'package:qayd/domain/exceptions/immutable_entity_exception.dart';
import 'package:qayd/domain/exceptions/invalid_amount_exception.dart';
import 'package:qayd/domain/exceptions/invalid_voucher_transition_exception.dart';
import 'package:qayd/domain/exceptions/self_canceling_entry_exception.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/attachment_ref.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/tripartite_meta.dart';
import 'package:qayd/domain/value_objects/agreement_status.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_lifecycle.dart';
import 'package:qayd/domain/value_objects/voucher_state.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Receipt or payment document with strict draft → confirmed → settled lifecycle.
///
/// Separation of concerns:
/// - [state] (VoucherState): Tracks the creator's workflow (Draft vs Confirmed).
/// - [agreementStatus] (AgreementStatus): Tracks the digital signature agreement (Accepted, Pending/UnderRequest, Rejected).
///
/// Threaded Financial Interactions:
/// - [originVoucherId]: Links reversals, corrections, and settlements back to the source voucher.
/// - [rejectionReason]: Stores the reason when a voucher is rejected by the counterparty.
/// - [withdrawnAt]: Timestamp when a voucher was withdrawn (non-destructive retraction).
class Voucher {
  const Voucher._({
    required this.id,
    required this.type,
    required this.referenceNumber,
    required this.date,
    required this.amount,
    required this.currency,
    required this.counterpartyId,
    required this.affectedAccountId,
    required this.state,
    required this.description,
    required this.attachmentRefs,
    required this.notes,
    required this.tags,
    required this.createdAt,
    required this.confirmedAt,
    required this.settledAt,
    required this.senderStatus,
    required this.receiverStatus,
    this.senderSignatureHex,
    this.receiverSignatureHex,
    this.senderPublicKeyHex,
    this.receiverPublicKeyHex,
    required this.lifecycleStatus,
    required this.signerPhone,
    this.canonicalSenderPhone,
    this.canonicalReceiverPhone,
    required this.tripartiteMeta,
    required this.originVoucherId,
    required this.rejectionReason,
    required this.withdrawnAt,
    this.reversalCount = 0,
    this.firstChildId,
    this.isInbound = false,
  });

  final VoucherId id;
  final VoucherType type;
  final String? referenceNumber;
  final DateTime date;
  final Money amount;
  final CurrencyCode currency;
  final AccountId counterpartyId;
  final AccountId affectedAccountId;

  /// Creator's validation state (Draft: mutable/internal, Confirmed: entries recorded).
  final VoucherState state;
  final String? description;
  final List<AttachmentRef> attachmentRefs;
  final String? notes;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final DateTime? settledAt;

  // ── Digital signature fields (Dual Party Protocol v2.0) ─────────────────

  /// Status of the sending party (usually Accepted upon creation).
  final AgreementStatus senderStatus;

  /// Status of the receiving party (UnderRequest, Accepted, or Rejected).
  final AgreementStatus receiverStatus;

  /// Ed25519 signature hex of the sender.
  final String? senderSignatureHex;

  /// Ed25519 signature hex of the receiver.
  final String? receiverSignatureHex;

  /// Public key of the sender.
  final String? senderPublicKeyHex;

  /// Public key of the receiver.
  final String? receiverPublicKeyHex;

  /// High-level lifecycle representing the document's journey.
  final VoucherLifecycle lifecycleStatus;

  /// Phone number of the counterparty (for discovery/matching).
  final String? signerPhone;

  // ── Canonical Signature Phones (Protocol v2.1) ──────────────────────────

  /// The sender's phone number **at the time of signing** (Party A).
  /// Frozen on first signature and never overwritten by subsequent operations.
  /// Used to reconstruct the canonical payload for integrity verification.
  final String? canonicalSenderPhone;

  /// The receiver's phone number **at the time of signing** (Party B).
  /// Frozen on first signature and never overwritten by subsequent operations.
  /// Used to reconstruct the canonical payload for integrity verification.
  final String? canonicalReceiverPhone;

  // ── Tripartite transfer fields ──────────────────────────────────────────

  /// Present only on vouchers created through the intermediary transfer flow.
  /// Links receipt (A→C) and payment (C→B) via a shared transfer group.
  final TripartiteMeta? tripartiteMeta;

  // ── Threaded Financial Interactions fields (Protocol v1.3) ──────────────

  /// UUID of the parent voucher for reversals, corrections, and settlements.
  /// Enables the "Reply" mechanism: any voucher carrying this field is a
  /// follow-up to the original voucher, rendered with a reply header in the UI.
  final VoucherId? originVoucherId;

  /// Reason provided when the counterparty rejects a voucher.
  /// Used for "Corrective Resubmission" flow — the creator sees this reason
  /// and can edit the draft before re-syncing.
  final String? rejectionReason;

  /// Timestamp when the voucher was withdrawn (non-destructive retraction).
  /// The record remains in the database for audit but is flagged as withdrawn.
  final DateTime? withdrawnAt;

  // ── UI-only metadata for navigation/threaded view ─────────────────────

  /// Number of reversals/settlements linked back to this voucher.
  final int reversalCount;

  /// ID of the first reversal/settlement child for jump-to navigation.
  final VoucherId? firstChildId;

  // ── Inbound-sync flag (Protocol §5 — Migration 037) ────────────────────

  /// `true` when this voucher arrived via a [SyncEventType.claim] event
  /// (i.e. was created by the counterparty and pushed to us).
  ///
  /// `false` (default) for vouchers the local user created themselves.
  ///
  /// This is the canonical source of truth for the chat UI's [isCreator] flag.
  final bool isInbound;

  // ── Computed helpers ───────────────────────────────────────────────────

  bool get hasSignature =>
      senderSignatureHex != null || receiverSignatureHex != null;

  /// Whether this voucher is part of a tripartite intermediary transfer.
  bool get isTripartite => tripartiteMeta != null;

  /// Whether this voucher is locked pending its parent's confirmation.
  bool get isContingent => tripartiteMeta?.isContingent ?? false;

  bool get isReceipt => type == VoucherType.receipt;
  bool get isPayment => type == VoucherType.payment;
  bool get isReply => originVoucherId != null;
  bool get isWithdrawn => state == VoucherState.withdrawn;

  /// Whether the voucher can be withdrawn by its creator.
  /// Allowed if it's a draft, OR if it's confirmed but the counterparty hasn't accepted it yet.
  bool get canWithdraw {
    if (state.isSettled || state.isWithdrawn) return false;
    if (state.isDraft) return true;
    return receiverStatus != AgreementStatus.accepted;
  }

  /// Rehydrates a voucher from persistence (data layer); not for new business creates.
  factory Voucher.restore({
    required VoucherId id,
    required VoucherType type,
    String? referenceNumber,
    required DateTime date,
    required Money amount,
    required CurrencyCode currency,
    required AccountId counterpartyId,
    required AccountId affectedAccountId,
    required VoucherState state,
    String? description,
    List<AttachmentRef> attachmentRefs = const [],
    String? notes,
    List<String> tags = const [],
    required DateTime createdAt,
    DateTime? confirmedAt,
    DateTime? settledAt,
    AgreementStatus senderStatus = AgreementStatus.accepted,
    AgreementStatus receiverStatus = AgreementStatus.underRequest,
    String? senderSignatureHex,
    String? receiverSignatureHex,
    String? senderPublicKeyHex,
    String? receiverPublicKeyHex,
    VoucherLifecycle lifecycleStatus = VoucherLifecycle.draft,
    String? signerPhone,
    String? canonicalSenderPhone,
    String? canonicalReceiverPhone,
    TripartiteMeta? tripartiteMeta,
    VoucherId? originVoucherId,
    String? rejectionReason,
    DateTime? withdrawnAt,
    int reversalCount = 0,
    VoucherId? firstChildId,
    bool isInbound = false,
  }) {
    return Voucher._(
      id: id,
      type: type,
      referenceNumber: referenceNumber,
      date: date,
      amount: amount,
      currency: currency,
      counterpartyId: counterpartyId,
      affectedAccountId: affectedAccountId,
      state: state,
      description: description,
      attachmentRefs: List.unmodifiable(attachmentRefs),
      notes: notes,
      tags: List.unmodifiable(tags),
      createdAt: createdAt,
      confirmedAt: confirmedAt,
      settledAt: settledAt,
      senderStatus: senderStatus,
      receiverStatus: receiverStatus,
      senderSignatureHex: senderSignatureHex,
      receiverSignatureHex: receiverSignatureHex,
      senderPublicKeyHex: senderPublicKeyHex,
      receiverPublicKeyHex: receiverPublicKeyHex,
      lifecycleStatus: lifecycleStatus,
      signerPhone: signerPhone,
      canonicalSenderPhone: canonicalSenderPhone,
      canonicalReceiverPhone: canonicalReceiverPhone,
      tripartiteMeta: tripartiteMeta,
      originVoucherId: originVoucherId,
      rejectionReason: rejectionReason,
      withdrawnAt: withdrawnAt,
      reversalCount: reversalCount,
      firstChildId: firstChildId,
      isInbound: isInbound,
    );
  }

  /// New business create.
  ///
  /// Policy:
  /// - Payments (الصرف) are "Accepted" by default because the creator is the signer (the payer).
  /// - Receipts (القبض) are "Under Request" because they require the counterparty's signature.
  factory Voucher.draft({
    required VoucherId id,
    required VoucherType type,
    required DateTime date,
    required Money amount,
    required CurrencyCode currency,
    required AccountId counterpartyId,
    required AccountId affectedAccountId,
    required DateTime createdAt,
    String? referenceNumber,
    String? description,
    List<AttachmentRef> attachmentRefs = const [],
    String? notes,
    List<String> tags = const [],
    String? senderSignatureHex,
    String? senderPublicKeyHex,
    String? receiverSignatureHex,
    String? receiverPublicKeyHex,
    String? signerPhone,
    String? canonicalSenderPhone,
    String? canonicalReceiverPhone,
    TripartiteMeta? tripartiteMeta,
    VoucherId? originVoucherId,
  }) {
    if (counterpartyId == affectedAccountId) {
      throw SelfCancelingEntryException(
        messageAr: AppStrings.theAffectedPartyAnd,
        code: 'voucher_self_counterparty',
      );
    }
    if (amount.isZero) {
      throw InvalidAmountException(
        messageAr: AppStrings.theBondAmountMust,
        code: 'voucher_amount_zero',
      );
    }

    // Policy v2.0:
    // Creating the voucher constitutes implicit approval by the sender.
    // Documentation completion requires the receiver's signature.
    final senderStatus = senderSignatureHex != null
        ? AgreementStatus.accepted
        : AgreementStatus.accepted;
    // Wait, if I am creating it, I am the sender, so I accept it by default.
    final receiverStatus = receiverSignatureHex != null
        ? AgreementStatus.accepted
        : AgreementStatus.underRequest;
    const lifecycleStatus = VoucherLifecycle.draft;

    return Voucher._(
      id: id,
      type: type,
      referenceNumber: referenceNumber,
      date: date,
      amount: amount,
      currency: currency,
      counterpartyId: counterpartyId,
      affectedAccountId: affectedAccountId,
      state: VoucherState.draft,
      description: description,
      attachmentRefs: List.unmodifiable(attachmentRefs),
      notes: notes,
      tags: List.unmodifiable(tags),
      createdAt: createdAt,
      confirmedAt: null,
      settledAt: null,
      senderStatus: senderStatus,
      receiverStatus: receiverStatus,
      senderSignatureHex: senderSignatureHex,
      receiverSignatureHex: receiverSignatureHex,
      senderPublicKeyHex: senderPublicKeyHex,
      receiverPublicKeyHex: receiverPublicKeyHex,
      lifecycleStatus: lifecycleStatus,
      signerPhone: signerPhone,
      canonicalSenderPhone: canonicalSenderPhone,
      canonicalReceiverPhone: canonicalReceiverPhone,
      tripartiteMeta: tripartiteMeta,
      originVoucherId: originVoucherId,
      rejectionReason: null,
      withdrawnAt: null,
    );
  }

  Voucher confirm(DateTime confirmedAt) {
    if (!state.isDraft) {
      throw InvalidVoucherTransitionException(
        messageAr: AppStrings.theBondCanOnly,
        from: state,
        to: VoucherState.confirmed,
      );
    }
    return _copyWith(
      state: VoucherState.confirmed,
      confirmedAt: confirmedAt,
    );
  }

  Voucher settle(DateTime settledAt) {
    if (!state.isConfirmed) {
      throw InvalidVoucherTransitionException(
        messageAr: AppStrings.theBondCanBe,
        from: state,
        to: VoucherState.settled,
      );
    }
    return _copyWith(
      state: VoucherState.settled,
      settledAt: settledAt,
    );
  }

  /// Withdraws a voucher (non-destructive retraction).
  /// Available only from Draft, UnderRequest, or Rejected agreement states.
  /// The record remains in the database for audit integrity.
  Voucher withdraw(DateTime withdrawnAt) {
    if (!canWithdraw) {
      throw InvalidVoucherTransitionException(
        messageAr: AppStrings.theBondCannotBe1,
        from: state,
        to: VoucherState.withdrawn,
      );
    }
    return _copyWith(
      state: VoucherState.withdrawn,
      withdrawnAt: withdrawnAt,
    );
  }

  /// Release the contingent lock on this voucher (for tripartite flows).
  Voucher releaseContingency() {
    if (tripartiteMeta == null) return this;
    return _copyWith(
      tripartiteMeta: tripartiteMeta!.release(),
    );
  }

  /// Attaches a cryptographic signature to a voucher from either party.
  ///
  /// [canonicalSenderPhone] and [canonicalReceiverPhone] are frozen on the
  /// **first** call (i.e. when the sender signs). Subsequent calls (receiver)
  /// must NOT overwrite them so the payload remains reconstructible.
  Voucher attachSignature({
    required String signatureHex,
    required String publicKeyHex,
    required bool isSender,
    required AgreementStatus status,
    String? signerPhone,
    String? canonicalSenderPhone,
    String? canonicalReceiverPhone,
  }) {
    return _copyWith(
      senderSignatureHex: isSender ? signatureHex : senderSignatureHex,
      receiverSignatureHex: !isSender ? signatureHex : receiverSignatureHex,
      senderPublicKeyHex: isSender ? publicKeyHex : senderPublicKeyHex,
      receiverPublicKeyHex: !isSender ? publicKeyHex : receiverPublicKeyHex,
      senderStatus: isSender ? status : senderStatus,
      receiverStatus: !isSender ? status : receiverStatus,
      signerPhone: signerPhone ?? this.signerPhone,
      // Freeze canonical phones on first write; never overwrite if already set.
      canonicalSenderPhone: this.canonicalSenderPhone ?? canonicalSenderPhone,
      canonicalReceiverPhone:
          this.canonicalReceiverPhone ?? canonicalReceiverPhone,
    );
  }

  /// Attaches a rejection reason from the counterparty.
  Voucher attachRejection({
    required String reason,
    required AgreementStatus status,
  }) {
    return _copyWith(
      receiverStatus: status,
      rejectionReason: reason,
      lifecycleStatus: VoucherLifecycle.rejected,
    );
  }

  Voucher updateDraft({
    VoucherType? type,
    String? referenceNumber,
    DateTime? date,
    Money? amount,
    CurrencyCode? currency,
    AccountId? counterpartyId,
    AccountId? affectedAccountId,
    String? description,
    List<AttachmentRef>? attachmentRefs,
    String? notes,
    List<String>? tags,
  }) {
    final canEdit = state.isDraft ||
        state.isWithdrawn ||
        receiverStatus == AgreementStatus.rejected;
    if (!canEdit) {
      throw ImmutableEntityException(
        messageAr: AppStrings.theInstrumentCannotBe,
        code: 'voucher_not_editable',
      );
    }
    final nextType = type ?? this.type;
    final nextDate = date ?? this.date;
    final nextCurrency = currency ?? this.currency;

    var nextAmount = amount ?? this.amount;
    if (nextCurrency != nextAmount.currency) {
      nextAmount = Money.positiveAmount(nextAmount.minorUnits, nextCurrency);
    }

    final nextCounterparty = counterpartyId ?? this.counterpartyId;
    final nextAffected = affectedAccountId ?? this.affectedAccountId;
    if (nextCounterparty == nextAffected) {
      throw SelfCancelingEntryException(
        messageAr: AppStrings.theAffectedPartyAnd,
        code: 'voucher_self_counterparty',
      );
    }
    if (nextAmount.isZero) {
      throw InvalidAmountException(
        messageAr: AppStrings.theBondAmountMust,
        code: 'voucher_amount_zero',
      );
    }
    return Voucher._(
      id: id,
      type: nextType,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      date: nextDate,
      amount: nextAmount,
      currency: nextCurrency,
      counterpartyId: nextCounterparty,
      affectedAccountId: nextAffected,
      state: VoucherState.draft,
      description: description ?? this.description,
      attachmentRefs: List.unmodifiable(attachmentRefs ?? this.attachmentRefs),
      notes: notes ?? this.notes,
      tags: List.unmodifiable(tags ?? this.tags),
      createdAt: createdAt,
      confirmedAt: null,
      settledAt: settledAt,
      senderStatus: AgreementStatus.accepted,
      receiverStatus: AgreementStatus.underRequest,
      senderSignatureHex: null,
      receiverSignatureHex: null,
      senderPublicKeyHex: null,
      receiverPublicKeyHex: null,
      lifecycleStatus: VoucherLifecycle.draft,
      signerPhone: signerPhone,
      tripartiteMeta: tripartiteMeta,
      originVoucherId: originVoucherId,
      rejectionReason: null,
      withdrawnAt: null,
    );
  }

  void assertDraftDeletionAllowed() {
    if (!state.isDraft) {
      throw ImmutableEntityException(
        messageAr: AppStrings.bondsCanBeDeleted,
        code: 'voucher_delete_not_draft',
      );
    }
  }

  void assertMutableForAccountingSideEffects() {
    if (state.isSettled) {
      throw ImmutableEntityException(
        messageAr: AppStrings.aSettledBondIs,
        code: 'voucher_settled_immutable',
      );
    }
  }

  /// Internal copy-with helper to reduce boilerplate in state transitions.
  Voucher _copyWith({
    VoucherState? state,
    DateTime? confirmedAt,
    DateTime? settledAt,
    DateTime? withdrawnAt,
    AgreementStatus? senderStatus,
    AgreementStatus? receiverStatus,
    String? senderSignatureHex,
    String? receiverSignatureHex,
    String? senderPublicKeyHex,
    String? receiverPublicKeyHex,
    VoucherLifecycle? lifecycleStatus,
    String? signerPhone,
    String? canonicalSenderPhone,
    String? canonicalReceiverPhone,
    String? rejectionReason,
    TripartiteMeta? tripartiteMeta,
    VoucherId? originVoucherId,
  }) {
    return Voucher._(
      id: id,
      type: type,
      referenceNumber: referenceNumber,
      date: date,
      amount: amount,
      currency: currency,
      counterpartyId: counterpartyId,
      affectedAccountId: affectedAccountId,
      state: state ?? this.state,
      description: description,
      attachmentRefs: attachmentRefs,
      notes: notes,
      tags: tags,
      createdAt: createdAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      settledAt: settledAt ?? this.settledAt,
      senderStatus: senderStatus ?? this.senderStatus,
      receiverStatus: receiverStatus ?? this.receiverStatus,
      senderSignatureHex: senderSignatureHex ?? this.senderSignatureHex,
      receiverSignatureHex: receiverSignatureHex ?? this.receiverSignatureHex,
      senderPublicKeyHex: senderPublicKeyHex ?? this.senderPublicKeyHex,
      receiverPublicKeyHex: receiverPublicKeyHex ?? this.receiverPublicKeyHex,
      lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
      signerPhone: signerPhone ?? this.signerPhone,
      canonicalSenderPhone: canonicalSenderPhone ?? this.canonicalSenderPhone,
      canonicalReceiverPhone:
          canonicalReceiverPhone ?? this.canonicalReceiverPhone,
      tripartiteMeta: tripartiteMeta ?? this.tripartiteMeta,
      originVoucherId: originVoucherId ?? this.originVoucherId,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      withdrawnAt: withdrawnAt ?? this.withdrawnAt,
      // isInbound is immutable — once set by the sync layer it never changes.
      isInbound: isInbound,
    );
  }
}
