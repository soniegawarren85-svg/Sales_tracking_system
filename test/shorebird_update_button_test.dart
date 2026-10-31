import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/shorebird_update_service.dart';
import 'package:sales_tracking/widgets/shorebird_update_button.dart';

void main() {
  tearDown(() {
    ShorebirdUpdateService.promptState.value =
        ShorebirdUpdatePromptState.hidden;
  });

  testWidgets(
    'update button appears after deferring and reflects restart state',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ShorebirdUpdateButton())),
      );
      expect(find.text('Ready to update'), findsNothing);

      ShorebirdUpdateService.promptState.value =
          ShorebirdUpdatePromptState.available;
      await tester.pump();
      expect(find.text('Ready to update'), findsOneWidget);

      ShorebirdUpdateService.promptState.value =
          ShorebirdUpdatePromptState.restartRequired;
      await tester.pump();
      expect(find.text('Update ready'), findsOneWidget);

      ShorebirdUpdateService.promptState.value =
          ShorebirdUpdatePromptState.hidden;
      await tester.pump();
      expect(find.text('Update ready'), findsNothing);
    },
  );
}
