import 'package:flutter/material.dart';

/// Keeps data sections mounted while showing one loader for the visible screen.
class ScreenLoadingRegion extends StatefulWidget {
  const ScreenLoadingRegion({super.key, required this.child});
  final Widget child;
  @override
  State<ScreenLoadingRegion> createState() => _ScreenLoadingRegionState();
}

class _ScreenLoadingRegionState extends State<ScreenLoadingRegion> {
  final _pending = <Object>{};
  bool _scheduled = false;
  void update(Object token, bool loading) {
    final changed = loading ? _pending.add(token) : _pending.remove(token);
    if (!changed || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // A page can also be used outside the dashboard shell.
    if (context.dependOnInheritedWidgetOfExactType<_LoadingHost>() != null)
      return widget.child;
    final loading = _pending.isNotEmpty;
    return _LoadingHost(
      owner: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: LinearProgressIndicator(semanticsLabel: 'Loading'),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadingHost extends InheritedWidget {
  const _LoadingHost({required this.owner, required super.child});
  final _ScreenLoadingRegionState owner;
  @override
  bool updateShouldNotify(_LoadingHost oldWidget) => owner != oldWidget.owner;
}

/// Reports a section's wait to its screen; works normally in standalone dialogs.
class ScreenLoadingIndicator extends StatefulWidget {
  const ScreenLoadingIndicator({super.key, this.color, this.strokeWidth = 4});
  final Color? color;
  final double strokeWidth;
  @override
  State<ScreenLoadingIndicator> createState() => _ScreenLoadingIndicatorState();
}

class _ScreenLoadingIndicatorState extends State<ScreenLoadingIndicator> {
  _ScreenLoadingRegionState? _owner;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = context
        .dependOnInheritedWidgetOfExactType<_LoadingHost>()
        ?.owner;
    if (owner == _owner) return;
    _owner?.update(this, false);
    _owner = owner;
    _owner?.update(this, true);
  }

  @override
  void dispose() {
    _owner?.update(this, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _owner == null
      ? CircularProgressIndicator(
          color: widget.color,
          strokeWidth: widget.strokeWidth,
        )
      : const SizedBox(width: 36, height: 36);
}
