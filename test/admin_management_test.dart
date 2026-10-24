import 'package:sales_tracking/services/report_cash_allocations.dart';
import 'package:sales_tracking/widgets/staff_deactivation_dialog.dart';
import 'package:sales_tracking/services/transaction_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sales_tracking/widgets/transaction_settings_dialog.dart';
import 'package:sales_tracking/services/database_backup.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/widgets/daily_sales_report.dart';

void main() {
  test('Daily cash correction replaces opening without double counting', () {
    final amounts = reportCashByOwner(
      [
        {
          'branchId': 'b',
          'type': 'set_daily_cash_drawer',
          'amount': 1200,
          'createdAt': DateTime(2026, 9, 27, 8),
        },
        {
          'branchId': 'b',
          'type': 'set_daily_cash_drawer',
          'amount': 1500,
          'createdAt': DateTime(2026, 9, 27, 9),
        },
        {
          'branchId': 'b',
          'type': 'allocation',
          'amount': 200,
          'createdAt': DateTime(2026, 9, 27, 10),
        },
      ],
      DateTime(2026, 9, 27),
      DateTime(2026, 9, 28),
    );
    expect(amounts['b'], 1700);
  });
  test('Cashier follows updated discount name/rate, off switch and void', () {
    final settings = <String, dynamic>{
      'discounts': [
        {'id': 'senior', 'name': 'Member', 'percent': 15},
      ],
    };
    expect(discountFraction(settings, 'senior'), .15);
    expect(selectedDiscount(settings, 'senior')['name'], 'Member');
    expect(
      discountFraction({...settings, 'discountsEnabled': false}, 'senior'),
      0,
    );
    expect(
      discountFraction({...settings, 'allowDiscounts': false}, 'senior'),
      0,
    );
    (settings['discounts'] as List).first['isVoided'] = true;
    expect(discountFraction(settings, 'senior'), 0);
  });
  testWidgets('Deactivation requires reason and explicit confirmation', (
    tester,
  ) async {
    String? reason;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () async {
                reason = await showDialog<String>(
                  context: context,
                  builder: (_) => const StaffDeactivationDialog(name: 'Ana'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Deactivate'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'No longer assigned');
    await tester.pump();
    expect(reason, isNull);
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    expect(reason, 'No longer assigned');
  });
  test(
    'Backup export includes records, nested messages and manifest counts',
    () async {
      final source = FakeFirebaseFirestore();
      await source.doc('allocation_checklist/pending').set({
        'status': 'pending',
        'quantity': 3,
      });
      await source.doc('staff_requests/admin').set({
        'firstName': 'Test',
        'createdAt': Timestamp.fromDate(DateTime(2026)),
        'passwordCredential': {'hash': 'do-not-export'},
        'api_key': 'do-not-export',
      });
      await source.doc('password_reset_otps/one-time-code').set({
        'otp': 'do-not-export',
      });
      await source.doc('messages/thread/items/message').set({'text': 'Hello'});
      await source.doc('messages/thread').set({'name': 'Branch'});
      final bytes = await DatabaseBackup.export(firestore: source);
      final records = DatabaseBackup.validate(bytes);
      expect(records['allocation_checklist/pending']!['quantity'], 3);
      expect(records['messages/thread/items/message']!['text'], 'Hello');
      expect(
        records['staff_requests/admin']!.containsKey('passwordCredential'),
        isFalse,
      );
      expect(records['staff_requests/admin']!.containsKey('api_key'), isFalse);
      expect(records.containsKey('password_reset_otps/one-time-code'), isFalse);
      expect(records['staff_requests/admin']!['createdAt'], isA<Timestamp>());
      final manifest = DatabaseBackup.inspect(bytes);
      expect(manifest.documentCount, 4);
      expect(manifest.collectionCounts['messages'], 2);
      expect(manifest.collectionCounts['password_reset_otps'], isNull);
    },
  );
  testWidgets('Discount edit, confirmation, void and restore persist', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('branches').doc('branch-dagupan').set({
      'name': 'Dagupan',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionSettingsDialog(kind: 'discounts', firestore: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Member');
    await tester.enterText(find.byType(TextField).last, '15');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('15.0%'), findsOneWidget);
    await tester.tap(find.byTooltip('Void').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Member'), findsOneWidget);
    await tester.tap(find.byTooltip('Void').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Member'), findsNothing);
    await tester.tap(find.byTooltip('Voided records'));
    await tester.pumpAndSettle();
    expect(find.text('Member'), findsOneWidget);
    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    final saved = (await db.doc('admin_settings/transactions').get()).data()!;
    final branchSettings =
        (saved['branchSettings'] as Map)['branch-dagupan'] as Map;
    expect(
      ((branchSettings['discounts'] as List).first as Map)['isVoided'],
      false,
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(
      find.text('Turn off all discounts in the Dagupan staff cashier?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(
      (((await db.doc('admin_settings/transactions').get())
                  .data()!['branchSettings']
              as Map)['branch-dagupan']
          as Map)['discountsEnabled'],
      false,
    );
  });
  testWidgets('Payment defaults contain locked Cash and GCash only', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('branches').doc('branch-dagupan').set({
      'name': 'Dagupan',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionSettingsDialog(kind: 'payments', firestore: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('GCash'), findsOneWidget);
    expect(find.text('Maya'), findsNothing);
    expect(find.byTooltip('Edit'), findsOneWidget);
  });
  testWidgets('All branches permission changes apply to every branch', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('branches').doc('branch-dagupan').set({
      'name': 'Dagupan',
    });
    await db.collection('branches').doc('branch-lingayen').set({
      'name': 'Lingayen',
    });
    await db.doc('admin_settings/transactions').set({
      'branchSettings': {
        'branch-dagupan': {'allowRefunds': false},
        'branch-lingayen': {'allowRefunds': true},
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionSettingsDialog(kind: 'permissions', firestore: db),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All branches').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Process refunds'));
    await tester.pumpAndSettle();

    final saved = (await db.doc('admin_settings/transactions').get()).data()!;
    final branchSettings = saved['branchSettings'] as Map;
    expect((branchSettings['branch-dagupan'] as Map)['allowRefunds'], isTrue);
    expect((branchSettings['branch-lingayen'] as Map)['allowRefunds'], isTrue);
  });
  testWidgets('A branch refund setting does not change other branches', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('branches').doc('branch-dagupan').set({
      'name': 'Dagupan',
    });
    await db.collection('branches').doc('branch-lingayen').set({
      'name': 'Lingayen',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionSettingsDialog(kind: 'permissions', firestore: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Process refunds'));
    await tester.pumpAndSettle();

    final saved = (await db.doc('admin_settings/transactions').get()).data()!;
    final branchSettings = saved['branchSettings'] as Map;
    expect((branchSettings['branch-dagupan'] as Map)['allowRefunds'], isFalse);
    expect(branchSettings.containsKey('branch-lingayen'), isFalse);
  });
  testWidgets(
    'Tax settings can be configured per branch and for all branches',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('branches').doc('branch-dagupan').set({
        'name': 'Dagupan',
      });
      await db.collection('branches').doc('branch-lingayen').set({
        'name': 'Lingayen',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionSettingsDialog(kind: 'tax', firestore: db),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final nonVatRadio = tester.widget<RadioListTile<String>>(
        find.widgetWithText(RadioListTile<String>, 'Non-VAT registered'),
      );
      expect(nonVatRadio.onChanged, isNull);
      final vatRadio = tester.widget<RadioListTile<String>>(
        find.widgetWithText(RadioListTile<String>, 'VAT registered (12%)'),
      );
      expect(vatRadio.onChanged, isNull);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioListTile<String>>(
              find.widgetWithText(
                RadioListTile<String>,
                'VAT registered (12%)',
              ),
            )
            .onChanged,
        isNotNull,
      );
      await tester.tap(find.text('VAT registered (12%)'));
      await tester.pumpAndSettle();
      var saved = (await db.doc('admin_settings/transactions').get()).data()!;
      var branchSettings = saved['branchSettings'] as Map;
      expect((branchSettings['branch-dagupan'] as Map)['taxEnabled'], isTrue);
      expect(
        (branchSettings['branch-dagupan'] as Map)['taxClassification'],
        'vat',
      );
      expect(branchSettings.containsKey('branch-lingayen'), isFalse);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All branches').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Enable tax'));
      await tester.pumpAndSettle();
      saved = (await db.doc('admin_settings/transactions').get()).data()!;
      branchSettings = saved['branchSettings'] as Map;
      expect((branchSettings['branch-dagupan'] as Map)['taxEnabled'], isTrue);
      expect((branchSettings['branch-lingayen'] as Map)['taxEnabled'], isTrue);
    },
  );
  testWidgets(
    'Reports show financial metrics and open current allocations on demand',
    (tester) async {
      tester.view.resetPhysicalSize();
      final now = Timestamp.now();
      final data = BranchReportData({
        'branches': [
          {'_id': 'b', 'name': 'Dagupan'},
        ],
        'completed_sales': [
          {
            'branchId': 'b',
            'timestamp': now,
            'total': 200,
            'tax': 21,
            'items': [
              {
                'name': 'Cookie',
                'variant': 'Red',
                'itemId': 'v',
                'sourceInventoryId': 'c',
                'price': 100,
                'quantity': 2,
              },
            ],
          },
        ],
        'sales_inventory': [
          {
            '_id': 'c',
            'name': 'Cookies',
            'items': [
              {
                'id': 'v',
                'publicId': 'CO-001',
                'name': 'Red',
                'price': 100,
                'costPrice': 50,
              },
            ],
          },
        ],
        'staff_inventory': [
          {
            '_id': 'a',
            'staffId': 'b',
            'sourceInventoryId': 'c',
            'assignedAt': now,
            'items': [
              {
                'id': 'v',
                'name': 'Red',
                'stock': 8,
                'assignedStartingStock': 10,
              },
            ],
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(home: DailySalesReport(data: Stream.value(data))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total sold items'), findsOneWidget);
      expect(find.text('Total transactions'), findsOneWidget);
      expect(find.text('Items allocated'), findsOneWidget);
      expect(find.text('Total VAT'), findsOneWidget);
      expect(find.text('₱21.00'), findsOneWidget);
      expect(find.text('Total net profit'), findsOneWidget);
      expect(find.text('₱79.00'), findsOneWidget);
      expect(find.text('Total net sales'), findsOneWidget);
      expect(find.text('₱179.00'), findsOneWidget);
      expect(find.text('Remaining'), findsNothing);
      await tester.tap(find.text('View allocated'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Remaining'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('CO-001'), findsOneWidget);
      expect(find.text('Dagupan'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
