import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/staff_onboarding_card.dart';

void main() {
  for (final width in [360.0, 768.0]) {
    testWidgets('tutorial controls fit at ${width}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var nextPressed = false;
      var backPressed = false;
      var skipPressed = false;
      var finishPressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Center(
                child: StaffOnboardingCard(
                  title: 'Products and Inventory',
                  description: 'Review allocated items for your branch.',
                  step: 2,
                  totalSteps: 10,
                  arrowPointsUp: false,
                  isLastStep: false,
                  isSaving: false,
                  isConfirmingSkip: skipPressed,
                  onBack: () => backPressed = true,
                  onCancelSkip: () => setState(() => skipPressed = false),
                  onNext: () => nextPressed = true,
                  onSkip: () => setState(() => skipPressed = true),
                  onFinish: () => finishPressed = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Step 2 of 10'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.tap(find.text('Next'));
      await tester.tap(find.text('Skip'));
      expect(backPressed, isTrue);
      expect(nextPressed, isTrue);
      await tester.pump();
      expect(find.text('Skip the staff tutorial?'), findsOneWidget);
      expect(find.text('Skip tutorial'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Keep learning'));
      await tester.pump();
      expect(find.text('Skip'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.tap(find.text('Skip tutorial'));
      expect(finishPressed, isTrue);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
