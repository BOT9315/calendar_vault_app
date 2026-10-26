import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'persistent_storage_service.dart';

class AuthService {
  static const String SECURE_PASSWORD_KEY = 'hidex_vault_password_sequence';
  static const String PREFS_PASSWORD_KEY = 'secret_date_sequence';
  static const List<int> DEFAULT_PASSWORD_SEQUENCE = [7, 14, 21, 28];

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
    ),
  );

  static List<int>? _cachedSequence;

  /// Retrieves the saved password sequence.
  /// Priority:
  /// 1. In-memory cache (if already loaded in this session)
  /// 2. FlutterSecureStorage (hardware-backed secure keystore)
  /// 3. SharedPreferences (persistent local storage fallback)
  /// 4. If an existing persistent vault is detected on disk (after reinstallation):
  ///    NEVER overwrite with default! Returns [] so user can restore using their original password.
  /// 5. Pure first-time setup only (no existing vault on device): default sequence [7, 14, 21, 28] is saved and returned.
  static Future<List<int>> getPasswordSequence() async {
    if (_cachedSequence != null && _cachedSequence!.isNotEmpty) {
      return List.unmodifiable(_cachedSequence!);
    }

    // 1. Try FlutterSecureStorage
    try {
      final secureVal = await _secureStorage.read(key: SECURE_PASSWORD_KEY);
      if (secureVal != null && secureVal.trim().isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(secureVal);
        final seq = decoded.map((e) => e as int).toList();
        if (seq.isNotEmpty) {
          _cachedSequence = List.from(seq);
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(PREFS_PASSWORD_KEY, secureVal);
          } catch (_) {}
          return List.unmodifiable(seq);
        }
      }
    } catch (e) {
      debugPrint('AuthService: Error reading from secure storage: $e');
    }

    // 2. Try SharedPreferences fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefsVal = prefs.getString(PREFS_PASSWORD_KEY);
      if (prefsVal != null && prefsVal.trim().isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(prefsVal);
        final seq = decoded.map((e) => e as int).toList();
        if (seq.isNotEmpty) {
          _cachedSequence = List.from(seq);
          try {
            await _secureStorage.write(key: SECURE_PASSWORD_KEY, value: prefsVal);
          } catch (_) {}
          return List.unmodifiable(seq);
        }
      }
    } catch (e) {
      debugPrint('AuthService: Error reading from SharedPreferences: $e');
    }

    // 3. Check if an existing vault exists on persistent storage (survived uninstallation)
    final existingVaultExists = await PersistentStorageService.doesExistingVaultExist();
    if (existingVaultExists) {
      // CRITICAL DATA PROTECTION: An existing vault was found on disk from prior install.
      // Do NOT overwrite with default password! Return empty list to prompt recovery.
      debugPrint('AuthService: Existing vault detected on device! Awaiting original password input.');
      return const [];
    }

    // 4. Pure first-time setup only: No vault has ever existed on this device.
    // Store and persist the default password permanently.
    final defaultSeq = List<int>.from(DEFAULT_PASSWORD_SEQUENCE);
    await setPasswordSequence(defaultSeq);
    _cachedSequence = List.from(defaultSeq);
    return List.unmodifiable(defaultSeq);
  }

  /// Check if a custom or existing password is configured in local app storage
  static Future<bool> isPasswordConfigured() async {
    try {
      final secureVal = await _secureStorage.read(key: SECURE_PASSWORD_KEY);
      if (secureVal != null && secureVal.trim().isNotEmpty) return true;
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final prefsVal = prefs.getString(PREFS_PASSWORD_KEY);
      if (prefsVal != null && prefsVal.trim().isNotEmpty) return true;
    } catch (_) {}

    return false;
  }

  /// Check if the app was reinstalled and has an existing vault waiting to be recovered
  static Future<bool> hasExistingVaultPendingRecovery() async {
    final localConfigured = await isPasswordConfigured();
    if (localConfigured) return false;
    return await PersistentStorageService.doesExistingVaultExist();
  }

  /// Verifies an input candidate sequence against the currently saved password
  static Future<bool> verifyCurrentPassword(List<int> candidate) async {
    final current = await getPasswordSequence();
    if (current.isEmpty) {
      // In recovery mode, verify directly against persistent vault config
      return await PersistentStorageService.verifySecretSequence(candidate.join('-'));
    }

    if (candidate.length != current.length) return false;
    for (int i = 0; i < current.length; i++) {
      if (candidate[i] != current[i]) return false;
    }
    return true;
  }

  /// Restore an existing vault using the original password after reinstallation
  static Future<bool> restoreVaultWithPassword(List<int> candidate) async {
    final isValid = await PersistentStorageService.verifySecretSequence(candidate.join('-'));
    if (!isValid) return false;

    // Password verified! Persist into app keystore & shared preferences
    final success = await setPasswordSequence(candidate);
    return success;
  }

  /// Permanently saves a password sequence to both FlutterSecureStorage and SharedPreferences
  /// and updates the persistent vault storage config.
  static Future<bool> setPasswordSequence(List<int> sequence) async {
    if (sequence.isEmpty) return false;
    final jsonStr = jsonEncode(sequence);

    bool secureSuccess = false;
    bool prefsSuccess = false;

    // 1. Write to FlutterSecureStorage
    try {
      await _secureStorage.write(key: SECURE_PASSWORD_KEY, value: jsonStr);
      final check = await _secureStorage.read(key: SECURE_PASSWORD_KEY);
      secureSuccess = (check == jsonStr);
    } catch (e) {
      debugPrint('AuthService: Failed writing to secure storage: $e');
    }

    // 2. Write to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      prefsSuccess = await prefs.setString(PREFS_PASSWORD_KEY, jsonStr);
    } catch (e) {
      debugPrint('AuthService: Failed writing to SharedPreferences: $e');
    }

    // 3. Write to persistent external storage config
    try {
      await PersistentStorageService.savePersistentVaultConfig(sequence.join('-'));
    } catch (e) {
      debugPrint('AuthService: Failed saving persistent vault config: $e');
    }

    if (secureSuccess || prefsSuccess) {
      _cachedSequence = List.from(sequence);
      return true;
    }

    return false;
  }

  /// Fully validated password change:
  /// - Validates current password
  /// - Validates new password length
  /// - Validates confirmation match
  /// - Saves to persistent secure storage
  /// - Returns error message if failed, or null if successful
  static Future<String?> changePassword({
    required List<int> currentPassword,
    required List<int> newPassword,
    required List<int> confirmPassword,
  }) async {
    // 1. Verify current password
    final isCurrentValid = await verifyCurrentPassword(currentPassword);
    if (!isCurrentValid) {
      return 'Current password verification failed. Please try again.';
    }

    // 2. Validate new password
    if (newPassword.length != 4) {
      return 'New password must contain exactly 4 dates.';
    }

    // 3. Validate confirmation
    if (newPassword.length != confirmPassword.length) {
      return 'Confirmation does not match new password.';
    }
    for (int i = 0; i < newPassword.length; i++) {
      if (newPassword[i] != confirmPassword[i]) {
        return 'Confirmation does not match new password.';
      }
    }

    // 4. Save permanently
    final success = await setPasswordSequence(newPassword);
    if (!success) {
      return 'Failed to save new password to secure storage. Please check device permissions.';
    }

    return null;
  }

  /// Completely resets all saved vault credentials and clears secure storage & shared preferences
  static Future<void> resetAllVaultCredentials() async {
    _cachedSequence = null;
    try {
      await _secureStorage.delete(key: SECURE_PASSWORD_KEY);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PREFS_PASSWORD_KEY);
      await prefs.remove('has_seen_onboarding_guide');
    } catch (_) {}
  }

  /// Clear in-memory cache (for testing app restart simulation)
  @visibleForTesting
  static void clearCacheForTesting() {
    _cachedSequence = null;
  }
}
