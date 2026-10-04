import 'package:flutter/material.dart';

/// Refresh only when a new gesture starts near the top of this scroll area.
class TopEdgeRefresh extends StatefulWidget {
  const TopEdgeRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color,
    this.backgroundColor,
    this.notificationPredicate,
    this.displacement = 40,
  });
  final Widget child;
  final Future<void> Function() onRefresh;
  final Color? color, backgroundColor;
  final double displacement;
  final bool Function(ScrollNotification)? notificationPredicate;
  @override
  State<TopEdgeRefresh> createState() => _TopEdgeRefreshState();
}

class _TopEdgeRefreshState extends State<TopEdgeRefresh> {
  bool nearTop = false;
  final offsets = <int, double>{};
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => nearTop =
        event.localPosition.dy <= 160 &&
        offsets.values.every((offset) => offset <= 0),
    child: RefreshIndicator(
      color: widget.color,
      backgroundColor: widget.backgroundColor,
      displacement: widget.displacement,
      triggerMode: RefreshIndicatorTriggerMode.onEdge,
      notificationPredicate: (notification) {
        if (notification.metrics.axis != Axis.vertical) return false;
        offsets[notification.depth] = notification.metrics.extentBefore;
        return nearTop &&
            (widget.notificationPredicate?.call(notification) ??
                notification.depth == 0);
      },
      onRefresh: widget.onRefresh,
      child: widget.child,
    ),
  );
}
