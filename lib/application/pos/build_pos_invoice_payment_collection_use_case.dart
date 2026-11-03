import 'package:qayd/application/failure_mapping.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/pos_accounting_posting.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_invoice_details.dart';
import 'package:qayd/domain/entities/pos_invoice_payment.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
import 'package:qayd/domain/entities/voucher.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/pos_invoice_read_repository.dart';
import 'package:qayd/domain/services/entry_generator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/account_nature.dart';
import 'package:qayd/domain/value_objects/entry_id.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_date.dart';
import 'package:qayd/domain/value_objects/standard_account_classification_kind.dart';
import 'package:qayd/domain/value_objects/transaction_id.dart';
import 'package:qayd/domain/value_objects/voucher_id.dart';
import 'package:qayd/domain/value_objects/voucher_type.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

final class BuildPosInvoicePaymentCollectionInput {
  const BuildPosInvoicePaymentCollectionInput({
    required this.invoiceId,
    required this.amountMinorUnits,
    required this.currencyCode,
    required this.paymentAccountId,
    required this.paymentMethod,
    required this.paymentId,
    required this.idempotencyKey,
    required this.occurredAt,
    required this.createdAt,
  });

  final String invoiceId;
  final int amountMinorUnits;
  final String currencyCode;
  final AccountId paymentAccountId;
  final PosPaymentMethod paymentMethod;
  final String paymentId;
  final String idempotencyKey;
  final DateTime occurredAt;
  final DateTime createdAt;
}

/// Builds one collection receipt without writing to SQLite.
final class BuildPosInvoicePaymentCollectionUseCase {
  BuildPosInvoicePaymentCollectionUseCase({
    required PosInvoiceReadRepository invoiceRepository,
    required AccountRepository accountRepository,
    EntryGenerator entryGenerator = const EntryGenerator(),
  })  : _invoiceRepository = invoiceRepository,
        _accountRepository = accountRepository,
        _entryGenerator = entryGenerator;

  final PosInvoiceReadRepository _invoiceRepository;
  final AccountRepository _accountRepository;
  final EntryGenerator _entryGenerator;

  Future<Result<PosInvoicePaymentCollectionPosting>> call(
    BuildPosInvoicePaymentCollectionInput input,
  ) async {
    try {
      final invoiceResult = await _invoiceRepository.getById(input.invoiceId);
      if (invoiceResult.isFailure) {
        return FailureResult(invoiceResult.failureOrNull!);
      }
      final details = invoiceResult.valueOrNull;
      if (details == null) return _invalid('pos_collection_invoice_missing');
      final invoice = details.invoice;
      final existing = details.payments
          .where((payment) => payment.idempotencyKey == input.idempotencyKey)
          .toList(growable: false);
      if (existing.isNotEmpty) {
        if (existing.length != 1 ||
            !_paymentMatches(existing.single, input)) {
          return _invalid('pos_collection_idempotency_conflict');
        }
        return Success(_posting(
          invoiceBefore: invoice,
          invoiceAfter: invoice,
          payment: existing.single,
          recordedAt: input.createdAt,
          isReplay: true,
        ));
      }

      if (PosDate.fromDateTime(input.occurredAt.toLocal()).isBefore(
        PosDate.fromDateTime(invoice.invoiceDate.toLocal()),
      )) {
        return _invalid('pos_collection_date_before_invoice');
      }

      if (input.invoiceId.trim().isEmpty ||
          input.paymentId.trim().isEmpty ||
          input.idempotencyKey.trim().isEmpty ||
          input.amountMinorUnits <= 0 ||
          input.paymentMethod == PosPaymentMethod.credit ||
          input.paymentMethod == PosPaymentMethod.other) {
        return _invalid('pos_collection_input_invalid');
      }
      if (invoice.type != PosInvoiceType.sale ||
          invoice.postedAt == null ||
          (invoice.status != PosDocumentStatus.posted &&
              invoice.status != PosDocumentStatus.partiallyPaid) ||
          invoice.counterpartyAccountId == null ||
          invoice.due.isZero ||
          invoice.currency.code != input.currencyCode.trim() ||
          input.amountMinorUnits > invoice.due.minorUnits) {
        return _invalid('pos_collection_invoice_not_collectable');
      }

      final paymentAccountResult =
          await _accountRepository.getById(input.paymentAccountId);
      if (paymentAccountResult.isFailure) {
        return FailureResult(paymentAccountResult.failureOrNull!);
      }
      final paymentAccount = paymentAccountResult.valueOrNull;
      if (paymentAccount == null ||
          !paymentAccount.isActive ||
          paymentAccount.isArchived ||
          paymentAccount.classification.standardKind !=
              StandardAccountClassificationKind.liquidAssets ||
          paymentAccount.nature != AccountNature.debit) {
        return _invalid('pos_collection_payment_account_invalid');
      }

      final customerResult =
          await _accountRepository.getById(invoice.counterpartyAccountId!);
      if (customerResult.isFailure) {
        return FailureResult(customerResult.failureOrNull!);
      }
      final customer = customerResult.valueOrNull;
      if (customer == null || !customer.isActive || customer.isArchived) {
        return _invalid('pos_collection_customer_invalid');
      }

      final historyTotal = _historyTotal(details);
      if (historyTotal == null || historyTotal != invoice.paid.minorUnits) {
        return _invalid('pos_collection_payment_history_mismatch');
      }

      final amount = Money.fromMinorUnits(
        input.amountMinorUnits,
        invoice.currency,
      );
      final after = invoice.applyPayment(amount, input.createdAt);
      final payment = PosInvoicePayment.create(
        id: input.paymentId,
        invoiceId: invoice.id,
        accountId: input.paymentAccountId,
        method: input.paymentMethod,
        amount: amount,
        currency: invoice.currency,
        occurredAt: input.occurredAt,
        idempotencyKey: input.idempotencyKey,
      );
      return Success(_posting(
        invoiceBefore: invoice,
        invoiceAfter: after,
        payment: payment,
        recordedAt: input.createdAt,
      ));
    } catch (error) {
      return FailureResult(failureFromDomainException(error));
    }
  }

