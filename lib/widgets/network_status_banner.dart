import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Keeps the offline state visible until a real internet connection returns.
class NetworkStatusBanner extends StatefulWidget {
  final Widget child;

  const NetworkStatusBanner({super.key, required this.child});

  @override
  State<NetworkStatusBanner> createState() => _NetworkStatusBannerState();
}

class _NetworkStatusBannerState extends State<NetworkStatusBanner> {
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _subscription = Connectivity().onConnectivityChanged.listen(
      _updateNetworkState,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _checkConnection());
  }

  Future<void> _checkConnection() async {
    try {
      _updateNetworkState(await Connectivity().checkConnectivity());
    } catch (_) {
      // Avoid showing a false offline warning when the platform query fails.
    }
  }

  void _updateNetworkState(List<ConnectivityResult> results) {
    final offline = results.isEmpty || results.contains(ConnectivityResult.none);
    if (mounted && offline != _isOffline) setState(() => _isOffline = offline);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        IgnorePointer(
          child: SafeArea(
            bottom: false,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              offset: _isOffline ? Offset.zero : const Offset(0, -1.4),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _isOffline ? 1 : 0,
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
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x44000000),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.wifi_off_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No network — you\'re offline',
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
        ),
      ],
    );
  }
}
