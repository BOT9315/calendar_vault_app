import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class EncryptionService {
  // Derive a 32-byte (256-bit) AES key from the user's secret passcode / sequence
  static enc.Key _deriveKey(String secret) {
    const salt = 'CalendarVault_SecureSalt_2026';
    final bytes = utf8.encode('$secret$salt');
    final digest = sha256.convert(bytes);
    return enc.Key(Uint8List.fromList(digest.bytes));
  }

  // Derive an IV from the first 16 bytes of MD5 of the secret
  static enc.IV _deriveIV(String secret) {
    final bytes = utf8.encode('${secret}_IV_SALT');
    final digest = md5.convert(bytes);
    return enc.IV(Uint8List.fromList(digest.bytes));
  }

  /// Encrypt arbitrary bytes with AES-256-CBC
  static Uint8List encryptBytes(Uint8List plainBytes, String secret) {
    final key = _deriveKey(secret);
    final iv = _deriveIV(secret);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);
    return encrypted.bytes;
  }

  /// Decrypt arbitrary bytes with AES-256-CBC
  static Uint8List decryptBytes(Uint8List cipherBytes, String secret) {
    final key = _deriveKey(secret);
    final iv = _deriveIV(secret);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final decrypted = encrypter.decryptBytes(enc.Encrypted(cipherBytes), iv: iv);
    return Uint8List.fromList(decrypted);
  }

  /// Encrypt a string (e.g., JSON manifest index)
  static String encryptString(String plainText, String secret) {
    final key = _deriveKey(secret);
    final iv = _deriveIV(secret);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.encrypt(plainText, iv: iv).base64;
  }

  /// Decrypt a string
  static String decryptString(String cipherBase64, String secret) {
    final key = _deriveKey(secret);
    final iv = _deriveIV(secret);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt64(cipherBase64, iv: iv);
  }

  /// Encrypt a local file directly and save to persistent vault location
  static Future<void> encryptFile(File sourceFile, File destinationFile, String secret) async {
    final bytes = await sourceFile.readAsBytes();
    final encryptedBytes = encryptBytes(bytes, secret);
    await destinationFile.writeAsBytes(encryptedBytes, flush: true);
  }

  /// Decrypt a vault file in-memory for secure viewing without saving to gallery
  static Future<Uint8List> decryptFileToMemory(File encryptedFile, String secret) async {
    final cipherBytes = await encryptedFile.readAsBytes();
    return decryptBytes(cipherBytes, secret);
  }

  /// Decrypt a vault file to public storage (when user chooses "Export / Unhide to Gallery")
  static Future<void> decryptFileToDestination(File encryptedFile, File destFile, String secret) async {
    final cipherBytes = await encryptedFile.readAsBytes();
    final plainBytes = decryptBytes(cipherBytes, secret);
    await destFile.writeAsBytes(plainBytes, flush: true);
  }
}
