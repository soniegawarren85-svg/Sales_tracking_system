import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/branch_analytics_bars.dart';

void main() {
  testWidgets(
    '24-hour chart scrolls horizontally on a phone without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 240,
              child: BranchAnalyticsBars(
                values: List.filled(24, 89),
                labels: List.generate(24, (hour) => '$hour:00'),
              ),
            ),
          ),
        ),
      );
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      await tester.drag(
        find.byType(BranchAnalyticsBars),
        const Offset(-800, 0),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );
  Future<void> showChart(WidgetTester tester, double count) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 240,
            child: BranchAnalyticsBars(
              values: [count],
              labels: const ['Sep'],
              refunds: const [0],
              reduced: const [0],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Uses peso intervals and keeps completed-only bars visible', (
    tester,
  ) async {
    await showChart(tester, 150);
    for (final label in ['0', '50', '100', '150', '200']) {
      expect(find.text(label), findsOneWidget);
    }
    final bar = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).gradient != null,
    );
    expect(tester.getSize(bar).width, greaterThan(0));
    expect(tester.getSize(bar).height, closeTo(185 * 150 / 200, 0.01));
    await tester.tap(bar);
    await tester.pumpAndSettle();
    expect(find.textContaining('Completed: ₱150.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Fits 10,000 pesos without scrolling or increasing chart height',
    (tester) async {
      await showChart(tester, 10000);
      expect(find.text('10000'), findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.getSize(find.byType(BranchAnalyticsBars)).height, 240);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Empty chart still shows its scale without errors', (
    tester,
  ) async {
    await showChart(tester, 0);
    expect(find.text('200'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
