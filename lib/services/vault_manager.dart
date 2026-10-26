import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:uuid/uuid.dart';
import '../models/album.dart';
import '../models/vault_item.dart';
import 'backup_service.dart';
import 'cloud_backup_service.dart';
import 'encryption_service.dart';
import 'original_media_cleanup_service.dart';
import 'persistent_storage_service.dart';

class VaultImportResult {
  final int totalImported;
  final List<VaultItem> importedItems;
  final VerificationResult verification;
  final int deletedOriginalsCount;

  VaultImportResult({
    required this.totalImported,
    required this.importedItems,
    required this.verification,
    required this.deletedOriginalsCount,
  });
}

class VaultManager extends ChangeNotifier {
  String _secretKey;
  List<VaultItem> _items = [];
  List<Album> _albums = [];
  Uint8List? _profileAvatarBytes;
  bool _isLoading = true;
  final Uuid _uuid = const Uuid();
  final List<File> _activeTempFiles = [];

  String get secretKey => _secretKey;
  List<VaultItem> get items => List.unmodifiable(_items);
  List<Album> get albums => List.unmodifiable(_albums);
  Uint8List? get profileAvatarBytes => _profileAvatarBytes;

  List<VaultItem> get photos => _items.where((e) => e.type == VaultMediaType.photo).toList();
  List<VaultItem> get videos => _items.where((e) => e.type == VaultMediaType.video).toList();
  List<VaultItem> get documents => _items.where((e) => e.type == VaultMediaType.document).toList();
  List<VaultItem> get audio => _items.where((e) => e.type == VaultMediaType.audio).toList();
  List<VaultItem> get others => _items.where((e) => e.type == VaultMediaType.other).toList();
  List<VaultItem> get favorites => _items.where((e) => e.isFavorite).toList();
  List<VaultItem> get downloads => _items.where((e) => e.isDownloaded).toList();
  List<VaultItem> get recentlyAdded {
    final copy = List<VaultItem>.from(_items);
    copy.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    return copy.take(20).toList();
  }

  bool get isLoading => _isLoading;

  VaultManager({required String secretKey}) : _secretKey = secretKey;

  /// Initialize and load all existing items, albums, and profile avatar from persistent storage
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    await PersistentStorageService.requestStoragePermissions();
    _items = await PersistentStorageService.loadVaultIndex(_secretKey);
    _albums = await PersistentStorageService.loadAlbums(_secretKey);
    _profileAvatarBytes = await PersistentStorageService.loadProfileAvatar(_secretKey);

    // Only attempt recovery from master backup bundle if vault index file is physically missing on disk
    // (e.g. fresh reinstall where index was not yet restored).
    // If the index file EXISTS on disk and is empty, that means the user intentionally deleted all items!
    final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();
    final indexFile = File('${vaultDir.path}/${PersistentStorageService.INDEX_FILE_NAME}');
    final secondaryDir = await PersistentStorageService.getSecondaryMirrorDirectory();
    final mirrorIndex = secondaryDir != null ? File('${secondaryDir.path}/${PersistentStorageService.INDEX_FILE_NAME}') : null;

    final indexFileExists = await indexFile.exists() || (mirrorIndex != null && await mirrorIndex.exists());

