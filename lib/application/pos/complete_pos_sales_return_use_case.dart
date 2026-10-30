import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:qayd/application/pos/build_pos_sales_return_posting_use_case.dart';
import 'package:qayd/application/pos/post_pos_sales_return_atomically_use_case.dart';
import 'package:qayd/application/pos/sign_pos_invoice_use_case.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';
import 'package:qayd/domain/entities/pos_sales_return_request_identity.dart';
import 'package:qayd/domain/repositories/pos_invoice_read_repository.dart';
import 'package:qayd/domain/repositories/pos_sales_return_request_identity_repository.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Complete application boundary for an atomic POS sales return/full void.
final class CompletePosSalesReturnUseCase {
  const CompletePosSalesReturnUseCase({
    required BuildPosSalesReturnPostingUseCase buildPosting,
    required PostPosSalesReturnAtomicallyUseCase postAtomically,
    required SignPosInvoiceUseCase signInvoice,
    required PosInvoiceReadRepository invoiceRepository,
    required PosSalesReturnRequestIdentityRepository requestIdentityRepository,
  })  : _buildPosting = buildPosting,
        _postAtomically = postAtomically,
        _signInvoice = signInvoice,
        _invoices = invoiceRepository,
        _requestIdentities = requestIdentityRepository;

  final BuildPosSalesReturnPostingUseCase _buildPosting;
  final PostPosSalesReturnAtomicallyUseCase _postAtomically;
  final SignPosInvoiceUseCase _signInvoice;
  final PosInvoiceReadRepository _invoices;
  final PosSalesReturnRequestIdentityRepository _requestIdentities;

  Future<Result<PosInvoice>> call(
    BuildPosSalesReturnPostingInput input,
  ) async {
    final fingerprintHash = _fingerprintHash(input);
    final identityResult = await _requestIdentities.getOrCreate(
      fingerprintHash: fingerprintHash,
      candidate: PosSalesReturnRequestIdentity(
        invoiceId: input.returnInvoiceId,
        idempotencyKey: input.idempotencyKey,
        createdAt: input.createdAt,
      ),
    );
    if (identityResult.isFailure) {
      return FailureResult(identityResult.failureOrNull!);
    }
    final identity = identityResult.valueOrNull!;
    final stableInput = _withIdentity(input, identity);

    final existingResult = await _invoices.getById(stableInput.returnInvoiceId);
    if (existingResult.isFailure) {
      return FailureResult(existingResult.failureOrNull!);
    }
    final existing = existingResult.valueOrNull;
    if (existing != null) {
      final recovered = await _recoverIfExact(existing.invoice, stableInput);
      if (recovered.isFailure) return FailureResult(recovered.failureOrNull!);
      if (!recovered.valueOrNull!) return _invalid();
      return _acknowledgeAndReturn(
        existing.invoice,
        fingerprintHash: fingerprintHash,
        identity: identity,
      );
    }

    final buildResult = await _buildPosting(stableInput);
    if (buildResult.isFailure) return FailureResult(buildResult.failureOrNull!);
    final posting = buildResult.valueOrNull!;
    final signedResult = await _signInvoice(
      invoice: posting.invoice,
      payments: posting.refundPayments,
      signedAt: stableInput.createdAt,
    );
    if (signedResult.isFailure) {
      return FailureResult(signedResult.failureOrNull!);
    }
    final signedPosting = PosSalesReturnPosting(
      invoice: signedResult.valueOrNull!,
      sourceInvoiceId: posting.sourceInvoiceId,
      salesReturnsAccountId: posting.salesReturnsAccountId,
      inventoryAccountId: posting.inventoryAccountId,
      costOfGoodsSoldAccountId: posting.costOfGoodsSoldAccountId,
      movements: posting.movements,
      postings: posting.postings,
      refundPayments: posting.refundPayments,
      voidSource: posting.voidSource,
      reason: posting.reason,
    );
    final commitResult = await _postAtomically(signedPosting);
    if (commitResult.isFailure) return FailureResult(commitResult.failureOrNull!);
    return _acknowledgeAndReturn(
      signedPosting.invoice,
      fingerprintHash: fingerprintHash,
      identity: identity,
    );
  }

