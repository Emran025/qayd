import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:qayd/application/pos/build_pos_invoice_payment_collection_use_case.dart';
import 'package:qayd/application/pos/post_pos_invoice_payment_collection_atomically_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/core/utils/id_generator.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_payment_collection_request_identity.dart';
import 'package:qayd/domain/repositories/pos_invoice_read_repository.dart';
import 'package:qayd/domain/repositories/pos_payment_collection_request_identity_repository.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class CompletePosInvoicePaymentCollectionInput {
  const CompletePosInvoicePaymentCollectionInput({
    required this.invoiceId,
    required this.amountMinorUnits,
    required this.currency,
    required this.paymentAccountId,
    required this.paymentMethod,
    required this.occurredAt,
  });

  final String invoiceId;
  final int amountMinorUnits;
  final CurrencyCode currency;
  final AccountId paymentAccountId;
  final PosPaymentMethod paymentMethod;
  final DateTime occurredAt;
}

/// Durable application boundary for later POS invoice collections.
final class CompletePosInvoicePaymentCollectionUseCase {
  const CompletePosInvoicePaymentCollectionUseCase({
    required BuildPosInvoicePaymentCollectionUseCase buildPosting,
    required PostPosInvoicePaymentCollectionAtomicallyUseCase postAtomically,
    required PosInvoiceReadRepository invoiceRepository,
    required PosPaymentCollectionRequestIdentityRepository identityRepository,
    required IdGenerator idGenerator,
  })  : _buildPosting = buildPosting,
        _postAtomically = postAtomically,
        _invoiceRepository = invoiceRepository,
        _identityRepository = identityRepository,
        _idGenerator = idGenerator;

  final BuildPosInvoicePaymentCollectionUseCase _buildPosting;
  final PostPosInvoicePaymentCollectionAtomicallyUseCase _postAtomically;
  final PosInvoiceReadRepository _invoiceRepository;
  final PosPaymentCollectionRequestIdentityRepository _identityRepository;
  final IdGenerator _idGenerator;

  Future<Result<PosInvoice>> call(
    CompletePosInvoicePaymentCollectionInput input,
  ) async {
    if (input.invoiceId.trim().isEmpty || input.amountMinorUnits <= 0) {
      return _invalid('pos_collection_input_invalid');
    }
    final fingerprintHash = _fingerprintHash(input);
    final now = DateTime.now().toUtc();
    final identityResult = await _identityRepository.getOrCreate(
      fingerprintHash: fingerprintHash,
      candidate: PosPaymentCollectionRequestIdentity(
        paymentId: _idGenerator.next(),
        idempotencyKey: 'pos-payment-collection:${_idGenerator.next()}',
        createdAt: now,
        occurredAt: input.occurredAt,
      ),
    );
    if (identityResult.isFailure) {
      return FailureResult(identityResult.failureOrNull!);
    }
    final identity = identityResult.valueOrNull!;
    final postingResult = await _buildPosting(
      BuildPosInvoicePaymentCollectionInput(
        invoiceId: input.invoiceId.trim(),
        amountMinorUnits: input.amountMinorUnits,
        currencyCode: input.currency.code,
        paymentAccountId: input.paymentAccountId,
        paymentMethod: input.paymentMethod,
        paymentId: identity.paymentId,
        idempotencyKey: identity.idempotencyKey,
        occurredAt: identity.occurredAt,
        createdAt: identity.createdAt,
      ),
    );
    if (postingResult.isFailure) {
      final failure = postingResult.failureOrNull!;
      if (failure is ValidationFailure &&
          failure.code == 'pos_collection_date_before_invoice') {
        final discarded = await _identityRepository.discardUncommitted(
          fingerprintHash: fingerprintHash,
          identity: identity,
        );
        if (discarded.isFailure) {
          return FailureResult(discarded.failureOrNull!);
        }
      }
      return FailureResult(failure);
    }
    final commitResult = await _postAtomically(postingResult.valueOrNull!);
    if (commitResult.isFailure) {
      final failure = commitResult.failureOrNull!;
      if (failure is ValidationFailure &&
          failure.code == 'pos_collection_closed_fiscal_period') {
        final discarded = await _identityRepository.discardUncommitted(
          fingerprintHash: fingerprintHash,
          identity: identity,
        );
        if (discarded.isFailure) {
          return FailureResult(discarded.failureOrNull!);
        }
      }
      return FailureResult(failure);
    }

    // Read the committed projection before deleting the retry identity. If this
    // read or the acknowledgement fails, the same request remains recoverable.
    final currentResult =
        await _invoiceRepository.getById(input.invoiceId.trim());
    if (currentResult.isFailure) {
      return FailureResult(currentResult.failureOrNull!);
    }
    final current = currentResult.valueOrNull;
    if (current == null) return _invalid('pos_collection_invoice_missing');

    final acknowledgement = await _identityRepository.acknowledgeCommitted(
      fingerprintHash: fingerprintHash,
      identity: identity,
    );
    if (acknowledgement.isFailure) {
      return FailureResult(acknowledgement.failureOrNull!);
    }
    return Success(current.invoice);
  }

  String _fingerprintHash(CompletePosInvoicePaymentCollectionInput input) {
    // Collection date/time is restored from the retained identity on retry;
    // changing the amount, invoice, method, currency, or receiving account
    // creates a distinct request fingerprint.
    final canonical = jsonEncode({
      'invoice_id': input.invoiceId.trim(),
      'amount_minor': input.amountMinorUnits,
      'currency_code': input.currency.code,
      'payment_account_id': input.paymentAccountId.value,
      'payment_method': input.paymentMethod.name,
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  FailureResult<PosInvoice> _invalid(String code) => FailureResult(
        ValidationFailure(
          messageAr: AppStrings.posInvoicePaymentInvalid,
          code: code,
        ),
      );
}
