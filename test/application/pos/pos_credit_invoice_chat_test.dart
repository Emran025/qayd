import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/pos/build_pos_invoice_pdf_use_case.dart';
import 'package:qayd/application/pos/pos_credit_invoice_chat_protocol.dart';
import 'package:qayd/application/pos/respond_to_pos_credit_invoice_in_chat_use_case.dart';
import 'package:qayd/application/pos/send_pos_credit_invoice_to_chat_use_case.dart';
import 'package:qayd/application/sync/sync_event_dispatcher.dart';
import 'package:qayd/core/error/failures.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/data/security/ed25519_identity_service.dart';
import 'package:qayd/domain/entities/notification_message.dart';
import 'package:qayd/domain/entities/pos_credit_invoice_chat_snapshot.dart';
import 'package:qayd/domain/entities/pos_invoice.dart';
import 'package:qayd/domain/entities/pos_sales_report.dart';
import 'package:qayd/domain/repositories/notification_message_repository.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/domain/services/pos_invoice_pdf_generator.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/currency_code.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/value_objects/digital_signature.dart';
import 'package:qayd/domain/value_objects/money.dart';
import 'package:qayd/domain/value_objects/pos_document_status.dart';
import 'package:qayd/domain/value_objects/pos_quantity.dart';

class _MockNotificationMessageRepository extends Mock
    implements NotificationMessageRepository {}

class _MockSyncEventDispatcher extends Mock implements SyncEventDispatcher {}

class _FixedPdfGenerator implements PosInvoicePdfGenerator {
  const _FixedPdfGenerator(this.bytes);

  final Uint8List bytes;

  @override
  Future<Result<Uint8List>> buildInvoicePdf(PosInvoice invoice) async =>
      Success(bytes);

  @override
  Future<Result<Uint8List>> buildSalesReportPdf(PosSalesReport report) async =>
      Success(bytes);
}

final _testPdfBytes = Uint8List.fromList(
  utf8.encode('%PDF-1.4\n% test credit invoice\n%%EOF\n'),
);
final _testPdfSha256 = crypto.sha256.convert(_testPdfBytes).toString();

final _testIdentityService = const Ed25519IdentityService();
final _testKeyPair = _testIdentityService.deriveKeyPair(
  _testIdentityService.generateMnemonic(),
);
final _testReceiptSigningService = ReceiptSigningService(
  cryptoService: _testIdentityService,
);

DigitalSignature _signAcknowledgment({
  required String invoiceNodeId,
  required String invoiceId,
  required String fingerprint,
  required String status,
  required DateTime respondedAt,
  CryptoKeyPair? keyPair,
}) {
  final signer = keyPair ?? _testKeyPair;
  final canonical = PosCreditInvoiceChatProtocol.acknowledgmentSigningPayload(
    invoiceNodeId: invoiceNodeId,
    invoiceId: invoiceId,
    fingerprint: fingerprint,
    pdfSha256: _testPdfSha256,
    status: status,
    respondedAt: respondedAt.toUtc().toIso8601String(),
    signerPublicKeyHex: signer.publicKeyHex,
  );
  return _testReceiptSigningService.signCanonicalString(canonical, signer);
}

Map<String, dynamic> _snapshotJson() => <String, dynamic>{
  'schema': PosCreditInvoiceChatSnapshot.schema,
  'invoice_id': 'pos-invoice-001',
  'invoice_number': 'POS-001',
  'counterparty_account_id': 'customer-account',
  'credit_due_date': '2026-12-03',
  'credit_terms': 'Net 30 days',
  'status': 'posted',
  'currency': <String, dynamic>{
    'code': 'YER',
    'name_ar': 'ريال يمني',
    'symbol': 'ر.ي',
    'fractional_digits': 0,
  },
  'subtotal_minor': 2500,
  'discount_minor': 0,
  'cart_discount_minor': 0,
  'invoice_level_tax_minor': 0,
  'tax_minor': 0,
  'total_minor': 2500,
  'paid_minor': 0,
  'due_minor': 2500,
  'invoice_date': '2026-11-03T10:00:00.000Z',
  'created_at': '2026-11-03T10:00:00.000Z',
  'updated_at': '2026-11-03T10:00:00.000Z',
  'posted_at': '2026-11-03T10:00:00.000Z',
  'lines': <Map<String, dynamic>>[
    <String, dynamic>{
      'name': 'منتج تجريبي',
      'barcode': null,
      'quantity_scaled': 1000,
      'quantity_scale': 3,
      'unit_price_minor': 2500,
      'discount_minor': 0,
      'tax_minor': 0,
      'line_total_minor': 2500,
    },
  ],
  'signature': null,
};

