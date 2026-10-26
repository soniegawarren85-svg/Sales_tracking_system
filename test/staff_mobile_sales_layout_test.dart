import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/theme/app_colors.dart';
import 'package:sales_tracking/widgets/logout_progress.dart';
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
        expect(find.byIcon(Icons.point_of_sale_rounded), findsNothing);
        expect(
          (tester.widget(find.byType(AppBar)) as AppBar).backgroundColor,
          AppColors.primaryDark,
        );
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

  testWidgets('sales header shows only title and cashier tools', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffMobileSalesLayout(
            reviewing: false,
            onBack: () {},
            onTools: () {},
            body: const Text('Items'),
          ),
        ),
      ),
    );

    expect(find.text('Sales Process'), findsOneWidget);
    expect(find.byIcon(Icons.point_of_sale_rounded), findsNothing);
    expect(find.byTooltip('Cashier tools'), findsOneWidget);
    expect(
      (tester.widget(find.byType(AppBar)) as AppBar).backgroundColor,
      AppColors.primaryDark,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('logout progress stays visible while logout is pending', (
    tester,
  ) async {
    final logoutCompleter = Completer<void>();
    late Future<void> logout;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                logout = runWithLogoutProgress(
                  context,
                  () => logoutCompleter.future,
                );
              },
              child: const Text('Logout'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Logout'));
    await tester.pump();
    expect(find.text('Logging out...'), findsOneWidget);

    logoutCompleter.complete();
    await tester.pumpAndSettle();
    await logout;
    expect(find.text('Logging out...'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
