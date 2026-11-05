import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qayd/application/sync/apply_inbound_pos_financial_event_use_case.dart';
import 'package:qayd/domain/entities/device_session.dart';
import 'package:qayd/domain/entities/pos_financial_apply_result.dart';
import 'package:qayd/domain/entities/pos_financial_sync_event.dart';
import 'package:qayd/domain/entities/pos_invoice_payment_collection_posting.dart';
import 'package:qayd/domain/entities/pos_purchase_posting.dart';
import 'package:qayd/domain/entities/pos_sale_posting.dart';
import 'package:qayd/domain/entities/pos_sales_return_posting.dart';
import 'package:qayd/domain/entities/sync_node.dart';
import 'package:qayd/domain/repositories/device_session_repository.dart';
import 'package:qayd/domain/repositories/pos_financial_inbound_application_repository.dart';

class _MockDeviceSessionRepository extends Mock
    implements DeviceSessionRepository {}

class _RecordingInboundApplicationRepository
    implements PosFinancialInboundApplicationRepository {
  int calls = 0;

  @override
  Future<PosFinancialApplyResult> applySaleAtomically({
    required PosFinancialSyncEvent event,
    required PosSalePosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  }) async {
    calls++;
    return PosFinancialApplyResult.applied;
  }

  @override
  Future<PosFinancialApplyResult> applyPurchaseAtomically({
    required PosFinancialSyncEvent event,
    required PosPurchasePosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  }) async {
    calls++;
    return PosFinancialApplyResult.applied;
  }

  @override
  Future<PosFinancialApplyResult> applySalesReturnAtomically({
    required PosFinancialSyncEvent event,
    required PosSalesReturnPosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  }) async {
    calls++;
    return PosFinancialApplyResult.applied;
  }

  @override
  Future<PosFinancialApplyResult> applyCollectionAtomically({
    required PosFinancialSyncEvent event,
    required PosInvoicePaymentCollectionPosting posting,
    required String transportNodeId,
    required String encryptedPayload,
  }) async {
    calls++;
    return PosFinancialApplyResult.applied;
  }
}

