import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qayd/application/pos/pos_credit_invoice_chat_protocol.dart';
import 'package:qayd/data/security/e2ee_encryption_service_impl.dart';
import 'package:qayd/data/security/e2ee_envelope_format.dart';
import 'package:qayd/data/security/ed25519_identity_service.dart';
import 'package:qayd/domain/entities/pos_credit_invoice_chat_snapshot.dart';
import 'package:sodium/sodium_sumo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native libsodium seals PDF invoice events and rejects tampering',
    (tester) async {
      final sodium = await SodiumSumoInit.init();
      const identityService = Ed25519IdentityService();
      final sender = identityService.deriveKeyPair(
        identityService.generateMnemonic(),
      );
      final recipient = identityService.deriveKeyPair(
        identityService.generateMnemonic(),
      );
      final service = E2EEEncryptionServiceImpl(sodium);
      final pdfBytes = Uint8List.fromList(
        utf8.encode('%PDF-1.4\n% E2EE-PDF-PLAINTEXT-MUST-NOT-LEAK\n%%EOF\n'),
      );
      final snapshot = PosCreditInvoiceChatSnapshot.fromJson(<String, dynamic>{
        'schema': PosCreditInvoiceChatSnapshot.schema,
        'invoice_id': 'native-integration-invoice',
        'invoice_number': 'PDF-ENCRYPTED-001',
        'status': 'posted',
        'currency': <String, dynamic>{
          'code': 'YER',
          'name_ar': 'ريال يمني',
          'symbol': 'ر.ي',
          'fractional_digits': 0,
        },
        'subtotal_minor': 7654321,
        'discount_minor': 0,
        'cart_discount_minor': 0,
        'invoice_level_tax_minor': 0,
        'tax_minor': 0,
        'total_minor': 7654321,
        'paid_minor': 0,
        'due_minor': 7654321,
        'invoice_date': '2026-11-03T10:00:00.000Z',
        'created_at': '2026-11-03T10:00:00.000Z',
        'updated_at': '2026-11-03T10:00:00.000Z',
        'posted_at': '2026-11-03T10:00:00.000Z',
        'lines': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Confidential PDF test product',
            'barcode': null,
            'quantity_scaled': 1000,
            'quantity_scale': 3,
            'unit_price_minor': 7654321,
            'discount_minor': 0,
            'tax_minor': 0,
            'line_total_minor': 7654321,
          },
        ],
        'signature': null,
      });
      final nodeId = PosCreditInvoiceChatProtocol.invoiceNodeIdForSnapshot(
        snapshot,
      );
      final payload = PosCreditInvoiceChatProtocol.invoiceEventPayload(
        invoiceNodeId: nodeId,
        snapshot: snapshot,
        pdfBytes: pdfBytes,
      );

      final envelope = await service.encryptPayload(
        rawPayload: payload,
        senderKeyPair: sender,
        receiverPublicKeyHex: recipient.publicKeyHex,
        nodeId: nodeId,
        eventType: PosCreditInvoiceChatProtocol.invoiceEventType,
      );
      expect(E2EEEnvelopeFormat.isSupported(envelope), isTrue);
      expect(envelope, isNot(contains('PDF-ENCRYPTED-001')));
      expect(envelope, isNot(contains('Confidential PDF test product')));
      expect(envelope, isNot(contains('E2EE-PDF-PLAINTEXT-MUST-NOT-LEAK')));
      expect(envelope, isNot(contains(base64Encode(pdfBytes))));

      final decryptedPayload = await service.decryptPayload(
        encryptedPayload: envelope,
        receiverKeyPair: recipient,
        senderPublicKeyHex: sender.publicKeyHex,
        nodeId: nodeId,
        eventType: PosCreditInvoiceChatProtocol.invoiceEventType,
      );
      final decryptedSnapshot =
          PosCreditInvoiceChatProtocol.snapshotFromEventPayload(
            decryptedPayload,
            expectedNodeId: nodeId,
          );
      expect(decryptedSnapshot.fingerprint, snapshot.fingerprint);
      expect(
        PosCreditInvoiceChatProtocol.pdfBytesFromEventPayload(
          decryptedPayload,
          expectedInvoiceFingerprint: snapshot.fingerprint,
        ),
        orderedEquals(pdfBytes),
      );

      final tampered = jsonDecode(envelope) as Map<String, dynamic>;
      final signature = base64Decode(tampered['signature'] as String);
      signature[0] ^= 1;
      tampered['signature'] = base64Encode(signature);
      await expectLater(
        service.decryptPayload(
          encryptedPayload: jsonEncode(tampered),
          receiverKeyPair: recipient,
          senderPublicKeyHex: sender.publicKeyHex,
          nodeId: nodeId,
          eventType: PosCreditInvoiceChatProtocol.invoiceEventType,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
