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
    this.startAreaHeight = 100,
  });
  final Widget child;
  final Future<void> Function() onRefresh;
  final Color? color, backgroundColor;
  final double displacement;
  final double startAreaHeight;
  final bool Function(ScrollNotification)? notificationPredicate;
  @override
  State<TopEdgeRefresh> createState() => _TopEdgeRefreshState();
}

class _TopEdgeRefreshState extends State<TopEdgeRefresh> {
  bool _refreshInProgress = false;
  bool _startedNearTop = false;

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
    onPointerDown: (event) =>
        _startedNearTop = event.localPosition.dy <= widget.startAreaHeight,
    child: RefreshIndicator(
      color: widget.color,
      backgroundColor: widget.backgroundColor,
      displacement: widget.displacement,
      triggerMode: RefreshIndicatorTriggerMode.onEdge,
      notificationPredicate: (notification) {
        if (notification.metrics.axis != Axis.vertical) return false;
        return _startedNearTop &&
            (widget.notificationPredicate?.call(notification) ?? true);
      },
      onRefresh: _refresh,
      child: widget.child,
    ),
  );
}
