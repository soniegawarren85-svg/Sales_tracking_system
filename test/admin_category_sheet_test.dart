import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/admin_category_sheet.dart';

void main() {
  testWidgets(
    'Category save removes the focused sheet before opening the item dialog',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Create category'),
                onPressed: () async {
                  final category = await showAdminCategorySheet(
                    context,
                    save: (name) async => {'id': 'category', 'name': name},
                  );
                  if (category != null && context.mounted) {
                    await showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Add item to ${category['name']}'),
                        content: const TextField(autofocus: true),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close item'),
                          ),
                        ],
                      ),
                    );
                  }
                },
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Create category'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Cakes');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('Add item to Cakes'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close item'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Category sheet validates and closes safely while input is focused',
    (tester) async {
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open'),
                onPressed: () => showAdminCategorySheet(
                  context,
                  save: (name) async {
                    saves++;
                    return {'name': name};
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save category'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a category name.'), findsOneWidget);
      expect(saves, 0);
      await tester.enterText(find.byType(TextField), 'Unsaved');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(saves, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
