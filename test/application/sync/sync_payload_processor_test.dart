import 'dart:convert';
import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/application/sync/sync_payload_processor.dart';
import 'package:qayd/application/pos/pos_credit_invoice_chat_protocol.dart';
import 'package:qayd/core/result/result.dart';
import 'package:qayd/domain/entities/sync_node.dart';
import 'package:qayd/domain/entities/notification_message.dart';
import 'package:qayd/domain/entities/pos_credit_invoice_chat_snapshot.dart';
import 'package:qayd/domain/repositories/notification_message_repository.dart';
import 'package:qayd/domain/repositories/account_repository.dart';
import 'package:qayd/domain/repositories/identity_repository.dart';
import 'package:qayd/domain/services/e2ee_encryption_service.dart';
import 'package:qayd/domain/value_objects/account_id.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/repositories/voucher_repository.dart';
import 'package:qayd/domain/repositories/ledger_repository.dart';
import 'package:qayd/domain/repositories/currency_repository.dart';
import 'package:qayd/domain/repositories/attachment_repository.dart';
import 'package:qayd/domain/repositories/collateral_repository.dart';
import 'package:qayd/domain/services/receipt_signing_service.dart';
import 'package:qayd/data/encryption/voucher_key_service.dart';
import 'package:qayd/domain/services/notification_filter_service.dart';
import 'package:qayd/domain/entities/party_details.dart';
import 'package:qayd/domain/entities/account.dart';
import 'package:qayd/domain/value_objects/account_classification.dart';

class MockIdentityRepository extends Mock implements IdentityRepository {}

class MockVoucherRepository extends Mock implements VoucherRepository {}

class MockLedgerRepository extends Mock implements LedgerRepository {}

class MockAccountRepository extends Mock implements AccountRepository {}

class MockCurrencyRepository extends Mock implements CurrencyRepository {}

class MockNotificationMessageRepository extends Mock
    implements NotificationMessageRepository {}

class MockE2EEEncryptionService extends Mock implements E2EEEncryptionService {}

class MockReceiptSigningService extends Mock implements ReceiptSigningService {}

class MockAttachmentRepository extends Mock implements AttachmentRepository {}

class MockCollateralRepository extends Mock implements CollateralRepository {}

class MockVoucherKeyService extends Mock implements VoucherKeyService {}

class MockNotificationFilterService extends Mock
    implements NotificationFilterService {}

Map<String, dynamic> _creditInvoiceSnapshotJson() => <String, dynamic>{
  'schema': PosCreditInvoiceChatSnapshot.schema,
  'invoice_id': 'sync-pos-invoice-001',
  'invoice_number': 'SYNC-001',
  'status': 'posted',
  'currency': <String, dynamic>{
    'code': 'YER',
    'name_ar': 'ريال يمني',
    'symbol': 'ر.ي',
    'fractional_digits': 0,
  },
  'subtotal_minor': 1000,
  'discount_minor': 0,
  'cart_discount_minor': 0,
  'invoice_level_tax_minor': 0,
  'tax_minor': 0,
  'total_minor': 1000,
  'paid_minor': 0,
  'due_minor': 1000,
  'invoice_date': '2026-11-03T10:00:00.000Z',
  'created_at': '2026-11-03T10:00:00.000Z',
  'updated_at': '2026-11-03T10:00:00.000Z',
  'posted_at': '2026-11-03T10:00:00.000Z',
  'lines': <Map<String, dynamic>>[
    <String, dynamic>{
      'name': 'تجريبي',
      'barcode': null,
      'quantity_scaled': 1000,
      'quantity_scale': 3,
      'unit_price_minor': 1000,
      'discount_minor': 0,
      'tax_minor': 0,
      'line_total_minor': 1000,
    },
  ],
  'signature': null,
};

