import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/widgets/activity_feed.dart';
import 'package:sales_tracking/widgets/transaction_settings_dialog.dart';

void main() {
  testWidgets('discount settings offer All branches first and apply globally', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('alpha').set({'name': 'Alpha'});
    await firestore.collection('branches').doc('beta').set({'name': 'Beta'});
    await firestore.doc('admin_settings/transactions').set({
      'branchSettings': {
        'alpha': {'discountsEnabled': true},
        'beta': {'discountsEnabled': false},
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionSettingsDialog(
            kind: 'discounts',
            firestore: firestore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('All branches'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('All branches').last).dy,
      lessThan(tester.getTopLeft(find.text('Alpha').last).dy),
    );
    await tester.tap(find.text('All branches').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    final settings = (await firestore.doc('admin_settings/transactions').get())
        .data()!;
    final branchSettings = settings['branchSettings'] as Map;
    expect((branchSettings['alpha'] as Map)['discountsEnabled'], isTrue);
    expect((branchSettings['beta'] as Map)['discountsEnabled'], isTrue);
  });

  testWidgets('payment settings offer an All branches selection', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('alpha').set({'name': 'Alpha'});
    await firestore.collection('branches').doc('beta').set({'name': 'Beta'});
    await firestore.doc('admin_settings/transactions').set({
      'branchSettings': {
        'alpha': {
          'payments': [
            {'id': 'cash', 'name': 'Cash'},
            {'id': 'gcash', 'name': 'GCash', 'qrUrl': 'alpha-qr'},
          ],
        },
        'beta': {
          'payments': [
            {'id': 'cash', 'name': 'Cash'},
            {'id': 'gcash', 'name': 'GCash', 'qrUrl': 'beta-qr'},
          ],
        },
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionSettingsDialog(
            kind: 'payments',
            firestore: firestore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('All branches'), findsNWidgets(2));
    await tester.tap(find.text('All branches').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Updated GCash');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final settings = (await firestore.doc('admin_settings/transactions').get())
        .data()!;
    final branches = settings['branchSettings'] as Map;
    for (final id in ['alpha', 'beta']) {
      final payments = (branches[id] as Map)['payments'] as List;
      final gcash = payments.whereType<Map>().firstWhere(
        (row) => row['id'] == 'gcash',
      );
      expect(gcash['name'], 'Updated GCash');
      expect(gcash['qrUrl'], id == 'alpha' ? 'alpha-qr' : 'beta-qr');
    }
    expect(find.text('All branches'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin tax configuration stays on the assigned branch', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('alpha').set({'name': 'Alpha'});
    await firestore.collection('branches').doc('beta').set({'name': 'Beta'});
    await firestore.doc('admin_settings/transactions').set({
      'branchSettings': {
        'alpha': {'taxEnabled': false, 'taxClassification': 'nonVat'},
        'beta': {'taxEnabled': false, 'taxClassification': 'nonVat'},
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionSettingsDialog(
            kind: 'tax',
            branchId: 'alpha',
            firestore: firestore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('All branches'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final settings = (await firestore.doc('admin_settings/transactions').get())
        .data()!;
    final branches = settings['branchSettings'] as Map;
    expect((branches['alpha'] as Map)['taxEnabled'], isTrue);
    expect((branches['beta'] as Map)['taxEnabled'], isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'admin discount settings stay on the assigned branch and log changes',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'lastRole': 'admin',
        'lastUserId': 'admin-doc',
      });
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('branches').doc('alpha').set({
        'name': 'Alpha',
      });
      await firestore.collection('branches').doc('beta').set({'name': 'Beta'});
      await firestore.collection('staff_requests').doc('admin-doc').set({
        'role': 'admin',
        'status': 'accepted',
        'adminId': 'ADM-002',
        'firstName': 'Branch',
        'lastName': 'Admin',
      });
      await firestore.doc('admin_settings/transactions').set({
        'branchSettings': {
          'alpha': {'discountsEnabled': true},
          'beta': {'discountsEnabled': true},
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionSettingsDialog(
              kind: 'discounts',
              branchId: 'alpha',
              firestore: firestore,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('All branches'), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      final settings =
          (await firestore.doc('admin_settings/transactions').get()).data()!;
      final branches = settings['branchSettings'] as Map;
      expect((branches['alpha'] as Map)['discountsEnabled'], isFalse);
      expect((branches['beta'] as Map)['discountsEnabled'], isTrue);
      final activity = (await firestore.collection('activity_logs').get()).docs;
      expect(activity, hasLength(1));
      expect(activity.single.data()['actorId'], 'admin-doc');
      expect(activity.single.data()['branchIds'], ['alpha']);
      expect(activity.single.data()['details']['fields'], ['discountsEnabled']);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActivityFeed(
              actorId: 'admin-doc',
              branchId: 'alpha',
              database: firestore,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('discount control updated successfully.'),
        findsWidgets,
      );
      expect(find.textContaining('Updated: discountsEnabled'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
