import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:qayd/application/identity/setup_identity_use_case.dart';
import 'package:qayd/application/sync/credential_bootstrap_payload.dart';
import 'package:qayd/application/sync/device_pairing_qr_service.dart';
import 'package:qayd/application/sync/manual_link_service.dart';
import 'package:qayd/core/constants/api_endpoints.dart';
import 'package:qayd/data/network/api_client.dart';
import 'package:qayd/data/security/license_vault.dart';
import 'package:qayd/data/security/mnemonic_vault.dart';
import 'package:qayd/domain/entities/device_session.dart';
import 'package:qayd/domain/repositories/device_registry_repository.dart';
import 'package:qayd/domain/repositories/device_session_repository.dart';
import 'package:qayd/domain/services/e2ee_encryption_service.dart';
import 'package:qayd/domain/value_objects/crypto_key_pair.dart';
import 'package:qayd/domain/value_objects/mnemonic_phrase.dart';
import 'package:qayd/domain/services/crypto_identity_service.dart';
import 'package:uuid/uuid.dart';

class CompanionLinkSession {
  const CompanionLinkSession({
    required this.qrPayload,
    required this.socketSessionId,
    required this.ephemeralKeyPair,
    required this.nonce,
  });

  final String qrPayload;
  final String socketSessionId;
  final CryptoKeyPair ephemeralKeyPair;
  final String nonce;
}

class CompanionLinkService {
  CompanionLinkService({
    required this.qrService,
    required this.e2eeService,
    required this.apiClient,
    required this.mnemonicVault,
    required this.licenseVault,
    required this.setupIdentityUseCase,
    required this.getCurrentKeyPair,
    required this.cryptoIdentityService,
    required this.deviceRegistryRepository,
    required this.getCurrentDeviceId,
    this.deviceSessionRepository,
  });

  final DevicePairingQrService qrService;
  final E2EEEncryptionService e2eeService;
  final ApiClient apiClient;
  final MnemonicVault mnemonicVault;
  final LicenseVault licenseVault;
  final SetupIdentityUseCase setupIdentityUseCase;
  final Future<CryptoKeyPair?> Function() getCurrentKeyPair;
  final CryptoIdentityService cryptoIdentityService;
  final DeviceRegistryRepository deviceRegistryRepository;
  final Future<String> Function() getCurrentDeviceId;
  // Injected after the SQLite stack is initialized (post-DB-open).
  // See InjectionContainer._initializeDatabaseDependentStack.
  DeviceSessionRepository? deviceSessionRepository;

  final Set<String> _usedNonces = <String>{};

  CompanionLinkSession startReceiverSession() {
    // Clear nonces from previous sessions to prevent unbounded accumulation.
    // Each QR has its own nonce, so old ones are irrelevant after the session expires.
    _usedNonces.clear();

    final ephemeral = _generateEphemeralKeyPair();
    final sessionId = const Uuid().v4();
    final qr = qrService.generateCompanionLinkQr(
      ephemeralPublicKeyHex: ephemeral.publicKeyHex,
      socketSessionId: sessionId,
    );
    final decoded = qrService.parseCompanionLinkQr(qr)!;
    return CompanionLinkSession(
      qrPayload: qr,
      socketSessionId: sessionId,
      ephemeralKeyPair: ephemeral,
      nonce: decoded.nonce,
    );
  }

  Future<void> sendBootstrapToCompanion({required String scannedQr}) async {
    final parsed = qrService.parseCompanionLinkQr(scannedQr);
    if (parsed == null) {
      throw StateError('Invalid companion QR payload.');
    }
    await _buildAndSendBootstrap(
      ephemeralPublicKeyHex: parsed.ephemeralPublicKeyHex,
      socketSessionId: parsed.socketSessionId,
      nonce: parsed.nonce,
    );
  }

