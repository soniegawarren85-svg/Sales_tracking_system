import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class StaffMobileSalesLayout extends StatelessWidget {
  const StaffMobileSalesLayout({
    super.key,
    required this.reviewing,
    required this.onBack,
    required this.onTools,
    required this.body,
    this.titleTourKey,
    this.actions,
    this.cartCount = 0,
  });

  final bool reviewing;
  final VoidCallback onBack;
  final VoidCallback onTools;
  final Widget body;
  final GlobalKey? titleTourKey;
  final Widget? actions;
  final int cartCount;

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
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
              expandedHeight: 56,
              leading: reviewing
                  ? IconButton(
                      tooltip: 'Back to items',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  : null,
              leadingWidth: reviewing ? 56 : 0,
              title: KeyedSubtree(
                key: titleTourKey,
                child: Text(
                  reviewing ? 'Order Review' : 'Sales Process',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              actions: [
                if (!reviewing)
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 32),
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$cartCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'Cashier tools',
                  onPressed: onTools,
                  icon: const Icon(Icons.menu_rounded),
                ),
              ],
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
