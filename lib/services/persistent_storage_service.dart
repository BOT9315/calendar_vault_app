import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/album.dart';
import '../models/vault_item.dart';
import 'auth_service.dart';
import 'encryption_service.dart';

class PersistentStorageService {
  static const String VAULT_DIR_NAME = '.calendar_vault';
  static const String SECONDARY_DIR_NAME = '.hidex_backup';
  static const String MASTER_BACKUP_NAME = 'hidex_master_backup.hidexenc';

  static const String INDEX_FILE_NAME = 'vault_index.enc';
  static const String CONFIG_FILE_NAME = 'vault_config.enc';
  static const String ALBUMS_FILE_NAME = 'albums_index.enc';
  static const String SETTINGS_FILE_NAME = 'vault_settings.enc';
  static const String AVATAR_FILE_NAME = 'profile_avatar.enc';

  /// Request necessary storage permissions for Android
  static Future<bool> requestStoragePermissions() async {
    if (Platform.isAndroid) {
      try {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }

        if (!status.isGranted) {
          await [
            Permission.storage,
            Permission.photos,
            Permission.videos,
          ].request();
        }
        return status.isGranted || await Permission.storage.isGranted;
      } catch (e) {
        debugPrint('PersistentStorageService: Permission request error: $e');
        return false;
      }
    }
    return true;
  }

  @visibleForTesting
  static Directory? customVaultDirForTesting;

  @visibleForTesting
  static Directory? customSecondaryDirForTesting;

  /// Locate or create the primary persistent vault directory on phone storage.
  /// Survives app uninstallation because it is in public Documents/.calendar_vault
  static Future<Directory> getPersistentVaultDirectory() async {
    if (customVaultDirForTesting != null) {
      if (!await customVaultDirForTesting!.exists()) {
        await customVaultDirForTesting!.create(recursive: true);
      }
      return customVaultDirForTesting!;
    }

    Directory vaultDir;

    if (Platform.isAndroid) {
      final persistentBase = Directory('/storage/emulated/0/Documents');
      if (await persistentBase.exists()) {
        vaultDir = Directory('${persistentBase.path}/$VAULT_DIR_NAME');
      } else {
        final rootStorage = Directory('/storage/emulated/0');
        if (await rootStorage.exists()) {
          vaultDir = Directory('${rootStorage.path}/$VAULT_DIR_NAME');
        } else {
          try {
            final externalDir = await getExternalStorageDirectory();
            vaultDir = Directory('${externalDir?.path ?? (await getApplicationDocumentsDirectory()).path}/$VAULT_DIR_NAME');
          } catch (_) {
            vaultDir = Directory('${Directory.systemTemp.path}/$VAULT_DIR_NAME');
          }
        }
      }
    } else {
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        vaultDir = Directory('${appDocDir.path}/$VAULT_DIR_NAME');
      } catch (_) {
        vaultDir = Directory('${Directory.systemTemp.path}/$VAULT_DIR_NAME');
      }
    }

    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }

    return vaultDir;
  }

  /// Locate or create the secondary persistent mirror directory on phone storage.
  /// Placed in Downloads/.hidex_backup for dual-layer survival across device storage cleaners
  static Future<Directory?> getSecondaryMirrorDirectory() async {
    if (customSecondaryDirForTesting != null) {
      if (!await customSecondaryDirForTesting!.exists()) {
        await customSecondaryDirForTesting!.create(recursive: true);
      }
      return customSecondaryDirForTesting;
    }

    if (!Platform.isAndroid) return null;
    try {
      final downloadBase = Directory('/storage/emulated/0/Download');
      if (await downloadBase.exists()) {
        final dir = Directory('${downloadBase.path}/$SECONDARY_DIR_NAME');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir;
      }
    } catch (e) {
      debugPrint('PersistentStorageService: Secondary directory error: $e');
    }
    return null;
  }

  /// Checks if an existing vault exists on the device from a previous installation
  static Future<bool> doesExistingVaultExist() async {
    try {
      // 1. Check primary persistent directory
      final primaryDir = await getPersistentVaultDirectory();
      final pConfig = File('${primaryDir.path}/$CONFIG_FILE_NAME');
      final pIndex = File('${primaryDir.path}/$INDEX_FILE_NAME');
      final pMaster = File('${primaryDir.path}/$MASTER_BACKUP_NAME');

      if (await pConfig.exists() || await pIndex.exists() || await pMaster.exists()) {
        return true;
      }

      // 2. Check secondary mirror directory (Download/.hidex_backup)
      final secondaryDir = await getSecondaryMirrorDirectory();
      if (secondaryDir != null) {
        final sConfig = File('${secondaryDir.path}/$CONFIG_FILE_NAME');
        final sIndex = File('${secondaryDir.path}/$INDEX_FILE_NAME');
        final sMaster = File('${secondaryDir.path}/$MASTER_BACKUP_NAME');

        if (await sConfig.exists() || await sIndex.exists() || await sMaster.exists()) {
          return true;
        }
      }

      // 3. Check fallback root directory (/storage/emulated/0/.calendar_vault)
      final rootFallback = Directory('/storage/emulated/0/$VAULT_DIR_NAME');
      if (await rootFallback.exists()) {
        final rConfig = File('${rootFallback.path}/$CONFIG_FILE_NAME');
        final rIndex = File('${rootFallback.path}/$INDEX_FILE_NAME');
        if (await rConfig.exists() || await rIndex.exists()) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('PersistentStorageService: doesExistingVaultExist check error: $e');
    }
    return false;
  }

  /// Saves the secret sequence / verification token to persistent storage (both primary and mirror)
  static Future<void> savePersistentVaultConfig(String secretSequence) async {
    final payload = jsonEncode({
      'token': 'VALID_VAULT_TOKEN',
      'created': DateTime.now().toIso8601String(),
      'hash': sha256.convert(utf8.encode(secretSequence)).toString(),
    });

    final encrypted = EncryptionService.encryptString(payload, secretSequence);

    // Save to primary directory
    try {
      final primaryDir = await getPersistentVaultDirectory();
      final configFile = File('${primaryDir.path}/$CONFIG_FILE_NAME');
      await configFile.writeAsString(encrypted, flush: true);
    } catch (e) {
      debugPrint('PersistentStorageService: Failed writing primary config: $e');
    }

    // Mirror to secondary directory
    try {
      final secondaryDir = await getSecondaryMirrorDirectory();
      if (secondaryDir != null) {
        final mirrorFile = File('${secondaryDir.path}/$CONFIG_FILE_NAME');
        await mirrorFile.writeAsString(encrypted, flush: true);
      }
    } catch (_) {}
  }

  /// Validates if an entered secret sequence is correct against persistent vault config
  static Future<bool> verifySecretSequence(String candidateSequence) async {
    try {
      // 1. Check primary directory config
      final primaryDir = await getPersistentVaultDirectory();
      File configFile = File('${primaryDir.path}/$CONFIG_FILE_NAME');

      // 2. If missing in primary, fallback to secondary mirror
      if (!await configFile.exists()) {
        final secondaryDir = await getSecondaryMirrorDirectory();
        if (secondaryDir != null) {
          final sFile = File('${secondaryDir.path}/$CONFIG_FILE_NAME');
          if (await sFile.exists()) {
            configFile = sFile;
          }
        }
      }

      // 3. Fallback to testing decryption on vault index directly if config file was deleted
      if (!await configFile.exists()) {
        final indexFile = File('${primaryDir.path}/$INDEX_FILE_NAME');
        if (await indexFile.exists()) {
          try {
            final encrypted = await indexFile.readAsString();
            final decrypted = EncryptionService.decryptString(encrypted, candidateSequence);
            final dynamic list = jsonDecode(decrypted);
            return list is List;
          } catch (_) {
            return false;
          }
        }
        return false;
      }

      final encrypted = await configFile.readAsString();
      final decrypted = EncryptionService.decryptString(encrypted, candidateSequence);
      final data = jsonDecode(decrypted);
      return data['token'] == 'VALID_VAULT_TOKEN';
    } catch (_) {
      return false;
    }
  }

  /// Reads and decrypts the vault media index
  static Future<List<VaultItem>> loadVaultIndex(String secret) async {
    try {
      final dir = await getPersistentVaultDirectory();
      File indexFile = File('${dir.path}/$INDEX_FILE_NAME');

      // If missing in primary, check secondary mirror
      if (!await indexFile.exists()) {
        final secondaryDir = await getSecondaryMirrorDirectory();
        if (secondaryDir != null) {
          final sFile = File('${secondaryDir.path}/$INDEX_FILE_NAME');
          if (await sFile.exists()) {
            indexFile = sFile;
          }
        }
      }

      // If still missing, check backup file (.bak)
      if (!await indexFile.exists()) {
        final bakFile = File('${dir.path}/$INDEX_FILE_NAME.bak');
        if (await bakFile.exists()) {
          indexFile = bakFile;
        }
      }

      if (!await indexFile.exists()) {
        return [];
      }

      final encrypted = await indexFile.readAsString();
      final decrypted = EncryptionService.decryptString(encrypted, secret);
      final List<dynamic> list = jsonDecode(decrypted);
      return list.map((item) => VaultItem.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('PersistentStorageService: Error loading vault index: $e');
      return [];
    }
  }

  /// Saves and encrypts the vault media index with safety checks against accidental data loss
  static Future<void> saveVaultIndex(
    List<VaultItem> items,
    String secret, {
    bool allowEmpty = false,
  }) async {
    final dir = await getPersistentVaultDirectory();
    final indexFile = File('${dir.path}/$INDEX_FILE_NAME');

    // DATA PROTECTION GUARD: Never overwrite an existing non-empty index with an empty list UNLESS allowEmpty is true!
    if (items.isEmpty && !allowEmpty && await indexFile.exists()) {
      try {
        final existingContent = await indexFile.readAsString();
        if (existingContent.trim().isNotEmpty) {
          debugPrint('PersistentStorageService DATA PROTECTION: Refusing to overwrite non-empty index with empty list (allowEmpty=false)!');
          return;
        }
      } catch (_) {}
    }

    // Create a .bak safety copy before writing new index
    if (await indexFile.exists()) {
      try {
        final bakFile = File('${dir.path}/$INDEX_FILE_NAME.bak');
        await indexFile.copy(bakFile.path);
      } catch (_) {}
    }

    final list = items.map((item) => item.toJson()).toList();
    final jsonStr = jsonEncode(list);
    final encrypted = EncryptionService.encryptString(jsonStr, secret);
    await indexFile.writeAsString(encrypted, flush: true);

    // If items is empty and allowEmpty is true, update the backup file too so deleted items are permanently erased
    if (items.isEmpty && allowEmpty) {
      try {
        final bakFile = File('${dir.path}/$INDEX_FILE_NAME.bak');
        await bakFile.writeAsString(encrypted, flush: true);
      } catch (_) {}
    }

    // Mirror to secondary persistent location
    try {
      final secondaryDir = await getSecondaryMirrorDirectory();
      if (secondaryDir != null) {
        final mirrorFile = File('${secondaryDir.path}/$INDEX_FILE_NAME');
        await mirrorFile.writeAsString(encrypted, flush: true);
        if (items.isEmpty && allowEmpty) {
          final mirrorBak = File('${secondaryDir.path}/$INDEX_FILE_NAME.bak');
          await mirrorBak.writeAsString(encrypted, flush: true);
        }
      }
    } catch (_) {}
  }

  /// Reads and decrypts the albums index
  static Future<List<Album>> loadAlbums(String secret) async {
    try {
      final dir = await getPersistentVaultDirectory();
      File albumsFile = File('${dir.path}/$ALBUMS_FILE_NAME');

      if (!await albumsFile.exists()) {
        final secondaryDir = await getSecondaryMirrorDirectory();
        if (secondaryDir != null) {
          final sFile = File('${secondaryDir.path}/$ALBUMS_FILE_NAME');
          if (await sFile.exists()) albumsFile = sFile;
        }
      }

      if (!await albumsFile.exists()) {
        return [];
      }

      final encrypted = await albumsFile.readAsString();
      final decrypted = EncryptionService.decryptString(encrypted, secret);
      final List<dynamic> list = jsonDecode(decrypted);
      return list.map((item) => Album.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('PersistentStorageService: Error loading albums: $e');
      return [];
    }
  }

  /// Saves and encrypts the albums index
  static Future<void> saveAlbums(List<Album> albums, String secret) async {
    final dir = await getPersistentVaultDirectory();
    final albumsFile = File('${dir.path}/$ALBUMS_FILE_NAME');
    final list = albums.map((album) => album.toJson()).toList();
    final jsonStr = jsonEncode(list);
    final encrypted = EncryptionService.encryptString(jsonStr, secret);
    await albumsFile.writeAsString(encrypted, flush: true);

    try {
      final secondaryDir = await getSecondaryMirrorDirectory();
      if (secondaryDir != null) {
        final mirrorFile = File('${secondaryDir.path}/$ALBUMS_FILE_NAME');
        await mirrorFile.writeAsString(encrypted, flush: true);
      }
    } catch (_) {}
  }

  /// Reads and decrypts custom user profile avatar bytes
  static Future<Uint8List?> loadProfileAvatar(String secret) async {
    try {
      final dir = await getPersistentVaultDirectory();
      File avatarFile = File('${dir.path}/$AVATAR_FILE_NAME');
      if (!await avatarFile.exists()) {
        final secondaryDir = await getSecondaryMirrorDirectory();
        if (secondaryDir != null) {
          final sFile = File('${secondaryDir.path}/$AVATAR_FILE_NAME');
          if (await sFile.exists()) avatarFile = sFile;
        }
      }
      if (!await avatarFile.exists()) return null;
      return await EncryptionService.decryptFileToMemory(avatarFile, secret);
    } catch (e) {
      debugPrint('PersistentStorageService: Error loading profile avatar: $e');
      return null;
    }
  }

  /// Saves and encrypts custom user profile avatar
  static Future<void> saveProfileAvatar(Uint8List imageBytes, String secret) async {
    final dir = await getPersistentVaultDirectory();
    final avatarFile = File('${dir.path}/$AVATAR_FILE_NAME');
    final cipher = EncryptionService.encryptBytes(imageBytes, secret);
    await avatarFile.writeAsBytes(cipher, flush: true);

    try {
      final secondaryDir = await getSecondaryMirrorDirectory();
      if (secondaryDir != null) {
        final mirrorFile = File('${secondaryDir.path}/$AVATAR_FILE_NAME');
        await mirrorFile.writeAsBytes(cipher, flush: true);
      }
    } catch (_) {}
  }

  /// Reads and decrypts user settings
  static Future<Map<String, dynamic>> loadUserSettings(String secret) async {
    try {
      final dir = await getPersistentVaultDirectory();
      final settingsFile = File('${dir.path}/$SETTINGS_FILE_NAME');
      if (!await settingsFile.exists()) return {};
      final encrypted = await settingsFile.readAsString();
      final decrypted = EncryptionService.decryptString(encrypted, secret);
      return jsonDecode(decrypted) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('PersistentStorageService: Error loading settings: $e');
      return {};
    }
  }

  /// Saves and encrypts user settings
  static Future<void> saveUserSettings(Map<String, dynamic> settings, String secret) async {
    final dir = await getPersistentVaultDirectory();
    final settingsFile = File('${dir.path}/$SETTINGS_FILE_NAME');
    final jsonStr = jsonEncode(settings);
    final encrypted = EncryptionService.encryptString(jsonStr, secret);
    await settingsFile.writeAsString(encrypted, flush: true);
  }

  /// Completely and permanently wipes the entire vault from device storage.
  /// Deletes all encrypted media files, indices, configs, albums, avatars, settings, and backups.
  static Future<void> wipeEntireVaultPermanently() async {
    try {
      // 1. Wipe primary vault directory
      final primaryDir = await getPersistentVaultDirectory();
      if (await primaryDir.exists()) {
        final files = primaryDir.listSync(recursive: true);
        for (final file in files) {
          try {
            if (file is File) await file.delete();
          } catch (_) {}
        }
      }

      // 2. Wipe secondary mirror directory
      final secondaryDir = await getSecondaryMirrorDirectory();
      if (secondaryDir != null && await secondaryDir.exists()) {
        final files = secondaryDir.listSync(recursive: true);
        for (final file in files) {
          try {
            if (file is File) await file.delete();
          } catch (_) {}
        }
      }

      // 3. Clear auth and recovery markers in AuthService & SharedPreferences
      await AuthService.resetAllVaultCredentials();
    } catch (e) {
      debugPrint('PersistentStorageService: wipeEntireVaultPermanently error: $e');
    }
  }
}