  bool _paymentMatches(
    PosInvoicePayment payment,
    BuildPosInvoicePaymentCollectionInput input,
  ) =>
      payment.id == input.paymentId.trim() &&
      payment.invoiceId == input.invoiceId.trim() &&
      payment.accountId == input.paymentAccountId &&
      payment.method == input.paymentMethod &&
      payment.amount.minorUnits == input.amountMinorUnits &&
      payment.currency.code == input.currencyCode.trim() &&
      payment.occurredAt.toUtc() == input.occurredAt.toUtc();

  int? _historyTotal(PosInvoiceDetails details) {
    var total = 0;
    for (final payment in details.payments) {
      if (payment.invoiceId != details.invoice.id ||
          payment.currency != details.invoice.currency ||
          payment.amount.minorUnits <= 0) {
        return null;
      }
      total += payment.amount.minorUnits;
    }
    return total;
  }

  PosInvoicePaymentCollectionPosting _posting({
    required PosInvoice invoiceBefore,
    required PosInvoice invoiceAfter,
    required PosInvoicePayment payment,
    required DateTime recordedAt,
    bool isReplay = false,
  }) {
    final customerAccountId = invoiceBefore.counterpartyAccountId;
    if (customerAccountId == null) {
      throw ArgumentError('A POS collection invoice must have a customer.');
    }
    final voucher = Voucher.draft(
      id: VoucherId('${payment.id}:voucher'),
      type: VoucherType.receipt,
      date: payment.occurredAt,
      amount: payment.amount,
      currency: payment.currency,
      counterpartyId: customerAccountId,
      affectedAccountId: payment.accountId,
      referenceNumber: payment.id,
      description: 'POS collection ${invoiceBefore.invoiceNumber}',
      createdAt: recordedAt,
    ).confirm(recordedAt);
    final accountingPosting = PosAccountingPosting(
      sourceId: payment.id,
      voucher: voucher,
      entries: _entryGenerator.generateForConfirmedVoucher(
        voucher: voucher,
        transactionId: TransactionId('${payment.id}:transaction'),
        debitEntryId: EntryId('${payment.id}:debit'),
        creditEntryId: EntryId('${payment.id}:credit'),
        ledgerCreatedAt: recordedAt,
      ),
    );
    return PosInvoicePaymentCollectionPosting(
      invoiceBefore: invoiceBefore,
      invoiceAfter: invoiceAfter,
      payment: payment,
      accountingPosting: accountingPosting,
      recordedAt: recordedAt.toUtc(),
      isReplay: isReplay,
    );
  }

  FailureResult<PosInvoicePaymentCollectionPosting> _invalid(String code) =>
      FailureResult(
        ValidationFailure(
          messageAr: AppStrings.posInvoicePaymentInvalid,
          code: code,
        ),
      );
}
