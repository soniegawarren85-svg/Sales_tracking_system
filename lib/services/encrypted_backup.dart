import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Password-encrypted local backup container (PBKDF2-HMAC-SHA256 + AES-256-GCM).
class EncryptedBackup {
  static const format = 'sales-tracking-encrypted-backup';
  static const version = 1;
  static const _iterations = 310000;
  static const _saltLength = 16;

  static Future<Uint8List> encrypt(
    Uint8List clearBytes,
    String password,
  ) async {
    if (password.isEmpty) throw ArgumentError('Backup password is required.');
    final algorithm = AesGcm.with256bits();
    final salt = await SecretKeyData.random(length: _saltLength).extractBytes();
    final key = await Pbkdf2.hmacSha256(
      iterations: _iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
    final box = await algorithm.encrypt(
      clearBytes,
      secretKey: key,
      nonce: algorithm.newNonce(),
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': format,
          'version': version,
          'kdf': 'PBKDF2-HMAC-SHA256',
          'iterations': _iterations,
          'cipher': 'AES-256-GCM',
          'salt': base64Encode(salt),
          'nonce': base64Encode(box.nonce),
          'cipherText': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
        }),
      ),
    );
  }

  static Future<Uint8List> decrypt(
    Uint8List encryptedBytes,
    String password,
  ) async {
    if (encryptedBytes.isEmpty || encryptedBytes.length > 80 * 1024 * 1024) {
      throw const FormatException('Encrypted backup is empty or exceeds 80 MB.');
    }
    try {
      final envelope = jsonDecode(utf8.decode(encryptedBytes));
      if (envelope is! Map ||
          envelope['format'] != format ||
          envelope['version'] != version ||
          envelope['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          envelope['cipher'] != 'AES-256-GCM' ||
          envelope['iterations'] != _iterations) {
        throw const FormatException('Unsupported or invalid encrypted backup.');
      }
      final salt = base64Decode(envelope['salt'] as String);
      final nonce = base64Decode(envelope['nonce'] as String);
      final cipherText = base64Decode(envelope['cipherText'] as String);
      final mac = base64Decode(envelope['mac'] as String);
      if (salt.length != _saltLength ||
          nonce.length != 12 ||
          mac.length != 16) {
        throw const FormatException('Encrypted backup header is invalid.');
      }
      final key = await Pbkdf2.hmacSha256(
        iterations: _iterations,
        bits: 256,
      ).deriveKeyFromPassword(password: password, nonce: salt);
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'The password is incorrect or the backup file has been changed.',
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'The password is incorrect or the backup file is corrupted.',
      );
    }
  }
}
