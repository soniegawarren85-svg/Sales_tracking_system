import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import 'super_admin.dart';

class AccountPresenceService with WidgetsBindingObserver {
  AccountPresenceService._();

  static final AccountPresenceService _instance = AccountPresenceService._();
  static const _heartbeatInterval = Duration(minutes: 1);
  static const _onlineGracePeriod = Duration(minutes: 3);

  Timer? _heartbeat;
  DocumentReference<Map<String, dynamic>>? _profile;

  static DocumentReference<Map<String, dynamic>> _profileFor({
    required String role,
    required String userId,
    required FirebaseFirestore database,
  }) {
    if (role == SuperAdmin.role) {
      return database.collection('super_admin_profiles').doc(SuperAdmin.id);
    }
    return database.collection('staff_requests').doc(userId);
  }

  static Future<void> start({
    required String role,
    required String userId,
    FirebaseFirestore? database,
  }) async {
    final db = database ?? FirebaseFirestore.instance;
    final service = _instance;
    service._heartbeat?.cancel();
    service._profile = _profileFor(role: role, userId: userId, database: db);
    WidgetsBinding.instance.addObserver(service);
    await service._writeOnline(true);
    service._startHeartbeat();
  }

  static Future<void> stop({
    required String role,
    required String userId,
    FirebaseFirestore? database,
  }) async {
    final service = _instance;
    service._heartbeat?.cancel();
    service._heartbeat = null;
    WidgetsBinding.instance.removeObserver(service);
    final profile =
        service._profile ??
        _profileFor(
          role: role,
          userId: userId,
          database: database ?? FirebaseFirestore.instance,
        );
    service._profile = null;
    await _writeOffline(profile, logout: true);
  }

  Future<void> _writeOnline(bool updateLoginTime) async {
    final profile = _profile;
    if (profile == null) return;
    try {
      await profile.set({
        'isOnline': true,
        'lastSeenAt': FieldValue.serverTimestamp(),
        if (updateLoginTime) 'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Unable to update account presence: $error');
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
      _heartbeatInterval,
      (_) => unawaited(_writeOnline(false)),
    );
  }

  static Future<void> _writeOffline(
    DocumentReference<Map<String, dynamic>> profile, {
    bool logout = false,
  }) async {
    try {
      await profile.set({
        'isOnline': false,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'lastOfflineAt': FieldValue.serverTimestamp(),
        if (logout) 'lastLogoutAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Unable to save offline presence: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_writeOnline(false));
      _startHeartbeat();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _heartbeat?.cancel();
      _heartbeat = null;
      final profile = _profile;
      if (profile != null) unawaited(_writeOffline(profile));
    }
  }

  static DateTime? lastSeen(Map<String, dynamic> data) {
    for (final field in [
      'lastSeenAt',
      'lastOfflineAt',
      'lastLogoutAt',
      'lastLoginAt',
    ]) {
      final value = data[field];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static bool isOnline(Map<String, dynamic> data, {DateTime? now}) {
    final seenAt = lastSeen(data);
    final referenceTime = now ?? DateTime.now();
    if (data['isOnline'] is bool) {
      return data['isOnline'] == true &&
          seenAt != null &&
          referenceTime.difference(seenAt) <= _onlineGracePeriod;
    }
    final lastLogin = data['lastLoginAt'];
    final loginAt = lastLogin is Timestamp
        ? lastLogin.toDate()
        : lastLogin is DateTime
        ? lastLogin
        : DateTime.tryParse('$lastLogin');
    return loginAt != null &&
        referenceTime.difference(loginAt) <= const Duration(minutes: 15);
  }

  static String offlineStatus(Map<String, dynamic> data, {DateTime? now}) {
    if (isOnline(data, now: now)) return 'Online';
    final lastSeenAt = lastSeen(data);
    if (lastSeenAt == null) return 'Offline';
    final difference = (now ?? DateTime.now()).difference(lastSeenAt);
    if (difference.isNegative || difference.inMinutes == 0) {
      return 'Offline · just now';
    }
    if (difference.inDays >= 365) {
      final years = difference.inDays ~/ 365;
      return 'Offline · $years ${years == 1 ? 'year' : 'years'} ago';
    }
    if (difference.inDays >= 30) {
      final months = difference.inDays ~/ 30;
      return 'Offline · $months ${months == 1 ? 'month' : 'months'} ago';
    }
    if (difference.inDays >= 1) {
      final days = difference.inDays;
      return 'Offline · $days ${days == 1 ? 'day' : 'days'} ago';
    }
    if (difference.inHours >= 1) {
      final hours = difference.inHours;
      return 'Offline · $hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }
    final minutes = difference.inMinutes;
    return 'Offline · $minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
  }
}
