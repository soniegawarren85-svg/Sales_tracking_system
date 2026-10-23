import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/login_validation.dart';
import 'package:sales_tracking/services/session_actor.dart';
import 'package:sales_tracking/services/super_admin.dart';
import 'package:sales_tracking/Super_admin_pages/super_admin_identity.dart';
import 'package:sales_tracking/Super_admin_pages/SettingsPage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'super admin credentials accept ID casing but require exact password',
    () {
      expect(loginInputError('spr-001', 'Super@123'), isNull);
      expect(SuperAdmin.matchesLogin('spr-001', 'Super@123'), isTrue);
      expect(SuperAdmin.matchesLogin('Spr-001', 'super@123'), isFalse);
      expect(SuperAdmin.matchesLogin('spr-002', 'Super@123'), isFalse);
    },
  );

  test('super admin can change and verify its local login password', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(
      await SuperAdmin.verifyPassword('Super@123', preferences: prefs),
      isTrue,
    );
    expect(
      await SuperAdmin.verifyPassword('wrong', preferences: prefs),
      isFalse,
    );

    await SuperAdmin.updatePassword('NewSuper@456', preferences: prefs);

    expect(
      await SuperAdmin.verifyPassword('NewSuper@456', preferences: prefs),
      isTrue,
    );
    expect(
      await SuperAdmin.verifyPassword('Super@123', preferences: prefs),
      isFalse,
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'lastStaffDocId': 'previous-staff',
      'lastStaffPublicId': 'STF-001',
    });
    await SuperAdmin.startSession(await SharedPreferences.getInstance());
  });

  test('session restores admin identity without creating a profile', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(SuperAdmin.isSession(prefs), isTrue);
    expect(prefs.getString('lastRole'), 'super_admin');
    expect(prefs.getString('superAdminId'), 'Spr-001');
    expect(prefs.getString('adminId'), isNull);
    expect(prefs.getString('lastStaffDocId'), isNull);
    expect(prefs.getString('lastStaffPublicId'), isNull);
    final db = FakeFirebaseFirestore();
    final actor = await resolveSessionActor(db, admin: true);
    expect(actor.id, 'Spr-001');
    expect(actor.publicId, 'Spr-001');
    expect(actor.name, 'Super admin');
    expect((await db.collection('staff_requests').get()).docs, isEmpty);
    await expectLater(resolveSessionActor(db, admin: false), throwsStateError);
    await prefs.remove('lastUserId');
    expect(SuperAdmin.isSession(prefs), isFalse);
  });

  testWidgets('greeting does not load a profile or show an avatar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuperAdminIdentity(
            greeting: true,
            firestore: FakeFirebaseFirestore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome super admin'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);
  });

  test(
    'previous super-admin session migrates without converting normal admins',
    () async {
      SharedPreferences.setMockInitialValues({
        'lastRole': 'admin',
        'lastUserId': 'super-admin',
        'adminId': 'Spr-001',
      });
      final prefs = await SharedPreferences.getInstance();
      await SuperAdmin.migrateLegacySession(prefs);
      expect(SuperAdmin.isSession(prefs), isTrue);
      expect(prefs.getString('adminId'), isNull);
      await prefs.setString('lastRole', 'admin');
      await prefs.setString('lastUserId', 'emergency-admin');
      await prefs.setString('adminId', 'ADM-0001');
      await SuperAdmin.migrateLegacySession(prefs);
      expect(SuperAdmin.isSession(prefs), isFalse);
      expect(prefs.getString('lastRole'), 'admin');
      expect(prefs.getString('adminId'), 'ADM-0001');
    },
  );

  test('super-admin pages are independent of the ordinary admin page tree', () {
    final pages = Directory(
      'lib/Super_admin_pages',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.dart'));
    expect(pages.length, greaterThan(6));
    for (final page in pages) {
      expect(
        page.readAsStringSync(),
        isNot(contains('Admin_pages/')),
        reason: page.path,
      );
    }
    final login = File('lib/Login/Login/Login.dart').readAsStringSync();
    final loginStart = login.indexOf('if (SuperAdmin.matchesId(username))');
    final loginEnd = login.indexOf('accountDocs =', loginStart);
    expect(
      login.substring(loginStart, loginEnd),
      contains('const SuperAdminDashboard()'),
    );
    expect(
      login.substring(loginStart, loginEnd),
      isNot(contains('const AdminDashboard()')),
    );
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains(
        'if (SuperAdmin.isSession(prefs)) return const SuperAdminDashboard();',
      ),
    );
  });

  testWidgets('settings show fixed identity and allow profile editing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SuperAdminSettingsPage(firestore: FakeFirebaseFirestore()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Super admin'), findsWidgets);
    expect(find.text('Spr-001'), findsOneWidget);
    expect(find.text('Account information'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Discount Control'), findsOneWidget);
  });

  testWidgets('change password sheet accepts a fair password', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SuperAdminSettingsPage(firestore: FakeFirebaseFirestore()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change Password'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    for (final entry in [(0, 'Super@123'), (1, 'Abcdefgh'), (2, 'Abcdefgh')]) {
      tester.widget<TextFormField>(fields.at(entry.$1)).controller!.text =
          entry.$2;
    }
    await tester.pump();
    expect(find.text('Fair password'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save Password'),
    );
    expect(saveButton.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
