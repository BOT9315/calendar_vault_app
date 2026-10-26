import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/vault_item.dart';
import 'encryption_service.dart';
import 'persistent_storage_service.dart';

class VerificationResult {
  final bool allVerified;
  final List<File> verifiedOriginals;
  final List<String> failedFileNames;
  final List<VaultItem> verifiedVaultItems;

  VerificationResult({
    required this.allVerified,
    required this.verifiedOriginals,
    required this.failedFileNames,
    required this.verifiedVaultItems,
  });
}

class OriginalMediaCleanupService {
  /// Verify each imported item in the vault before allowing deletion of phone originals
  static Future<VerificationResult> verifyImportedFiles({
    required List<VaultItem> vaultItems,
    required List<File> originalFiles,
    required String secretKey,
  }) async {
    final vaultDir = await PersistentStorageService.getPersistentVaultDirectory();
    final List<File> verifiedOriginals = [];
    final List<VaultItem> verifiedVaultItems = [];
    final List<String> failedNames = [];

    for (int i = 0; i < vaultItems.length; i++) {
      final item = vaultItems[i];
      final original = (i < originalFiles.length) ? originalFiles[i] : null;

      try {
        final encFile = File('${vaultDir.path}/${item.encryptedFileName}');

        // Check 1: Encrypted file must exist
        if (!await encFile.exists()) {
          debugPrint('Verification failed: Encrypted file does not exist: ${encFile.path}');
          failedNames.add(item.originalName);
          continue;
        }

        // Check 2: File must not be 0 bytes
        final length = await encFile.length();
        if (length == 0) {
          debugPrint('Verification failed: Encrypted file is empty (0 bytes): ${encFile.path}');
          failedNames.add(item.originalName);
          continue;
        }

        // Check 3: File must be decryptable with secret key
        final decrypted = await EncryptionService.decryptFileToMemory(encFile, secretKey);
        if (decrypted.isEmpty) {
          debugPrint('Verification failed: Decrypted bytes are empty for: ${item.originalName}');
          failedNames.add(item.originalName);
          continue;
        }

        // Verification passed for this item
        verifiedVaultItems.add(item);
        if (original != null) {
          verifiedOriginals.add(original);
        }
      } catch (e) {
        debugPrint('Verification exception for ${item.originalName}: $e');
        failedNames.add(item.originalName);
      }
    }

    final allVerified = failedNames.isEmpty && verifiedOriginals.length == originalFiles.length;
    return VerificationResult(
      allVerified: allVerified,
      verifiedOriginals: verifiedOriginals,
      failedFileNames: failedNames,
      verifiedVaultItems: verifiedVaultItems,
    );
  }

  /// Delete verified original files from device with safety checks
  static Future<int> deleteVerifiedOriginals({
    required List<File> verifiedOriginals,
  }) async {
    int deletedCount = 0;

    for (final original in verifiedOriginals) {
      try {
        if (await original.exists()) {
          await original.delete();
          deletedCount++;
        }
      } catch (e) {
        debugPrint('OriginalMediaCleanupService: Could not delete ${original.path}: $e');
      }
    }

    return deletedCount;
  }
}
