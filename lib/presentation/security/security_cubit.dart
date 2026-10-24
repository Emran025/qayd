import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qayd/core/error/exceptions.dart';
import 'package:qayd/data/security/app_pin_storage.dart';
import 'package:qayd/data/security/hardware_id_service.dart';
import 'package:qayd/data/security/license_vault.dart';
import 'package:qayd/data/security/monotonic_clock_guard.dart';
import 'package:qayd/data/security/panic_wipe_service.dart';
import 'package:qayd/di/injection_container.dart';
import 'package:qayd/domain/repositories/auth_repository.dart';
import 'package:qayd/application/identity/sync_identity_to_internal_accounts_use_case.dart';
import 'package:qayd/presentation/security/security_state.dart';
import 'package:qayd/presentation/l10n/app_strings.dart';

/// Unified security cubit.
///
/// Responsibilities (Phase 7):
///   1. PIN / biometric lock (existing).
///   2. License status: pending → trial → active | trialExpired | revoked | deviceUnbound.
///   3. Monotonic clock tamper detection.
///   4. Panic wipe on FORCE_REVOKE.
class SecurityCubit extends Cubit<SecurityState> {
  SecurityCubit({
    required AppPinStorage pinStorage,
    required LicenseVault licenseVault,
    required HardwareIdService hardwareIdService,
    required MonotonicClockGuard clockGuard,
    required PanicWipeService panicWipeService,
    required AuthRepository authRepository,
    SyncIdentityToInternalAccountsUseCase? syncIdentityUseCase,
    LocalAuthentication? localAuth,
    Duration lockAfterBackground = const Duration(minutes: 5),
  })  : _pinStorage = pinStorage,
        _licenseVault = licenseVault,
        _hardwareIdService = hardwareIdService,
        _clockGuard = clockGuard,
        _panicWipeService = panicWipeService,
        _authRepository = authRepository,
        _syncIdentityUseCase = syncIdentityUseCase,
        _localAuth = localAuth ?? LocalAuthentication(),
        _lockAfterBackground = lockAfterBackground,
        super(
          const SecurityUnlocked(
            licenseStatus: LicenseStatus.booting,
            trialDaysRemaining: LicenseVault.trialDurationDays,
          ),
        );

  final AppPinStorage _pinStorage;
  final LicenseVault _licenseVault;
  final HardwareIdService _hardwareIdService;
  final MonotonicClockGuard _clockGuard;
  final PanicWipeService _panicWipeService;
  final AuthRepository _authRepository;
  SyncIdentityToInternalAccountsUseCase? _syncIdentityUseCase;
  final LocalAuthentication _localAuth;
  final Duration _lockAfterBackground;

  /// Late-bind the sync identity use case after the database is ready.
  set syncIdentityUseCase(SyncIdentityToInternalAccountsUseCase uc) =>
      _syncIdentityUseCase = uc;

  DateTime? _pausedAt;

  // ── Boot sequence ─────────────────────────────────────────────────────────

  /// Must be called once after construction, before rendering.
  Future<void> bootCheck() async {
    // 1. Clock tamper detection.
    final tampered = await _clockGuard.detectTamper();
    if (tampered) {
      final trialDays = await trialDaysRemaining();
      emit(_withClock(ClockStatus.tampered, trialDaysRemaining: trialDays));
      return;
    }

    // 2. License check (Returns persisted settings from the vault).
    final (licenseStatus, ownerAcc, payInstr, updUrl, bReason) =
        await _resolveLicenseStatus();

    // Only show trial days if we are actually in a trial state.
    final trialDays = (licenseStatus == LicenseStatus.trial ||
            licenseStatus == LicenseStatus.trialExpired)
        ? await trialDaysRemaining()
        : null;

    // 3. If FORCE_REVOKE — wipe immediately.
    if (licenseStatus == LicenseStatus.revoked) {
      await _panicWipeService.wipeAll();
      emit(
        _buildState(
          licenseStatus: LicenseStatus.revoked,
          clockStatus: ClockStatus.clean,
          trialDaysRemaining: trialDays,
          ownerAccountNumber: ownerAcc,
          paymentInstructionsAr: payInstr,
          updateUrl: updUrl,
          banReason: bReason,
        ),
      );
      return;
    }

    // 4. PIN lock on startup if enabled.
    final lockEnabled = await _pinStorage.isLockEnabled();
    final hasPin = await _pinStorage.hasPinConfigured();
    final shouldPinLock = lockEnabled && hasPin;

    // 5. Sync identity to internal accounts (Owner link)
    // Only call if DB is ready (Phase B completed).
    if (InjectionContainer.isDatabaseReady) {
      _syncIdentityUseCase?.call().ignore();
    }

    // 6. Retry any pending server key registration (non-blocking).
    InjectionContainer.setupIdentityUseCase.ensureServerRegistration().ignore();

    emit(
      shouldPinLock
          ? SecurityLocked(
              licenseStatus: licenseStatus,
              trialDaysRemaining: trialDays,
              ownerAccountNumber: ownerAcc,
              paymentInstructionsAr: payInstr,
              updateUrl: updUrl,
              banReason: bReason,
            )
          : SecurityUnlocked(
              licenseStatus: licenseStatus,
              trialDaysRemaining: trialDays,
              ownerAccountNumber: ownerAcc,
              paymentInstructionsAr: payInstr,
              updateUrl: updUrl,
              banReason: bReason,
            ),
    );
  }

