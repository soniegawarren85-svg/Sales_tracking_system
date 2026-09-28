import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/top_notification.dart';

void main() {
  testWidgets('welcome remains visible after replacing the login route', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(body: TextButton(onPressed: () {
        showTopNotification(context, 'Welcome, Maria!', delay: const Duration(milliseconds: 400));
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Dashboard')),
        ));
      }, child: const Text('Sign in')));
    })));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Welcome, Maria!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Welcome, Maria!'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