NotificationMessage _message({
  required String id,
  required String channel,
  required String counterpartyAccountId,
  required String rawPayloadJson,
  String bodyText = 'فاتورة آجل',
}) => NotificationMessage(
  id: id,
  bodyText: bodyText,
  channel: channel,
  counterpartyAccountId: counterpartyAccountId,
  createdAt: DateTime.utc(2026, 11, 3, 10),
  processed: false,
  rawPayloadJson: rawPayloadJson,
);

PosInvoice _postedInvoice({
  PosInvoiceType type = PosInvoiceType.sale,
  int paidMinor = 0,
  int dueMinor = 2500,
  DateTime? creditDueDate,
  String? creditTerms,
}) {
  final currency = CurrencyCode(
    code: 'YER',
    nameAr: 'ريال يمني',
    symbol: 'ر.ي',
    fractionalDigits: 0,
  );
  final now = DateTime.utc(2026, 11, 3, 10);
  final zero = Money.zero(currency);
  final line = PosInvoiceLine.fromPersistence(
    id: 'line-1',
    invoiceId: 'sale-001',
    productId: 'product-1',
    productNameSnapshot: 'منتج تجريبي',
    quantity: PosQuantity.fromScaled(1000, scale: 3),
    unitPrice: Money.fromMinorUnits(2500, currency),
    unitCost: Money.fromMinorUnits(1000, currency),
    discount: zero,
    tax: zero,
    lineTotal: Money.fromMinorUnits(2500, currency),
    createdAt: now,
  );
  return PosInvoice.fromPersistence(
    id: 'sale-001',
    invoiceNumber: 'POS-001',
    type: type,
    status: PosDocumentStatus.posted,
    counterpartyAccountId: AccountId('customer-account'),
    warehouseId: 'warehouse-1',
    sourceInvoiceId: null,
    currency: currency,
    lines: [line],
    subtotal: Money.fromMinorUnits(2500, currency),
    discount: zero,
    cartDiscount: zero,
    tax: zero,
    total: Money.fromMinorUnits(2500, currency),
    paid: Money.fromMinorUnits(paidMinor, currency),
    due: Money.fromMinorUnits(dueMinor, currency),
    creditDueDate: creditDueDate,
    creditTerms: creditTerms,
    idempotencyKey: 'sale-idempotency-1',
    invoiceDate: now,
    createdAt: now,
    updatedAt: now,
    postedAt: now,
    signature: null,
  );
}

