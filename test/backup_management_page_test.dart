import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales_tracking/widgets/backup_restore_dialog.dart';

void main() {
  testWidgets('manual backup creates a real history record on Spark UI', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lastRole': 'admin',
      'lastUserId': 'admin-doc',
    });
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('staff_requests').doc('admin-doc').set({
      'firstName': 'Branch',
      'passwordCredential': {'hash': 'never-export'},
    });

    await tester.binding.setSurfaceSize(const Size(1100, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BackupRestoreDialog(firestore: firestore)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backup Management'), findsOneWidget);
    expect(find.text('Automatic backup'), findsOneWidget);
    expect(find.text('No backup attempts yet'), findsOneWidget);
    expect(find.text('Upload & Restore'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );

    await tester.ensureVisible(find.text('Create backup'));
    await tester.tap(find.text('Create backup'));
    await tester.pumpAndSettle();

    final history = await firestore.collection('backup_history').get();
    expect(history.docs, hasLength(1));
    expect(history.docs.single.data()['status'], 'successful');
    expect(history.docs.single.data()['createdById'], 'admin-doc');
    expect(history.docs.single.data()['storageLocation'], 'session_memory');
    expect(
      find.text(
        'Backup file created. Download it to save a copy on this device.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(null);
  });
}
