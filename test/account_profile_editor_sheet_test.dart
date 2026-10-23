import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/account_profile_editor_sheet.dart';

void main() {
  testWidgets('email edits reveal current password and save profile values', (
    tester,
  ) async {
    AccountProfileValues? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountProfileEditorSheet(
            profile: const {
              'firstName': 'Angel',
              'middleName': '',
              'lastName': 'Bites',
              'email': 'old@gmail.com',
              'age': '25',
              'address': 'Manila',
            },
            readOnly: false,
            onSave: (values) async {
              saved = values;
              return 'Saved.';
            },
          ),
        ),
      ),
    );

    expect(find.text('Current Password'), findsNothing);
    await tester.enterText(find.byType(TextFormField).at(3), 'new@gmail.com');
    await tester.pumpAndSettle();
    expect(find.text('Current Password'), findsOneWidget);

    tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('profile-current-password')),
            )
            .controller!
            .text =
        'Current@123';
    await tester.pump();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter your current password to change Gmail.'),
      findsNothing,
    );
    expect(saved, isNotNull);
    expect(saved!.firstName, 'Angel');
    expect(saved!.email, 'new@gmail.com');
    expect(saved!.currentPassword, 'Current@123');
    expect(saved!.emailChanged, isTrue);
    expect(find.text('Saved.'), findsNothing);
  });

  testWidgets('pending verification is visibly marked in the profile sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountProfileEditorSheet(
            profile: const {
              'firstName': 'Angel',
              'lastName': 'Bites',
              'email': 'old@gmail.com',
              'pendingAuthEmail': 'new@gmail.com',
              'age': '25',
              'address': 'Manila',
            },
            readOnly: false,
            onSave: (_) async => 'Unused.',
          ),
        ),
      ),
    );
    await tester.ensureVisible(
      find.textContaining('Gmail verification pending'),
    );
    expect(find.textContaining('new@gmail.com'), findsWidgets);
    expect(find.text('Check / resend'), findsOneWidget);
    await tester.tap(find.text('Check / resend'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('profile-current-password')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