  /// COMPANION DEVICE (Manual Code flow):
  /// Generates an ephemeral session and submits the companion's public key
  /// to the server using the short code entered by the user.
  ///
  /// Returns the [CompanionLinkSession] that will be used to poll for the
  /// bootstrap payload from the Primary (same as the QR flow after this point).
  Future<CompanionLinkSession> submitViaManualCode({
    required String shortCode,
    required ManualLinkService manualLinkService,
  }) async {
    // Generate a fresh ephemeral key pair — same as startReceiverSession().
    _usedNonces.clear();
    final ephemeral = _generateEphemeralKeyPair();
    final sessionId = const Uuid().v4();
    final qr = qrService.generateCompanionLinkQr(
      ephemeralPublicKeyHex: ephemeral.publicKeyHex,
      socketSessionId: sessionId,
    );
    final decoded = qrService.parseCompanionLinkQr(qr)!;

    // Submit the companion's data to the server using the manual code.
    final success = await manualLinkService.submitCompanionData(
      shortCode: shortCode,
      companionSessionId: sessionId,
      companionEphemeralKey: ephemeral.publicKeyHex,
      companionNonce: decoded.nonce,
    );

    if (!success) {
      throw StateError(
        'Failed to submit companion data for short code: $shortCode',
      );
    }

    return CompanionLinkSession(
      qrPayload: qr,
      socketSessionId: sessionId,
      ephemeralKeyPair: ephemeral,
      nonce: decoded.nonce,
    );
  }

  /// PRIMARY DEVICE (Manual Code flow):
  /// Builds the bootstrap payload using companion data received via the server
  /// (no QR scan required) and sends it to the bootstrap endpoint.
  Future<void> sendBootstrapToCompanionViaCode({
    required CompanionPairingData companionData,
  }) async {
    await _buildAndSendBootstrap(
      ephemeralPublicKeyHex: companionData.companionEphemeralKey,
      socketSessionId: companionData.companionSessionId,
      nonce: companionData.companionNonce,
    );
  }

  /// Core bootstrap builder — shared between QR and Manual Code flows.
  Future<void> _buildAndSendBootstrap({
    required String ephemeralPublicKeyHex,
    required String socketSessionId,
    required String nonce,
  }) async {
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(const Duration(minutes: 30));
    final mnemonic = await mnemonicVault.readMnemonic();
    final jwt = await licenseVault.readJwt();
    final senderPair = await getCurrentKeyPair();
    if (mnemonic == null || jwt == null || jwt.isEmpty || senderPair == null) {
      throw StateError('Missing secure credentials for bootstrap.');
    }

    // --- CROSS-SIGNING LOGIC ---
    final payloadToSign = utf8.encode(
      'device_certificate:$ephemeralPublicKeyHex',
    );
    final hash = Uint8List.fromList(sha256.convert(payloadToSign).bytes);
    final signature = cryptoIdentityService.sign(hash, senderPair);
    final deviceCertificate = signature.signatureHex;

    final payload = CredentialBootstrapPayload(
      version: 1,
      nonce: nonce,
      mnemonic: mnemonic.phrase,
      jwt: jwt,
      issuedAtIso: now.toIso8601String(),
      expiresAtIso: expiresAt.toIso8601String(),
      licenseData: await licenseVault.readLicenseData(),
      deviceCertificate: deviceCertificate,
    );

    final encrypted = await e2eeService.encryptPayload(
      rawPayload: payload.toMap(),
      senderKeyPair: senderPair,
      receiverPublicKeyHex: ephemeralPublicKeyHex,
      nodeId: socketSessionId,
      eventType: 'credentialBootstrap',
    );
    await apiClient.post(
      ApiEndpoints.devicesCompanionBootstrap,
      body: {
        'socket_session_id': socketSessionId,
        'encrypted_payload': encrypted,
        'nonce': nonce,
        'expires_at': expiresAt.toIso8601String(),
      },
    );
  }

