import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales_tracking/widgets/backup_restore_dialog.dart';

void main() {
  testWidgets('Admin sees only assigned-branch history and creator role', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lastRole': 'admin',
      'lastUserId': 'admin-doc',
    });
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('staff_requests').doc('admin-doc').set({
      'firstName': 'Branch',
      'lastName': 'Admin',
      'branchIds': ['branch-001'],
    });
    await firestore.collection('branches').doc('branch-001').set({
      'name': 'Lingayen',
    });
    await firestore.collection('backup_history').doc('history-id').set({
      'backupId': 'history-id',
      'backupCode': 'Bkp-0001',
      'backupName': 'Branch inventory snapshot',
      'status': 'successful',
      'backupVersion': 1,
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 8, 12)),
      'createdById': 'admin-doc',
      'createdByName': 'Branch Admin',
      'createdByRole': 'admin',
      'scopeType': 'branch',
      'scopeBranchIds': ['branch-001'],
      'fileSizeBytes': 2048,
      'fileAvailable': true,
      'storagePath': 'system_backups/history-id/Bkp-0001.stbackup',
    });
    await firestore.collection('backup_history').doc('global-backup').set({
      'backupId': 'global-backup',
      'backupCode': 'Bkp-0002',
      'backupName': 'Global system snapshot',
      'status': 'successful',
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 8, 13)),
      'createdById': 'super-admin-id',
      'createdByName': 'Warren Soniega',
      'createdByRole': 'super_admin',
      'scopeType': 'global',
      'fileSizeBytes': 2048,
      'storagePath': 'system_backups/global-backup/Bkp-0002.stbackup',
    });

    await tester.binding.setSurfaceSize(const Size(1100, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BackupRestoreDialog(firestore: firestore)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Back and Restore'), findsOneWidget);
    expect(find.text('Manual backups only.'), findsNothing);
    expect(find.textContaining('Manual exports exclude'), findsNothing);
    expect(
      find.widgetWithText(TextField, 'Search backup name, ID, or status'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.date_range), findsOneWidget);
    expect(find.text('Backup Name'), findsOneWidget);
    expect(find.text('Branch inventory snapshot'), findsOneWidget);
    expect(find.text('Bkp-0001'), findsOneWidget);
    expect(find.text('Branch Admin'), findsOneWidget);
    expect(find.text('Creator Role'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Bkp-0002'), findsNothing);
    expect(find.text('Warren Soniega'), findsNothing);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(null);
  });
}
