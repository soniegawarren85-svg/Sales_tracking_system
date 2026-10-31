import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/widgets/activity_feed.dart';
import 'package:sales_tracking/widgets/transaction_settings_dialog.dart';

void main() {
  testWidgets('permissions omit inventory edit and voided branches', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('alpha').set({'name': 'Alpha'});
    await firestore.collection('branches').doc('voided').set({
      'name': 'SM Urdaneta',
      'isVoided': true,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionSettingsDialog(
            kind: 'permissions',
            separateRoles: true,
            firestore: firestore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('SM Urdaneta'), findsNothing);
    await tester.tap(find.text('Alpha').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin permissions'));
    await tester.pumpAndSettle();
    expect(find.text('Edit inventory'), findsNothing);
    expect(find.text('Staff permissions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('branch settings include every non-voided Branch Sales location', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    for (final entry in [
      ('dagupan', 'SM Dagupan'),
      ('urdaneta', 'SM Urdaneta'),
      ('lingayen', 'Lingayen'),
    ]) {
      await firestore.collection('branches').doc(entry.$1).set({
        'name': entry.$2,
      });
    }
    await firestore.collection('branches').doc('voided').set({
      'name': 'Voided branch',
      'isVoided': true,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionSettingsDialog(
            kind: 'tax',
            firestore: firestore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('SM Dagupan'), findsOneWidget);
    expect(find.text('SM Urdaneta'), findsOneWidget);
    expect(find.text('Lingayen'), findsOneWidget);
    expect(find.text('Voided branch'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discount control omits insignificant decimal zeros', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('alpha').set({'name': 'Alpha'});
    await firestore.doc('admin_settings/transactions').set({
      'branchSettings': {
        'alpha': {
          'discounts': [
            {'id': 'senior', 'name': 'Senior', 'percent': 10.0},
            {'id': 'pwd', 'name': 'PWD', 'percent': 10.5},
          ],
        },
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

    expect(find.text('10%'), findsOneWidget);
    expect(find.text('10.5%'), findsOneWidget);
    expect(find.text('10.0%'), findsNothing);
  });

  testWidgets('new branch starts with discounts disabled and no records', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('new-branch').set({
      'name': 'New Branch',
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
    await tester.tap(find.text('New Branch').last);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('Senior'), findsNothing);
    expect(find.text('PWD'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('VAT configuration saves an optional branch BIR TIN', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('alpha').set({'name': 'Alpha'});
    await firestore.doc('admin_settings/transactions').set({
      'branchSettings': {
        'alpha': {'taxEnabled': true, 'taxClassification': 'vat'},
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

    expect(find.text('BIR TIN (optional)'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '123-456-789-000');
    await tester.tap(find.byTooltip('Save TIN'));
    await tester.pumpAndSettle();

    final settings = (await firestore.doc('admin_settings/transactions').get())
        .data()!;
    expect(
      ((settings['branchSettings'] as Map)['alpha'] as Map)['taxTin'],
      '123-456-789-000',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('All branches VAT configuration applies one optional BIR TIN', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('alpha').set({'name': 'Alpha'});
    await firestore.collection('branches').doc('beta').set({'name': 'Beta'});
    await firestore.doc('admin_settings/transactions').set({
      'branchSettings': {
        'alpha': {
          'taxEnabled': true,
          'taxClassification': 'vat',
          'taxTin': '111-111-111-000',
        },
        'beta': {
          'taxEnabled': true,
          'taxClassification': 'vat',
          'taxTin': '222-222-222-000',
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionSettingsDialog(kind: 'tax', firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All branches'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '123-456-789-000');
    await tester.tap(find.byTooltip('Save TIN'));
    await tester.pumpAndSettle();

    final branchSettings =
        (await firestore.doc('admin_settings/transactions').get())
                .data()!['branchSettings']
            as Map;
    for (final branchId in ['alpha', 'beta']) {
      expect((branchSettings[branchId] as Map)['taxTin'], '123-456-789-000');
    }
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
      expect(
        find.textContaining('Updated fields: Discounts Enabled'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
