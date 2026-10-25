import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/raspberry_cupcake_loader.dart';

void main() {
  for (final width in [360.0, 768.0]) {
    testWidgets('branded loader fits at ${width}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RaspberryCupcakeLoader(
              fullScreen: true,
              message: 'Loading your workspace...',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Angelz Bites Cupcakes'), findsOneWidget);
      expect(find.text('Loading your workspace...'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
