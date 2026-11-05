import 'dart:convert';

/// Version marker and conservative parser for the serialized E2EE envelope.
///
/// This is used only to prevent legacy/plain payloads from being re-sent. It is
/// not a substitute for signature verification or decryption, which are always
/// performed by [E2EEEncryptionServiceImpl].
abstract final class E2EEEnvelopeFormat {
  static const int version = 1;
  static const String algorithm = 'qayd-sealedbox-ed25519-v1';

  static bool isSupported(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return false;
      return decoded['version'] == version &&
          decoded['algorithm'] == algorithm &&
          _isNonEmptyString(decoded['node_id']) &&
          _isNonEmptyString(decoded['event_type']) &&
          _isPublicKey(decoded['sender_public_key']) &&
          _isPublicKey(decoded['recipient_public_key']) &&
          _isNonEmptyString(decoded['ciphertext']) &&
          _isNonEmptyString(decoded['signature']);
    } catch (_) {
      return false;
    }
  }

  static bool _isNonEmptyString(Object? value) =>
      value is String && value.isNotEmpty;

  static bool _isPublicKey(Object? value) =>
      value is String && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
}
