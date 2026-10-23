import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/password_policy.dart';
import 'package:sales_tracking/widgets/password_strength_checklist.dart';

void main() {
  test('every requirement is mandatory for strong passwords', () {
    expect(PasswordStrength('Abcdef1!').isStrong, isTrue);
    for (final password in [
      'Abc1!',
      'abcdef1!',
      'ABCDEF1!',
      'Abcdefg!',
      'Abcdef12',
    ]) {
      expect(PasswordStrength(password).isStrong, isFalse);
    }
  });
  test('three of five requirements are acceptable as a fair password', () {
    expect(PasswordStrength('Abcdefgh').score, 3);
    expect(PasswordStrength('Abcdefgh').isAcceptable, isTrue);
    expect(PasswordStrength('abc').isAcceptable, isFalse);
  });
  test('password input accepts typing/deletion and rejects bulk paste', () {
    const formatter = PasswordTypingFormatter();
    const empty = TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
    const typed = TextEditingValue(
      text: 'A',
      selection: TextSelection.collapsed(offset: 1),
    );
    const pasted = TextEditingValue(
      text: 'Abcdef1!',
      selection: TextSelection.collapsed(offset: 8),
    );
    expect(formatter.formatEditUpdate(empty, typed), typed);
    expect(formatter.formatEditUpdate(empty, pasted), empty);
    expect(formatter.formatEditUpdate(typed, empty), empty);
  });
  for (final width in [360.0, 900.0]) {
    testWidgets('live checklist fits $width and updates its progress', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PasswordStrengthChecklist(password: '')),
        ),
      );
      expect(
        find.text('Type a password to check its strength'),
        findsOneWidget,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PasswordStrengthChecklist(password: 'abc')),
        ),
      );
      expect(find.text('Weak password'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .2,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PasswordStrengthChecklist(password: 'Abcdefgh')),
        ),
      );
      expect(find.text('Fair password'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .6,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PasswordStrengthChecklist(password: 'Abcdef1!')),
        ),
      );
      expect(find.text('Strong password'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
