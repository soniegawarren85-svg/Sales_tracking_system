import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum AdminSkeletonKind { dashboard, staff, inventory, reports, settings }

class AdminPageSkeleton extends StatelessWidget {
  const AdminPageSkeleton({super.key, required this.kind});
  final AdminSkeletonKind kind;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.background,
    child: SafeArea(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: switch (kind) {
                AdminSkeletonKind.dashboard => _dashboard(context),
                AdminSkeletonKind.staff => _staff(context),
                AdminSkeletonKind.inventory => _inventory(context),
                AdminSkeletonKind.reports => _reports(context),
                AdminSkeletonKind.settings => _settings(context),
              },
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _dashboard(BuildContext context) => [
    _block(height: 104, radius: 24),
    const SizedBox(height: 18),
    _grid(context, 4, height: 116),
    const SizedBox(height: 18),
    _block(height: 260, radius: 20),
    const SizedBox(height: 16),
    _block(height: 180, radius: 20),
  ];

  List<Widget> _staff(BuildContext context) => [
    _block(height: 66, radius: 18),
    const SizedBox(height: 16),
    _row([_block(height: 42, radius: 14), _block(height: 42, radius: 14)]),
    const SizedBox(height: 12),
    _block(height: 50, radius: 16),
    const SizedBox(height: 16),
    for (var i = 0; i < 3; i++) ...[_staffCard(), const SizedBox(height: 12)],
  ];

  List<Widget> _inventory(BuildContext context) => [
    _block(height: 96, radius: 22),
    const SizedBox(height: 16),
    _row(List.generate(3, (_) => _block(height: 42, radius: 14))),
    const SizedBox(height: 12),
    _block(height: 52, radius: 16),
    const SizedBox(height: 14),
    _block(height: 48, radius: 14),
    const SizedBox(height: 8),
    for (var i = 0; i < 4; i++) ...[
      _block(height: 86, radius: 16),
      const SizedBox(height: 10),
    ],
  ];

  List<Widget> _reports(BuildContext context) => [
    _block(height: 64, radius: 18),
    const SizedBox(height: 16),
    _row(List.generate(3, (_) => _block(height: 42, radius: 14))),
    const SizedBox(height: 16),
    _grid(context, 4, height: 96),
    const SizedBox(height: 16),
    _block(height: 270, radius: 20),
    const SizedBox(height: 14),
    _block(height: 190, radius: 20),
  ];

  List<Widget> _settings(BuildContext context) => [
    _block(height: 166, radius: 24),
    const SizedBox(height: 20),
    _block(height: 120, radius: 20),
    const SizedBox(height: 14),
    for (var i = 0; i < 4; i++) ...[
      _block(height: 76, radius: 18),
      const SizedBox(height: 12),
    ],
  ];

  Widget _staffCard() => _block(
    height: 148,
    radius: 18,
    child: Row(
      children: [
        _block(height: 50, width: 50, radius: 25),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _block(height: 17, width: 170, radius: 8),
              const SizedBox(height: 10),
              _block(height: 13, width: 230, radius: 7),
              const SizedBox(height: 12),
              _block(height: 30, width: 120, radius: 10),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _grid(BuildContext context, int count, {required double height}) {
    final columns = MediaQuery.sizeOf(context).width >= 900 ? 4 : 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: List.generate(
        count,
        (_) => SizedBox(
          width:
              (MediaQuery.sizeOf(context).width.clamp(320, 1100).toDouble() -
                  (columns - 1) * 12 -
                  32) /
              columns,
          child: _block(height: height, radius: 18),
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) => Row(
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(child: children[i]),
      ],
    ],
  );

  Widget _block({
    required double height,
    double? width,
    required double radius,
    Widget? child,
  }) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF3E4E9),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.blush.withValues(alpha: .8)),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    ),
  );
}
