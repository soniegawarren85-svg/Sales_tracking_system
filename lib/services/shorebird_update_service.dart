import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// App controlled Shorebird updates and the optional Android status bar alert.
class ShorebirdUpdateService {
  ShorebirdUpdateService._();

  static final ShorebirdUpdater updater = ShorebirdUpdater();
  static final ValueNotifier<bool> salesProcessActive = ValueNotifier(false);
  static const _notifications = MethodChannel(
    'com.example.sales_tracking/updates',
  );

  static Future<UpdateStatus> check() => updater.checkForUpdate();

  static Future<void> download() => updater.update();

  static Future<void> notifyAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _notifications.invokeMethod<void>('showUpdateAvailable');
    } on MissingPluginException {
      debugPrint('Shorebird notification channel is unavailable.');
    } on PlatformException catch (error) {
      debugPrint('Unable to show the Shorebird update notification: $error');
    }
  }

  static Future<void> clearNotification() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _notifications.invokeMethod<void>('clearUpdateNotification');
    } on MissingPluginException {
      debugPrint('Shorebird notification channel is unavailable.');
    } on PlatformException catch (error) {
      debugPrint('Unable to clear the Shorebird update notification: $error');
    }
  }
}
