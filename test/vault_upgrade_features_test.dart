import 'dart:typed_data';
import 'package:calendar_vault_app/models/album.dart';
import 'package:calendar_vault_app/models/vault_item.dart';
import 'package:calendar_vault_app/services/backup_service.dart';
import 'package:calendar_vault_app/services/encryption_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HideX App Vault Upgrade Features Tests', () {
    test('1. Album Model serialization, deserialization, and copyWith', () {
      final now = DateTime.now();
      final album = Album(
        id: 'album-101',
        name: 'Private Trip Photos',
        createdAt: now,
        coverItemId: 'item-555',
      );

      final json = album.toJson();
      expect(json['id'], 'album-101');
      expect(json['name'], 'Private Trip Photos');
      expect(json['coverItemId'], 'item-555');

      final reconstructed = Album.fromJson(json);
      expect(reconstructed.id, album.id);
      expect(reconstructed.name, album.name);
      expect(reconstructed.coverItemId, album.coverItemId);

      final updated = album.copyWith(name: 'Renamed Trip');
      expect(updated.name, 'Renamed Trip');
      expect(updated.id, 'album-101');
    });

    test('2. VaultItem Model supports albums, favorites, notes, and copyWith', () {
      final item = VaultItem(
        id: 'vault-1',
        originalName: 'confidential_contract.pdf',
        encryptedFileName: 'enc_vault-1.dat',
        type: VaultMediaType.document,
        fileSizeBytes: 2048576,
        dateAdded: DateTime.now(),
        albumId: 'album-101',
        isFavorite: true,
        notes: 'Signed NDA document',
      );

      expect(item.fileExtension, 'pdf');
      expect(item.isFavorite, isTrue);
      expect(item.albumId, 'album-101');
      expect(item.notes, 'Signed NDA document');

      final json = item.toJson();
      final decoded = VaultItem.fromJson(json);

      expect(decoded.id, item.id);
      expect(decoded.originalName, item.originalName);
      expect(decoded.albumId, 'album-101');
      expect(decoded.isFavorite, isTrue);
      expect(decoded.notes, 'Signed NDA document');

      final unfavorited = item.copyWith(isFavorite: false, notes: 'Updated notes');
      expect(unfavorited.isFavorite, isFalse);
      expect(unfavorited.notes, 'Updated notes');
    });

    test('3. Military-grade Encryption and Decryption consistency test', () {
      const secret = '7-14-21-28';
      final plainData = Uint8List.fromList(List.generate(1024, (i) => i % 256));

      final encrypted = EncryptionService.encryptBytes(plainData, secret);
      expect(encrypted.length, isNot(equals(plainData.length)));

      final decrypted = EncryptionService.decryptBytes(encrypted, secret);
      expect(decrypted, equals(plainData));

      // With wrong password, decryption fails
      expect(
        () => EncryptionService.decryptBytes(encrypted, 'wrong-password'),
        throwsA(anything),
      );
    });

    test('4. Backup and Restore Result verification check', () {
      final successResult = BackupRestoreResult(
        isSuccess: true,
        message: 'Restore successful',
        itemsRestored: 15,
        albumsRestored: 3,
      );

      expect(successResult.isSuccess, isTrue);
      expect(successResult.itemsRestored, 15);
      expect(successResult.albumsRestored, 3);

      final failureResult = BackupRestoreResult(
        isSuccess: false,
        message: 'Invalid password',
      );

      expect(failureResult.isSuccess, isFalse);
      expect(failureResult.itemsRestored, 0);
    });
  });
}