    if (!indexFileExists && _items.isEmpty) {
      try {
        final masterFile = File('${vaultDir.path}/${PersistentStorageService.MASTER_BACKUP_NAME}');
        if (await masterFile.exists()) {
          final res = await BackupService.restoreFromEncryptedBackupArchive(
            backupFile: masterFile,
            secretKey: _secretKey,
          );
          if (res.isSuccess) {
            _items = await PersistentStorageService.loadVaultIndex(_secretKey);
            _albums = await PersistentStorageService.loadAlbums(_secretKey);
            _profileAvatarBytes = await PersistentStorageService.loadProfileAvatar(_secretKey);
          }
        }
      } catch (e) {
        debugPrint('VaultManager: master backup fallback error: $e');
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Automatically build verified master package and sync to cloud if enabled
  Future<void> triggerAutoBackup() async {
    try {
      final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();
      final masterPath = '${vaultDir.path}/${PersistentStorageService.MASTER_BACKUP_NAME}';
      await BackupService.createEncryptedBackupArchive(
        secretKey: _secretKey,
        items: _items,
        albums: _albums,
        destinationFilePath: masterPath,
      );

      // Mirror master backup to secondary directory
      final secondaryDir = await PersistentStorageService.getSecondaryMirrorDirectory();
      if (secondaryDir != null) {
        final secMaster = File('${secondaryDir.path}/${PersistentStorageService.MASTER_BACKUP_NAME}');
        final priMaster = File(masterPath);
        if (await priMaster.exists()) {
          await priMaster.copy(secMaster.path);
        }
      }

      // Sync to cloud in background
      CloudBackupService.uploadMasterBackupToCloud(
        secretKey: _secretKey,
        items: _items,
        albums: _albums,
      );
    } catch (e) {
      debugPrint('VaultManager: triggerAutoBackup error: $e');
    }
  }

  /// Updates the secret encryption key when user changes their password,
  /// re-encrypts all vault files, index, albums, and profile avatar with the new key.
  Future<void> updateSecretKey(String newSecretKey) async {
    final oldKey = _secretKey;
    _secretKey = newSecretKey;

    try {
      final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();

      // Re-encrypt media items
      for (final item in _items) {
        try {
          final file = File('${vaultDir.path}/${item.encryptedFileName}');
          if (await file.exists()) {
            final plainBytes = await EncryptionService.decryptFileToMemory(file, oldKey);
            final newEncrypted = EncryptionService.encryptBytes(plainBytes, newSecretKey);
            await file.writeAsBytes(newEncrypted, flush: true);
          }
        } catch (e) {
          debugPrint('VaultManager: Error re-encrypting item ${item.originalName}: $e');
        }
      }

      // Re-save index and albums
      await PersistentStorageService.saveVaultIndex(_items, newSecretKey);
      await PersistentStorageService.saveAlbums(_albums, newSecretKey);

      // Re-encrypt profile avatar if present
      if (_profileAvatarBytes != null) {
        await PersistentStorageService.saveProfileAvatar(_profileAvatarBytes!, newSecretKey);
      }

      await BackupService.markVaultModified();
      await triggerAutoBackup();
      notifyListeners();
    } catch (e) {
      debugPrint('VaultManager: Failed updating secret key: $e');
    }
  }

  /// Import files with verified optional deletion of phone originals
  Future<VaultImportResult> importMediaFilesWithVerification({
    required List<File> files,
    bool deleteOriginals = false,
    bool isDownloaded = false,
    String? targetAlbumId,
  }) async {
    final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();
    final List<VaultItem> newlyImportedItems = [];

    for (final file in files) {
      try {
        final originalFileName = file.path.split(Platform.pathSeparator).last;
        final mediaType = detectMediaType(originalFileName);
        final uniqueId = _uuid.v4();
        final encryptedFileName = 'enc_$uniqueId.dat';
        final destinationFile = File('${vaultDir.path}/$encryptedFileName');

        // Encrypt the file using AES-256
        await EncryptionService.encryptFile(file, destinationFile, secretKey);

        final stat = await file.stat();
        final newItem = VaultItem(
          id: uniqueId,
          originalName: originalFileName,
          encryptedFileName: encryptedFileName,
          type: mediaType,
          fileSizeBytes: stat.size,
          dateAdded: DateTime.now(),
          isDownloaded: isDownloaded,
          albumId: targetAlbumId,
        );

        _items.insert(0, newItem);
        newlyImportedItems.add(newItem);
      } catch (e) {
        debugPrint('Failed to import file ${file.path}: $e');
      }
    }

    // Step 2: Verification check on all newly created vault items
    final verification = await OriginalMediaCleanupService.verifyImportedFiles(
      vaultItems: newlyImportedItems,
      originalFiles: files,
      secretKey: secretKey,
    );

    int deletedCount = 0;
    // Step 3: Delete originals only if requested AND verification passes 100%
    if (deleteOriginals && verification.allVerified) {
      deletedCount = await OriginalMediaCleanupService.deleteVerifiedOriginals(
        verifiedOriginals: verification.verifiedOriginals,
      );
    }

    if (newlyImportedItems.isNotEmpty) {
      await PersistentStorageService.saveVaultIndex(_items, secretKey);
      await BackupService.markVaultModified();
      notifyListeners();
    }

    return VaultImportResult(
      totalImported: newlyImportedItems.length,
      importedItems: newlyImportedItems,
      verification: verification,
      deletedOriginalsCount: deletedCount,
    );
  }

  /// Backward-compatible import method
  Future<int> importMediaFiles({
    required List<File> files,
    bool deleteOriginals = false,
    bool isDownloaded = false,
  }) async {
    final result = await importMediaFilesWithVerification(
      files: files,
      deleteOriginals: deleteOriginals,
      isDownloaded: isDownloaded,
    );
    return result.totalImported;
  }

  /// Save raw bytes downloaded from the Private Browser directly into the encrypted persistent vault
  Future<VaultItem?> savePrivateBrowserDownload({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();
      final mediaType = detectMediaType(fileName);
      final uniqueId = _uuid.v4();
      final encryptedFileName = 'enc_$uniqueId.dat';
      final destinationFile = File('${vaultDir.path}/$encryptedFileName');

      // Encrypt bytes directly into vault file
      final cipherBytes = EncryptionService.encryptBytes(bytes, secretKey);
      await destinationFile.writeAsBytes(cipherBytes, flush: true);

      final newItem = VaultItem(
        id: uniqueId,
        originalName: fileName,
        encryptedFileName: encryptedFileName,
        type: mediaType,
        fileSizeBytes: bytes.length,
        dateAdded: DateTime.now(),
        isDownloaded: true,
      );

      _items.insert(0, newItem);
      await PersistentStorageService.saveVaultIndex(_items, secretKey);
      await BackupService.markVaultModified();
      notifyListeners();
      return newItem;
    } catch (e) {
      debugPrint('Failed to save private browser download: $e');
      return null;
    }
  }

  /// Decrypt a specific vault item into memory for instant display in the app viewer
  Future<Uint8List> getDecryptedBytes(VaultItem item) async {
    final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();
    final encryptedFile = File('${vaultDir.path}/${item.encryptedFileName}');
    return EncryptionService.decryptFileToMemory(encryptedFile, secretKey);
  }

  /// Decrypt to a temporary file in memory/system cache and open with system/app viewer
  Future<OpenResult> openVaultItem(VaultItem item) async {
    final bytes = await getDecryptedBytes(item);
    final tempDir = Directory.systemTemp;
    final extension = item.fileExtension.isNotEmpty ? item.fileExtension : 'dat';
    final tempFile = File('${tempDir.path}/temp_${item.id}.$extension');
    await tempFile.writeAsBytes(bytes);
    _activeTempFiles.add(tempFile);

    return OpenFilex.open(tempFile.path);
  }

  /// Decrypt a video into a temporary file for the video player controller
  Future<File> getDecryptedTempFile(VaultItem item) async {
    final bytes = await getDecryptedBytes(item);
    final tempDir = Directory.systemTemp;
    final extension = item.fileExtension.isNotEmpty ? item.fileExtension : 'mp4';
    final tempFile = File('${tempDir.path}/temp_${item.id}.$extension');
    await tempFile.writeAsBytes(bytes);
    _activeTempFiles.add(tempFile);
    return tempFile;
  }

  /// Export / Restore an item back to the phone's public folder (Downloads / Gallery)
  Future<bool> exportItemToPublicStorage(VaultItem item, String targetFolderPath) async {
    try {
      final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();
      final encryptedFile = File('${vaultDir.path}/${item.encryptedFileName}');
      final targetFile = File('$targetFolderPath/${item.originalName}');
      await EncryptionService.decryptFileToDestination(encryptedFile, targetFile, secretKey);
      return true;
    } catch (e) {
      debugPrint('Export error: $e');
      return false;
    }
  }

  /// Batch export multiple items
  Future<int> exportMultipleItems(List<VaultItem> itemsToExport, String targetFolderPath) async {
    int successCount = 0;
    for (final item in itemsToExport) {
      final ok = await exportItemToPublicStorage(item, targetFolderPath);
      if (ok) successCount++;
    }
    return successCount;
  }

  /// Toggle favorite status of an item
  Future<void> toggleFavorite(VaultItem item) async {
    final index = _items.indexWhere((e) => e.id == item.id);
    if (index != -1) {
      _items[index].isFavorite = !_items[index].isFavorite;
      await PersistentStorageService.saveVaultIndex(_items, secretKey);
      await BackupService.markVaultModified();
      notifyListeners();
    }
  }

  /// Rename an item
  Future<void> renameItem(VaultItem item, String newName) async {
    final index = _items.indexWhere((e) => e.id == item.id);
    if (index != -1) {
      _items[index].originalName = newName;
      _items[index].dateModified = DateTime.now();
      await PersistentStorageService.saveVaultIndex(_items, secretKey);
      await BackupService.markVaultModified();
      notifyListeners();
    }
  }

  /// Update notes on an item
  Future<void> updateNotes(VaultItem item, String notes) async {
    final index = _items.indexWhere((e) => e.id == item.id);
    if (index != -1) {
      _items[index].notes = notes;
      _items[index].dateModified = DateTime.now();
      await PersistentStorageService.saveVaultIndex(_items, secretKey);
      await BackupService.markVaultModified();
      notifyListeners();
    }
  }

  /// Permanently delete an item from the secret vault and all persistent mirrors
  Future<void> deleteItem(VaultItem item) async {
    try {
      final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();
      final secondaryDir = await PersistentStorageService.getSecondaryMirrorDirectory();

      // 1. Delete from primary directory
      final encryptedFile = File('${vaultDir.path}/${item.encryptedFileName}');
      if (await encryptedFile.exists()) {
        await encryptedFile.delete();
      }

      // 2. Delete from secondary mirror directory
      if (secondaryDir != null) {
        final mirrorFile = File('${secondaryDir.path}/${item.encryptedFileName}');
        if (await mirrorFile.exists()) {
          await mirrorFile.delete();
        }
      }

      // 3. Delete from active temp files
      _activeTempFiles.removeWhere((file) {
        if (file.path.contains(item.id)) {
          try {
            if (file.existsSync()) file.deleteSync();
          } catch (_) {}
          return true;
        }
        return false;
      });

      // 4. Remove from in-memory list
      _items.removeWhere((e) => e.id == item.id);

      // 5. Save updated index to storage (allowEmpty: true so empty vault is saved!)
      await PersistentStorageService.saveVaultIndex(_items, secretKey, allowEmpty: true);

      // 6. If vault is now empty, purge master backup archive so items are not resurrected
      if (_items.isEmpty) {
        final masterFile = File('${vaultDir.path}/${PersistentStorageService.MASTER_BACKUP_NAME}');
        if (await masterFile.exists()) {
          await masterFile.delete();
        }
        if (secondaryDir != null) {
          final secMaster = File('${secondaryDir.path}/${PersistentStorageService.MASTER_BACKUP_NAME}');
          if (await secMaster.exists()) {
            await secMaster.delete();
          }
        }
      } else {
        await triggerAutoBackup();
      }

      await BackupService.markVaultModified();
      notifyListeners();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  /// Permanently delete multiple items
  Future<int> deleteMultipleItems(List<VaultItem> itemsToDelete) async {
    int deleted = 0;
    final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();
    final secondaryDir = await PersistentStorageService.getSecondaryMirrorDirectory();
    final idsToRemove = <String>{};

    for (final item in itemsToDelete) {
      try {
        final encryptedFile = File('${vaultDir.path}/${item.encryptedFileName}');
        if (await encryptedFile.exists()) {
          await encryptedFile.delete();
        }
        if (secondaryDir != null) {
          final mirrorFile = File('${secondaryDir.path}/${item.encryptedFileName}');
          if (await mirrorFile.exists()) {
            await mirrorFile.delete();
          }
        }
        _activeTempFiles.removeWhere((file) {
          if (file.path.contains(item.id)) {
            try {
              if (file.existsSync()) file.deleteSync();
            } catch (_) {}
            return true;
          }
          return false;
        });

        idsToRemove.add(item.id);
        deleted++;
      } catch (e) {
        debugPrint('Batch delete error for ${item.originalName}: $e');
      }
    }

    _items.removeWhere((e) => idsToRemove.contains(e.id));
    await PersistentStorageService.saveVaultIndex(_items, secretKey, allowEmpty: true);

    if (_items.isEmpty) {
      final masterFile = File('${vaultDir.path}/${PersistentStorageService.MASTER_BACKUP_NAME}');
      if (await masterFile.exists()) {
        await masterFile.delete();
      }
      if (secondaryDir != null) {
        final secMaster = File('${secondaryDir.path}/${PersistentStorageService.MASTER_BACKUP_NAME}');
        if (await secMaster.exists()) {
          await secMaster.delete();
        }
      }
    } else {
      await triggerAutoBackup();
    }

    await BackupService.markVaultModified();
    notifyListeners();
    return deleted;
  }

  /// Completely wipe and permanently reset all vault data from this phone
  Future<void> wipeEntireVault() async {
    await PersistentStorageService.wipeEntireVaultPermanently();
    _items.clear();
    _albums.clear();
    _profileAvatarBytes = null;
    notifyListeners();
  }

  /// Alias for wipeEntireVault
  Future<void> wipeVault() => wipeEntireVault();

  // ================= ALBUMS MANAGEMENT =================

  /// Create a new album
  Future<Album> createAlbum(String name) async {
    final newAlbum = Album(
      id: _uuid.v4(),
      name: name.trim(),
      createdAt: DateTime.now(),
    );
    _albums.add(newAlbum);
    await PersistentStorageService.saveAlbums(_albums, secretKey);
    await BackupService.markVaultModified();
    notifyListeners();
    return newAlbum;
  }

  /// Rename an album
  Future<void> renameAlbum(String albumId, String newName) async {
    final index = _albums.indexWhere((a) => a.id == albumId);
    if (index != -1) {
      _albums[index].name = newName.trim();
      await PersistentStorageService.saveAlbums(_albums, secretKey);
      await BackupService.markVaultModified();
      notifyListeners();
    }
  }

  /// Delete an album (files are kept in vault, albumId unassigned)
  Future<void> deleteAlbum(String albumId) async {
    _albums.removeWhere((a) => a.id == albumId);
    for (final item in _items) {
      if (item.albumId == albumId) {
        item.albumId = null;
      }
    }
    await PersistentStorageService.saveAlbums(_albums, secretKey);
    await PersistentStorageService.saveVaultIndex(_items, secretKey);
    await BackupService.markVaultModified();
    notifyListeners();
  }

  /// Move item to an album
  Future<void> assignItemToAlbum(String itemId, String? albumId) async {
    final itemIndex = _items.indexWhere((e) => e.id == itemId);
    if (itemIndex != -1) {
      _items[itemIndex].albumId = albumId;

      // Update album cover if needed
      if (albumId != null) {
        final albumIndex = _albums.indexWhere((a) => a.id == albumId);
        if (albumIndex != -1 && _albums[albumIndex].coverItemId == null) {
          _albums[albumIndex].coverItemId = itemId;
          await PersistentStorageService.saveAlbums(_albums, secretKey);
        }
      }

      await PersistentStorageService.saveVaultIndex(_items, secretKey);
      await BackupService.markVaultModified();
      notifyListeners();
    }
  }

  /// Move multiple items to an album
  Future<void> moveMultipleItemsToAlbum(List<VaultItem> itemsToMove, String? albumId) async {
    for (final item in itemsToMove) {
      final index = _items.indexWhere((e) => e.id == item.id);
      if (index != -1) {
        _items[index].albumId = albumId;
      }
    }

    if (albumId != null && itemsToMove.isNotEmpty) {
      final albumIndex = _albums.indexWhere((a) => a.id == albumId);
      if (albumIndex != -1) {
        _albums[albumIndex].coverItemId = itemsToMove.first.id;
        await PersistentStorageService.saveAlbums(_albums, secretKey);
      }
    }

    await PersistentStorageService.saveVaultIndex(_items, secretKey);
    await BackupService.markVaultModified();
    notifyListeners();
  }

  /// Get items belonging to an album
  List<VaultItem> getItemsForAlbum(String albumId) {
    return _items.where((e) => e.albumId == albumId).toList();
  }

  // ================= PROFILE AVATAR =================

  /// Save user profile picture in the encrypted vault
  Future<void> setProfileAvatar(Uint8List imageBytes) async {
    _profileAvatarBytes = imageBytes;
    await PersistentStorageService.saveProfileAvatar(imageBytes, secretKey);
    await BackupService.markVaultModified();
    notifyListeners();
  }

  // ================= STORAGE BREAKDOWN =================

  int getTotalStorageBytes() {
    return _items.fold(0, (sum, item) => sum + item.fileSizeBytes);
  }

  int getStorageBytesForType(VaultMediaType type) {
    return _items.where((e) => e.type == type).fold(0, (sum, item) => sum + item.fileSizeBytes);
  }

  /// Clean up any decrypted temporary preview files from disk cache for privacy
  void cleanupTempFiles() {
    for (final file in _activeTempFiles) {
      try {
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
    _activeTempFiles.clear();
  }

  static VaultMediaType detectMediaType(String fileName) {
    final lower = fileName.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';

    const photoExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'svg'};
    const videoExts = {'mp4', 'mov', 'avi', 'mkv', '3gp', 'webm', 'flv', 'wmv'};
    const audioExts = {'mp3', 'wav', 'm4a', 'flac', 'aac', 'ogg', 'wma', 'opus'};
    const docExts = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'rtf', 'odt', 'ods', 'odp'};

    if (photoExts.contains(ext)) return VaultMediaType.photo;
    if (videoExts.contains(ext)) return VaultMediaType.video;
    if (audioExts.contains(ext)) return VaultMediaType.audio;
    if (docExts.contains(ext)) return VaultMediaType.document;
    return VaultMediaType.other;
  }
}
