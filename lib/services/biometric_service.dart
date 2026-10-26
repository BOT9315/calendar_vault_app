import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();
  static const String PREF_BIOMETRIC_ENABLED = 'hidex_biometric_enabled';

  /// Check whether the device hardware supports biometrics and has enrolled credentials.
  /// Returns true only when real biometric authentication (fingerprint, face, iris) is possible.
  static Future<bool> isBiometricAvailable() async {
    try {
      // canCheckBiometrics: true if hardware is present
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      // isDeviceSupported: true if any secure auth (including PIN) is available
      final bool isSupported = await _auth.isDeviceSupported();

      if (!canAuthenticateWithBiometrics && !isSupported) {
        debugPrint('[BiometricService] Device has no biometric hardware and no device auth.');
        return false;
      }

      // Also verify that at least one biometric type is enrolled
      final enrolled = await _auth.getAvailableBiometrics();
      debugPrint('[BiometricService] canCheckBiometrics=$canAuthenticateWithBiometrics, '
          'isDeviceSupported=$isSupported, enrolledBiometrics=$enrolled');

      if (enrolled.isEmpty && canAuthenticateWithBiometrics) {
        // Hardware present but nothing enrolled
        debugPrint('[BiometricService] Biometric hardware exists but no biometrics enrolled.');
        return false;
      }

      // Accept if hardware + enrolled, OR if device supports secure auth as fallback
      return canAuthenticateWithBiometrics || isSupported;
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] isBiometricAvailable PlatformException: $e');
      return false;
    } catch (e) {
      debugPrint('[BiometricService] isBiometricAvailable error: $e');
      return false;
    }
  }

  /// Get list of available biometric types on device (e.g., fingerprint, face)
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Check if user has enabled biometric unlock in app settings
  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(PREF_BIOMETRIC_ENABLED) ?? false;
  }

  /// Toggle biometric unlock preference
  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PREF_BIOMETRIC_ENABLED, enabled);
  }

  /// Trigger biometric authentication prompt.
  /// Returns true if authentication succeeded.
  /// Returns false on failure, cancellation, or error.
  /// [errorCallback] receives a human-readable error message if authentication fails.
  static Future<bool> authenticate({
    String reason = 'Authenticate to access HideX Vault',
    void Function(String errorMessage)? errorCallback,
  }) async {
    try {
      debugPrint('[BiometricService] authenticate() called — showing biometric prompt...');
      final result = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      debugPrint('[BiometricService] authenticate() result: $result');
      if (!result) {
        errorCallback?.call('Biometric authentication was cancelled or failed.');
      }
      return result;
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] authenticate() PlatformException: code=${e.code}, message=${e.message}');
      String msg;
      switch (e.code) {
        case 'NotAvailable':
          msg = 'Biometric authentication is not available on this device.';
          break;
        case 'NotEnrolled':
          msg = 'No biometrics enrolled. Please add a fingerprint or face in Settings.';
          break;
        case 'LockedOut':
          msg = 'Too many failed attempts. Biometric is temporarily locked.';
          break;
        case 'PermanentlyLockedOut':
          msg = 'Biometric is permanently locked out. Use your device PIN to unlock.';
          break;
        default:
          msg = 'Biometric error: ${e.message ?? e.code}';
      }
      errorCallback?.call(msg);
      return false;
    } catch (e) {
      debugPrint('[BiometricService] authenticate() error: $e');
      errorCallback?.call('Unexpected biometric error: $e');
      return false;
    }
  }
}
