import 'package:flutter/material.dart';

void showTopNotification(
  BuildContext context,
  String message, {
  bool isError = false,
  Color? backgroundColor,
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  final entry = OverlayEntry(
    builder: (context) => _TopNotificationOverlay(
      message: message,
      isError: isError,
      backgroundColor: backgroundColor,
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 2800), entry.remove);
}

class _TopNotificationOverlay extends StatefulWidget {
  final String message;
  final bool isError;
  final Color? backgroundColor;

  const _TopNotificationOverlay({
    required this.message,
    required this.isError,
    required this.backgroundColor,
  });

  @override
  State<_TopNotificationOverlay> createState() =>
      _TopNotificationOverlayState();
}

class _TopNotificationOverlayState extends State<_TopNotificationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 12;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: widget.backgroundColor ??
                      (widget.isError
                          ? const Color(0xFFB71C1C)
                          : const Color(0xFF8B0035)),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.isError
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
