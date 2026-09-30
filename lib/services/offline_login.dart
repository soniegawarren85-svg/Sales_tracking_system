import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'account_username.dart';
import 'local_database_sync_service.dart';

bool offlineUsernameMatches(Map<String, dynamic> account, String username) =>
    ['adminId', 'staffId', 'username'].any(
      (field) =>
          normalizeAccountUsername('${account[field] ?? ''}') ==
          normalizeAccountUsername(username),
    );

bool offlineAccountAllowed(Map<String, dynamic> account) {
  final role = '${account['role'] ?? 'staff'}'.trim().toLowerCase();
  final status = '${account['status'] ?? ''}'.trim().toLowerCase();
  return (account['_localDocId']?.toString().isNotEmpty ?? false) &&
      (role == 'admin' || role == 'staff') &&
      (status == 'accepted' || (role == 'admin' && status.isEmpty)) &&
      account['isVoided'] != true;
}

String offlineCredentialVersion(Map<String, dynamic> account) {
  final value = account['credentialsChangedAt'];
  return value is Timestamp
      ? '${value.microsecondsSinceEpoch}'
      : '${value ?? ''}';
}

bool offlineStoredPasswordMatches(
  Map<String, dynamic> account,
  String password,
) {
  // Legacy password fields are stale after a Firebase password change.
  if (password.isEmpty || account['credentialsChangedAt'] != null) return false;
  return [
    'password',
    'loginPassword',
    'plainPassword',
    'temporaryPassword',
    'defaultPassword',
    'Password',
    'LoginPassword',
    'TemporaryPassword',
  ].any((field) => account[field]?.toString() == password);
}

/// Keep the device's account list current, including deletions and deactivation.
/// Cache-only snapshots must not erase an already saved full collection.
class OfflineAccountSync {
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  static Future<void> _pending = Future<void>.value();

  static void start() {
    _subscription ??= FirebaseFirestore.instance
        .collection('staff_requests')
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (snapshot.metadata.isFromCache ||
                snapshot.metadata.hasPendingWrites)
              return;
            _pending = _pending
                .then(
                  (_) => LocalDatabaseSyncService().cacheCollectionDocs(
                    'staff_requests',
                    snapshot.docs.map(
                      (doc) => {...doc.data(), '_localDocId': doc.id},
                    ),
                  ),
                )
                .catchError((Object error) {
                  debugPrint('Unable to sync offline accounts: $error');
                });
          },
          onError: (Object error) {
            debugPrint('Account sync unavailable: $error');
            _subscription?.cancel();
            _subscription = null;
          },
        );
  }
}
