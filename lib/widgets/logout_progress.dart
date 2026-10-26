import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

Future<T> runWithLogoutProgress<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => const _LogoutProgressDialog(),
  );
  unawaited(navigator.push(route));
  await Future<void>.delayed(Duration.zero);

  try {
    return await action();
  } finally {
    if (navigator.mounted && route.isActive) {
      navigator.removeRoute(route);
    }
  }
}

class _LogoutProgressDialog extends StatelessWidget {
  const _LogoutProgressDialog();

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 18),
            const Flexible(
              child: Text(
                'Logging out...',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