void main() {
  const localSenderAccountUuid = 'a1000001-1111-4111-a111-a11111111111';

  late SyncPayloadProcessor processor;
  late MockIdentityRepository mockIdentityRepo;
  late MockAccountRepository mockAccountRepo;
  late MockVoucherRepository mockVoucherRepo;
  late MockLedgerRepository mockLedgerRepo;
  late MockNotificationMessageRepository mockNotificationRepo;
  late MockNotificationFilterService mockFilterRepo;
  late MockE2EEEncryptionService mockE2ee;

  setUp(() {
    mockIdentityRepo = MockIdentityRepository();
    mockAccountRepo = MockAccountRepository();
    mockVoucherRepo = MockVoucherRepository();
    mockLedgerRepo = MockLedgerRepository();
    mockNotificationRepo = MockNotificationMessageRepository();
    mockFilterRepo = MockNotificationFilterService();
    mockE2ee = MockE2EEEncryptionService();

    when(() => mockFilterRepo.isPeerActivityEnabled).thenReturn(true);
    when(() => mockFilterRepo.isSelfActivityEnabled).thenReturn(true);

    registerFallbackValue(AccountId(localSenderAccountUuid));

    processor = SyncPayloadProcessor(
      identityRepository: mockIdentityRepo,
      voucherRepository: mockVoucherRepo,
      ledgerRepository: mockLedgerRepo,
      accountRepository: mockAccountRepo,
      currencyRepository: MockCurrencyRepository(),
      notificationMessageRepository: mockNotificationRepo,
      notificationFilterService: mockFilterRepo,
      e2eeService: mockE2ee,
      signingService: MockReceiptSigningService(),
      getCurrentUserKeyPair: () async => CryptoKeyPair.fromHex(
        publicKeyHex:
            '0000000000000000000000000000000000000000000000000000000000000000',
        privateKeyHex:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
      attachmentRepository: MockAttachmentRepository(),
      collateralRepository: MockCollateralRepository(),
      voucherKeyService: MockVoucherKeyService(),
    );

    registerFallbackValue(
      CryptoKeyPair(publicKey: Uint8List(32), privateKey: Uint8List(32)),
    );
  });

  group('SyncPayloadProcessor - TripartiteRequest', () {
    test(
      'should process inbound tripartite request and save notification',
      () async {
        // Arrange
        final node = SyncNode(
          id: 'node-123',
          senderId:
              101, // Sender A — server FK only; local counterpart uses UUID below
          receiverId: 202, // Me (B)
          eventType: SyncEventType.tripartiteRequest,
          encryptedPayload: 'secret-payload',
          syncState: 'pending',
          clientTimestamp: DateTime.now(),
          senderPublicKey: 'sender-pub',
          senderPhone: '0500000000',
        );

        final partyDetails = PartyDetails(
          accountId: AccountId(localSenderAccountUuid),
          phoneNumber: '0500000000',
          currentPublicKeyHex: 'sender-pub',
        );

        final senderAccount = Account.createRoot(
          id: AccountId(localSenderAccountUuid),
          name: 'Sender A',
          classification: AccountClassification.personalExpenses,
          createdAt: DateTime.now(),
        );

        when(
          () => mockAccountRepo.findAccountByPublicKey('sender-pub'),
        ).thenAnswer((_) async => Success(AccountId(localSenderAccountUuid)));
        when(
          () => mockAccountRepo.getPartyDetails(
            AccountId(localSenderAccountUuid),
          ),
        ).thenAnswer((_) async => Success(partyDetails));
        when(
          () => mockE2ee.decryptPayload(
            encryptedPayload: any(named: 'encryptedPayload'),
            receiverKeyPair: any(named: 'receiverKeyPair'),
            senderPublicKeyHex: any(named: 'senderPublicKeyHex'),
            nodeId: any(named: 'nodeId'),
            eventType: any(named: 'eventType'),
          ),
        ).thenAnswer(
          (_) async => {
            'type': 'tripartite_request',
            'amountMinorUnits': 1000,
            'currencyCode': 'SAR',
          },
        );

        when(
          () => mockAccountRepo.getById(AccountId(localSenderAccountUuid)),
        ).thenAnswer((_) async => Success(senderAccount));
        when(
          () => mockNotificationRepo.insert(
            id: any(named: 'id'),
            counterpartyAccountId: any(named: 'counterpartyAccountId'),
            bodyText: any(named: 'bodyText'),
            channel: any(named: 'channel'),
            createdAtIso: any(named: 'createdAtIso'),
            rawPayloadJson: any(named: 'rawPayloadJson'),
          ),
        ).thenAnswer((_) async => const Success(null));

        // Act
        await processor.processIncomingNodes([node]);

        // Assert
        verify(
          () => mockNotificationRepo.insert(
            id: any(named: 'id'),
            counterpartyAccountId: localSenderAccountUuid,
            bodyText: any(named: 'bodyText', that: contains('Sender A')),
            channel: 'tripartite_event',
            createdAtIso: any(named: 'createdAtIso'),
            rawPayloadJson: any(named: 'rawPayloadJson'),
          ),
        ).called(1);
      },
    );

    test(
      'should NOT save notification when peer activity is disabled',
      () async {
        // Arrange
        when(() => mockFilterRepo.isPeerActivityEnabled).thenReturn(false);

        final node = SyncNode(
          id: 'node-123',
          senderId: 101,
          receiverId: 202,
          eventType: SyncEventType.tripartiteRequest,
          encryptedPayload: 'secret-payload',
          syncState: 'pending',
          clientTimestamp: DateTime.now(),
          senderPublicKey: 'sender-pub',
          senderPhone: '0500000000',
        );

        final partyDetails = PartyDetails(
          accountId: AccountId(localSenderAccountUuid),
          phoneNumber: '0500000000',
          currentPublicKeyHex: 'sender-pub',
        );

        when(
          () => mockAccountRepo.findAccountByPublicKey('sender-pub'),
        ).thenAnswer((_) async => Success(AccountId(localSenderAccountUuid)));
        when(
          () => mockAccountRepo.getPartyDetails(
            AccountId(localSenderAccountUuid),
          ),
        ).thenAnswer((_) async => Success(partyDetails));
        when(
          () => mockE2ee.decryptPayload(
            encryptedPayload: any(named: 'encryptedPayload'),
            receiverKeyPair: any(named: 'receiverKeyPair'),
            senderPublicKeyHex: any(named: 'senderPublicKeyHex'),
            nodeId: any(named: 'nodeId'),
            eventType: any(named: 'eventType'),
          ),
        ).thenAnswer(
          (_) async => {
            'type': 'tripartite_request',
            'amountMinorUnits': 1000,
            'currencyCode': 'SAR',
          },
        );

        when(
          () => mockAccountRepo.getById(AccountId(localSenderAccountUuid)),
        ).thenAnswer(
          (_) async => Success(
            Account.createRoot(
              id: AccountId(localSenderAccountUuid),
              name: 'Sender A',
              classification: AccountClassification.personalExpenses,
              createdAt: DateTime.now(),
            ),
          ),
        );

        // Act
        await processor.processIncomingNodes([node]);

        // Assert
        verifyNever(
          () => mockNotificationRepo.insert(
            id: any(named: 'id'),
            counterpartyAccountId: any(named: 'counterpartyAccountId'),
            bodyText: any(named: 'bodyText'),
            channel: any(named: 'channel'),
            createdAtIso: any(named: 'createdAtIso'),
            rawPayloadJson: any(named: 'rawPayloadJson'),
          ),
        );
      },
    );
  });

  group('SyncPayloadProcessor - POS credit invoice chat', () {
    late PartyDetails senderParty;
    late String invoiceNodeId;

    setUp(() {
      senderParty = PartyDetails(
        accountId: AccountId(localSenderAccountUuid),
        phoneNumber: '0500000000',
        currentPublicKeyHex: 'sender-public',
      );
      when(
        () => mockAccountRepo.findAccountByPublicKey('sender-public'),
      ).thenAnswer((_) async => Success(AccountId(localSenderAccountUuid)));
      when(
        () =>
            mockAccountRepo.getPartyDetails(AccountId(localSenderAccountUuid)),
      ).thenAnswer((_) async => Success(senderParty));
    });

    test('stores incoming invoice as a chat notification only', () async {
      final snapshot = PosCreditInvoiceChatSnapshot.fromJson(
        _creditInvoiceSnapshotJson(),
      );
      invoiceNodeId = PosCreditInvoiceChatProtocol.invoiceNodeId(
        snapshot.invoiceId,
      );
      final eventPayload = PosCreditInvoiceChatProtocol.invoiceEventPayload(
        invoiceNodeId: invoiceNodeId,
        snapshot: snapshot,
      );
      final node = SyncNode(
        id: invoiceNodeId,
        senderId: 101,
        receiverId: 202,
        eventType: SyncEventType.posCreditInvoice,
        encryptedPayload: 'authenticated-envelope',
        syncState: 'pending',
        clientTimestamp: DateTime.utc(2026, 11, 3, 10),
        senderPublicKey: 'sender-public',
      );
      when(
        () => mockE2ee.decryptPayload(
          encryptedPayload: any(named: 'encryptedPayload'),
          receiverKeyPair: any(named: 'receiverKeyPair'),
          senderPublicKeyHex: any(named: 'senderPublicKeyHex'),
          nodeId: any(named: 'nodeId'),
          eventType: any(named: 'eventType'),
        ),
      ).thenAnswer((_) async => eventPayload);
      when(
        () => mockNotificationRepo.findById(invoiceNodeId),
      ).thenAnswer((_) async => null);
      when(
        () => mockNotificationRepo.insert(
          id: invoiceNodeId,
          bodyText: any(named: 'bodyText'),
          channel: PosCreditInvoiceChatProtocol.incomingChannel,
          counterpartyAccountId: localSenderAccountUuid,
          createdAtIso: any(named: 'createdAtIso'),
          rawPayloadJson: any(named: 'rawPayloadJson'),
        ),
      ).thenAnswer((_) async => const Success(null));

      final applied = await processor.processIncomingNodes([node]);

      expect(applied, contains(invoiceNodeId));
      final inserted =
          verify(
                () => mockNotificationRepo.insert(
                  id: invoiceNodeId,
                  bodyText: any(named: 'bodyText'),
                  channel: PosCreditInvoiceChatProtocol.incomingChannel,
                  counterpartyAccountId: localSenderAccountUuid,
                  createdAtIso: any(named: 'createdAtIso'),
                  rawPayloadJson: captureAny(named: 'rawPayloadJson'),
                ),
              ).captured.single
              as String;
      final localPayload = jsonDecode(inserted) as Map<String, dynamic>;
      expect(localPayload['acknowledgment_status'], 'pending');
      expect(localPayload['invoice_id'], snapshot.invoiceId);
      verifyNoMoreInteractions(mockVoucherRepo);
      verifyNoMoreInteractions(mockLedgerRepo);
    });

    test('applies acknowledgment by updating chat metadata only', () async {
      final snapshot = PosCreditInvoiceChatSnapshot.fromJson(
        _creditInvoiceSnapshotJson(),
      );
      invoiceNodeId = PosCreditInvoiceChatProtocol.invoiceNodeId(
        snapshot.invoiceId,
      );
      final invoiceEvent = PosCreditInvoiceChatProtocol.invoiceEventPayload(
        invoiceNodeId: invoiceNodeId,
        snapshot: snapshot,
      );
      final outgoingPayload = PosCreditInvoiceChatProtocol.localInvoicePayload(
        eventPayload: invoiceEvent,
        acknowledgementStatus: 'pending',
        deliveryStatus: 'queued',
      );
      final outgoingMessage = NotificationMessage(
        id: invoiceNodeId,
        bodyText: 'فاتورة آجل',
        channel: PosCreditInvoiceChatProtocol.outgoingChannel,
        counterpartyAccountId: localSenderAccountUuid,
        createdAt: DateTime.utc(2026, 11, 3, 10),
        processed: false,
        rawPayloadJson: jsonEncode(outgoingPayload),
      );
      final ackNodeId = PosCreditInvoiceChatProtocol.acknowledgementNodeId(
        invoiceNodeId,
        snapshot.fingerprint,
      );
      final ackPayload =
          PosCreditInvoiceChatProtocol.acknowledgementEventPayload(
            invoiceNodeId: invoiceNodeId,
            invoiceId: snapshot.invoiceId,
            fingerprint: snapshot.fingerprint,
            status: 'accepted',
            respondedAt: DateTime.utc(2026, 11, 3, 10, 5),
          );
      final node = SyncNode(
        id: ackNodeId,
        senderId: 101,
        receiverId: 202,
        eventType: SyncEventType.posCreditInvoiceAcknowledgment,
        encryptedPayload: 'authenticated-envelope',
        syncState: 'pending',
        clientTimestamp: DateTime.utc(2026, 11, 3, 10, 5),
        senderPublicKey: 'sender-public',
      );
      when(
        () => mockE2ee.decryptPayload(
          encryptedPayload: any(named: 'encryptedPayload'),
          receiverKeyPair: any(named: 'receiverKeyPair'),
          senderPublicKeyHex: any(named: 'senderPublicKeyHex'),
          nodeId: any(named: 'nodeId'),
          eventType: any(named: 'eventType'),
        ),
      ).thenAnswer((_) async => ackPayload);
      when(
        () => mockNotificationRepo.findById(invoiceNodeId),
      ).thenAnswer((_) async => outgoingMessage);
      when(
        () => mockNotificationRepo.updateBodyAndPayload(
          id: invoiceNodeId,
          bodyText: any(named: 'bodyText'),
          rawPayloadJson: any(named: 'rawPayloadJson'),
        ),
      ).thenAnswer((_) async => const Success(null));

      final applied = await processor.processIncomingNodes([node]);

      expect(applied, contains(ackNodeId));
      final updatedPayload =
          verify(
                () => mockNotificationRepo.updateBodyAndPayload(
                  id: invoiceNodeId,
                  bodyText: any(named: 'bodyText'),
                  rawPayloadJson: captureAny(named: 'rawPayloadJson'),
                ),
              ).captured.single
              as String;
      expect(
        (jsonDecode(updatedPayload)
            as Map<String, dynamic>)['acknowledgment_status'],
        'accepted',
      );
      verifyNoMoreInteractions(mockVoucherRepo);
      verifyNoMoreInteractions(mockLedgerRepo);
    });
  });
}
