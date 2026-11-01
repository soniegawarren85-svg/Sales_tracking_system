import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/shorebird_update_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'restart acknowledgement remains stored until update is applied',
    () async {
      ShorebirdUpdateService.promptState.value =
          ShorebirdUpdatePromptState.restartRequired;
      await ShorebirdUpdateService.acknowledgeRestartPrompt();

      expect(
        await ShorebirdUpdateService.isRestartPromptAcknowledged(),
        isTrue,
      );
      expect(
        ShorebirdUpdateService.promptState.value,
        ShorebirdUpdatePromptState.hidden,
      );

      await ShorebirdUpdateService.clearRestartPromptAcknowledgement();

      expect(
        await ShorebirdUpdateService.isRestartPromptAcknowledged(),
        isFalse,
      );
    },
  );
}