void main() {
  group('POS credit invoice chat snapshot', () {
    test('validates totals and creates a presentation-only PDF invoice', () {
      final snapshot = PosCreditInvoiceChatSnapshot.fromJson(_snapshotJson());
      final pdfInvoice = snapshot.toPdfInvoice();

      expect(snapshot.fingerprint, isNotEmpty);
      expect(snapshot.dueMinorUnits, 2500);
      expect(snapshot.counterpartyAccountId, 'customer-account');
      expect(snapshot.creditDueDate, DateTime.utc(2026, 12, 3));
      expect(snapshot.creditTerms, 'Net 30 days');
      expect(snapshot.lines.single.productName, 'منتج تجريبي');
      expect(pdfInvoice.due.minorUnits, 2500);
      expect(pdfInvoice.counterpartyAccountId, isNull);
      expect(pdfInvoice.creditDueDate, DateTime.utc(2026, 12, 3));
      expect(pdfInvoice.creditTerms, 'Net 30 days');
      expect(pdfInvoice.idempotencyKey, 'shared:pos-invoice-001');
      expect(pdfInvoice.signature, isNull);
    });

    test('fingerprint binds the counterparty and explicit credit terms', () {
      final original = PosCreditInvoiceChatSnapshot.fromJson(_snapshotJson());
      final changedParty = _snapshotJson()
        ..['counterparty_account_id'] = 'different-customer';
      final changedDate = _snapshotJson()..['credit_due_date'] = '2026-12-04';
      final changedTerms = _snapshotJson()..['credit_terms'] = 'Net 45 days';

      expect(
        PosCreditInvoiceChatSnapshot.fromJson(changedParty).fingerprint,
        isNot(original.fingerprint),
      );
      expect(
        PosCreditInvoiceChatSnapshot.fromJson(changedDate).fingerprint,
        isNot(original.fingerprint),
      );
      expect(
        PosCreditInvoiceChatSnapshot.fromJson(changedTerms).fingerprint,
        isNot(original.fingerprint),
      );

      final invoiceSnapshot = PosCreditInvoiceChatSnapshot.fromInvoice(
        _postedInvoice(
          creditDueDate: DateTime.utc(2026, 12, 3),
          creditTerms: 'Net 30 days',
        ),
      );
      expect(invoiceSnapshot.counterpartyAccountId, 'customer-account');
      expect(invoiceSnapshot.creditDueDate, DateTime.utc(2026, 12, 3));
      expect(invoiceSnapshot.creditTerms, 'Net 30 days');
    });

    test(
      'rejects a modified line total instead of showing an invalid invoice',
      () {
        final tampered = _snapshotJson();
        (tampered['lines'] as List<Map<String, dynamic>>)
                .single['line_total_minor'] =
            2400;

        expect(
          () => PosCreditInvoiceChatSnapshot.fromJson(tampered),
          throwsFormatException,
        );
      },
    );

    test('rejects negative discounts and inconsistent tax breakdowns', () {
      final negativeDiscount = _snapshotJson()
        ..['discount_minor'] = -1
        ..['cart_discount_minor'] = -1
        ..['total_minor'] = 2501
        ..['due_minor'] = 2501;
      final mismatchedTax = _snapshotJson()
        ..['invoice_level_tax_minor'] = 10
        ..['tax_minor'] = 11
        ..['total_minor'] = 2511
        ..['due_minor'] = 2511;

      expect(
        () => PosCreditInvoiceChatSnapshot.fromJson(negativeDiscount),
        throwsFormatException,
      );
      expect(
        () => PosCreditInvoiceChatSnapshot.fromJson(mismatchedTax),
        throwsFormatException,
      );
    });

    test('rejects unsafe integer magnitudes and oversized snapshots', () {
      final unsafeAmount = _snapshotJson();
      (unsafeAmount['lines'] as List<Map<String, dynamic>>)
              .single['unit_price_minor'] =
          PosCreditInvoiceChatSnapshot.maxExactInteger + 1;
      expect(
        () => PosCreditInvoiceChatSnapshot.fromJson(unsafeAmount),
        throwsFormatException,
      );

      final oversized = _snapshotJson();
      oversized['subtotal_minor'] = PosCreditInvoiceChatSnapshot.maxLines;
      oversized['total_minor'] = PosCreditInvoiceChatSnapshot.maxLines;
      oversized['due_minor'] = PosCreditInvoiceChatSnapshot.maxLines;
      oversized['lines'] = List<Map<String, dynamic>>.generate(
        PosCreditInvoiceChatSnapshot.maxLines,
        (_) => <String, dynamic>{
          'name': List<String>.filled(240, 'N').join(),
          'barcode': List<String>.filled(128, 'B').join(),
          'quantity_scaled': 1,
          'quantity_scale': 0,
          'unit_price_minor': 1,
          'discount_minor': 0,
          'tax_minor': 0,
          'line_total_minor': 1,
        },
      );
      expect(
        utf8.encode(jsonEncode(oversized)).length,
        greaterThan(PosCreditInvoiceChatSnapshot.maxSerializedBytes),
      );
      expect(
        () => PosCreditInvoiceChatSnapshot.fromJson(oversized),
        throwsFormatException,
      );
    });

    test(
      'binds each immutable snapshot version to its deterministic node id',
      () {
        final snapshot = PosCreditInvoiceChatSnapshot.fromJson(_snapshotJson());
        final nodeId = PosCreditInvoiceChatProtocol.invoiceNodeIdForSnapshot(
          snapshot,
        );
        final changedSnapshot = PosCreditInvoiceChatSnapshot.fromJson(
          _snapshotJson()..['credit_terms'] = 'Net 45 days',
        );
        expect(
          PosCreditInvoiceChatProtocol.invoiceNodeIdForSnapshot(snapshot),
          nodeId,
        );
        expect(
          PosCreditInvoiceChatProtocol.invoiceNodeIdForSnapshot(
            changedSnapshot,
          ),
          isNot(nodeId),
        );
        final eventPayload = PosCreditInvoiceChatProtocol.invoiceEventPayload(
          invoiceNodeId: nodeId,
          snapshot: snapshot,
          pdfBytes: _testPdfBytes,
        );

        expect(
          PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
            eventPayload,
            expectedNodeId: nodeId,
          ).fingerprint,
          snapshot.fingerprint,
        );
        expect(
          PosCreditInvoiceChatProtocol.pdfBytesFromEventPayload(
            eventPayload,
            expectedInvoiceFingerprint: snapshot.fingerprint,
          ),
          orderedEquals(_testPdfBytes),
        );
        expect(
          PosCreditInvoiceChatProtocol.pdfSha256FromEventPayload(
            eventPayload,
            expectedInvoiceFingerprint: snapshot.fingerprint,
          ),
          _testPdfSha256,
        );
        final tampered = Map<String, dynamic>.from(eventPayload);
        tampered['pdf_attachment'] = Map<String, dynamic>.from(
          eventPayload['pdf_attachment'] as Map,
        )..['sha256'] = List<String>.filled(64, '0').join();
        expect(
          () => PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
            tampered,
            expectedNodeId: nodeId,
          ),
          throwsFormatException,
        );
        final changedTerms = Map<String, dynamic>.from(eventPayload)
          ..['invoice_snapshot'] = Map<String, dynamic>.from(
            eventPayload['invoice_snapshot'] as Map,
          )
          ..['credit_terms'] = 'Net 45 days';
        expect(
          () => PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
            changedTerms,
            expectedNodeId: nodeId,
          ),
          throwsFormatException,
        );
        expect(
          () => PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
            eventPayload,
            expectedNodeId: 'another-node',
          ),
          throwsFormatException,
        );
        final replay = Map<String, dynamic>.from(eventPayload)
          ..['invoice_node_id'] = 'replayed-node';
        expect(
          () => PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
            replay,
            expectedNodeId: 'replayed-node',
          ),
          throwsFormatException,
        );
        expect(
          () => PosCreditInvoiceChatProtocol.invoiceEventPayload(
            invoiceNodeId: 'replayed-node',
            snapshot: snapshot,
            pdfBytes: _testPdfBytes,
          ),
          throwsFormatException,
        );
      },
    );

    test('caps acknowledgment event payloads at one kibibyte', () {
      final invoiceId = 'pos-invoice-001';
      final fingerprint = List<String>.filled(64, 'a').join();
      final invoiceNodeId = PosCreditInvoiceChatProtocol.invoiceNodeId(
        invoiceId,
        fingerprint: fingerprint,
      );
      final acknowledgment =
          PosCreditInvoiceChatProtocol.acknowledgementEventPayload(
            invoiceNodeId: invoiceNodeId,
            invoiceId: invoiceId,
            fingerprint: List<String>.filled(64, 'a').join(),
            pdfSha256: _testPdfSha256,
            status: 'accepted',
            respondedAt: DateTime.utc(2026, 11, 3),
            signature: _signAcknowledgment(
              invoiceNodeId: invoiceNodeId,
              invoiceId: invoiceId,
              fingerprint: List<String>.filled(64, 'a').join(),
              status: 'accepted',
              respondedAt: DateTime.utc(2026, 11, 3),
            ),
          );
      expect(
        PosCreditInvoiceChatProtocol.isValidAcknowledgmentEventPayload(
          acknowledgment,
          expectedNodeId: invoiceNodeId,
        ),
        isTrue,
      );

      final oversizedInvoiceId = List<String>.filled(2048, 'I').join();
      final oversizedNodeId = PosCreditInvoiceChatProtocol.invoiceNodeId(
        oversizedInvoiceId,
        fingerprint: fingerprint,
      );
      final oversizedAcknowledgment = Map<String, dynamic>.from(acknowledgment)
        ..['invoice_id'] = oversizedInvoiceId
        ..['invoice_node_id'] = oversizedNodeId;
      expect(
        PosCreditInvoiceChatProtocol.isValidAcknowledgmentEventPayload(
          oversizedAcknowledgment,
          expectedNodeId: oversizedNodeId,
        ),
        isFalse,
      );
      expect(
        () => PosCreditInvoiceChatProtocol.acknowledgementEventPayload(
          invoiceNodeId: oversizedNodeId,
          invoiceId: oversizedInvoiceId,
          fingerprint: List<String>.filled(64, 'a').join(),
          pdfSha256: _testPdfSha256,
          status: 'accepted',
          respondedAt: DateTime.utc(2026, 11, 3),
          signature: _signAcknowledgment(
            invoiceNodeId: oversizedNodeId,
            invoiceId: oversizedInvoiceId,
            fingerprint: List<String>.filled(64, 'a').join(),
            status: 'accepted',
            respondedAt: DateTime.utc(2026, 11, 3),
          ),
        ),
        throwsFormatException,
      );
    });

    test('binds signature to invoice, decision, time and signer key', () {
      final invoiceId = 'pos-invoice-bound';
      final fingerprint = List<String>.filled(64, 'b').join();
      final invoiceNodeId = PosCreditInvoiceChatProtocol.invoiceNodeId(
        invoiceId,
        fingerprint: fingerprint,
      );
      final respondedAt = DateTime.utc(2026, 11, 3, 12, 30);
      final payload = PosCreditInvoiceChatProtocol.acknowledgementEventPayload(
        invoiceNodeId: invoiceNodeId,
        invoiceId: invoiceId,
        fingerprint: List<String>.filled(64, 'b').join(),
        pdfSha256: _testPdfSha256,
        status: 'rejected',
        respondedAt: respondedAt,
        signature: _signAcknowledgment(
          invoiceNodeId: invoiceNodeId,
          invoiceId: invoiceId,
          fingerprint: List<String>.filled(64, 'b').join(),
          status: 'rejected',
          respondedAt: respondedAt,
        ),
      );
      expect(
        PosCreditInvoiceChatProtocol.isValidAcknowledgmentEventPayload(
          payload,
          expectedNodeId: invoiceNodeId,
        ),
        isTrue,
      );

      for (final tamper in <(String, Object)>[
        ('invoice_id', 'pos-invoice-other'),
        ('fingerprint', List<String>.filled(64, 'c').join()),
        ('status', 'accepted'),
        ('responded_at', DateTime.utc(2026, 11, 3, 12, 31).toIso8601String()),
        ('signer_public_key_hex', List<String>.filled(64, '0').join()),
      ]) {
        final modified = Map<String, dynamic>.from(payload)
          ..[tamper.$1] = tamper.$2;
        expect(
          PosCreditInvoiceChatProtocol.isValidAcknowledgmentEventPayload(
            modified,
            expectedNodeId: invoiceNodeId,
          ),
          isFalse,
          reason: '${tamper.$1} is signed and must not be mutable',
        );
      }
    });
  });

  group('SendPosCreditInvoiceToChatUseCase', () {
    late _MockNotificationMessageRepository notifications;
    late _MockSyncEventDispatcher sync;
    late SendPosCreditInvoiceToChatUseCase useCase;

    setUp(() {
      notifications = _MockNotificationMessageRepository();
      sync = _MockSyncEventDispatcher();
      useCase = SendPosCreditInvoiceToChatUseCase(
        notificationMessageRepository: notifications,
        syncEventDispatcher: sync,
        pdfUseCase: BuildPosInvoicePdfUseCase(
          generator: _FixedPdfGenerator(_testPdfBytes),
        ),
      );
    });

    test(
      'sends a deterministic encrypted event for a posted credit sale',
      () async {
        final invoice = _postedInvoice();
        final nodeId = PosCreditInvoiceChatProtocol.invoiceNodeIdForSnapshot(
          PosCreditInvoiceChatSnapshot.fromInvoice(invoice),
        );
        when(
          () => notifications.findById(nodeId),
        ).thenAnswer((_) async => null);
        when(
          () => notifications.insert(
            id: nodeId,
            bodyText: any(named: 'bodyText'),
            channel: PosCreditInvoiceChatProtocol.outgoingChannel,
            counterpartyAccountId: 'customer-account',
            createdAtIso: any(named: 'createdAtIso'),
            rawPayloadJson: any(named: 'rawPayloadJson'),
          ),
        ).thenAnswer((_) async => const Success(null));
        when(
          () => notifications.updateBodyAndPayloadIfUnchanged(
            id: nodeId,
            expectedRawPayloadJson: any(named: 'expectedRawPayloadJson'),
            bodyText: any(named: 'bodyText'),
            rawPayloadJson: any(named: 'rawPayloadJson'),
          ),
        ).thenAnswer((_) async => const Success(true));
        when(
          () => sync.dispatchGenericEvent(
            counterpartyAccountId: 'customer-account',
            eventType: PosCreditInvoiceChatProtocol.invoiceEventType,
            payload: any(named: 'payload'),
            nodeId: nodeId,
          ),
        ).thenAnswer((_) async => const Success(null));

        final result = await useCase(invoice);

        expect(result.isSuccess, isTrue);
        final sentPayload =
            verify(
                  () => sync.dispatchGenericEvent(
                    counterpartyAccountId: 'customer-account',
                    eventType: PosCreditInvoiceChatProtocol.invoiceEventType,
                    payload: captureAny(named: 'payload'),
                    nodeId: nodeId,
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(sentPayload['invoice_id'], invoice.id);
        expect(sentPayload['fingerprint'], isNotEmpty);
        expect(
          PosCreditInvoiceChatProtocol.pdfBytesFromEventPayload(
            sentPayload,
            expectedInvoiceFingerprint: sentPayload['fingerprint'] as String,
          ),
          orderedEquals(_testPdfBytes),
        );
        verify(
          () => notifications.insert(
            id: nodeId,
            bodyText: any(named: 'bodyText'),
            channel: PosCreditInvoiceChatProtocol.outgoingChannel,
            counterpartyAccountId: 'customer-account',
            createdAtIso: any(named: 'createdAtIso'),
            rawPayloadJson: any(named: 'rawPayloadJson'),
          ),
        ).called(1);
        expect(invoice.due.minorUnits, 2500);
      },
    );

    test('does not create chat events for cash sales or purchases', () async {
      final cashSale = _postedInvoice(paidMinor: 2500, dueMinor: 0);
      final purchase = _postedInvoice(type: PosInvoiceType.purchase);

      expect((await useCase(cashSale)).isSuccess, isTrue);
      expect((await useCase(purchase)).isSuccess, isTrue);
      verifyNever(
        () => sync.dispatchGenericEvent(
          counterpartyAccountId: 'customer-account',
          eventType: PosCreditInvoiceChatProtocol.invoiceEventType,
          payload: any(named: 'payload'),
          nodeId: any(named: 'nodeId'),
        ),
      );
    });

    test('keeps the posted invoice unchanged if chat delivery fails', () async {
      final invoice = _postedInvoice();
      final nodeId = PosCreditInvoiceChatProtocol.invoiceNodeIdForSnapshot(
        PosCreditInvoiceChatSnapshot.fromInvoice(invoice),
      );
      when(() => notifications.findById(nodeId)).thenAnswer((_) async => null);
      when(
        () => notifications.insert(
          id: nodeId,
          bodyText: any(named: 'bodyText'),
          channel: PosCreditInvoiceChatProtocol.outgoingChannel,
          counterpartyAccountId: 'customer-account',
          createdAtIso: any(named: 'createdAtIso'),
          rawPayloadJson: any(named: 'rawPayloadJson'),
        ),
      ).thenAnswer((_) async => const Success(null));
      when(
        () => notifications.updateBodyAndPayloadIfUnchanged(
          id: nodeId,
          expectedRawPayloadJson: any(named: 'expectedRawPayloadJson'),
          bodyText: any(named: 'bodyText'),
          rawPayloadJson: any(named: 'rawPayloadJson'),
        ),
      ).thenAnswer((_) async => const Success(true));
      when(
        () => sync.dispatchGenericEvent(
          counterpartyAccountId: 'customer-account',
          eventType: PosCreditInvoiceChatProtocol.invoiceEventType,
          payload: any(named: 'payload'),
          nodeId: nodeId,
        ),
      ).thenAnswer(
        (_) async => FailureResult(ValidationFailure(messageAr: 'offline')),
      );

      final result = await useCase(invoice);

      expect(result.isFailure, isTrue);
      expect(invoice.status, PosDocumentStatus.posted);
      expect(invoice.due.minorUnits, 2500);
    });

    test(
      'fails closed when the generated PDF exceeds the inline limit',
      () async {
        final invoice = _postedInvoice();
        final nodeId = PosCreditInvoiceChatProtocol.invoiceNodeIdForSnapshot(
          PosCreditInvoiceChatSnapshot.fromInvoice(invoice),
        );
        when(
          () => notifications.findById(nodeId),
        ).thenAnswer((_) async => null);
        final oversizedUseCase = SendPosCreditInvoiceToChatUseCase(
          notificationMessageRepository: notifications,
          syncEventDispatcher: sync,
          pdfUseCase: BuildPosInvoicePdfUseCase(
            generator: _FixedPdfGenerator(
              Uint8List(PosCreditInvoiceChatProtocol.maxPdfAttachmentBytes + 1),
            ),
          ),
        );

        final result = await oversizedUseCase(invoice);

        expect(result.isFailure, isTrue);
        verifyNever(
          () => notifications.insert(
            id: nodeId,
            bodyText: any(named: 'bodyText'),
            channel: PosCreditInvoiceChatProtocol.outgoingChannel,
            counterpartyAccountId: 'customer-account',
            createdAtIso: any(named: 'createdAtIso'),
            rawPayloadJson: any(named: 'rawPayloadJson'),
          ),
        );
        verifyNever(
          () => sync.dispatchGenericEvent(
            counterpartyAccountId: any(named: 'counterpartyAccountId'),
            eventType: any(named: 'eventType'),
            payload: any(named: 'payload'),
            nodeId: any(named: 'nodeId'),
          ),
        );
      },
    );
  });

  group('RespondToPosCreditInvoiceInChatUseCase', () {
    late _MockNotificationMessageRepository notifications;
    late _MockSyncEventDispatcher sync;
    late RespondToPosCreditInvoiceInChatUseCase useCase;
    late NotificationMessage storedMessage;
    late String invoiceNodeId;

    setUp(() {
      notifications = _MockNotificationMessageRepository();
      sync = _MockSyncEventDispatcher();
      useCase = RespondToPosCreditInvoiceInChatUseCase(
        notificationMessageRepository: notifications,
        syncEventDispatcher: sync,
        signingService: _testReceiptSigningService,
        getCurrentUserKeyPair: () async => _testKeyPair,
      );

      final snapshot = PosCreditInvoiceChatSnapshot.fromJson(_snapshotJson());
      invoiceNodeId = PosCreditInvoiceChatProtocol.invoiceNodeIdForSnapshot(
        snapshot,
      );
      final eventPayload = PosCreditInvoiceChatProtocol.invoiceEventPayload(
        invoiceNodeId: invoiceNodeId,
        snapshot: snapshot,
        pdfBytes: _testPdfBytes,
      );
      final localPayload = PosCreditInvoiceChatProtocol.localInvoicePayload(
        eventPayload: eventPayload,
        acknowledgementStatus: 'pending',
        deliveryStatus: 'received',
      );
      storedMessage = _message(
        id: invoiceNodeId,
        channel: PosCreditInvoiceChatProtocol.incomingChannel,
        counterpartyAccountId: 'seller-account',
        rawPayloadJson: jsonEncode(localPayload),
      );

      when(
        () => notifications.findById(invoiceNodeId),
      ).thenAnswer((_) async => storedMessage);
      when(
        () => notifications.updateBodyAndPayloadIfUnchanged(
          id: invoiceNodeId,
          expectedRawPayloadJson: any(named: 'expectedRawPayloadJson'),
          bodyText: any(named: 'bodyText'),
          rawPayloadJson: any(named: 'rawPayloadJson'),
        ),
      ).thenAnswer((invocation) async {
        final bodyText = invocation.namedArguments[#bodyText] as String;
        final rawPayloadJson =
            invocation.namedArguments[#rawPayloadJson] as String;
        storedMessage = _message(
          id: invoiceNodeId,
          channel: PosCreditInvoiceChatProtocol.incomingChannel,
          counterpartyAccountId: 'seller-account',
          bodyText: bodyText,
          rawPayloadJson: rawPayloadJson,
        );
        return const Success(true);
      });
      when(
        () => sync.dispatchGenericEvent(
          counterpartyAccountId: 'seller-account',
          eventType: PosCreditInvoiceChatProtocol.acknowledgementEventType,
          payload: any(named: 'payload'),
          nodeId: any(named: 'nodeId'),
        ),
      ).thenAnswer((_) async => const Success(null));
    });

    test(
      'records a signed-sync acknowledgment once without a financial event',
      () async {
        final first = await useCase.call(
          notificationId: invoiceNodeId,
          accepted: true,
        );
        final duplicate = await useCase.call(
          notificationId: invoiceNodeId,
          accepted: true,
        );

        expect(first.isSuccess, isTrue);
        expect(duplicate.isSuccess, isTrue);
        final savedPayload =
            jsonDecode(storedMessage.rawPayloadJson!) as Map<String, dynamic>;
        expect(savedPayload['acknowledgment_status'], 'accepted');

        final dispatchVerification = verify(
          () => sync.dispatchGenericEvent(
            counterpartyAccountId: 'seller-account',
            eventType: PosCreditInvoiceChatProtocol.acknowledgementEventType,
            payload: captureAny(named: 'payload'),
            nodeId: any(named: 'nodeId'),
          ),
        );
        final sentPayload =
            dispatchVerification.captured.single as Map<String, dynamic>;
        dispatchVerification.called(1);
        expect(sentPayload['status'], 'accepted');
        expect(sentPayload['invoice_node_id'], invoiceNodeId);
        expect(sentPayload['signer_public_key_hex'], _testKeyPair.publicKeyHex);
        final signature = DigitalSignature.fromHex(
          signatureHex: sentPayload['signature_hex'] as String,
          signerPublicKeyHex: sentPayload['signer_public_key_hex'] as String,
          payloadHashHex: sentPayload['payload_hash_hex'] as String,
        );
        expect(
          _testReceiptSigningService.verifyRaw(
            signatureBytes: signature.signatureBytes,
            payloadHash: signature.payloadHash,
            publicKey: signature.signerPublicKey,
          ),
          isTrue,
        );
      },
    );

    test(
      'retries the identical signed decision after dispatch failure',
      () async {
        var attempts = 0;
        final dispatchedPayloads = <Map<String, dynamic>>[];
        when(
          () => sync.dispatchGenericEvent(
            counterpartyAccountId: 'seller-account',
            eventType: PosCreditInvoiceChatProtocol.acknowledgementEventType,
            payload: any(named: 'payload'),
            nodeId: any(named: 'nodeId'),
          ),
        ).thenAnswer((invocation) async {
          attempts++;
          dispatchedPayloads.add(
            Map<String, dynamic>.from(
              invocation.namedArguments[#payload] as Map,
            ),
          );
          if (attempts == 1) {
            return const FailureResult(ValidationFailure(messageAr: 'offline'));
          }
          return const Success(null);
        });

        final first = await useCase.call(
          notificationId: invoiceNodeId,
          accepted: false,
        );
        final retry = await useCase.call(
          notificationId: invoiceNodeId,
          accepted: false,
        );

        expect(first.isFailure, isTrue);
        expect(retry.isSuccess, isTrue);
        expect(dispatchedPayloads, hasLength(2));
        expect(dispatchedPayloads[0], dispatchedPayloads[1]);
        expect(dispatchedPayloads.first['status'], 'rejected');
        expect(
          dispatchedPayloads.first['signer_public_key_hex'],
          _testKeyPair.publicKeyHex,
        );
        final stored =
            jsonDecode(storedMessage.rawPayloadJson!) as Map<String, dynamic>;
        expect(stored['acknowledgment_status'], 'rejected');
        expect(
          stored['acknowledgment_event_payload'],
          dispatchedPayloads.first,
        );
      },
    );

    test('serializes concurrent accept and reject decisions', () async {
      final dispatchStarted = Completer<void>();
      final dispatchResult = Completer<Result<void>>();
      when(
        () => sync.dispatchGenericEvent(
          counterpartyAccountId: 'seller-account',
          eventType: PosCreditInvoiceChatProtocol.acknowledgementEventType,
          payload: any(named: 'payload'),
          nodeId: any(named: 'nodeId'),
        ),
      ).thenAnswer((_) {
        if (!dispatchStarted.isCompleted) dispatchStarted.complete();
        return dispatchResult.future;
      });

      final accept = useCase.call(
        notificationId: invoiceNodeId,
        accepted: true,
      );
      final reject = useCase.call(
        notificationId: invoiceNodeId,
        accepted: false,
      );
      await dispatchStarted.future;
      dispatchResult.complete(const Success(null));
      final results = await Future.wait([accept, reject]);

      expect(results[0].isSuccess, isTrue);
      expect(results[1].isFailure, isTrue);
      final saved =
          jsonDecode(storedMessage.rawPayloadJson!) as Map<String, dynamic>;
      expect(saved['acknowledgment_status'], 'accepted');
      expect(
        (saved['acknowledgment_event_payload']
            as Map<String, dynamic>)['status'],
        'accepted',
      );
      verify(
        () => sync.dispatchGenericEvent(
          counterpartyAccountId: 'seller-account',
          eventType: PosCreditInvoiceChatProtocol.acknowledgementEventType,
          payload: any(named: 'payload'),
          nodeId: any(named: 'nodeId'),
        ),
      ).called(1);
    });

    test(
      'does not dispatch when the durable decision compare-and-set loses',
      () async {
        when(
          () => notifications.updateBodyAndPayloadIfUnchanged(
            id: invoiceNodeId,
            expectedRawPayloadJson: any(named: 'expectedRawPayloadJson'),
            bodyText: any(named: 'bodyText'),
            rawPayloadJson: any(named: 'rawPayloadJson'),
          ),
        ).thenAnswer((_) async => const Success(false));

        final result = await useCase.call(
          notificationId: invoiceNodeId,
          accepted: true,
        );

        expect(result.isFailure, isTrue);
        verifyNever(
          () => sync.dispatchGenericEvent(
            counterpartyAccountId: 'seller-account',
            eventType: PosCreditInvoiceChatProtocol.acknowledgementEventType,
            payload: any(named: 'payload'),
            nodeId: any(named: 'nodeId'),
          ),
        );
      },
    );

    test('does not dispatch a response for an untrusted payload', () async {
      storedMessage = _message(
        id: invoiceNodeId,
        channel: PosCreditInvoiceChatProtocol.incomingChannel,
        counterpartyAccountId: 'seller-account',
        rawPayloadJson: '{"schema":"wrong"}',
      );

      final result = await useCase.call(
        notificationId: invoiceNodeId,
        accepted: false,
      );

      expect(result.isFailure, isTrue);
      verifyNever(
        () => sync.dispatchGenericEvent(
          counterpartyAccountId: any(named: 'counterpartyAccountId'),
          eventType: any(named: 'eventType'),
          payload: any(named: 'payload'),
          nodeId: any(named: 'nodeId'),
        ),
      );
    });
  });
}
