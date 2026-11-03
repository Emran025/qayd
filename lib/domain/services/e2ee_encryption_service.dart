import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/value_objects/digital_signature.dart';

/// End-to-end encryption for sync data. Implementations must fail closed: a
/// payload that cannot be authenticated and decrypted is never returned.
abstract interface class E2EEEncryptionService {
  /// Seals a JSON payload for [receiverPublicKeyHex] and authenticates it with
  /// [senderKeyPair]. The signed envelope binds the payload to [nodeId] and
  /// [eventType], so relay metadata cannot be changed independently.
  Future<String> encryptPayload({
    required Map<String, dynamic> rawPayload,
    required CryptoKeyPair senderKeyPair,
    required String receiverPublicKeyHex,
    required String nodeId,
    required String eventType,
  });

  /// Authenticates and decrypts a versioned envelope using the receiver's
  /// Ed25519 seed and the sender's already-resolved Ed25519 public key.
  Future<Map<String, dynamic>> decryptPayload({
    required String encryptedPayload,
    required CryptoKeyPair receiverKeyPair,
    required String senderPublicKeyHex,
    required String nodeId,
    required String eventType,
  });

  /// Verifies a signed payload digest and confirms the signer key is exactly
  /// [senderPublicKeyHex]. The caller remains responsible for constructing and
  /// comparing the digest against its domain-specific canonical payload.
  bool verifySignerAuthenticity({
    required Map<String, dynamic> decryptedPayload,
    required String senderPublicKeyHex,
    required DigitalSignature signature,
  });
}
