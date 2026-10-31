import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

enum ShorebirdUpdatePromptState { hidden, available, restartRequired }

/// App controlled Shorebird updates and the optional Android status bar alert.
class ShorebirdUpdateService {
  ShorebirdUpdateService._();

  static final ShorebirdUpdater updater = ShorebirdUpdater();
  static final ValueNotifier<bool> salesProcessActive = ValueNotifier(false);
  static final ValueNotifier<ShorebirdUpdatePromptState> promptState =
      ValueNotifier(ShorebirdUpdatePromptState.hidden);
  static const _notifications = MethodChannel(
    'com.example.sales_tracking/updates',
  );
  static Future<void> Function()? _onUpdatePromptRequested;

  static Future<UpdateStatus> check() => updater.checkForUpdate();

  static Future<void> download() => updater.update();

  static void registerUpdatePromptHandler(Future<void> Function() handler) {
    _onUpdatePromptRequested = handler;
    _notifications.setMethodCallHandler((call) async {
      if (call.method == 'openUpdatePrompt') {
        await _onUpdatePromptRequested?.call();
      }
    });
    if (defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_consumePendingUpdatePrompt());
    }
  }

  static Future<void> requestUpdatePrompt() async {
    await _onUpdatePromptRequested?.call();
  }

  static Future<void> _consumePendingUpdatePrompt() async {
    try {
      final pending = await _notifications.invokeMethod<bool>(
        'consumeUpdatePrompt',
      );
      if (pending == true) await requestUpdatePrompt();
    } on MissingPluginException {
      debugPrint('Shorebird notification channel is unavailable.');
    } on PlatformException catch (error) {
      debugPrint('Unable to read Shorebird notification tap: $error');
    }
  }

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

  static Future<void> notifyApplied() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _notifications.invokeMethod<void>('showUpdateApplied');
    } on MissingPluginException {
      debugPrint('Shorebird notification channel is unavailable.');
    } on PlatformException catch (error) {
      debugPrint('Unable to show update success notification: $error');
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