  Future<bool> pollAndConsumeBootstrap({
    required CompanionLinkSession session,
    VoidCallback? onPayloadReceived,
  }) async {
    debugPrint(
      'CompanionLink: 🔍 Polling bootstrap for session: ${session.socketSessionId}',
    );

    // NOTE: apiClient.post() calls _extractData() internally, which already
    // unwraps the API envelope and returns body['data'] directly.
    // So when the server returns {"status":"success","data":null}  → returns null.
    // When server returns {"status":"success","data":{...}}        → returns {...}.
    // We must NOT do res['data'] again — the unwrapping is already done.
    dynamic rawResponse;
    try {
      rawResponse = await apiClient.post(
        ApiEndpoints.devicesCompanionConsume,
        body: {'socket_session_id': session.socketSessionId},
      );
    } catch (e) {
      debugPrint('CompanionLink: ❌ Poll request failed: $e');
      return false;
    }

    // null means no bootstrap record exists yet — keep polling silently.
    if (rawResponse == null) return false;

    final Map<String, dynamic> data = rawResponse as Map<String, dynamic>;

    final encrypted = data['encrypted_payload'] as String?;
    final senderPublicKey = data['sender_public_key'] as String?;

    debugPrint(
      'CompanionLink: 🔍 Extracted - encrypted: ${encrypted != null}, senderKey: ${senderPublicKey != null}',
    );

    if (encrypted == null || senderPublicKey == null) {
      return false;
    }

    debugPrint('CompanionLink: 📦 Bootstrap payload received. Decrypting...');
    Map<String, dynamic> payload;
    try {
      payload = await e2eeService.decryptPayload(
        encryptedPayload: encrypted,
        receiverKeyPair: session.ephemeralKeyPair,
        senderPublicKeyHex: senderPublicKey,
        nodeId: session.socketSessionId,
        eventType: 'credentialBootstrap',
      );
      debugPrint('CompanionLink: ✅ Decryption successful.');
    } catch (e) {
      debugPrint('CompanionLink: ❌ Decryption failed: $e');
      return false;
    }

    final model = CredentialBootstrapPayload.fromMap(payload);
    // Don't add to _usedNonces until we are sure persistence succeeds,
    // otherwise a DB error will cause permanent 'stale bootstrap' on retry.
    if (!_validateNonceAndFreshness(model, session.nonce)) {
      debugPrint('CompanionLink: ⚠️ Nonce/freshness check failed.');
      return false;
    }

    // Notify the UI that the payload was received and validated,
    // so it can hide the QR code and show a migration progress indicator.
    onPayloadReceived?.call();

    try {
      debugPrint('CompanionLink: 💾 Persisting bootstrap credentials...');
      // §C-1: Persist mnemonic + JWT for data access, and save the cross-signed
      // ephemeral keypair as this companion device's own identity.
      final companionKeyPair = await _persistBootstrap(
        model,
        session.ephemeralKeyPair,
      );
      debugPrint('CompanionLink: 🔑 Companion keypair persisted locally.');

      // §C-4: Register the companion's unique device key on the server.
      await mnemonicVault.markServerKeyRegistered();

      debugPrint('CompanionLink: 📡 Registering companion on server...');
      await _registerCompanionDeviceWithOwnKey(
        companionKeyPair,
        model.deviceCertificate,
      );

      // Mark nonce as used only AFTER successful persistence to allow retries on DB failure
      _usedNonces.add(model.nonce);
      debugPrint('CompanionLink: 🎉 Registration process completed.');

      return true;
    } catch (e, stack) {
      debugPrint('CompanionLink: ❌ FATAL error: $e\n$stack');
      return false;
    }
  }

  /// Persists the bootstrap credentials and sets up the mnemonic identity
  /// for data access. Returns the **companion-specific keypair** which has
  /// been cross-signed by the Primary.
  ///
  /// §C-1 Security Note:
  /// The mnemonic received from Primary is used to restore data access
  /// (voucher decryption keys), but the companion uses its OWN
  /// Ed25519 keypair for device authentication and sync routing.
  /// This prevents the identity mismatch where both devices fight over
  /// the same public key on the server.
  Future<CryptoKeyPair> _persistBootstrap(
    CredentialBootstrapPayload payload,
    CryptoKeyPair ephemeralKeyPair,
  ) async {
    debugPrint('CompanionLink: 💾 Writing JWT and license data...');
    // §C-7: Reset the initial sync flag before writing new credentials.
    // This ensures the companion_link_page waits for a fresh snapshot
    // even if a previous pairing had already set this flag to true.
    await licenseVault.resetInitialSyncStatus();

    await licenseVault.writeJwt(payload.jwt);

    await licenseVault.setIsCompanionDevice(true);
    if (payload.licenseData != null) {
      await licenseVault.writeLicenseData(payload.licenseData!);
    }

    // Restore mnemonic for data-layer key derivation (voucher encryption).
    // primaryLicenseData is passed so recoverFromMnemonic skips server
    // re-registration of the Primary's key under our identity.
    debugPrint('CompanionLink: 🔐 Recovering identity from mnemonic...');
    try {
      await setupIdentityUseCase.recoverFromMnemonic(
        MnemonicPhrase.fromPhrase(payload.mnemonic),
        primaryLicenseData: payload.licenseData,
      );
      debugPrint('CompanionLink: ✅ Identity recovery successful.');
    } catch (e) {
      debugPrint('CompanionLink: ❌ Identity recovery failed: $e');
      rethrow;
    }

    // §C-1: Save the ephemeral keypair as the unique keypair for this companion device.
    // This is entirely separate from the mnemonic-derived Primary key.
    // The Primary device has already cross-signed this keypair.
    debugPrint(
      'CompanionLink: 🔑 Storing unique companion keypair (already signed by primary)...',
    );
    await mnemonicVault.writeKeyPair(ephemeralKeyPair);

    debugPrint(
      'CompanionLink: ✅ Companion device key set to: '
      '${ephemeralKeyPair.publicKeyHex.substring(0, 8)}…',
    );
    return ephemeralKeyPair;
  }

