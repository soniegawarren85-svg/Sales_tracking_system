import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/staff_mobile_sales_layout.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'mobile header collapses and ticket actions stay below items at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var toolsOpened = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: const SizedBox(height: 75),
              body: StaffMobileSalesLayout(
                reviewing: false,
                onBack: () {},
                onTools: () => toolsOpened = true,
                body: const SizedBox(height: 1600, child: Text('Items')),
                actions: const SizedBox(
                  key: ValueKey('dock'),
                  height: 96,
                  child: Text('Review ticket'),
                ),
              ),
            ),
          ),
        );
        final initialHeight = tester.getSize(find.byType(AppBar)).height;
        final dockBefore = tester.getTopLeft(
          find.byKey(const ValueKey('dock')),
        );
        expect(tester.getTopLeft(find.byType(AppBar)), Offset.zero);
        expect(tester.getSize(find.byType(AppBar)).width, width);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -220));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(AppBar)).height,
          lessThan(initialHeight),
        );
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('dock'))),
          dockBefore,
        );
        expect(
          tester.getBottomLeft(find.byKey(const ValueKey('dock'))).dy,
          725,
        );
        await tester.tap(find.byTooltip('Cashier tools'));
        expect(toolsOpened, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('review header has both back and cashier tools controls', (
    tester,
  ) async {
    var wentBack = false;
    var openedTools = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffMobileSalesLayout(
            reviewing: true,
            onBack: () => wentBack = true,
            onTools: () => openedTools = true,
            body: const Text('Ticket'),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Cashier tools'));
    await tester.tap(find.byTooltip('Back to items'));
    expect(openedTools, isTrue);
    expect(wentBack, isTrue);
    expect(find.text('Order Review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
