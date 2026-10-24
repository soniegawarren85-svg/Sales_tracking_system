import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/Login/Login/forgot_password.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/password_reset_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'screen expires after ten minutes without forgetting the resend deadline',
    () async {
      SharedPreferences.setMockInitialValues({});
      final sentAt = DateTime.utc(2026, 10, 23, 10);
      final session = PasswordResetSession(
        email: 'staff@example.com',
        resendAvailableAt: sentAt.add(passwordResetWindow),
      );
      await session.persist();
      expect(
        session.shouldResumeAt(sentAt.add(const Duration(minutes: 9))),
        isTrue,
      );
      expect(
        session.shouldResumeAt(sentAt.add(const Duration(minutes: 10))),
        isFalse,
      );
      expect(
        (await PasswordResetSession.restore())
            ?.resendAvailableAt
            .millisecondsSinceEpoch,
        sentAt.add(const Duration(minutes: 3)).millisecondsSinceEpoch,
      );
    },
  );

  test('only the matching reset request can show completion', () async {
    SharedPreferences.setMockInitialValues({});
    await PasswordResetSession(
      email: 'staff@example.com',
      resendAvailableAt: DateTime.now(),
      requestId: 'current-request',
    ).persist();
    expect(await PasswordResetSession.markCompleted('older-request'), isFalse);
    expect((await PasswordResetSession.restore())?.completed, isFalse);
    expect(await PasswordResetSession.markCompleted('current-request'), isTrue);
    expect((await PasswordResetSession.restore())?.completed, isTrue);
  });

  testWidgets(
    'old request opens email entry and same email resumes without a new timer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final deadline = DateTime.now().subtract(const Duration(minutes: 12));
      await PasswordResetSession(
        email: 'staff@example.com',
        resendAvailableAt: deadline,
      ).persist();
      await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Forgot password?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'staff@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('You can resend now'), findsOneWidget);
      expect(find.text('Return to Login'), findsNothing);
      expect(
        (await PasswordResetSession.restore())
            ?.resendAvailableAt
            .millisecondsSinceEpoch,
        deadline.millisecondsSinceEpoch,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('confirmed completion shows the check mark and login button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await PasswordResetSession(
      email: 'staff@example.com',
      resendAvailableAt: DateTime.now(),
      completed: true,
    ).persist();
    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Password changed!'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('Return to Login'), findsOneWidget);
    expect(find.text('Resend Email'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'reset session keeps the email and resend cooldown after screen exit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final resendAvailableAt = DateTime.utc(2026, 10, 21, 10, 1);

      await PasswordResetSession(
        email: 'staff@example.com',
        resendAvailableAt: resendAvailableAt,
      ).persist();
      final restored = await PasswordResetSession.restore();

      expect(restored?.email, 'staff@example.com');
      expect(
        restored?.resendAvailableAt.millisecondsSinceEpoch,
        resendAvailableAt.millisecondsSinceEpoch,
      );
    },
  );

  testWidgets('forgot screen restores resend cooldown after returning', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await PasswordResetSession(
      email: 'staff@example.com',
      resendAvailableAt: DateTime.now().add(const Duration(seconds: 60)),
    ).persist();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ForgotPasswordScreen(),
                ),
              ),
              child: const Text('Open recovery'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open recovery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Resend Email ('), findsOneWidget);
    expect(find.text('Resend available in'), findsOneWidget);
    expect(find.textContaining('Resend Email ('), findsOneWidget);
    expect(find.textContaining('5-minute'), findsNothing);
    expect(find.textContaining('expires'), findsNothing);
    expect(find.text('Password changed? Return to Login'), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open recovery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Resend Email ('), findsOneWidget);
    expect(find.text('Resend available in'), findsOneWidget);
    expect(find.text('staff@example.com'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid email is rejected before calling Firebase Auth', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Send reset link'));
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
