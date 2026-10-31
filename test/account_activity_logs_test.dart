import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales_tracking/services/account_login_session.dart';
import 'package:sales_tracking/widgets/account_activity_logs_dialog.dart';
import 'package:sales_tracking/widgets/login_session_alert_watcher.dart';

void main() {
  test(
    'Admin sign-in and sign-out create activity and session records',
    () async {
      SharedPreferences.setMockInitialValues({
        'lastRole': 'admin',
        'lastUserId': 'admin-doc',
      });
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('staff_requests').doc('admin-doc').set({
        'role': 'admin',
        'status': 'accepted',
        'adminId': 'ADM-001',
        'firstName': 'Branch',
        'lastName': 'Admin',
      });

      await AccountLoginSession.start(
        userId: 'admin-doc',
        actorId: 'admin-doc',
        publicId: 'ADM-001',
        name: 'Branch Admin',
        role: 'admin',
        database: firestore,
      );
      final sessions = await firestore
          .collection('staff_login_sessions')
          .where('userId', isEqualTo: 'admin-doc')
          .get();
      expect(sessions.docs, hasLength(1));
      expect(sessions.docs.single.data()['role'], 'admin');

      await AccountLoginSession.close(database: firestore);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          'accountLoginSessionId',
        ),
        isFalse,
      );
      final closedSession = await sessions.docs.single.reference.get();
      expect(closedSession.data()?['logoutAt'], isNotNull);
      final logs = await firestore
          .collection('activity_logs')
          .where('actorId', isEqualTo: 'admin-doc')
          .get();
      expect(
        logs.docs.map((doc) => doc.data()['action']),
        containsAll(['account_login', 'account_logout']),
      );
    },
  );

  testWidgets('activity log dialog renders the actor activity table', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('activity_logs').doc('change').set({
      'actorId': 'admin-doc',
      'actorRole': 'admin',
      'action': 'settings_updated',
      'description': 'Updated tax settings',
      'branchIds': ['alpha'],
      'createdAt': DateTime(2026, 10, 24, 10),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountActivityLogsDialog(
            actorId: 'admin-doc',
            firestore: firestore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Activity Logs'), findsOneWidget);
    expect(find.text('Date & Time'), findsOneWidget);
    expect(find.text('Settings updated'), findsOneWidget);
    expect(find.text('Updated tax settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin is alerted when another active login is recorded', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lastRole': 'admin',
      'lastUserId': 'admin-doc',
      'accountLoginSessionId': 'own-session',
    });
    final firestore = FakeFirebaseFirestore();
    final now = DateTime.now();
    await firestore.collection('staff_login_sessions').doc('own-session').set({
      'userId': 'admin-doc',
      'actorId': 'admin-doc',
      'loginAt': now.subtract(const Duration(minutes: 10)),
      'logoutAt': null,
    });
    await firestore.collection('staff_login_sessions').doc('other-session').set(
      {
        'userId': 'admin-doc',
        'actorId': 'admin-doc',
        'loginAt': now,
        'logoutAt': null,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LoginSessionAlertWatcher(firestore: firestore)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Another device has signed in to your account. Check your activity logs if this was not you.',
      ),
      findsOneWidget,
    );
    expect(find.text('View logs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
