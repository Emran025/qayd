import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qayd/data/security/e2ee_encryption_service_impl.dart';
import 'package:qayd/data/security/e2ee_envelope_format.dart';
import 'package:qayd/data/security/ed25519_identity_service.dart';
import 'package:sodium/sodium_sumo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native libsodium seals, authenticates, and rejects tampering', (
    tester,
  ) async {
    final sodium = await SodiumSumoInit.init();
    const identityService = Ed25519IdentityService();
    final sender = identityService.deriveKeyPair(
      identityService.generateMnemonic(),
    );
    final recipient = identityService.deriveKeyPair(
      identityService.generateMnemonic(),
    );
    final service = E2EEEncryptionServiceImpl(sodium);
    const payload = <String, dynamic>{
      'invoice_id': 'native-integration-invoice',
      'amount_minor_units': 7654321,
      'description': 'authenticated native payload',
    };

    final envelope = await service.encryptPayload(
      rawPayload: payload,
      senderKeyPair: sender,
      receiverPublicKeyHex: recipient.publicKeyHex,
      nodeId: 'native-integration-node',
      eventType: 'nativeCryptoIntegration',
    );
    expect(E2EEEnvelopeFormat.isSupported(envelope), isTrue);
    expect(envelope, isNot(contains('authenticated native payload')));
    expect(
      jsonEncode(
        await service.decryptPayload(
          encryptedPayload: envelope,
          receiverKeyPair: recipient,
          senderPublicKeyHex: sender.publicKeyHex,
          nodeId: 'native-integration-node',
          eventType: 'nativeCryptoIntegration',
        ),
      ),
      jsonEncode(payload),
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
        nodeId: 'native-integration-node',
        eventType: 'nativeCryptoIntegration',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
