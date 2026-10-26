import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/raspberry_mobile_navigation.dart';

void main() {
  Widget buildNavigation({
    required int selectedIndex,
    required bool moreSelected,
    required ValueChanged<int> onDestinationSelected,
    required VoidCallback onMoreSelected,
    String branchLabel = 'Branch Sales',
  }) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: RaspberryMobileNavigation(
          items: [
            RaspberryMobileNavItem(
              icon: Icons.dashboard_rounded,
              label: 'Dashboard',
              index: 0,
            ),
            RaspberryMobileNavItem(
              icon: Icons.storefront_rounded,
              label: branchLabel,
              index: 1,
            ),
            RaspberryMobileNavItem(
              icon: Icons.inventory_2_rounded,
              label: 'Inventory',
              index: 2,
              badgeCount: 3,
            ),
          ],
          selectedIndex: selectedIndex,
          moreSelected: moreSelected,
          onDestinationSelected: onDestinationSelected,
          onMoreSelected: onMoreSelected,
        ),
      ),
    );
  }

  testWidgets('expands the active destination and keeps More icon-only', (
    tester,
  ) async {
    var selectedIndex = 0;
    var moreSelected = false;
    await tester.pumpWidget(
      buildNavigation(
        selectedIndex: selectedIndex,
        moreSelected: moreSelected,
        onDestinationSelected: (index) => selectedIndex = index,
        onMoreSelected: () => moreSelected = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Branch Sales'), findsNothing);
    expect(find.text('More'), findsNothing);
    expect(find.byKey(const ValueKey('raspberry-more-button')), findsOneWidget);
    final background = tester.widget<Container>(
      find.byKey(const ValueKey('raspberry-navigation-background')),
    );
    expect(background.color, Colors.transparent);
    expect(
      tester.getSize(find.byKey(const ValueKey('raspberry-nav-0'))).height,
      56,
    );

    await tester.tap(find.byKey(const ValueKey('raspberry-nav-1')));
    await tester.pumpAndSettle();

    expect(selectedIndex, 1);
    await tester.pumpWidget(
      buildNavigation(
        selectedIndex: selectedIndex,
        moreSelected: moreSelected,
        onDestinationSelected: (index) => selectedIndex = index,
        onMoreSelected: () => moreSelected = true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Branch Sales'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('raspberry-more-button')));
    expect(moreSelected, isTrue);
  });

  testWidgets('fits narrow mobile width without layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildNavigation(
        selectedIndex: 1,
        moreSelected: false,
        onDestinationSelected: (_) {},
        onMoreSelected: () {},
        branchLabel: 'Branch Performance',
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Branch Performance'), findsOneWidget);
    expect(find.byKey(const ValueKey('raspberry-more-button')), findsOneWidget);
  });
}