  BuildPosSalesReturnPostingInput _withIdentity(
    BuildPosSalesReturnPostingInput input,
    PosSalesReturnRequestIdentity identity,
  ) {
    final id = identity.invoiceId.trim();
    final shortId = id.length > 8 ? id.substring(0, 8) : id;
    final timestamp = identity.createdAt.toUtc();
    return BuildPosSalesReturnPostingInput(
      returnInvoiceId: id,
      returnInvoiceNumber: 'R-$shortId',
      sourceInvoiceId: input.sourceInvoiceId.trim(),
      idempotencyKey: identity.idempotencyKey.trim(),
      lines: List.unmodifiable(input.lines),
      invoiceDate: timestamp,
      createdAt: timestamp,
      reason: input.reason?.trim(),
      voidSource: input.voidSource,
    );
  }

  String _fingerprintHash(BuildPosSalesReturnPostingInput input) {
    final lines = [...input.lines]
      ..sort((left, right) =>
          left.sourceLineId.trim().compareTo(right.sourceLineId.trim()));
    final canonical = jsonEncode({
      'source_invoice_id': input.sourceInvoiceId.trim(),
      'void_source': input.voidSource,
      'reason': input.reason?.trim() ?? '',
      'lines': lines
          .map((line) => {
                'source_line_id': line.sourceLineId.trim(),
                'quantity_scaled': line.quantity.scaledUnits,
                'quantity_scale': line.quantity.scale,
              })
          .toList(growable: false),
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  Future<Result<PosInvoice>> _acknowledgeAndReturn(
    PosInvoice invoice, {
    required String fingerprintHash,
    required PosSalesReturnRequestIdentity identity,
  }) async {
    final acknowledgement = await _requestIdentities.acknowledgeCommitted(
      fingerprintHash: fingerprintHash,
      identity: identity,
    );
    if (acknowledgement.isFailure) {
      return FailureResult(acknowledgement.failureOrNull!);
    }
    return Success(invoice);
  }

  Future<Result<bool>> _recoverIfExact(
    PosInvoice invoice,
    BuildPosSalesReturnPostingInput input,
  ) async {
    if (invoice.type != PosInvoiceType.salesReturn ||
        invoice.status != PosDocumentStatus.paid ||
        invoice.signature == null ||
        invoice.id != input.returnInvoiceId.trim() ||
        invoice.idempotencyKey != input.idempotencyKey.trim() ||
        invoice.sourceInvoiceId != input.sourceInvoiceId.trim()) {
      return const Success(false);
    }
    final sourceResult = await _invoices.getById(input.sourceInvoiceId);
    if (sourceResult.isFailure) return FailureResult(sourceResult.failureOrNull!);
    final source = sourceResult.valueOrNull?.invoice;
    if (source == null) return const Success(false);

    final stored = <String, PosQuantity>{};
    for (final line in invoice.lines) {
      final sourceLineId = line.sourceLineId;
      if (sourceLineId == null || stored.containsKey(sourceLineId)) {
        return const Success(false);
      }
      stored[sourceLineId] = line.quantity;
    }
    if (input.voidSource) {
      if (source.status != PosDocumentStatus.voided ||
          stored.length != source.lines.length) return const Success(false);
      return Success(source.lines.every((line) {
        final quantity = stored[line.id];
        return quantity != null &&
            quantity.scale == line.quantity.scale &&
            quantity.scaledUnits == line.quantity.scaledUnits;
      }));
    }
    if (!source.status.isReturned || input.lines.length != stored.length) {
      return const Success(false);
    }
    final requested = <String, PosQuantity>{};
    for (final line in input.lines) {
      final id = line.sourceLineId.trim();
      if (id.isEmpty || requested.containsKey(id)) return const Success(false);
      requested[id] = line.quantity;
    }
    return Success(requested.length == stored.length &&
        requested.entries.every((entry) {
          final quantity = stored[entry.key];
          return quantity != null &&
              quantity.scale == entry.value.scale &&
              quantity.scaledUnits == entry.value.scaledUnits;
        }));
  }

  FailureResult<PosInvoice> _invalid() => FailureResult(
        ValidationFailure(messageAr: AppStrings.posInvoiceInvalid),
      );
}
