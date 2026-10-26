import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/album.dart';
import '../models/vault_item.dart';
import 'backup_service.dart';
import 'persistent_storage_service.dart';

class CloudSyncConfig {
  final String serverUrl;
  final String authToken;
  final bool isEnabled;
  final DateTime? lastSyncTime;
  final String? lastStatusMessage;

  CloudSyncConfig({
    required this.serverUrl,
    required this.authToken,
    this.isEnabled = true,
    this.lastSyncTime,
    this.lastStatusMessage,
  });

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'authToken': authToken,
        'isEnabled': isEnabled,
        'lastSyncTime': lastSyncTime?.toIso8601String(),
        'lastStatusMessage': lastStatusMessage,
      };

  factory CloudSyncConfig.fromJson(Map<String, dynamic> json) => CloudSyncConfig(
        serverUrl: json['serverUrl'] as String? ?? '',
        authToken: json['authToken'] as String? ?? '',
        isEnabled: json['isEnabled'] as bool? ?? false,
        lastSyncTime: json['lastSyncTime'] != null ? DateTime.tryParse(json['lastSyncTime'] as String) : null,
        lastStatusMessage: json['lastStatusMessage'] as String?,
      );
}

class CloudBackupService {
  static const String PREF_CLOUD_CONFIG = 'hidex_cloud_sync_config';

  /// Load saved Cloud configuration
  static Future<CloudSyncConfig?> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(PREF_CLOUD_CONFIG);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        return CloudSyncConfig.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('CloudBackupService: loadConfig error: $e');
    }
    return null;
  }

  /// Save Cloud configuration
  static Future<void> saveConfig(CloudSyncConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PREF_CLOUD_CONFIG, jsonEncode(config.toJson()));
    } catch (e) {
      debugPrint('CloudBackupService: saveConfig error: $e');
    }
  }

  /// Test connectivity to the specified cloud server
  static Future<Map<String, dynamic>> testConnection({
    required String serverUrl,
    required String authToken,
  }) async {
    try {
      final uri = Uri.parse(serverUrl.trim());
      final headers = <String, String>{
        'User-Agent': 'HideX-Vault-Client/1.0',
        if (authToken.trim().isNotEmpty) 'Authorization': 'Bearer ${authToken.trim()}',
      };

      // Try HEAD request first, fallback to GET
      http.Response response;
      try {
        response = await http.head(uri, headers: headers).timeout(const Duration(seconds: 10));
      } catch (_) {
        response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      }

      if (response.statusCode >= 200 && response.statusCode < 400) {
        return {
          'success': true,
          'message': 'Connected successfully! (HTTP ${response.statusCode})',
        };
      } else {
        return {
          'success': false,
          'message': 'Server responded with HTTP ${response.statusCode}: ${response.reasonPhrase ?? 'Error'}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      };
    }
  }

  /// Create verified master package and upload to remote cloud storage
  static Future<bool> uploadMasterBackupToCloud({
    required String secretKey,
    required List<VaultItem> items,
    required List<Album> albums,
    Function(double progress, String status)? onProgress,
  }) async {
    final config = await loadConfig();
    if (config == null || !config.isEnabled || config.serverUrl.trim().isEmpty) {
      return false;
    }

    try {
      onProgress?.call(0.1, 'Building verified encrypted vault package...');
      final primaryDir = await PersistentStorageService.getPersistentVaultDirectory();
      final masterPackagePath = '${primaryDir.path}/${PersistentStorageService.MASTER_BACKUP_NAME}';

      final packageFile = await BackupService.createEncryptedBackupArchive(
        secretKey: secretKey,
        items: items,
        albums: albums,
        destinationFilePath: masterPackagePath,
        onProgress: (p, msg) => onProgress?.call(0.1 + (0.5 * p), msg),
      );

      if (packageFile == null || !await packageFile.exists()) {
        throw Exception('Failed creating local master backup package.');
      }

      final fileBytes = await packageFile.readAsBytes();
      final fileHash = sha256.convert(fileBytes).toString();

      onProgress?.call(0.7, 'Connecting to remote cloud destination...');
      final uri = Uri.parse(config.serverUrl.trim());
      final headers = <String, String>{
        'Content-Type': 'application/octet-stream',
        'X-Hidex-Vault-Checksum': fileHash,
        'X-Hidex-Item-Count': items.length.toString(),
        if (config.authToken.trim().isNotEmpty) 'Authorization': 'Bearer ${config.authToken.trim()}',
      };

      onProgress?.call(0.8, 'Uploading encrypted vault to cloud...');
      final response = await http
          .put(uri, headers: headers, body: fileBytes)
          .timeout(const Duration(minutes: 5));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final updatedConfig = CloudSyncConfig(
          serverUrl: config.serverUrl,
          authToken: config.authToken,
          isEnabled: true,
          lastSyncTime: DateTime.now(),
          lastStatusMessage: 'Synced & Verified (${items.length} items)',
        );
        await saveConfig(updatedConfig);

        onProgress?.call(1.0, 'Cloud backup uploaded and verified successfully!');
        return true;
      } else {
        throw Exception('Server rejected upload with HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('CloudBackupService: upload error: $e');
      onProgress?.call(0.0, 'Cloud upload failed: $e');
      return false;
    }
  }

  /// Download and restore encrypted vault from remote cloud storage
  static Future<BackupRestoreResult> restoreVaultFromCloud({
    required String serverUrl,
    required String authToken,
    required String secretKey,
    Function(double progress, String status)? onProgress,
  }) async {
    try {
      onProgress?.call(0.15, 'Connecting to remote cloud vault...');
      final uri = Uri.parse(serverUrl.trim());
      final headers = <String, String>{
        if (authToken.trim().isNotEmpty) 'Authorization': 'Bearer ${authToken.trim()}',
      };

      onProgress?.call(0.3, 'Downloading encrypted backup from cloud...');
      final response = await http.get(uri, headers: headers).timeout(const Duration(minutes: 5));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return BackupRestoreResult(
          isSuccess: false,
          message: 'Cloud server returned HTTP ${response.statusCode}: ${response.reasonPhrase ?? 'Not found'}',
        );
      }

      final downloadedBytes = response.bodyBytes;
      if (downloadedBytes.isEmpty) {
        return BackupRestoreResult(
          isSuccess: false,
          message: 'Downloaded package is empty.',
        );
      }

      onProgress?.call(0.5, 'Saving temporary cloud package...');
      final tempFile = File('${Directory.systemTemp.path}/cloud_restore_${DateTime.now().millisecondsSinceEpoch}.hidexenc');
      await tempFile.writeAsBytes(downloadedBytes, flush: true);

      onProgress?.call(0.65, 'Decrypting and verifying vault contents...');
      final result = await BackupService.restoreFromEncryptedBackupArchive(
        backupFile: tempFile,
        secretKey: secretKey,
        onProgress: (p, msg) => onProgress?.call(0.65 + (0.35 * p), msg),
      );

      // Clean up temp file
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}

      if (result.isSuccess) {
        // Save cloud config
        final config = CloudSyncConfig(
          serverUrl: serverUrl,
          authToken: authToken,
          isEnabled: true,
          lastSyncTime: DateTime.now(),
          lastStatusMessage: 'Restored from cloud (${result.itemsRestored} items)',
        );
        await saveConfig(config);
      }

      return result;
    } catch (e) {
      debugPrint('CloudBackupService: restore error: $e');
      return BackupRestoreResult(
        isSuccess: false,
        message: 'Cloud restore error: ${e.toString()}',
      );
    }
  }
}
