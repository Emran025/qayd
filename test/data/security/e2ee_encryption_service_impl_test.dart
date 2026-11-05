import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/security/e2ee_encryption_service_impl.dart';
import 'package:qayd/data/security/e2ee_envelope_format.dart';
import 'package:qayd/data/security/ed25519_identity_service.dart';
import 'package:qayd/domain/value_objects/digital_signature.dart';
import 'package:sodium/sodium_sumo.dart';

void main() {
  late SodiumSumo sodium;
  late E2EEEncryptionServiceImpl service;
  const identityService = Ed25519IdentityService();

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
    service = E2EEEncryptionServiceImpl(sodium);
  });

  test(
    'seals payload to the recipient and authenticates sender and context',
    () async {
      final sender = identityService.deriveKeyPair(
        identityService.generateMnemonic(),
      );
      final recipient = identityService.deriveKeyPair(
        identityService.generateMnemonic(),
      );
      final payload = <String, dynamic>{
        'invoice_id': 'invoice-123',
        'amount_minor_units': 7654321,
        'description': 'Confidential credit sale',
      };

      final envelope = await service.encryptPayload(
        rawPayload: payload,
        senderKeyPair: sender,
        receiverPublicKeyHex: recipient.publicKeyHex,
        nodeId: 'node-123',
        eventType: 'posCreditInvoice',
      );

      expect(E2EEEnvelopeFormat.isSupported(envelope), isTrue);
      expect(envelope, isNot(contains('Confidential credit sale')));
      expect(envelope, isNot(contains('7654321')));
      expect(
        await service.decryptPayload(
          encryptedPayload: envelope,
          receiverKeyPair: recipient,
          senderPublicKeyHex: sender.publicKeyHex,
          nodeId: 'node-123',
          eventType: 'posCreditInvoice',
        ),
        payload,
      );
    },
  );

  test('rejects a different recipient, sender, node, or event type', () async {
    final sender = identityService.deriveKeyPair(
      identityService.generateMnemonic(),
    );
    final recipient = identityService.deriveKeyPair(
      identityService.generateMnemonic(),
    );
    final other = identityService.deriveKeyPair(
      identityService.generateMnemonic(),
    );
    final envelope = await service.encryptPayload(
      rawPayload: const {'amount_minor_units': 100},
      senderKeyPair: sender,
      receiverPublicKeyHex: recipient.publicKeyHex,
      nodeId: 'node-1',
      eventType: 'claim',
    );

    Future<Map<String, dynamic>> decrypt({
      required String senderKey,
      required String nodeId,
      required String eventType,
      required dynamic receiver,
    }) => service.decryptPayload(
      encryptedPayload: envelope,
      receiverKeyPair: receiver,
      senderPublicKeyHex: senderKey,
      nodeId: nodeId,
      eventType: eventType,
    );

    await expectLater(
      decrypt(
        senderKey: sender.publicKeyHex,
        nodeId: 'node-1',
        eventType: 'claim',
        receiver: other,
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      decrypt(
        senderKey: other.publicKeyHex,
        nodeId: 'node-1',
        eventType: 'claim',
        receiver: recipient,
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      decrypt(
        senderKey: sender.publicKeyHex,
        nodeId: 'node-2',
        eventType: 'claim',
        receiver: recipient,
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      decrypt(
        senderKey: sender.publicKeyHex,
        nodeId: 'node-1',
        eventType: 'acceptance',
        receiver: recipient,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects a modified ciphertext before returning data', () async {
    final sender = identityService.deriveKeyPair(
      identityService.generateMnemonic(),
    );
    final recipient = identityService.deriveKeyPair(
      identityService.generateMnemonic(),
    );
    final envelope = await service.encryptPayload(
      rawPayload: const {'amount_minor_units': 100},
      senderKeyPair: sender,
      receiverPublicKeyHex: recipient.publicKeyHex,
      nodeId: 'node-1',
      eventType: 'claim',
    );
    final tampered = jsonDecode(envelope) as Map<String, dynamic>;
    final ciphertext = base64Decode(tampered['ciphertext'] as String);
    ciphertext[ciphertext.length - 1] ^= 1;
    tampered['ciphertext'] = base64Encode(ciphertext);

    await expectLater(
      service.decryptPayload(
        encryptedPayload: jsonEncode(tampered),
        receiverKeyPair: recipient,
        senderPublicKeyHex: sender.publicKeyHex,
        nodeId: 'node-1',
        eventType: 'claim',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'rejects legacy Base64 JSON rather than treating it as encrypted',
    () async {
      final recipient = identityService.deriveKeyPair(
        identityService.generateMnemonic(),
      );
      final legacy = base64Encode(utf8.encode('{"amount_minor_units":100}'));

      expect(E2EEEnvelopeFormat.isSupported(legacy), isFalse);
      await expectLater(
        service.decryptPayload(
          encryptedPayload: legacy,
          receiverKeyPair: recipient,
          senderPublicKeyHex: recipient.publicKeyHex,
          nodeId: 'node-1',
          eventType: 'claim',
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'verifies the real Ed25519 signature and binds it to the sender key',
    () {
      final sender = identityService.deriveKeyPair(
        identityService.generateMnemonic(),
      );
      final other = identityService.deriveKeyPair(
        identityService.generateMnemonic(),
      );
      final digest = Uint8List.fromList(
        crypto.sha256.convert(utf8.encode('canonical invoice hash')).bytes,
      );
      final secretMaterial = sodium.secureCopy(sender.privateKey);
      final seed = sodium.crypto.sign.skToSeed(secretMaterial);
      secretMaterial.dispose();
      final signingPair = sodium.crypto.sign.seedKeyPair(seed);
      seed.dispose();
      late Uint8List signatureBytes;
      try {
        signatureBytes = sodium.crypto.sign.detached(
          message: digest,
          secretKey: signingPair.secretKey,
        );
      } finally {
        signingPair.dispose();
      }
      final signature = DigitalSignature(
        signatureBytes: signatureBytes,
        signerPublicKey: sender.publicKey,
        payloadHash: digest,
      );
      final payload = {'signature_payload_hash': signature.payloadHashHex};

      expect(
        service.verifySignerAuthenticity(
          decryptedPayload: payload,
          senderPublicKeyHex: sender.publicKeyHex,
          signature: signature,
        ),
        isTrue,
      );
      expect(
        service.verifySignerAuthenticity(
          decryptedPayload: payload,
          senderPublicKeyHex: other.publicKeyHex,
          signature: signature,
        ),
        isFalse,
      );
      expect(
        service.verifySignerAuthenticity(
          decryptedPayload: {'signature_payload_hash': '00'},
          senderPublicKeyHex: sender.publicKeyHex,
          signature: signature,
        ),
        isFalse,
      );
    },
  );

  test('libsodium seed derivation matches Qayd Ed25519 public keys', () {
    final keyPair = identityService.deriveKeyPair(
      identityService.generateMnemonic(),
    );
    final secretMaterial = sodium.secureCopy(keyPair.privateKey);
    final seed = sodium.crypto.sign.skToSeed(secretMaterial);
    secretMaterial.dispose();
    final sodiumPair = sodium.crypto.sign.seedKeyPair(seed);
    seed.dispose();
    try {
      expect(sodiumPair.publicKey, keyPair.publicKey);
      final converted = sodium.crypto.sign.pkToCurve25519(sodiumPair.publicKey);
      expect(converted.length, sodium.crypto.box.publicKeyBytes);
    } finally {
      sodiumPair.dispose();
    }
  });
}
