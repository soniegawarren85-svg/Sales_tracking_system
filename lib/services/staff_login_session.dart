import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_ip.dart';
import 'local_database_sync_service.dart';

class StaffLoginSession {
  static Future<void> _flushQueue = Future<void>.value();
  static Future<void> start(
    BuildContext context,
    String uid,
    Map<String, dynamic> staff, {
    bool offline = false,
  }) async {
    final loginAt = DateTime.now();
    try {
      unawaited(flush());
      final prefs = await SharedPreferences.getInstance();
      await close();
      final deviceId =
          prefs.getString('staffDeviceId') ??
          FirebaseFirestore.instance
              .collection('staff_login_sessions')
              .doc()
              .id;
      await prefs.setString('staffDeviceId', deviceId);
      final query = FirebaseFirestore.instance.collection('branches');
      List<Map<String, dynamic>> branches;
      try {
        if (offline) {
          branches = await LocalDatabaseSyncService().getCachedCollection(
            'branches',
          );
        } else {
          final snapshot = await query
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 5));
          branches = snapshot.docs
              .map((doc) => {...doc.data(), '_localDocId': doc.id})
              .toList();
          await LocalDatabaseSyncService().cacheCollectionDocs(
            'branches',
            branches,
          );
        }
      } catch (_) {
        branches = await LocalDatabaseSyncService().getCachedCollection(
          'branches',
        );
      }
      final assigned = branches.where((doc) {
        final ids = doc['staffIds'] as List? ?? [];
        return doc['isVoided'] != true &&
            (ids.contains(uid) ||
                ids.contains(staff['staffId']) ||
                (staff['branchIds'] as List? ?? []).contains(
                  doc['_localDocId'],
                ));
      }).toList();
      String? branchId;
      if (assigned.length == 1)
        branchId = assigned.single['_localDocId']?.toString();
      if (assigned.length > 1 && context.mounted) {
        branchId = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => PopScope(
            canPop: false,
            child: SimpleDialog(
              title: const Text('Select your work branch'),
              children: assigned
                  .map(
                    (branch) => SimpleDialogOption(
                      onPressed: () =>
                          Navigator.pop(context, branch['_localDocId']),
                      child: Text('${branch['name']}'),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      }
      final ipFuture = (offline ? Future<String?>.value(null) : loginIp())
          .timeout(const Duration(seconds: 3), onTimeout: () => null)
          .catchError((_) => null);
      final ref = FirebaseFirestore.instance
          .collection('staff_login_sessions')
          .doc();
      final branch = assigned
          .where((doc) => doc['_localDocId'] == branchId)
          .firstOrNull;
      final record = <String, dynamic>{
        'userId': uid,
        'deviceId': deviceId,
        'staffId': staff['staffId'],
        'staffName': ['firstName', 'middleName', 'lastName']
            .map((key) => '${staff[key] ?? ''}'.trim())
            .where((part) => part.isNotEmpty)
            .join(' '),
        'photoUrl': staff['photoUrl'] ?? staff['profileImageUrl'],
        'branchId': branchId,
        'branchName': branch?['name'],
        'type': 'User',
        'loginAt': loginAt.toIso8601String(),
        'logoutAt': null,
        'ipType': kIsWeb ? 'Public IP' : 'Device network IP',
      };
      await prefs.setString(
        'staffSessionPending.${ref.id}',
        jsonEncode(record),
      );
      await prefs.setString('staffLoginSessionId', ref.id);
      unawaited(flush());
      unawaited(
        ipFuture
            .then((ip) async {
              if (ip != null)
                await ref.set({'ipAddress': ip}, SetOptions(merge: true));
            })
            .catchError((Object error) {
              debugPrint('Session IP: $error');
            }),
      );
    } catch (error) {
      debugPrint('Unable to record staff login: $error');
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Signed in, but the activity log could not be saved.',
            ),
          ),
        );
    }
  }

  static Future<void> close() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('staffLoginSessionId');
    if (id == null) return;
    final key = 'staffSessionPending.$id';
    final pending = prefs.getString(key);
    final record = pending == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(pending) as Map);
    record['logoutAt'] = DateTime.now().toIso8601String();
    await prefs.setString(key, jsonEncode(record));
    await prefs.remove('staffLoginSessionId');
    unawaited(flush());
  }

  // Keep failed/offline writes until a later successful login or logout.
  static Future<void> flush() {
    final next = _flushQueue.then((_) => _flushPending());
    _flushQueue = next.catchError((Object error) {
      debugPrint('Session sync deferred: $error');
    });
    return _flushQueue;
  }

  static Future<void> _flushPending() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith('staffSessionPending.'),
    )) {
      final encoded = prefs.getString(key)!;
      final record = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      for (final field in ['loginAt', 'logoutAt']) {
        if (record[field] != null)
          record[field] = Timestamp.fromDate(
            DateTime.parse(record[field] as String),
          );
      }
      try {
        await FirebaseFirestore.instance
            .collection('staff_login_sessions')
            .doc(key.substring('staffSessionPending.'.length))
            .set(record, SetOptions(merge: true))
            .timeout(const Duration(seconds: 3));
        if (prefs.getString(key) == encoded) await prefs.remove(key);
      } catch (error) {
        debugPrint('Session log awaiting sync: $error');
      }
    }
  }
}
