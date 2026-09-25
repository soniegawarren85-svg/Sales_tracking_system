import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_ip.dart';

class StaffLoginSession {
  static Future<void> start(
    BuildContext context,
    String uid,
    Map<String, dynamic> staff,
  ) async {
    final loginAt = DateTime.now();
    try {
      await flush();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('staffLoginSessionId');
      final query = FirebaseFirestore.instance.collection('branches');
      QuerySnapshot<Map<String, dynamic>> branches;
      try {
        branches = await query.get().timeout(const Duration(seconds: 5));
      } catch (_) {
        branches = await query.get(const GetOptions(source: Source.cache));
      }
      final assigned = branches.docs.where((doc) {
        final ids = doc.data()['staffIds'] as List? ?? [];
        return doc.data()['isVoided'] != true &&
            (ids.contains(uid) ||
                ids.contains(staff['staffId']) ||
                (staff['branchIds'] as List? ?? []).contains(doc.id));
      }).toList();
      String? branchId;
      if (assigned.length == 1) branchId = assigned.single.id;
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
                      onPressed: () => Navigator.pop(context, branch.id),
                      child: Text('${branch.data()['name']}'),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      }
      String? ip;
      try {
        ip = await loginIp().timeout(const Duration(seconds: 3));
      } catch (_) {}
      final ref = FirebaseFirestore.instance
          .collection('staff_login_sessions')
          .doc();
      final branch = assigned.where((doc) => doc.id == branchId).firstOrNull;
      final record = <String, dynamic>{
        'userId': uid,
        'staffId': staff['staffId'],
        'staffName': ['firstName', 'middleName', 'lastName']
            .map((key) => '${staff[key] ?? ''}'.trim())
            .where((part) => part.isNotEmpty)
            .join(' '),
        'photoUrl': staff['photoUrl'] ?? staff['profileImageUrl'],
        'branchId': branchId,
        'branchName': branch?.data()['name'],
        'type': 'User',
        'loginAt': loginAt.toIso8601String(),
        'logoutAt': null,
        'ipAddress': ip,
        'ipType': kIsWeb ? 'Public IP' : 'Device network IP',
      };
      await prefs.setString(
        'staffSessionPending.${ref.id}',
        jsonEncode(record),
      );
      await prefs.setString('staffLoginSessionId', ref.id);
      await flush();
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
    await flush();
  }

  // Keep failed/offline writes until a later successful login or logout.
  static Future<void> flush() async {
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