  /// Registers the companion's OWN unique keypair with the server.
  /// This is distinct from the Primary's keypair stored in license_data.
  ///
  /// §C-4: We ONLY register with devices/pair — never with identity/register-key.
  /// The companion's unique key lives in user_devices.public_key only.
  /// The account's users.public_key remains the Primary's key, untouched.
  Future<void> _registerCompanionDeviceWithOwnKey(
    CryptoKeyPair companionKeyPair,
    String? deviceCertificate,
  ) async {
    final publicKeyHex = companionKeyPair.publicKeyHex.toLowerCase();
    final deviceId = await getCurrentDeviceId();
    final now = DateTime.now();
    debugPrint(
      'CompanionLink: 🆔 Attempting to register device: $deviceId with key: ${publicKeyHex.substring(0, 10)}...',
    );

    // Use the cross-signed device certificate if available, otherwise fallback.
    final signedChallenge =
        deviceCertificate ??
        'companion-bootstrap:$deviceId:${DateTime.now().millisecondsSinceEpoch}';
    try {
      final serverSession = await deviceRegistryRepository.pairDevice(
        deviceId: deviceId,
        deviceName: 'Companion Device',
        publicKeyHex: publicKeyHex,
        signedChallenge: signedChallenge,
      );
      debugPrint(
        'CompanionLink: companion registered on server '
        '[key: ${publicKeyHex.substring(0, 8)}…, device: $deviceId]',
      );

      // §C-6: Also persist this companion's session locally so it appears
      // in the device list on the Companion device itself. Without this,
      // only the Primary's session is visible in SQLite.
      final sessionRepo = deviceSessionRepository;
      if (sessionRepo != null) {
        await sessionRepo.upsert(
          DeviceSession(
            deviceId: serverSession.deviceId,
            deviceName: serverSession.deviceName ?? 'Companion Device',
            publicKeyHex: serverSession.publicKeyHex,
            pairedAt: serverSession.pairedAt,
            lastSyncSeq: serverSession.lastSyncSeq,
            lastSeenAt: serverSession.lastSeenAt ?? now,
            isCurrent: true, // This IS the current device.
            isActive: serverSession.isActive,
            role: serverSession.role,
          ),
        );
        debugPrint('CompanionLink: ✅ Companion session persisted to local DB.');
      }
    } catch (e) {
      // Non-fatal — credentials are already persisted.
      // The device will re-register on next app start via the normal device refresh.
      debugPrint('CompanionLink: ❌ server device registration deferred: $e');
    }
  }

  bool _validateNonceAndFreshness(
    CredentialBootstrapPayload payload,
    String expectedNonce,
  ) {
    if (payload.nonce.isEmpty || payload.nonce != expectedNonce) return false;
    if (_usedNonces.contains(payload.nonce)) return false;

    final issuedAt = DateTime.tryParse(payload.issuedAtIso);
    final expiresAt = DateTime.tryParse(payload.expiresAtIso);
    final now = DateTime.now().toUtc();
    if (issuedAt == null || expiresAt == null) return false;
    if (now.isAfter(expiresAt)) return false;
    if (issuedAt.isAfter(now.add(const Duration(minutes: 1)))) return false;
    return true;
  }

  CryptoKeyPair _generateEphemeralKeyPair() {
    final mnemonic = cryptoIdentityService.generateMnemonic();
    return cryptoIdentityService.deriveKeyPair(mnemonic);
  }
}
