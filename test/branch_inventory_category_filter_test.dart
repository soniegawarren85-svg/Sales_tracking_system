import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/admin_catalog.dart';
import 'package:sales_tracking/services/branch_status.dart';
import 'package:sales_tracking/services/branch_lifecycle.dart';
import 'package:sales_tracking/services/login_validation.dart';

void main() {
  test('branch list filters distinguish active from performance-visible', () {
    expect(isActiveBranch({'name': 'Open branch'}), isTrue);
    expect(isActiveBranch({'isVoided': true}), isFalse);
    expect(isActiveBranch({'isDeactivated': true}), isFalse);
    expect(isVisibleInBranchPerformance({'status': 'deactivated'}), isTrue);
    expect(isVisibleInBranchPerformance({'isVoided': true}), isFalse);
  });

  test('voiding a branch unassigns its staff profiles', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('branches').doc('lingayen').set({
      'name': 'Lingayen',
      'staffIds': ['staff-a', 'staff-b'],
      'staffNames': ['Staff A', 'Staff B'],
    });
    await firestore.collection('staff_requests').doc('staff-a').set({
      'branchIds': ['lingayen', 'rosales'],
    });
    await firestore.collection('staff_requests').doc('staff-b').set({
      'branchIds': ['lingayen'],
    });

    await voidBranchAndUnassignStaff(firestore, 'lingayen');

    final branch =
        (await firestore.collection('branches').doc('lingayen').get()).data()!;
    expect(branch['isVoided'], isTrue);
    expect(branch['staffIds'], isEmpty);
    expect(branch['staffNames'], isEmpty);
    expect(
      (await firestore.collection('staff_requests').doc('staff-a').get())
          .data()!['branchIds'],
      isEmpty,
    );
    expect(
      (await firestore.collection('staff_requests').doc('staff-a').get())
          .data()!['requiresBranchAssignment'],
      isTrue,
    );
    expect(
      (await firestore.collection('staff_requests').doc('staff-b').get())
          .data()!['branchIds'],
      isEmpty,
    );
    expect(
      loginAccountStatusError(
        (await firestore.collection('staff_requests').doc('staff-b').get())
            .data()!,
      ),
      contains('no assigned branch'),
    );
  });

  testWidgets(
    'branch category selector shows allocated categories and filters the table',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final firestore = FakeFirebaseFirestore();
      await firestore.collection('branches').doc('dagupan').set({
        'name': 'SM Dagupan',
      });
      await firestore.collection('branches').doc('lingayen').set({
        'name': 'Lingayen',
      });
      await firestore.collection('branches').doc('lingayen').set({
        'name': 'Lingayen',
        'deactivatedAt': 'legacy timestamp',
      });
      await firestore.collection('branches').doc('rosales').set({
        'name': 'SM Rosales',
        'isDeactivated': true,
        'status': 'deactivated',
      });
      await firestore.collection('branches').doc('urdaneta').set({
        'name': 'SM Urdaneta',
        'isVoided': true,
      });
      await firestore.collection('branches').doc('inactive').set({
        'name': 'Inactive branch',
        'isVoided': true,
      });
      await firestore.collection('sales_inventory').doc('cookies').set({
        'name': 'Cookies',
        'items': [
          {'id': 'cookie-1', 'name': 'Cookie A', 'stock': 3},
        ],
      });
      await firestore.collection('sales_inventory').doc('chocolate').set({
        'name': 'Chocolate Bar',
        'items': [
          {'id': 'chocolate-1', 'name': 'Chocolate A', 'stock': 4},
        ],
      });
      await firestore.collection('sales_inventory').doc('cakes').set({
        'name': 'Cakes',
        'items': [
          {'id': 'cake-1', 'name': 'Cake A', 'stock': 5},
        ],
      });
      await firestore
          .collection('staff_inventory')
          .doc('cookies-allocation')
          .set({
            'staffId': 'dagupan',
            'sourceInventoryId': 'cookies',
            'name': 'Cookies',
            'items': [
              {'id': 'cookie-1', 'name': 'Cookie A', 'stock': 3},
            ],
          });
      await firestore
          .collection('staff_inventory')
          .doc('chocolate-allocation')
          .set({
            'staffId': 'dagupan',
            'sourceInventoryId': 'chocolate',
            'name': 'Chocolate Bar',
            'items': [
              {'id': 'chocolate-1', 'name': 'Chocolate A', 'stock': 4},
            ],
          });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminCatalog(
              firestore: firestore,
              type: 'Categories',
              allowBranchEdits: false,
              showBranchActions: true,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Inactive branch'), findsNothing);
      expect(find.text('Lingayen'), findsOneWidget);
      expect(find.text('SM Rosales'), findsOneWidget);
      expect(find.text('SM Urdaneta'), findsNothing);
      await tester.tap(find.text('SM Dagupan').last);
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Cookies'), findsOneWidget);
      expect(find.text('Chocolate Bar'), findsOneWidget);
      expect(find.text('Cakes'), findsNothing);
      expect(find.text('Cookie A'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SM Dagupan').last);
      await tester.pumpAndSettle();
      expect(find.text('Cookies'), findsOneWidget);
      expect(find.text('Cookie A'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lingayen').last);
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Cookie A'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SM Dagupan').last);
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Cookies'), findsOneWidget);
      expect(find.text('Cookie A'), findsOneWidget);

      await tester.tap(find.text('Chocolate Bar'));
      await tester.pumpAndSettle();
      expect(find.text('Chocolate A'), findsOneWidget);
      expect(find.text('Cookie A'), findsNothing);
      expect(find.byTooltip('Edit branch inventory'), findsNothing);
      expect(find.text('Actions'), findsOneWidget);
      expect(find.byTooltip('View history'), findsOneWidget);
      expect(find.byTooltip('Void allocation'), findsWidgets);

      await tester.ensureVisible(find.byTooltip('Void allocation').first);
      await tester.tap(find.byTooltip('Void allocation').first);
      await tester.pumpAndSettle();
      expect(find.text('Not sold out yet'), findsOneWidget);
      expect(
        (await firestore
                .collection('staff_inventory')
                .doc('chocolate-allocation')
                .get())
            .data()!['isDeleted'],
        isNot(true),
      );
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      await firestore
          .collection('staff_inventory')
          .doc('chocolate-allocation')
          .update({
            'items': [
              {'id': 'chocolate-1', 'name': 'Chocolate A', 'stock': 0},
            ],
          });
      await firestore.collection('sales_inventory').doc('chocolate').update({
        'items': [
          {'id': 'chocolate-1', 'name': 'Chocolate A', 'stock': 0},
        ],
      });
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.ensureVisible(find.byTooltip('Void allocation').first);
      await tester.tap(find.byTooltip('Void allocation').first);
      await tester.pumpAndSettle();
      expect(find.text('Void allocation?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Void'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final voidedAllocation =
          (await firestore
                  .collection('staff_inventory')
                  .doc('chocolate-allocation')
                  .get())
              .data()!;
      expect(voidedAllocation['items'], isEmpty);
      expect(voidedAllocation['isDeleted'], isTrue);
      expect(voidedAllocation['removedItems'], hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