  Future<(LicenseStatus, String?, String?, String?, String?)>
      _resolveLicenseStatus() async {
    final provisioned = await _licenseVault.isProvisioned();
    if (!provisioned) return (LicenseStatus.pending, null, null, null, null);

    // Verify hardware binding.
    final currentHwId = await _hardwareIdService.obtainHardwareId();
    final boundHwId = await _licenseVault.readProvisionedHardwareId();
    if (boundHwId != null && boundHwId.isNotEmpty && boundHwId != currentHwId) {
      return (LicenseStatus.deviceUnbound, null, null, null, null);
    }

    // Read license data.
    final data = await _licenseVault.readLicenseData();
    String? ownerAcc;
    String? payInstr;

    if (data != null) {
      final status = data['status'] as String? ?? '';
      final hasFormalLicense = data['has_formal_license'] as bool? ?? false;
      final isActive = data['is_active'] as bool? ?? true;
      final accountClosed = data['account_closed'] as bool? ?? false;

      // Extract payment details from nested settings (attached to license)
      final settings = data['settings'] as Map<String, dynamic>?;
      String? updateUrl;
      String? banReason;

      if (settings != null) {
        ownerAcc = settings['owner_payment_account'] as String?;
        payInstr = settings['support_message_ar'] as String?;
        updateUrl = settings['app_update_url'] as String?;

        // ── App Version Check ────────────────────────────────────────────────
        final minVer = settings['min_android_version'] as String?;
        final forceUpd = settings['force_update']?.toString() == '1';

        if (minVer != null) {
          final packageInfo = await PackageInfo.fromPlatform();
          final currentVer = packageInfo.version;
          if (_isUpdateRequired(currentVer, minVer) && forceUpd) {
            return (
              LicenseStatus.updateRequired,
              ownerAcc,
              payInstr,
              updateUrl,
              null
            );
          }
        }
      }

      // ── Ban Check ──────────────────────────────────────────────────────────
      final isBanned = data['is_banned'] as bool? ?? false;
      banReason = data['ban_reason'] as String?;
      if (isBanned) {
        return (LicenseStatus.banned, ownerAcc, payInstr, updateUrl, banReason);
      }

      // Hard admin revoke (FORCE_REVOKE) or deactivated account → panic wipe.
      if (status == 'FORCE_REVOKE' || status == 'revoked') {
        return (
          LicenseStatus.revoked,
          ownerAcc,
          payInstr,
          updateUrl,
          banReason
        );
      }
      // Admin deactivated the user account (not a payment issue) → revoke.
      if (!isActive) {
        return (
          LicenseStatus.revoked,
          ownerAcc,
          payInstr,
          updateUrl,
          banReason
        );
      }
      // Trial ended without a formal license → hard lock (NO panic wipe).
      if (accountClosed) {
        return (
          LicenseStatus.trialExpired,
          ownerAcc,
          payInstr,
          updateUrl,
          banReason
        );
      }
      // Full active license or server confirmed active status.
      if (hasFormalLicense || status == 'active') {
        return (LicenseStatus.active, ownerAcc, payInstr, updateUrl, banReason);
      }
      // Admin-suspended → read-only.
      if (status == 'suspended') {
        return (
          LicenseStatus.suspended,
          ownerAcc,
          payInstr,
          updateUrl,
          banReason
        );
      }
    }

    // Fall back to trial clock.
    final trialStart = await _licenseVault.readTrialStart();
    if (trialStart == null) {
      await _licenseVault.writeTrialStart(DateTime.now().toUtc());
      return (LicenseStatus.trial, null, null, null, null);
    }
    if (_licenseVault.isTrialExpired(trialStart)) {
      return (LicenseStatus.trialExpired, null, null, null, null);
    }
    return (LicenseStatus.trial, null, null, null, null);
  }

