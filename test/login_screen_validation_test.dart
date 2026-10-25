import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/Login/Login/Login.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in [const Size(390, 844), const Size(768, 1024)]) {
    testWidgets(
      'login shows bottom validation notifications at ${size.width}px',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Sign In'));
        await tester.tap(find.text('Sign In'));
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(find.text('Email address is required.'), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Password is required.'), findsNothing);
        expect(find.text('Please enter a valid email address.'), findsNothing);
        expect(
          tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
          SnackBarBehavior.floating,
        );

        ScaffoldMessenger.of(
          tester.element(find.byType(LoginScreen)),
        ).hideCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).first,
          'not-an-email',
        );
        await tester.enterText(find.byType(TextFormField).last, 'password');
        await tester.tap(find.text('Sign In'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Please enter a valid email address.'),
          findsOneWidget,
        );

        ScaffoldMessenger.of(
          tester.element(find.byType(LoginScreen)),
        ).hideCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).first,
          'valid@example.com',
        );
        await tester.enterText(find.byType(TextFormField).last, '');
        await tester.tap(find.text('Sign In'));
        await tester.pump();
        expect(find.text('Password is required.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