void main() {
  const currentUserId = 42;
  const currentDeviceId = 'device-current';
  const peerDeviceId = 'device-peer';
  final peerPublicKey = List.filled(64, 'a').join();

  late _MockDeviceSessionRepository sessions;
  late _RecordingInboundApplicationRepository applicationRepository;
  late ApplyInboundPosFinancialEventUseCase useCase;

  setUp(() {
    sessions = _MockDeviceSessionRepository();
    applicationRepository = _RecordingInboundApplicationRepository();
    useCase = ApplyInboundPosFinancialEventUseCase(
      deviceSessionRepository: sessions,
      applicationRepository: applicationRepository,
      currentUserId: currentUserId,
      currentDeviceId: currentDeviceId,
    );
  });

  DeviceSession pairedSession({
    String deviceId = peerDeviceId,
    String? publicKeyHex,
    bool isActive = true,
    bool isCurrent = false,
  }) => DeviceSession(
    deviceId: deviceId,
    publicKeyHex: publicKeyHex ?? peerPublicKey,
    pairedAt: DateTime.utc(2026, 11, 1),
    lastSyncSeq: 0,
    isActive: isActive,
    isCurrent: isCurrent,
  );

  SyncNode financialNode({
    int senderId = currentUserId,
    int? receiverId = currentUserId,
    String? senderDeviceId = peerDeviceId,
    String? targetDeviceId = currentDeviceId,
    String? senderPublicKey,
    SyncEventType eventType = SyncEventType.posSale,
  }) => SyncNode(
    id: 'transport-node-1',
    senderId: senderId,
    receiverId: receiverId,
    senderDeviceId: senderDeviceId,
    targetDeviceId: targetDeviceId,
    senderPublicKey: senderPublicKey ?? peerPublicKey,
    eventType: eventType,
    encryptedPayload: 'opaque-ciphertext',
    syncState: 'pending',
  );

  Map<String, dynamic> eventPayload({
    String kind = 'sale',
    int ownerUserId = currentUserId,
    String sourceDeviceId = peerDeviceId,
    String targetDeviceId = currentDeviceId,
  }) => <String, dynamic>{
    'version': 2,
    'kind': kind,
    'owner_user_id': ownerUserId,
    'source_device_id': sourceDeviceId,
    'target_device_id': targetDeviceId,
    'event_id': 'event-1',
    'aggregate_id': 'event-1',
    'idempotency_key': 'idempotency-1',
    'currency_code': 'YER',
    'occurred_at': '2026-11-01T10:00:00.000Z',
    'total_minor': 100,
    'lines': <Map<String, Object?>>[
      <String, Object?>{
        'product_id': 'product-1',
        'quantity_scaled': 1000,
        'quantity_scale': 3,
        'unit_price_minor': 100,
        'total_minor': 100,
      },
    ],
    'snapshot': <String, Object?>{},
  };

  group('trustedSenderPublicKey', () {
    test('accepts only a matching active paired device session', () async {
      when(
        () => sessions.getById(peerDeviceId),
      ).thenAnswer((_) async => pairedSession());

      expect(
        await useCase.trustedSenderPublicKey(financialNode()),
        peerPublicKey,
      );
      verify(() => sessions.getById(peerDeviceId)).called(1);
    });

    test(
      'rejects cross-account or wrong-target routes before key lookup',
      () async {
        expect(
          await useCase.trustedSenderPublicKey(
            financialNode(senderId: currentUserId + 1),
          ),
          isNull,
        );
        expect(
          await useCase.trustedSenderPublicKey(
            financialNode(receiverId: currentUserId + 1),
          ),
          isNull,
        );
        expect(
          await useCase.trustedSenderPublicKey(
            financialNode(targetDeviceId: 'another-device'),
          ),
          isNull,
        );
        verifyNever(() => sessions.getById(any()));
      },
    );

    test(
      'rejects self-sent, missing, or non-financial device identities',
      () async {
        expect(
          await useCase.trustedSenderPublicKey(
            financialNode(senderDeviceId: currentDeviceId),
          ),
          isNull,
        );
        expect(
          await useCase.trustedSenderPublicKey(
            financialNode(senderDeviceId: null),
          ),
          isNull,
        );
        expect(
          await useCase.trustedSenderPublicKey(
            financialNode(eventType: SyncEventType.acceptance),
          ),
          isNull,
        );
        verifyNever(() => sessions.getById(any()));
      },
    );

    test(
      'rejects revoked, current, malformed, or mismatched paired keys',
      () async {
        when(
          () => sessions.getById(peerDeviceId),
        ).thenAnswer((_) async => pairedSession(isActive: false));
        expect(await useCase.trustedSenderPublicKey(financialNode()), isNull);

        when(
          () => sessions.getById(peerDeviceId),
        ).thenAnswer((_) async => pairedSession(isCurrent: true));
        expect(await useCase.trustedSenderPublicKey(financialNode()), isNull);

        when(() => sessions.getById(peerDeviceId)).thenAnswer(
          (_) async => pairedSession(publicKeyHex: 'not-a-public-key'),
        );
        expect(await useCase.trustedSenderPublicKey(financialNode()), isNull);

        when(
          () => sessions.getById(peerDeviceId),
        ).thenAnswer((_) async => pairedSession());
        expect(
          await useCase.trustedSenderPublicKey(
            financialNode(senderPublicKey: List.filled(64, 'b').join()),
          ),
          isNull,
        );
      },
    );
  });

  test('does not apply an event claiming another account owner', () async {
    when(
      () => sessions.getById(peerDeviceId),
    ).thenAnswer((_) async => pairedSession());

    await expectLater(
      useCase.call(
        node: financialNode(),
        decryptedPayload: eventPayload(ownerUserId: currentUserId + 1),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(applicationRepository.calls, 0);
  });

  test(
    'fails closed on purchase-return without an atomic posting path',
    () async {
      when(
        () => sessions.getById(peerDeviceId),
      ).thenAnswer((_) async => pairedSession());

      await expectLater(
        useCase.call(
          node: financialNode(eventType: SyncEventType.posPurchaseReturn),
          decryptedPayload: eventPayload(kind: 'purchaseReturn'),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(applicationRepository.calls, 0);
    },
  );
}
