import 'dart:convert';
import 'dart:typed_data';

import 'package:qayd/data/security/e2ee_envelope_format.dart';
import 'package:qayd/domain/services/e2ee_encryption_service.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/value_objects/digital_signature.dart';
import 'package:sodium/sodium_sumo.dart';

/// E2EE envelope implemented with the maintained libsodium bindings.
///
/// The existing account identity is an Ed25519 seed/public key. Libsodium's
/// documented Ed25519-to-Curve25519 conversion feeds a sealed box addressed to
/// the recipient; a detached Ed25519 signature authenticates the complete
/// ciphertext and its routing context. No plaintext or key material is put in
/// the relay envelope.
final class E2EEEncryptionServiceImpl implements E2EEEncryptionService {
  E2EEEncryptionServiceImpl(this._sodium);

  final SodiumSumo _sodium;

  static final Uint8List _signatureDomain = Uint8List.fromList(
    utf8.encode('QAYD:E2EE:ENVELOPE:v1\u0000'),
  );

  @override
  Future<String> encryptPayload({
    required Map<String, dynamic> rawPayload,
    required CryptoKeyPair senderKeyPair,
    required String receiverPublicKeyHex,
    required String nodeId,
    required String eventType,
  }) async {
    final recipientHex = _normalizePublicKey(receiverPublicKeyHex);
    _validateContext(nodeId, eventType);

    KeyPair? signingKeyPair;
    try {
      signingKeyPair = _signingKeyPair(senderKeyPair);
      if (!_constantTimeEquals(
        signingKeyPair.publicKey,
        senderKeyPair.publicKey,
      )) {
        throw StateError('Secure identity key pair is inconsistent.');
      }

      final recipientEdPublic = _hexToBytes(recipientHex);
      final recipientCurvePublic = _sodium.crypto.sign.pkToCurve25519(
        recipientEdPublic,
      );
      final cleartext = Uint8List.fromList(utf8.encode(jsonEncode(rawPayload)));
      final ciphertext = _sodium.crypto.box.seal(
        message: cleartext,
        publicKey: recipientCurvePublic,
      );

      final signedFields = <String, Object>{
        'version': E2EEEnvelopeFormat.version,
        'algorithm': E2EEEnvelopeFormat.algorithm,
        'node_id': nodeId,
        'event_type': eventType,
        'sender_public_key': senderKeyPair.publicKeyHex.toLowerCase(),
        'recipient_public_key': recipientHex,
        'ciphertext': base64Encode(ciphertext),
      };
      final signature = _sodium.crypto.sign.detached(
        message: _signatureMessage(signedFields),
        secretKey: signingKeyPair.secretKey,
      );
      final envelope = <String, Object>{
        ...signedFields,
        'signature': base64Encode(signature),
      };
      return jsonEncode(envelope);
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('Unable to create a secure sync envelope.');
    } finally {
      signingKeyPair?.dispose();
    }
  }

  @override
  Future<Map<String, dynamic>> decryptPayload({
    required String encryptedPayload,
    required CryptoKeyPair receiverKeyPair,
    required String senderPublicKeyHex,
    required String nodeId,
    required String eventType,
  }) async {
    _validateContext(nodeId, eventType);

    KeyPair? receiverSigningKeyPair;
    SecureKey? receiverCurveSecret;
    try {
      final decoded = jsonDecode(encryptedPayload);
      if (decoded is! Map<String, dynamic> || decoded.length != 8) {
        throw const FormatException();
      }
      final fields = decoded;
      if (fields['version'] != E2EEEnvelopeFormat.version ||
          fields['algorithm'] != E2EEEnvelopeFormat.algorithm ||
          fields['node_id'] != nodeId ||
          fields['event_type'] != eventType) {
        throw const FormatException();
      }

      final senderHex = _normalizePublicKey(senderPublicKeyHex);
      final envelopeSenderHex = _normalizePublicKey(
        fields['sender_public_key'] as String,
      );
      final recipientHex = _normalizePublicKey(
        fields['recipient_public_key'] as String,
      );
      if (envelopeSenderHex != senderHex) throw const FormatException();

      receiverSigningKeyPair = _signingKeyPair(receiverKeyPair);
      if (!_constantTimeEquals(
            receiverSigningKeyPair.publicKey,
            receiverKeyPair.publicKey,
          ) ||
          recipientHex != receiverKeyPair.publicKeyHex.toLowerCase()) {
        throw const FormatException();
      }

      final signedFields = <String, Object>{
        'version': E2EEEnvelopeFormat.version,
        'algorithm': E2EEEnvelopeFormat.algorithm,
        'node_id': nodeId,
        'event_type': eventType,
        'sender_public_key': envelopeSenderHex,
        'recipient_public_key': recipientHex,
        'ciphertext': fields['ciphertext'] as String,
      };
      final signature = base64Decode(fields['signature'] as String);
      final senderPublicBytes = _hexToBytes(senderHex);
      final signatureIsValid = _sodium.crypto.sign.verifyDetached(
        message: _signatureMessage(signedFields),
        signature: signature,
        publicKey: senderPublicBytes,
      );
      if (!signatureIsValid) throw const FormatException();

      final receiverCurvePublic = _sodium.crypto.sign.pkToCurve25519(
        receiverSigningKeyPair.publicKey,
      );
      receiverCurveSecret = _sodium.crypto.sign.skToCurve25519(
        receiverSigningKeyPair.secretKey,
      );
      final ciphertext = base64Decode(fields['ciphertext'] as String);
      final cleartext = _sodium.crypto.box.sealOpen(
        cipherText: ciphertext,
        publicKey: receiverCurvePublic,
        secretKey: receiverCurveSecret,
      );
      final clearPayload = jsonDecode(utf8.decode(cleartext));
      if (clearPayload is! Map<String, dynamic>) {
        throw const FormatException();
      }
      return clearPayload;
    } catch (_) {
      throw StateError('The encrypted sync payload is invalid or unsupported.');
    } finally {
      receiverCurveSecret?.dispose();
      receiverSigningKeyPair?.dispose();
    }
  }

