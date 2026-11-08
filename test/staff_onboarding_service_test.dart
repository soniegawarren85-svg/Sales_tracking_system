import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/staff_onboarding_service.dart';

void main() {
  late FakeFirebaseFirestore database;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = FakeFirebaseFirestore();
  });

  test(
    'tutorial is required only for accounts explicitly marked incomplete',
    () async {
      await database.collection('staff_requests').doc('new-staff').set({
        'role': 'staff',
        'onboardingCompleted': false,
      });
      await database.collection('staff_requests').doc('returning-staff').set({
        'role': 'staff',
        'onboardingCompleted': true,
      });
      await database.collection('staff_requests').doc('legacy-staff').set({
        'role': 'staff',
      });

      expect(
        await StaffOnboardingService.shouldShowTutorial(
          database: database,
          staffDocumentId: 'new-staff',
        ),
        isTrue,
      );
      expect(
        await StaffOnboardingService.shouldShowTutorial(
          database: database,
          staffDocumentId: 'returning-staff',
        ),
        isFalse,
      );
      expect(
        await StaffOnboardingService.shouldShowTutorial(
          database: database,
          staffDocumentId: 'legacy-staff',
        ),
        isFalse,
      );
      expect(
        (await database.collection('staff_requests').doc('legacy-staff').get())
            .data(),
        isNot(contains('onboardingCompleted')),
      );
    },
  );

  test('detects an accepted admin assigned to the staff branch', () async {
    await database.collection('staff_requests').doc('staff').set({
      'role': 'staff',
      'branchIds': ['dagupan'],
    });
    await database.collection('staff_requests').doc('matching-admin').set({
      'role': 'admin',
      'status': 'accepted',
      'branchIds': ['dagupan'],
    });
    await database.collection('staff_requests').doc('other-admin').set({
      'role': 'admin',
      'status': 'accepted',
      'branchIds': ['manila'],
    });

    expect(
      await StaffOnboardingService.hasAcceptedBranchAdmin(
        database: database,
        staffDocumentId: 'staff',
      ),
      isTrue,
    );

    await database.collection('staff_requests').doc('matching-admin').update({
      'status': 'pending',
    });
    expect(
      await StaffOnboardingService.hasAcceptedBranchAdmin(
        database: database,
        staffDocumentId: 'staff',
      ),
      isFalse,
    );
  });

  test('completion is saved to the matching staff document only', () async {
    await database.collection('staff_requests').doc('staff-one').set({
      'role': 'staff',
      'onboardingCompleted': false,
    });
    await database.collection('staff_requests').doc('staff-two').set({
      'role': 'staff',
      'onboardingCompleted': false,
    });

    await StaffOnboardingService.markCompleted(
      database: database,
      staffDocumentId: 'staff-one',
    );

    final completed =
        (await database.collection('staff_requests').doc('staff-one').get())
            .data()!;
    final untouched =
        (await database.collection('staff_requests').doc('staff-two').get())
            .data()!;
    expect(completed['onboardingCompleted'], isTrue);
    expect(completed['onboardingCompletedAt'], isA<Timestamp>());
    expect(untouched['onboardingCompleted'], isFalse);
    expect(
      await StaffOnboardingService.shouldShowTutorial(
        database: database,
        staffDocumentId: 'staff-one',
      ),
      isFalse,
    );
  });

  test('replaying leaves saved completion status unchanged', () async {
    await database.collection('staff_requests').doc('staff-one').set({
      'role': 'staff',
      'onboardingCompleted': true,
    });

    await StaffOnboardingService.completeTutorial(
      database: database,
      staffDocumentId: 'staff-one',
      isReplay: true,
    );

    expect(
      (await database.collection('staff_requests').doc('staff-one').get())
          .data(),
      {'role': 'staff', 'onboardingCompleted': true},
    );
  });

  test('completion rejects invalid document paths', () async {
    await expectLater(
      StaffOnboardingService.markCompleted(
        database: database,
        staffDocumentId: 'staff/one',
      ),
      throwsArgumentError,
    );
  });
}
