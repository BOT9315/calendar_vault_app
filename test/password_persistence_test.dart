import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calendar_vault_app/models/album.dart';
import 'package:calendar_vault_app/models/vault_item.dart';
import 'package:calendar_vault_app/services/auth_service.dart';
import 'package:calendar_vault_app/services/persistent_storage_service.dart';
import 'package:calendar_vault_app/services/sequence_detector_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempPrimaryDir;
  late Directory tempSecondaryDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AuthService.clearCacheForTesting();
    tempPrimaryDir = Directory.systemTemp.createTempSync('hidex_pw_test_p_');
    tempSecondaryDir = Directory.systemTemp.createTempSync('hidex_pw_test_s_');
    PersistentStorageService.customVaultDirForTesting = tempPrimaryDir;
    PersistentStorageService.customSecondaryDirForTesting = tempSecondaryDir;
  });

  tearDown(() {
    try {
      if (tempPrimaryDir.existsSync()) {
        tempPrimaryDir.deleteSync(recursive: true);
      }
      if (tempSecondaryDir.existsSync()) {
        tempSecondaryDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    PersistentStorageService.customVaultDirForTesting = null;
    PersistentStorageService.customSecondaryDirForTesting = null;
  });

  group('HideX App Password Persistence Tests', () {
    test('1. First-time setup returns default sequence [7, 14, 21, 28] and permanently persists it', () async {
      final initialSeq = await AuthService.getPasswordSequence();
      expect(initialSeq, equals([7, 14, 21, 28]));

      // Verify it was persisted to storage
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AuthService.PREFS_PASSWORD_KEY), isNotNull);
    });

    test('2. Changing password requires valid current password and validates confirmation', () async {
      // Initialize first
      await AuthService.getPasswordSequence();

      // Wrong current password must fail
      final errorWrongCurrent = await AuthService.changePassword(
        currentPassword: [9, 9, 9, 9],
        newPassword: [3, 6, 9, 12],
        confirmPassword: [3, 6, 9, 12],
      );
      expect(errorWrongCurrent, contains('Current password verification failed'));

      // Mismatching confirmation must fail
      final errorMismatch = await AuthService.changePassword(
        currentPassword: [7, 14, 21, 28],
        newPassword: [3, 6, 9, 12],
        confirmPassword: [3, 6, 9, 15],
      );
      expect(errorMismatch, contains('Confirmation does not match'));

      // Invalid length must fail
      final errorLength = await AuthService.changePassword(
        currentPassword: [7, 14, 21, 28],
        newPassword: [1, 2, 3],
        confirmPassword: [1, 2, 3],
      );
      expect(errorLength, contains('exactly 4 dates'));
    });

    test('3. Successfully changing password saves permanently and survives app restarts', () async {
      // 1. Initial password
      final initialSeq = await AuthService.getPasswordSequence();
      expect(initialSeq, equals([7, 14, 21, 28]));

      // 2. Change password to new dates: [5, 10, 15, 20]
      final result = await AuthService.changePassword(
        currentPassword: [7, 14, 21, 28],
        newPassword: [5, 10, 15, 20],
        confirmPassword: [5, 10, 15, 20],
      );
      expect(result, isNull); // null means success

      // 3. Verify in current session
      final currentInSession = await AuthService.getPasswordSequence();
      expect(currentInSession, equals([5, 10, 15, 20]));
      expect(await AuthService.verifyCurrentPassword([5, 10, 15, 20]), isTrue);
      expect(await AuthService.verifyCurrentPassword([7, 14, 21, 28]), isFalse);

      // 4. SIMULATE APP RESTART: Wipe memory cache completely
      AuthService.clearCacheForTesting();

      // 5. Re-query password as if app just started cold
      final reloadedSeq = await AuthService.getPasswordSequence();

      // MUST be the new password [5, 10, 15, 20], NOT the default [7, 14, 21, 28]!
      expect(reloadedSeq, equals([5, 10, 15, 20]));
      expect(reloadedSeq, isNot(equals([7, 14, 21, 28])));

      // 6. Old password must be rejected, new password must be accepted
      expect(await AuthService.verifyCurrentPassword([7, 14, 21, 28]), isFalse);
      expect(await AuthService.verifyCurrentPassword([5, 10, 15, 20]), isTrue);
    });

    test('4. Sequential password changes maintain the latest password across restarts', () async {
      await AuthService.getPasswordSequence(); // default 7, 14, 21, 28

      // Change 1 -> [2, 4, 6, 8]
      await AuthService.changePassword(
        currentPassword: [7, 14, 21, 28],
        newPassword: [2, 4, 6, 8],
        confirmPassword: [2, 4, 6, 8],
      );

      // Change 2 -> [11, 12, 13, 14]
      await AuthService.changePassword(
        currentPassword: [2, 4, 6, 8],
        newPassword: [11, 12, 13, 14],
        confirmPassword: [11, 12, 13, 14],
      );

      // Simulate app kill & reopen
      AuthService.clearCacheForTesting();

      final active = await AuthService.getPasswordSequence();
      expect(active, equals([11, 12, 13, 14]));
      expect(await AuthService.verifyCurrentPassword([11, 12, 13, 14]), isTrue);
      expect(await AuthService.verifyCurrentPassword([2, 4, 6, 8]), isFalse);
      expect(await AuthService.verifyCurrentPassword([7, 14, 21, 28]), isFalse);
    });
  });

  group('HideX App Reinstallation & Vault Recovery Tests', () {
    test('5. First install: setup custom password and save vault items and albums', () async {
      final success = await AuthService.setPasswordSequence([3, 6, 9, 12]);
      expect(success, isTrue);

      final configFile = File('${tempPrimaryDir.path}/${PersistentStorageService.CONFIG_FILE_NAME}');
      expect(await configFile.exists(), isTrue);

      final items = <VaultItem>[
        VaultItem(
          id: 'item_1',
          originalName: 'family_photo.jpg',
          encryptedFileName: 'family_photo.jpg.enc',
          fileSizeBytes: 10240,
          dateAdded: DateTime.now(),
          type: VaultMediaType.photo,
          albumId: 'album_1',
          isFavorite: true,
        ),
        VaultItem(
          id: 'item_2',
          originalName: 'holiday_video.mp4',
          encryptedFileName: 'holiday_video.mp4.enc',
          fileSizeBytes: 5242880,
          dateAdded: DateTime.now(),
          type: VaultMediaType.video,
          albumId: 'album_1',
          isFavorite: false,
        ),
      ];

      await PersistentStorageService.saveVaultIndex(items, '3-6-9-12');
      final indexFile = File('${tempPrimaryDir.path}/${PersistentStorageService.INDEX_FILE_NAME}');
      expect(await indexFile.exists(), isTrue);

      final albums = <Album>[
        Album(id: 'album_1', name: 'Personal Vacation', createdAt: DateTime.now()),
      ];
      await PersistentStorageService.saveAlbums(albums, '3-6-9-12');
      final albumsFile = File('${tempPrimaryDir.path}/${PersistentStorageService.ALBUMS_FILE_NAME}');
      expect(await albumsFile.exists(), isTrue);

      final loadedItems = await PersistentStorageService.loadVaultIndex('3-6-9-12');
      expect(loadedItems.length, equals(2));
      expect(loadedItems[0].originalName, equals('family_photo.jpg'));
    });

    test('6. Uninstall & Reinstall simulation: Persistent storage survives and prevents default reset', () async {
      await AuthService.setPasswordSequence([3, 6, 9, 12]);
      final items = <VaultItem>[
        VaultItem(
          id: 'photo_rec',
          originalName: 'confidential.png',
          encryptedFileName: 'confidential.png.enc',
          fileSizeBytes: 4096,
          dateAdded: DateTime.now(),
          type: VaultMediaType.photo,
        ),
      ];
      await PersistentStorageService.saveVaultIndex(items, '3-6-9-12');

      // SIMULATE UNINSTALLATION: Sandbox wiped
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      AuthService.clearCacheForTesting();

      expect(await PersistentStorageService.doesExistingVaultExist(), isTrue);
      expect(await AuthService.isPasswordConfigured(), isFalse);
      expect(await AuthService.hasExistingVaultPendingRecovery(), isTrue);

      // CRITICAL: getPasswordSequence() MUST NOT blindly set default password [7, 14, 21, 28]!
      final reinstalledSeq = await AuthService.getPasswordSequence();
      expect(reinstalledSeq, isEmpty);

      final configFile = File('${tempPrimaryDir.path}/${PersistentStorageService.CONFIG_FILE_NAME}');
      expect(await configFile.exists(), isTrue);
    });

    test('7. Recovery verification: Wrong password fails, original password successfully restores vault', () async {
      await AuthService.setPasswordSequence([4, 8, 12, 16]);
      final testItems = <VaultItem>[
        VaultItem(
          id: 'secret_doc',
          originalName: 'financial_records.pdf',
          encryptedFileName: 'financial_records.pdf.enc',
          fileSizeBytes: 20480,
          dateAdded: DateTime.now(),
          type: VaultMediaType.document,
        ),
      ];
      await PersistentStorageService.saveVaultIndex(testItems, '4-8-12-16');

      // Simulate Reinstall
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      AuthService.clearCacheForTesting();

      // Test 1: User tries default password [7, 14, 21, 28] -> MUST FAIL
      final defaultAttempt = await AuthService.restoreVaultWithPassword([7, 14, 21, 28]);
      expect(defaultAttempt, isFalse);

      // Test 2: User tries random wrong dates [1, 2, 3, 4] -> MUST FAIL
      final wrongAttempt = await AuthService.restoreVaultWithPassword([1, 2, 3, 4]);
      expect(wrongAttempt, isFalse);

      // Test 3: User enters their correct original password [4, 8, 12, 16] -> MUST SUCCEED
      final correctAttempt = await AuthService.restoreVaultWithPassword([4, 8, 12, 16]);
      expect(correctAttempt, isTrue);

      expect(await AuthService.isPasswordConfigured(), isTrue);
      expect(await AuthService.getPasswordSequence(), equals([4, 8, 12, 16]));
      expect(await AuthService.hasExistingVaultPendingRecovery(), isFalse);

      final restoredItems = await PersistentStorageService.loadVaultIndex('4-8-12-16');
      expect(restoredItems.length, equals(1));
      expect(restoredItems.first.originalName, equals('financial_records.pdf'));
    });

    test('8. Data Protection Guard: Refuses to overwrite non-empty index with empty list', () async {
      final items = <VaultItem>[
        VaultItem(
          id: 'item_protect',
          originalName: 'passport.jpg',
          encryptedFileName: 'passport.jpg.enc',
          fileSizeBytes: 8192,
          dateAdded: DateTime.now(),
          type: VaultMediaType.photo,
        ),
      ];
      await PersistentStorageService.saveVaultIndex(items, '5-10-15-20');

      // Attempt to save an empty list
      await PersistentStorageService.saveVaultIndex([], '5-10-15-20');

      // The original items must still be preserved!
      final preservedItems = await PersistentStorageService.loadVaultIndex('5-10-15-20');
      expect(preservedItems.length, equals(1));
      expect(preservedItems.first.originalName, equals('passport.jpg'));
    });

    test('9. Sequence Detector automatically recovers vault when user taps original 4 dates on calendar grid', () async {
      await AuthService.setPasswordSequence([2, 5, 10, 15]);

      // Simulate reinstallation
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      AuthService.clearCacheForTesting();

      bool didUnlock = false;
      final detector = SequenceDetectorService(
        targetSequence: const [],
        onMatched: () {
          didUnlock = true;
        },
        onCandidateCheck: (candidate) async {
          return await AuthService.restoreVaultWithPassword(candidate);
        },
      );

      // User taps wrong 4 dates: 1, 2, 3, 4
      detector.onDateTapped(1);
      detector.onDateTapped(2);
      detector.onDateTapped(3);
      detector.onDateTapped(4);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(didUnlock, isFalse);

      detector.reset();

      // User taps correct original 4 dates: 2, 5, 10, 15
      detector.onDateTapped(2);
      detector.onDateTapped(5);
      detector.onDateTapped(10);
      detector.onDateTapped(15);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(didUnlock, isTrue);
      expect(await AuthService.getPasswordSequence(), equals([2, 5, 10, 15]));
    });

    test('10. Explicit Permanent Deletion: Deleting all items with allowEmpty: true empties the vault permanently', () async {
      final items = <VaultItem>[
        VaultItem(
          id: 'item_to_delete',
          originalName: 'temp.jpg',
          encryptedFileName: 'temp.jpg.enc',
          fileSizeBytes: 1024,
          dateAdded: DateTime.now(),
          type: VaultMediaType.photo,
        ),
      ];
      await PersistentStorageService.saveVaultIndex(items, '7-14-21-28');
      expect((await PersistentStorageService.loadVaultIndex('7-14-21-28')).length, equals(1));

      // Explicit permanent deletion with allowEmpty: true
      await PersistentStorageService.saveVaultIndex([], '7-14-21-28', allowEmpty: true);

      // Now index must be empty on disk
      final remaining = await PersistentStorageService.loadVaultIndex('7-14-21-28');
      expect(remaining, isEmpty);
    });

    test('11. Wipe Entire Vault Permanently: Cleans all files, indices, configs, and resets credentials', () async {
      await AuthService.setPasswordSequence([1, 2, 3, 4]);
      final items = <VaultItem>[
        VaultItem(
          id: 'wipe_me',
          originalName: 'wipe.pdf',
          encryptedFileName: 'wipe.pdf.enc',
          fileSizeBytes: 2048,
          dateAdded: DateTime.now(),
          type: VaultMediaType.document,
        ),
      ];
      await PersistentStorageService.saveVaultIndex(items, '1-2-3-4');
      expect(await PersistentStorageService.doesExistingVaultExist(), isTrue);

      // Wipe entire vault permanently
      await PersistentStorageService.wipeEntireVaultPermanently();

      // Everything must now be gone!
      expect(await PersistentStorageService.doesExistingVaultExist(), isFalse);
      expect(await AuthService.isPasswordConfigured(), isFalse);
      expect(await AuthService.hasExistingVaultPendingRecovery(), isFalse);
    });
  });
}
