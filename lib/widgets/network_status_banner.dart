import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../services/local_database_sync_service.dart';

class NetworkStatusBanner extends StatefulWidget {
  final Widget child;

  const NetworkStatusBanner({super.key, required this.child});

  @override
  State<NetworkStatusBanner> createState() => _NetworkStatusBannerState();
}

class _NetworkStatusBannerState extends State<NetworkStatusBanner> {
  Timer? _pollTimer;
  Timer? _noticeTimer;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _offline = false;
  bool _showNotice = false;
  bool _markDismissed = false;

  @override
  void initState() {
    super.initState();
    _check();
    _subscription = Connectivity().onConnectivityChanged.listen(_update);
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  Future<void> _check() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _update(results);
    } catch (_) {}
  }

  void _update(List<ConnectivityResult> state) {
    if (!mounted) return;

    final offline = state.isEmpty || state.contains(ConnectivityResult.none);
    if (offline == _offline) return;

    _noticeTimer?.cancel();
    setState(() {
      _offline = offline;
      _showNotice = offline;
      _markDismissed = false;
    });

    if (offline) {
      _noticeTimer = Timer(const Duration(seconds: 10), () {
        if (mounted && _offline) {
          setState(() => _showNotice = false);
        }
      });
    } else {
      unawaited(LocalDatabaseSyncService().syncPendingSales());
      unawaited(LocalDatabaseSyncService().syncPendingCashDrawerChanges());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _noticeTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        SafeArea(
          bottom: false,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            offset: _showNotice ? Offset.zero : const Offset(0, -1.4),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _showNotice ? 1 : 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC62828),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.wifi_off_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No internet connection — Offline mode',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
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
        ),
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 180),
              offset: _offline && !_showNotice && !_markDismissed
                  ? Offset.zero
                  : const Offset(0, -1.5),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _offline && !_showNotice && !_markDismissed ? 1 : 0,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.only(
                        left: 13,
                        top: 6,
                        bottom: 6,
                        right: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B0035),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Offline mode',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                            onPressed: () =>
                                setState(() => _markDismissed = true),
                            tooltip: null,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 15,
                              semanticLabel: 'Dismiss offline mark',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
