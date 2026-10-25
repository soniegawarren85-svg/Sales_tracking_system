import 'dart:async';

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
  bool _refreshInProgress = false;
  bool nearTop = false;
  final offsets = <int, double>{};

  Future<void> _refresh() async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    var showedSlowNotice = false;
    final slowRefreshTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_refreshInProgress) return;
      showedSlowNotice = true;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Poor connection. Refresh is taking longer than usual.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
    });

    try {
      await widget.onRefresh().timeout(const Duration(seconds: 20));
    } on TimeoutException catch (error) {
      debugPrint('Staff page refresh timed out: $error');
      if (mounted && !showedSlowNotice) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Poor connection. Refresh did not finish. Pull down to try again.',
              ),
            ),
          );
      }
    } catch (error) {
      debugPrint('Staff page refresh failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to refresh. Check your connection and try again.',
              ),
            ),
          );
      }
    } finally {
      slowRefreshTimer.cancel();
      _refreshInProgress = false;
    }
  }

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
      onRefresh: _refresh,
      child: widget.child,
    ),
  );
}
