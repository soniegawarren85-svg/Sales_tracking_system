import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class StaffMobileSalesLayout extends StatelessWidget {
  const StaffMobileSalesLayout({
    super.key,
    required this.reviewing,
    required this.onBack,
    required this.onTools,
    required this.body,
    this.actions,
  });

  final bool reviewing;
  final VoidCallback onBack;
  final VoidCallback onTools;
  final Widget body;
  final Widget? actions;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: CustomScrollView(
          key: ValueKey(reviewing),
          slivers: [
            SliverAppBar(
              pinned: true,
              automaticallyImplyLeading: false,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              expandedHeight: reviewing ? 56 : 94,
              leading: reviewing
                  ? IconButton(
                      tooltip: 'Back to items',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  : const Icon(Icons.point_of_sale_rounded),
              title: Text(
                reviewing ? 'Order Review' : 'Sales Process',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Cashier tools',
                  onPressed: onTools,
                  icon: const Icon(Icons.menu_rounded),
                ),
              ],
              flexibleSpace: reviewing
                  ? null
                  : FlexibleSpaceBar(
                      background: Container(
                        alignment: Alignment.bottomLeft,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: const Text(
                          'Build and review staff orders',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              sliver: SliverToBoxAdapter(child: body),
            ),
          ],
        ),
      ),
      if (actions != null) actions!,
    ],
  );
}
