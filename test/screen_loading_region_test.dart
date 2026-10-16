import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/screen_loading_region.dart';

void main() {
  testWidgets('multiple sections share one loader until all sections finish', (
    tester,
  ) async {
    final first = ValueNotifier(true);
    final second = ValueNotifier(true);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget section(ValueNotifier<bool> pending, String label) =>
        ValueListenableBuilder<bool>(
          valueListenable: pending,
          builder: (_, loading, _) =>
              loading ? const ScreenLoadingIndicator() : Text(label),
        );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenLoadingRegion(
            child: Column(
              children: [
                section(first, 'Totals'),
                section(second, 'Inventory'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    first.value = false;
    await tester.pump();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Totals').hitTestable(), findsOneWidget);
    second.value = false;
    await tester.pump();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Totals'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
    first.value = true;
    await tester.pump();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'nested page regions share the shell loader and release on navigation',
    (tester) async {
      final showPage = ValueNotifier(true);
      addTearDown(showPage.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScreenLoadingRegion(
              child: ValueListenableBuilder<bool>(
                valueListenable: showPage,
                builder: (_, show, _) => show
                    ? const ScreenLoadingRegion(
                        child: Column(
                          children: [
                            ScreenLoadingIndicator(),
                            ScreenLoadingIndicator(),
                          ],
                        ),
                      )
                    : const Text('Next page'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      showPage.value = false;
      await tester.pump();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Next page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'standalone dialog loader remains visible without a screen region',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: ScreenLoadingIndicator())),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );
}