  /// Semver comparison helper. Returns true if current < required.
  bool _isUpdateRequired(String current, String required) {
    try {
      final curParts = current.split('.').map(int.parse).toList();
      final reqParts = required.split('.').map(int.parse).toList();

      for (var i = 0; i < reqParts.length; i++) {
        final cur = i < curParts.length ? curParts[i] : 0;
        final req = reqParts[i];
        if (cur < req) return true;
        if (cur > req) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  bool _isRefreshing = false;
  DateTime? _lastRefreshAt;
  DateTime? _blockedUntil;

  /// Refreshes the license state from the server and updates the lock state.
  ///
  /// [isManual] indicates a user-initiated refresh (cooldown: 30s).
  /// [isForced] indicates a system-triggered refresh (e.g. 403 Interceptor) which bypasses all timers.
  Future<({bool success, String? errorAr})> refreshLicenseStatus({
    bool isManual = false,
    bool isForced = false,
  }) async {
    if (_isRefreshing) return (success: true, errorAr: null);

    final now = DateTime.now();

    // ── Server-driven Rate Limiting (429 Too Many Requests) ──────────
    if (_blockedUntil != null && now.isBefore(_blockedUntil!)) {
      final waitSecs = _blockedUntil!.difference(now).inSeconds;
      return (
        success: false,
        errorAr: AppStrings.waitSecondsBeforeRetry(waitSecs),
      );
    }

    // ── Throttling Logic ─────────────────────────────────────────────────────
    if (isForced) {
      // Even forced refreshes should be throttled to prevent API spam loops
      // if multiple requests fail with 403 simultaneously.
      if (_lastRefreshAt != null &&
          now.difference(_lastRefreshAt!) < const Duration(seconds: 10)) {
        return (success: true, errorAr: null);
      }
    } else {
      if (isManual) {
        // Manual refresh cooldown: 30 seconds to prevent spamming.
        if (_lastRefreshAt != null &&
            now.difference(_lastRefreshAt!) < const Duration(seconds: 30)) {
          return (
            success: false,
            errorAr: AppStrings.pleaseWaitAFewMinutes, // Generic "wait" message
          );
        }
      } else {
        // Automatic refresh (on resume) cooldown: 1 hour.
        // We only poll automatically if enough time has passed.
        if (_lastRefreshAt != null &&
            now.difference(_lastRefreshAt!) < const Duration(hours: 1)) {
          return (success: true, errorAr: null);
        }
      }
    }
    // ──────────────────────────────────────────────────────────────────────────

    _isRefreshing = true;
    // Set the cooldown timestamp BEFORE making the network call so that
    // failed requests (like 429) don't bypass the local cooldown.
    _lastRefreshAt = now;

    try {
      final newData = await _authRepository.refreshLicense();

      // Clear any previous blocks on success
      _blockedUntil = null;

      // Merge new status fields into the existing license data
      final existingData = await _licenseVault.readLicenseData() ?? {};

      // Keys matching what the backend's /license/refresh returns
      if (newData.containsKey('status')) {
        existingData['status'] = newData['status'];
      }
      if (newData.containsKey('is_active')) {
        existingData['is_active'] = newData['is_active'];
      }
      if (newData.containsKey('has_formal_license')) {
        existingData['has_formal_license'] = newData['has_formal_license'];
      }
      if (newData.containsKey('account_closed')) {
        existingData['account_closed'] = newData['account_closed'];
      }
      if (newData.containsKey('settings')) {
        existingData['settings'] = newData['settings'];
      }
      if (newData.containsKey('is_banned')) {
        existingData['is_banned'] = newData['is_banned'];
      }
      if (newData.containsKey('ban_reason')) {
        existingData['ban_reason'] = newData['ban_reason'];
      }
      if (newData.containsKey('device_role')) {
        final dr = newData['device_role'] as String?;
        if (dr != null) {
          existingData['device_role'] = dr;
          await _licenseVault.setIsCompanionDevice(dr == 'companion');
        }
      }

      await _licenseVault.writeLicenseData(existingData);

      final (ls, ownerAcc, payInstr, updUrl, bReason) =
          await _resolveLicenseStatus();

      // Only show trial days if we are actually in a trial state.
      final trialDays =
          (ls == LicenseStatus.trial || ls == LicenseStatus.trialExpired)
              ? _licenseVault.daysRemainingInTrial(
                  await _licenseVault.readTrialStart() ?? DateTime.now(),
                )
              : null;

      if (ls != LicenseStatus.active && ls != LicenseStatus.trial) {
        emit(SecurityLocked(
          licenseStatus: ls,
          clockStatus: state.clockStatus,
          trialDaysRemaining: trialDays,
          ownerAccountNumber: ownerAcc,
          paymentInstructionsAr: payInstr,
          updateUrl: updUrl,
          banReason: bReason,
        ));
      } else {
        // If the license is active/trial, we return to the previous PIN lock state
        // (either SecurityLocked or SecurityUnlocked) instead of forcing Unlocked.
        if (state is SecurityLocked) {
          emit(SecurityLocked(
            licenseStatus: ls,
            clockStatus: state.clockStatus,
            trialDaysRemaining: trialDays,
            ownerAccountNumber: ownerAcc,
            paymentInstructionsAr: payInstr,
            updateUrl: updUrl,
            banReason: bReason,
          ));
        } else {
          emit(SecurityUnlocked(
            licenseStatus: ls,
            clockStatus: state.clockStatus,
            trialDaysRemaining: trialDays,
            ownerAccountNumber: ownerAcc,
            paymentInstructionsAr: payInstr,
            updateUrl: updUrl,
            banReason: bReason,
          ));
        }
      }

      return (success: true, errorAr: null);
    } on AuthException catch (e) {
      if (e.retryAfterSeconds != null) {
        _blockedUntil =
            DateTime.now().add(Duration(seconds: e.retryAfterSeconds!));
      }
      return (success: false, errorAr: e.messageAr);
    } catch (e) {
      return (success: false, errorAr: AppStrings.failedToUpdateLicense);
    } finally {
      _isRefreshing = false;
    }
  }

  // ── PIN preferences ───────────────────────────────────────────────────────

  Future<void> refreshPreferences() async {
    final lockOn = await _pinStorage.isLockEnabled();
    final hasPin = await _pinStorage.hasPinConfigured();
    final ls = state.licenseStatus;
    final cs = state.clockStatus;
    if (!lockOn || !hasPin) {
      emit(
        SecurityUnlocked(
          licenseStatus: ls,
          clockStatus: cs,
          trialDaysRemaining: state.trialDaysRemaining,
          ownerAccountNumber: state.ownerAccountNumber,
          paymentInstructionsAr: state.paymentInstructionsAr,
        ),
      );
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void onAppLifecycle(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      // Stamp the monotonic clock every time we background.
      _clockGuard.stamp();
      return;
    }
    if (lifecycle == AppLifecycleState.resumed) {
      _maybeLockOnResume();
      // Proactively refresh license status on resume to catch bans or payment updates.
      if (InjectionContainer.isDatabaseReady &&
          state.licenseStatus != LicenseStatus.pending) {
        refreshLicenseStatus().ignore();
      }
    }
  }

  Future<void> _maybeLockOnResume() async {
    final enabled = await _pinStorage.isLockEnabled();
    final hasPin = await _pinStorage.hasPinConfigured();
    if (!enabled || !hasPin) return;
    final t = _pausedAt;
    if (t == null) return;
    if (DateTime.now().difference(t) >= _lockAfterBackground) {
      emit(
        SecurityLocked(
          licenseStatus: state.licenseStatus,
          clockStatus: state.clockStatus,
          trialDaysRemaining: state.trialDaysRemaining,
          ownerAccountNumber: state.ownerAccountNumber,
          paymentInstructionsAr: state.paymentInstructionsAr,
        ),
      );
    }
    _pausedAt = null;
  }

  // ── PIN unlock ────────────────────────────────────────────────────────────

  Future<void> unlockWithPin(String pin) async {
    final ok = await _pinStorage.verifyPin(pin);
    if (ok) {
      emit(
        SecurityUnlocked(
          licenseStatus: state.licenseStatus,
          clockStatus: state.clockStatus,
          trialDaysRemaining: state.trialDaysRemaining,
          ownerAccountNumber: state.ownerAccountNumber,
          paymentInstructionsAr: state.paymentInstructionsAr,
        ),
      );
    }
  }

  Future<bool> unlockWithBiometric({required String localizedReason}) async {
    final enabled = await _pinStorage.isBiometricEnabled();
    if (!enabled) return false;
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      final ok = await _localAuth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        emit(
          SecurityUnlocked(
            licenseStatus: state.licenseStatus,
            clockStatus: state.clockStatus,
            trialDaysRemaining: state.trialDaysRemaining,
            ownerAccountNumber: state.ownerAccountNumber,
            paymentInstructionsAr: state.paymentInstructionsAr,
          ),
        );
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> canUseBiometric() async {
    if (!await _pinStorage.isBiometricEnabled()) return false;
    try {
      if (!await _localAuth.isDeviceSupported()) return false;
      final biometrics = await _localAuth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── API provisioning ──────────────────────────────────────────────────────

  /// Login to governance API and store credentials.
  Future<ProvisioningResult> provisionDevice({
    required String email,
    required String password,
  }) async {
    try {
      final hardwareId = await _hardwareIdService.obtainHardwareId();

      final result = await _authRepository.login(
        email: email,
        password: password,
        deviceId: hardwareId,
      );

      return await _handleAuthResponse(result, hardwareId);
    } on AuthException catch (e) {
      return ProvisioningResult.failure(e.messageAr);
    } catch (e, stack) {
      debugPrint('Provisioning Error: $e\n$stack');
      return ProvisioningResult.failure(
        AppStrings.anUnexpectedErrorOccurred1,
      );
    }
  }

  /// Register a new account and provision the device.
  Future<ProvisioningResult> registerDevice({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final hardwareId = await _hardwareIdService.obtainHardwareId();

      final result = await _authRepository.register(
        name: name,
        email: email,
        phone: phone,
        password: password,
        deviceId: hardwareId,
      );

      return await _handleAuthResponse(result, hardwareId);
    } on AuthException catch (e) {
      return ProvisioningResult.failure(e.messageAr);
    } catch (e, stack) {
      debugPrint('Registration Error: $e\n$stack');
      return ProvisioningResult.failure(
        AppStrings.anUnexpectedErrorOccurred2,
      );
    }
  }

  Future<ProvisioningResult> _handleAuthResponse(
    ({String jwt, Map<String, dynamic> licenseData, String serverSalt}) result,
    String hardwareId,
  ) async {
    try {
      // --- ACCOUNT SWITCH DETECTION ---
      final oldLicenseData = await _licenseVault.readLicenseData();
      final oldUserId = oldLicenseData?['id'] as int?;
      final newUserId = result.licenseData['id'] as int?;

      final localKeyPair = await InjectionContainer.mnemonicVault.readKeyPair();
      final localPublicKey = localKeyPair?.publicKeyHex;
      final serverPublicKey = result.licenseData['public_key'] as String?;

      final isDifferentAccount =
          oldUserId != null && newUserId != null && oldUserId != newUserId;

      // Check if the identity restored from file storage belongs to a different user.
      // If serverPublicKey is empty, it might be a fresh account on the server,
      // so we don't treat it as "different" yet to allow for identity binding.
      final isDifferentIdentity = localPublicKey != null &&
          serverPublicKey != null &&
          serverPublicKey.isNotEmpty &&
          localPublicKey != serverPublicKey;

      // If we have evidence of a DIFFERENT user (IDs don't match or keys don't match), we wipe.
      // If it's a fresh install (oldUserId == null) but we found a restored identity
      // that belongs to a different user, we wipe.
      // We do NOT wipe if it's a fresh install and we found a restored database but no identity yet,
      // to give the user a chance to recover via mnemonic if it's actually their account.
      final isDifferentUserDetected = isDifferentAccount || isDifferentIdentity;
      // Fallback: If IDs match but server has NO public key while local DOES,
      // the server DB might have been wiped/reset. We must wipe local to match.
      final oldPublicKey = oldLicenseData?['public_key'] as String?;
      // Special case: if server was wiped (server key is empty but we had one before)
      final isServerWiped = oldPublicKey != null &&
          oldPublicKey.isNotEmpty &&
          (serverPublicKey == null || serverPublicKey.isEmpty);

      if (isDifferentUserDetected || isServerWiped) {
        // A DIFFERENT user logged into this device (or server was reset). We MUST wipe the old data
        // to prevent data mixing and privacy breaches.
        await InjectionContainer.wipeLocalDataForAccountSwitch();
      }
      // --------------------------------

      await _licenseVault.writeJwt(result.jwt);
      await _licenseVault.writeLicenseData(result.licenseData);
      await _licenseVault.writeProvisionedHardwareId(hardwareId);
      final deviceRole = result.licenseData['device_role'] as String?;
      await _licenseVault.setIsCompanionDevice(deviceRole == 'companion');
      if (result.serverSalt.isNotEmpty) {
        await _licenseVault.writeServerSalt(result.serverSalt);
      }

      // Start trial clock if no license status found.
      final status = result.licenseData['status'] as String? ?? '';
      final emailVerifiedAt = result.licenseData['email_verified_at'];
      final emailUnverified = emailVerifiedAt == null;

      if (status.isEmpty || status == 'trial') {
        final serverTrialStart =
            result.licenseData['trial_started_at'] as String?;
        if (serverTrialStart != null) {
          final dt = DateTime.tryParse(serverTrialStart);
          if (dt != null) {
            await _licenseVault.writeTrialStart(dt);
          }
        } else {
          final trialStart = await _licenseVault.readTrialStart();
          if (trialStart == null) {
            await _licenseVault.writeTrialStart(DateTime.now().toUtc());
          }
        }
      }

      if (!emailUnverified) {
        final (licenseStatus, ownerAcc, payInstr, updUrl, bReason) =
            await _resolveLicenseStatus();
        final trialDays = await trialDaysRemaining();
        emit(
          SecurityUnlocked(
            licenseStatus: licenseStatus,
            trialDaysRemaining: trialDays,
            ownerAccountNumber: ownerAcc,
            paymentInstructionsAr: payInstr,
            updateUrl: updUrl,
            banReason: bReason,
          ),
        );
      }

      // Sync identity to internal accounts after successful provision
      // Only call if DB is ready.
      if (InjectionContainer.isDatabaseReady) {
        _syncIdentityUseCase?.call().ignore();
      }

      return ProvisioningResult.success(emailUnverified: emailUnverified);
    } catch (e, stack) {
      debugPrint('Post-Auth Processing Error: $e\n$stack');
      return ProvisioningResult.failure(
        AppStrings.anErrorOccurredWhile,
      );
    }
  }

  Future<bool> verifyEmailOtp(String code) async {
    try {
      final success = await _authRepository.verifyEmailOtp(code);
      if (success) {
        final (licenseStatus, ownerAcc, payInstr, updUrl, bReason) =
            await _resolveLicenseStatus();
        final trialDays = await trialDaysRemaining();
        emit(
          SecurityUnlocked(
            licenseStatus: licenseStatus,
            trialDaysRemaining: trialDays,
            ownerAccountNumber: ownerAcc,
            paymentInstructionsAr: payInstr,
            updateUrl: updUrl,
            banReason: bReason,
          ),
        );
      }
      return success;
    } catch (e) {
      rethrow;
    }
  }

  // ── Panic wipe ────────────────────────────────────────────────────────────

  Future<void> executePanicWipe() async {
    await _panicWipeService.wipeAll();
    emit(
      const SecurityUnlocked(
        licenseStatus: LicenseStatus.pending,
        trialDaysRemaining: LicenseVault.trialDurationDays,
      ),
    );
  }

  // ── PIN management ────────────────────────────────────────────────────────

  Future<void> saveNewPin(String pin) async {
    await _pinStorage.setPin(pin);
    await _pinStorage.setLockEnabled(true);
    await refreshPreferences();
  }

  Future<void> setLockEnabled(bool enabled) async {
    if (enabled && !await _pinStorage.hasPinConfigured()) return;
    await _pinStorage.setLockEnabled(enabled);
    await refreshPreferences();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _pinStorage.setBiometricEnabled(enabled);
    await refreshPreferences();
  }

  Future<bool> hasPinConfigured() => _pinStorage.hasPinConfigured();
  Future<bool> isLockEnabled() => _pinStorage.isLockEnabled();
  Future<bool> isBiometricEnabled() => _pinStorage.isBiometricEnabled();

  // ── Trial info ────────────────────────────────────────────────────────────

  Future<int> trialDaysRemaining() async {
    final start = await _licenseVault.readTrialStart();
    if (start == null) return LicenseVault.trialDurationDays;
    return _licenseVault.daysRemainingInTrial(start);
  }
  // ── Auth & Logout ─────────────────────────────────────────────────────────

  /// Clears the session after the server reports this device was revoked.
  Future<void> handleDeviceRevoked() async {
    await _licenseVault.setPendingAuthBannerAr(
      AppStrings.deviceAuthorizationRevoked,
    );
    await logout(skipRemoteLogout: true);
  }

  Future<void> logout({bool skipRemoteLogout = false}) async {
    if (!skipRemoteLogout) {
      try {
        await _authRepository.logout();
      } catch (_) {
        // Still sign out locally if the network call fails.
      }
    }

    // 1. Clear session from vault (JWT) but retain User ID and Public Key
    // to identify returning users and prevent accidental data wipes.
    final oldData = await _licenseVault.readLicenseData() ?? {};
    final retainedData = <String, dynamic>{};
    if (oldData.containsKey('id')) retainedData['id'] = oldData['id'];
    if (oldData.containsKey('public_key')) {
      retainedData['public_key'] = oldData['public_key'];
    }

    await _licenseVault.writeJwt('');
    await _licenseVault.writeLicenseData(retainedData);

    // 2. Stop background services if running
    if (InjectionContainer.syncCoordinatorService.isRunning) {
      InjectionContainer.syncCoordinatorService.stop();
    }

    // 3. Close database and reset epoch
    // NOTE: This will trigger UI rebuilds and force the bootstrapper to re-evaluate
    await InjectionContainer.closeDatabaseForRestore();

    // 4. Emit pending status to force redirect to login
    emit(
      const SecurityUnlocked(
        licenseStatus: LicenseStatus.pending,
        trialDaysRemaining: LicenseVault.trialDurationDays,
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  SecurityState _withClock(ClockStatus cs, {int? trialDaysRemaining}) {
    return SecurityLocked(
      licenseStatus: state.licenseStatus,
      clockStatus: cs,
      trialDaysRemaining: trialDaysRemaining ?? state.trialDaysRemaining,
      ownerAccountNumber: state.ownerAccountNumber,
      paymentInstructionsAr: state.paymentInstructionsAr,
      updateUrl: state.updateUrl,
      banReason: state.banReason,
    );
  }

  SecurityState _buildState({
    required LicenseStatus licenseStatus,
    required ClockStatus clockStatus,
    int? trialDaysRemaining,
    String? ownerAccountNumber,
    String? paymentInstructionsAr,
    String? updateUrl,
    String? banReason,
  }) {
    return SecurityUnlocked(
      licenseStatus: licenseStatus,
      clockStatus: clockStatus,
      trialDaysRemaining: trialDaysRemaining ?? state.trialDaysRemaining,
      ownerAccountNumber: ownerAccountNumber ?? state.ownerAccountNumber,
      paymentInstructionsAr:
          paymentInstructionsAr ?? state.paymentInstructionsAr,
      updateUrl: updateUrl ?? state.updateUrl,
      banReason: banReason ?? state.banReason,
    );
  }
}

/// Result of a provisioning (API login) attempt.
final class ProvisioningResult {
  const ProvisioningResult._({
    required this.success,
    this.emailUnverified = false,
    this.errorAr,
  });

  factory ProvisioningResult.success({bool emailUnverified = false}) =>
      ProvisioningResult._(success: true, emailUnverified: emailUnverified);

  factory ProvisioningResult.failure(String messageAr) =>
      ProvisioningResult._(success: false, errorAr: messageAr);

  final bool success;
  final bool emailUnverified;
  final String? errorAr;
}