  @override
  bool verifySignerAuthenticity({
    required Map<String, dynamic> decryptedPayload,
    required String senderPublicKeyHex,
    required DigitalSignature signature,
  }) {
    try {
      final senderBytes = _hexToBytes(_normalizePublicKey(senderPublicKeyHex));
      if (!_constantTimeEquals(senderBytes, signature.signerPublicKey) ||
          signature.signatureBytes.length != _sodium.crypto.sign.bytes ||
          signature.payloadHash.length != 32) {
        return false;
      }
      final declaredHash = decryptedPayload['signature_payload_hash'];
      if (declaredHash is String &&
          declaredHash.toLowerCase() != signature.payloadHashHex) {
        return false;
      }
      return _sodium.crypto.sign.verifyDetached(
        message: signature.payloadHash,
        signature: signature.signatureBytes,
        publicKey: senderBytes,
      );
    } catch (_) {
      return false;
    }
  }

  KeyPair _signingKeyPair(CryptoKeyPair keyPair) {
    final signing = _sodium.crypto.sign;
    if ((keyPair.privateKey.length != signing.seedBytes &&
            keyPair.privateKey.length != signing.secretKeyBytes) ||
        keyPair.publicKey.length != signing.publicKeyBytes) {
      throw StateError('Secure identity key has an invalid length.');
    }
    final secretMaterial = _sodium.secureCopy(keyPair.privateKey);
    SecureKey? seed;
    try {
      seed = keyPair.privateKey.length == signing.secretKeyBytes
          ? signing.skToSeed(secretMaterial)
          : secretMaterial.copy();
      final derived = signing.seedKeyPair(seed);
      if (!_constantTimeEquals(derived.publicKey, keyPair.publicKey)) {
        derived.dispose();
        throw StateError('Secure identity key pair is inconsistent.');
      }
      return derived;
    } finally {
      seed?.dispose();
      secretMaterial.dispose();
    }
  }

  static Uint8List _signatureMessage(Map<String, Object> fields) =>
      Uint8List.fromList(<int>[
        ..._signatureDomain,
        ...utf8.encode(jsonEncode(fields)),
      ]);

  static void _validateContext(String nodeId, String eventType) {
    if (nodeId.trim().isEmpty || eventType.trim().isEmpty) {
      throw ArgumentError('A secure sync envelope requires event context.');
    }
  }

  static String _normalizePublicKey(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw const FormatException('Invalid Ed25519 public key.');
    }
    return normalized;
  }

  static Uint8List _hexToBytes(String value) {
    final normalized = _normalizePublicKey(value);
    final bytes = Uint8List(normalized.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(normalized.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}

/// Installed only if the native crypto provider cannot initialize. It lets the
/// app start but disables all sync encryption/decryption rather than falling
/// back to the legacy Base64 placeholder.
final class UnavailableE2EEEncryptionService implements E2EEEncryptionService {
  const UnavailableE2EEEncryptionService();

  @override
  Future<String> encryptPayload({
    required Map<String, dynamic> rawPayload,
    required CryptoKeyPair senderKeyPair,
    required String receiverPublicKeyHex,
    required String nodeId,
    required String eventType,
  }) async => throw StateError('Secure sync is unavailable on this device.');

  @override
  Future<Map<String, dynamic>> decryptPayload({
    required String encryptedPayload,
    required CryptoKeyPair receiverKeyPair,
    required String senderPublicKeyHex,
    required String nodeId,
    required String eventType,
  }) async => throw StateError('Secure sync is unavailable on this device.');

  @override
  bool verifySignerAuthenticity({
    required Map<String, dynamic> decryptedPayload,
    required String senderPublicKeyHex,
    required DigitalSignature signature,
  }) => false;
}
