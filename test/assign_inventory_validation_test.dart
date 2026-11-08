import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/assign_inventory_tile.dart';

void main() {
  test('category quantity validation is scoped to the active category tab', () {
    final category = TextEditingController(text: '7');
    final oldBundle = TextEditingController(text: '2');
    addTearDown(category.dispose);
    addTearDown(oldBundle.dispose);

    expect(
      assignmentQuantityValidationMessage(
        controllers: {'category': category, 'bundle': oldBundle},
        kinds: {'category': 'category', 'bundle': 'bundle'},
        limits: {'category': 301, 'bundle': 80},
        activeKinds: {'category'},
      ),
      'Category quantity must be at least 20 and no more than 150 units per item.',
    );
  });

  test('bundle quantity validation uses bundle-specific limits', () {
    final bundle = TextEditingController(text: '51');
    addTearDown(bundle.dispose);

    expect(
      assignmentQuantityValidationMessage(
        controllers: {'bundle': bundle},
        kinds: {'bundle': 'bundle'},
        limits: {'bundle': 80},
        activeKinds: {'bundle'},
      ),
      'Bundle quantity must be at least 10 and no more than 50.',
    );
  });

  test('valid category quantity cannot exceed available stock', () {
    final category = TextEditingController(text: '40');
    addTearDown(category.dispose);

    expect(
      assignmentQuantityValidationMessage(
        controllers: {'category': category},
        kinds: {'category': 'category'},
        limits: {'category': 30},
        activeKinds: {'category'},
      ),
      'Only 30 units are available for this item.',
    );
  });

  testWidgets('assignment validation notice is styled as a single alert', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssignmentValidationNotice(
            message:
                'Category quantity must be at least 20 and no more than 150 units per item.',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    expect(
      find.text(
        'Category quantity must be at least 20 and no more than 150 units per item.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
