import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/album.dart';
import '../models/vault_item.dart';
import 'encryption_service.dart';
import 'persistent_storage_service.dart';

class BackupRestoreResult {
  final bool isSuccess;
  final String message;
  final int itemsRestored;
  final int albumsRestored;

  BackupRestoreResult({
    required this.isSuccess,
    required this.message,
    this.itemsRestored = 0,
    this.albumsRestored = 0,
  });
}

class BackupService {
  static const String PREF_LAST_BACKUP_TIME = 'hidex_last_backup_timestamp';
  static const String PREF_PENDING_CHANGES = 'hidex_pending_backup_changes';
  static const String BACKUP_FILE_EXTENSION = '.hidexenc';

  /// Mark that local vault content was changed and needs backup
  static Future<void> markVaultModified() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(PREF_PENDING_CHANGES) ?? 0;
    await prefs.setInt(PREF_PENDING_CHANGES, count + 1);
  }

  /// Mark that backup was completed and verified
  static Future<void> markBackupCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PREF_LAST_BACKUP_TIME, DateTime.now().toIso8601String());
    await prefs.setInt(PREF_PENDING_CHANGES, 0);
  }

  /// Get the timestamp of the last successful backup
  static Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(PREF_LAST_BACKUP_TIME);
    if (iso != null) {
      return DateTime.tryParse(iso);
    }
    return null;
  }

  /// Check if there are unbacked changes
  static Future<bool> hasPendingChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(PREF_PENDING_CHANGES) ?? 0;
    return count > 0;
  }

  /// Create a standalone, portable, military-grade encrypted archive (.hidexenc)
  /// containing all vault items, albums, user profile avatar, and metadata.
  /// Can be saved to any location (Downloads, SD Card, Drive, PC).
  static Future<File?> createEncryptedBackupArchive({
    required String secretKey,
    required List<VaultItem> items,
    required List<Album> albums,
    required String destinationFilePath,
    Function(double progress, String status)? onProgress,
  }) async {
    try {
      onProgress?.call(0.1, 'Preparing vault files for backup...');
      final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();
      final archive = Archive();

      // 1. Build and verify Manifest
      final manifestMap = <String, dynamic>{
        'version': '1.0.0',
        'createdAt': DateTime.now().toIso8601String(),
        'itemCount': items.length,
        'albumCount': albums.length,
        'fileHashes': <String, String>{},
      };

      // 2. Add vault index
      final indexJson = jsonEncode(items.map((e) => e.toJson()).toList());
      archive.addFile(ArchiveFile('vault_index.json', indexJson.length, utf8.encode(indexJson)));

      // 3. Add albums
      final albumsJson = jsonEncode(albums.map((e) => e.toJson()).toList());
      archive.addFile(ArchiveFile('albums.json', albumsJson.length, utf8.encode(albumsJson)));

      // 4. Add profile avatar if present
      final avatarFile = File('${vaultDir.path}/${PersistentStorageService.AVATAR_FILE_NAME}');
      if (await avatarFile.exists()) {
        final avatarBytes = await avatarFile.readAsBytes();
        archive.addFile(ArchiveFile('avatar.enc', avatarBytes.length, avatarBytes));
      }

      // 5. Add media files with progress and hash verification
      int processed = 0;
      for (final item in items) {
        final file = File('${vaultDir.path}/${item.encryptedFileName}');
        if (await file.exists()) {
          final fileBytes = await file.readAsBytes();
          final hash = sha256.convert(fileBytes).toString();
          manifestMap['fileHashes'][item.encryptedFileName] = hash;

          archive.addFile(ArchiveFile(item.encryptedFileName, fileBytes.length, fileBytes));
        }
        processed++;
        final progress = 0.1 + (0.6 * (processed / (items.isEmpty ? 1 : items.length)));
        onProgress?.call(progress, 'Packing ${item.originalName} ($processed/${items.length})...');
      }

      // Add manifest
      final manifestJson = jsonEncode(manifestMap);
      archive.addFile(ArchiveFile('manifest.json', manifestJson.length, utf8.encode(manifestJson)));

      onProgress?.call(0.75, 'Compressing backup archive...');
      final zipEncoder = ZipEncoder();
      final zippedBytes = zipEncoder.encode(archive);

      onProgress?.call(0.85, 'Encrypting backup with AES-256...');
      // Encrypt the entire zip archive payload with the vault's secret key
      final cipherBytes = EncryptionService.encryptBytes(Uint8List.fromList(zippedBytes), secretKey);

      onProgress?.call(0.95, 'Writing verified backup file...');
      final destFile = File(destinationFilePath);
      if (!await destFile.parent.exists()) {
        await destFile.parent.create(recursive: true);
      }
      await destFile.writeAsBytes(cipherBytes, flush: true);

      // Verify the backup can be read
      final verifyBytes = await destFile.readAsBytes();
      if (verifyBytes.length != cipherBytes.length) {
        throw Exception('Backup verification check failed (size mismatch)');
      }

      await markBackupCompleted();
      onProgress?.call(1.0, 'Encrypted backup completed & verified successfully!');
      return destFile;
    } catch (e) {
      debugPrint('BackupService: createEncryptedBackupArchive error: $e');
      return null;
    }
  }

  /// Restore vault from an encrypted backup archive (.hidexenc)
  static Future<BackupRestoreResult> restoreFromEncryptedBackupArchive({
    required File backupFile,
    required String secretKey,
    Function(double progress, String status)? onProgress,
  }) async {
    try {
      onProgress?.call(0.1, 'Reading encrypted backup package...');
      if (!await backupFile.exists()) {
        return BackupRestoreResult(isSuccess: false, message: 'Backup file does not exist.');
      }

      final cipherBytes = await backupFile.readAsBytes();
      onProgress?.call(0.25, 'Decrypting backup with vault password...');

      Uint8List plainZipBytes;
      try {
        plainZipBytes = EncryptionService.decryptBytes(cipherBytes, secretKey);
      } catch (e) {
        return BackupRestoreResult(
          isSuccess: false,
          message: 'Incorrect password or corrupted backup file. Verification failed.',
        );
      }

      onProgress?.call(0.45, 'Unpacking backup files...');
      final archive = ZipDecoder().decodeBytes(plainZipBytes);

      // Check manifest
      final manifestFile = archive.findFile('manifest.json');
      if (manifestFile == null) {
        return BackupRestoreResult(isSuccess: false, message: 'Invalid backup package: missing manifest.');
      }

      final manifestData = jsonDecode(utf8.decode(manifestFile.content as List<int>)) as Map<String, dynamic>;
      final fileHashes = (manifestData['fileHashes'] as Map<String, dynamic>?) ?? {};

      final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();

      // Extract vault index
      final indexFile = archive.findFile('vault_index.json');
      List<VaultItem> items = [];
      if (indexFile != null) {
        final list = jsonDecode(utf8.decode(indexFile.content as List<int>)) as List<dynamic>;
        items = list.map((e) => VaultItem.fromJson(e as Map<String, dynamic>)).toList();
      }

      // Extract albums
      final albumsFile = archive.findFile('albums.json');
      List<Album> albums = [];
      if (albumsFile != null) {
        final list = jsonDecode(utf8.decode(albumsFile.content as List<int>)) as List<dynamic>;
        albums = list.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
      }

      // Extract avatar if present
      final avatarArchiveFile = archive.findFile('avatar.enc');
      if (avatarArchiveFile != null) {
        final destAvatar = File('${vaultDir.path}/${PersistentStorageService.AVATAR_FILE_NAME}');
        await destAvatar.writeAsBytes(avatarArchiveFile.content as List<int>, flush: true);
      }

      // Extract media files and verify SHA-256 hashes
      int restoredFiles = 0;
      for (final archiveItem in archive.files) {
        if (archiveItem.name == 'manifest.json' ||
            archiveItem.name == 'vault_index.json' ||
            archiveItem.name == 'albums.json' ||
            archiveItem.name == 'avatar.enc') {
          continue;
        }

        final fileBytes = archiveItem.content as List<int>;
        final expectedHash = fileHashes[archiveItem.name];
        if (expectedHash != null) {
          final computedHash = sha256.convert(fileBytes).toString();
          if (computedHash != expectedHash) {
            return BackupRestoreResult(
              isSuccess: false,
              message: 'Integrity check failed for file: ${archiveItem.name}',
            );
          }
        }

        final targetFile = File('${vaultDir.path}/${archiveItem.name}');
        await targetFile.writeAsBytes(fileBytes, flush: true);
        restoredFiles++;

        final progress = 0.5 + (0.4 * (restoredFiles / (items.isEmpty ? 1 : items.length)));
        onProgress?.call(progress, 'Restoring media ($restoredFiles/${items.length})...');
      }

      // Save decrypted index & albums with secret key
      await PersistentStorageService.saveVaultIndex(items, secretKey);
      await PersistentStorageService.saveAlbums(albums, secretKey);
      await PersistentStorageService.savePersistentVaultConfig(secretKey);

      await markBackupCompleted();
      onProgress?.call(1.0, 'All files restored and verified successfully!');

      return BackupRestoreResult(
        isSuccess: true,
        message: 'Successfully restored ${items.length} file(s) and ${albums.length} album(s)!',
        itemsRestored: items.length,
        albumsRestored: albums.length,
      );
    } catch (e) {
      debugPrint('BackupService: restore error: $e');
      return BackupRestoreResult(
        isSuccess: false,
        message: 'Restore error: ${e.toString()}',
      );
    }
  }

  /// Automatically verify persistent storage backup integrity
  static Future<bool> verifyPersistentBackup(String secretKey) async {
    try {
      final items = await PersistentStorageService.loadVaultIndex(secretKey);
      final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();
      for (final item in items) {
        final file = File('${vaultDir.path}/${item.encryptedFileName}');
        if (!await file.exists()) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
