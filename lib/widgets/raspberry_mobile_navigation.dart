import 'package:flutter/material.dart';
import 'package:sales_tracking/theme/app_colors.dart';

class RaspberryMobileNavItem {
  const RaspberryMobileNavItem({
    required this.icon,
    required this.label,
    required this.index,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final int index;
  final int badgeCount;
}

class RaspberryMobileNavigation extends StatelessWidget {
  const RaspberryMobileNavigation({
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onMoreSelected,
    required this.moreSelected,
    super.key,
  });

  final List<RaspberryMobileNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onMoreSelected;
  final bool moreSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('raspberry-navigation-background'),
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pillWidth = constraints.maxWidth;
                    final availableWidth = pillWidth - 8 * (items.length - 1);
                    final selectedWidth = availableWidth * 0.48;
                    final idleWidth = items.length > 1
                        ? (availableWidth - selectedWidth) / (items.length - 1)
                        : availableWidth;

                    return Container(
                      height: 64,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.rose,
                        borderRadius: BorderRadius.circular(34),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final item in items)
                            _NavigationDestination(
                              item: item,
                              selected: selectedIndex == item.index,
                              width: selectedIndex == item.index
                                  ? selectedWidth
                                  : idleWidth,
                              onTap: () => onDestinationSelected(item.index),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: 'More',
                child: Material(
                  color: moreSelected ? AppColors.primaryDark : AppColors.rose,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const ValueKey('raspberry-more-button'),
                    customBorder: const CircleBorder(),
                    onTap: onMoreSelected,
                    child: SizedBox(
                      width: 58,
                      height: 58,
                      child: Icon(
                        Icons.more_horiz_rounded,
                        color: moreSelected
                            ? Colors.white
                            : AppColors.primaryDark,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationDestination extends StatelessWidget {
  const _NavigationDestination({
    required this.item,
    required this.selected,
    required this.width,
    required this.onTap,
  });

  final RaspberryMobileNavItem item;
  final bool selected;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badgeText = item.badgeCount > 99 ? '99+' : '${item.badgeCount}';

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: AnimatedContainer(
        key: ValueKey('raspberry-nav-${item.index}'),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        width: width,
        height: 56,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Badge(
                    isLabelVisible: item.badgeCount > 0,
                    label: Text(badgeText),
                    child: Icon(
                      item.icon,
                      size: 22,
                      color: selected ? Colors.white : AppColors.primaryDark,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: Text(
                          item.label,
                          key: ValueKey(item.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
