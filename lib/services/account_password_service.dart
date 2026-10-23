import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

const legacyPasswordFields = [
  'password',
  'loginPassword',
  'plainPassword',
  'temporaryPassword',
  'defaultPassword',
  'Password',
  'LoginPassword',
  'TemporaryPassword',
];

String _derive(Map<String, String> input) {
  final mac = Hmac(sha256, utf8.encode(input['password']!));
  var block = mac.convert([...base64Decode(input['salt']!), 0, 0, 0, 1]).bytes;
  final result = List<int>.of(block);
  for (var i = 1; i < 100000; i++) {
    block = mac.convert(block).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= block[j];
    }
  }
  return base64Encode(result);
}

Future<Map<String, dynamic>> createPasswordCredential(String password) async {
  final random = Random.secure();
  final salt = base64Encode(List.generate(16, (_) => random.nextInt(256)));
  return {
    'algorithm': 'pbkdf2-sha256-100000',
    'salt': salt,
    'hash': await compute(_derive, {'password': password, 'salt': salt}),
  };
}

Future<bool> matchesAccountPassword(
  Map<String, dynamic> account,
  String password,
) async {
  final credential = account['passwordCredential'];
  if (credential is Map) {
    if (credential['algorithm'] != 'pbkdf2-sha256-100000' ||
        credential['salt'] is! String)
      return false;
    final actual = await compute(_derive, {
      'password': password,
      'salt': credential['salt'] as String,
    });
    return actual == credential['hash'];
  }
  if (account['credentialsChangedAt'] != null) return false;
  return legacyPasswordFields.any(
    (field) => account[field] == password && password.isNotEmpty,
  );
}

Future<void> changeFirestoreAccountPassword({
  required DocumentReference<Map<String, dynamic>> account,
  required String currentPassword,
  required String newPassword,
}) async {
  if (newPassword.length < 6) throw ArgumentError('Use at least 6 characters.');
  final before = (await account.get(
    const GetOptions(source: Source.server),
  )).data();
  if (before == null ||
      !await matchesAccountPassword(before, currentPassword)) {
    throw StateError('Current password is incorrect.');
  }
  final credential = await createPasswordCredential(newPassword);
  await account.firestore.runTransaction((tx) async {
    final latest = (await tx.get(account)).data();
    if (jsonEncode(latest?['passwordCredential']) !=
            jsonEncode(before['passwordCredential']) ||
        latest?['credentialsChangedAt'] != before['credentialsChangedAt']) {
      throw StateError('Credentials changed. Please sign in again.');
    }
    tx.update(account, {
      'passwordCredential': credential,
      'passwordAuthMode': 'firestore',
      'credentialsChangedAt': FieldValue.serverTimestamp(),
      'mustChangePassword': false,
      'passwordChangedAt': FieldValue.serverTimestamp(),
      for (final field in legacyPasswordFields) field: FieldValue.delete(),
    });
  });
}
