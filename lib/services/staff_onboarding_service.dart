import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StaffOnboardingService {
  static const _completedPrefix = 'staff_tutorial_completed.';
  static const _pendingKey = 'staff_tutorial_completion_queue';

  static bool requiresTutorial(Map<String, dynamic> profile) =>
      profile['onboardingCompleted'] == false;

  static Future<bool> shouldShowTutorial({
    required FirebaseFirestore database,
    required String staffDocumentId,
  }) async {
    if (staffDocumentId.trim().isEmpty || staffDocumentId.contains('/')) {
      throw ArgumentError('A valid staff account is required.');
    }
    final preferences = await SharedPreferences.getInstance();
    try {
      final profile = await database
          .collection('staff_requests')
          .doc(staffDocumentId)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!profile.exists) {
        throw StateError('The signed-in staff account could not be found.');
      }
      final required = requiresTutorial(profile.data() ?? const {});
      await preferences.setBool('$_completedPrefix$staffDocumentId', !required);
      return required;
    } on FirebaseException catch (error) {
      if (!_isConnectionError(error.code)) rethrow;
      return !(preferences.getBool('$_completedPrefix$staffDocumentId') ??
          false);
    } on TimeoutException {
      return !(preferences.getBool('$_completedPrefix$staffDocumentId') ??
          false);
    }
  }

  static Future<void> markCompleted({
    required FirebaseFirestore database,
    required String staffDocumentId,
  }) async {
    if (staffDocumentId.trim().isEmpty || staffDocumentId.contains('/')) {
      throw ArgumentError('A valid staff account is required.');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('$_completedPrefix$staffDocumentId', true);
    final pending = preferences.getStringList(_pendingKey) ?? [];
    if (!pending.contains(staffDocumentId)) {
      pending.add(staffDocumentId);
      await preferences.setStringList(_pendingKey, pending);
    }
    await _syncOne(database, staffDocumentId);
  }

  static bool _isConnectionError(String code) => const {
    'unavailable',
    'deadline-exceeded',
    'network-request-failed',
  }.contains(code);

  static Future<void> syncPendingTutorialCompletions({
    required FirebaseFirestore database,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final pending = preferences.getStringList(_pendingKey) ?? [];
    for (final staffDocumentId in pending) {
      await _syncOne(database, staffDocumentId);
    }
  }

  static Future<void> _syncOne(
    FirebaseFirestore database,
    String staffDocumentId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    try {
      await database
          .collection('staff_requests')
          .doc(staffDocumentId)
          .update({
            'onboardingCompleted': true,
            'onboardingCompletedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 12));
      final pending = preferences.getStringList(_pendingKey) ?? [];
      pending.remove(staffDocumentId);
      await preferences.setStringList(_pendingKey, pending);
    } on FirebaseException catch (error) {
      if (!_isConnectionError(error.code)) rethrow;
    } on TimeoutException {
      // Keep the completion queued until a connection is available.
    }
  }

  static Future<void> completeTutorial({
    required FirebaseFirestore database,
    required String staffDocumentId,
    required bool isReplay,
  }) async {
    if (isReplay) return;
    await markCompleted(database: database, staffDocumentId: staffDocumentId);
  }
}
