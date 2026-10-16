import 'package:flutter/material.dart';

/// Keeps the controls mounted while sliding them out of the inventory viewport.
class InventoryHeaderTransition extends StatelessWidget {
  const InventoryHeaderTransition({
    super.key,
    required this.collapsed,
    required this.child,
  });

  final bool collapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(end: collapsed ? 0 : 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 360),
    curve: Curves.easeInOutCubic,
    child: child,
    builder: (context, visible, child) {
      if (visible == 0) return const SizedBox.shrink();
      return IgnorePointer(
        ignoring: collapsed,
        child: ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: visible,
            child: child,
          ),
        ),
      );
    },
  );
}
