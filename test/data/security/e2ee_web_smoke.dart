import 'dart:convert';

import 'package:qayd/data/security/e2ee_encryption_service_impl.dart';
import 'package:qayd/data/security/e2ee_envelope_format.dart';
import 'package:qayd/data/security/ed25519_identity_service.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  final body = web.document.body!;
  body.textContent = 'E2EE_WEB_SMOKE_RUNNING';

  try {
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
      'message': 'authenticated libsodium web payload',
      'amount_minor_units': 7654321,
    };

    final envelope = await service.encryptPayload(
      rawPayload: payload,
      senderKeyPair: sender,
      receiverPublicKeyHex: recipient.publicKeyHex,
      nodeId: 'web-smoke-node',
      eventType: 'webCryptoSmoke',
    );
    if (!E2EEEnvelopeFormat.isSupported(envelope)) {
      throw StateError('The web E2EE envelope format was not recognized.');
    }
    final decrypted = await service.decryptPayload(
      encryptedPayload: envelope,
      receiverKeyPair: recipient,
      senderPublicKeyHex: sender.publicKeyHex,
      nodeId: 'web-smoke-node',
      eventType: 'webCryptoSmoke',
    );
    if (jsonEncode(decrypted) != jsonEncode(payload)) {
      throw StateError('The decrypted web payload did not match the input.');
    }

    final tampered = jsonDecode(envelope) as Map<String, dynamic>;
    final signature = base64Decode(tampered['signature'] as String);
    signature[0] ^= 1;
    tampered['signature'] = base64Encode(signature);
    var rejectedTamperedSignature = false;
    try {
      await service.decryptPayload(
        encryptedPayload: jsonEncode(tampered),
        receiverKeyPair: recipient,
        senderPublicKeyHex: sender.publicKeyHex,
        nodeId: 'web-smoke-node',
        eventType: 'webCryptoSmoke',
      );
    } on StateError {
      rejectedTamperedSignature = true;
    }
    if (!rejectedTamperedSignature) {
      throw StateError('The web crypto path accepted a modified signature.');
    }

    body.setAttribute('data-e2ee-web', 'PASS');
    body.textContent = 'E2EE_WEB_SMOKE_PASS';
  } catch (error, stackTrace) {
    body.setAttribute('data-e2ee-web', 'FAIL');
    body.textContent = 'E2EE_WEB_SMOKE_FAIL: $error\n$stackTrace';
  }
}
