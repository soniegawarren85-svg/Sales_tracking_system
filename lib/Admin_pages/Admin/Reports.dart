import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ─── Palette ────────────────────────────────────────────────────────────────
const _primary = Color(0xFFE91E63);
const _primaryDeep = Color(0xFFAD1457);
const _primaryLight = Color(0xFFF48FB1);
const _primaryGlow = Color(0xFFFF80AB);
const _bg = Color(0xFFFFF0F5);
const _border = Color(0xFFF8BBD0);
const _cardBg = Color(0xFFFFFFFF);
const _accent = Color(0xFFFF4081);

// ─── Entry Point ────────────────────────────────────────────────────────────
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: _bg,
      extendBodyBehindAppBar: true,
      appBar: _GradientAppBar(),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firestore
            .collection('completed_sales')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, salesSnapshot) {
          if (salesSnapshot.hasError) {
            return _EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Unable to load reports',
              message: salesSnapshot.error.toString(),
            );
          }
          if (!salesSnapshot.hasData) {
            return const _LoadingShimmer();
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: firestore
                .collection('coffee_products')
                .where('isDeleted', isEqualTo: false)
                .snapshots(),
            builder: (context, coffeeSnapshot) {
              final coffeeRefs = _CoffeeRefs.fromDocs(
                coffeeSnapshot.data?.docs ?? const [],
              );
              final report = _ReportData.fromDocs(
                salesSnapshot.data!.docs,
                coffeeRefs,
              );

              if (report.transactions.isEmpty) {
                return const _EmptyState(
                  icon: Icons.assessment_outlined,
                  title: 'No reports yet',
                  message: 'Completed sales will appear here automatically.',
                );
              }

              return _AnimatedReportBody(report: report);
            },
          );
        },
      ),
    );
  }
}

// ─── Gradient AppBar ─────────────────────────────────────────────────────────
class _GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 20);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE91E63), Color(0xFFAD1457), Color(0xFF880E4F)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x44E91E63),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.assessment_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Sales Reports',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF69FF47),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'Live',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Animated Body ────────────────────────────────────────────────────────────
class _AnimatedReportBody extends StatefulWidget {
  final _ReportData report;
  const _AnimatedReportBody({required this.report});

  @override
  State<_AnimatedReportBody> createState() => _AnimatedReportBodyState();
}

class _AnimatedReportBodyState extends State<_AnimatedReportBody>
    with TickerProviderStateMixin {
  late final AnimationController _masterController;
  final List<Animation<double>> _sectionAnims = [];

  @override
  void initState() {
    super.initState();
    _masterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    for (var i = 0; i < 8; i++) {
      final start = (i * 0.08).clamp(0.0, 0.8);
      final end = (start + 0.25).clamp(0.0, 1.0);
      _sectionAnims.add(
        CurvedAnimation(
          parent: _masterController,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );
    }

    _masterController.forward();
  }

  @override
  void dispose() {
    _masterController.dispose();
    super.dispose();
  }

  Widget _slide(int index, Widget child) {
    return AnimatedBuilder(
      animation: _sectionAnims[index],
      builder: (context, _) => Opacity(
        opacity: _sectionAnims[index].value,
        child: Transform.translate(
          offset: Offset(0, 32 * (1 - _sectionAnims[index].value)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + kToolbarHeight + 28,
        16,
        40,
      ),
      children: [
        _slide(0, _HeaderPanel(report: r)),
        const SizedBox(height: 16),
        _slide(1, _SummaryGrid(report: r)),
        const SizedBox(height: 16),
        _slide(2, _SalesBarChart(days: r.dailySales)),
        const SizedBox(height: 16),
        _slide(
          3,
          _TopSellingSection(
            title: 'Top 10 Overall',
            icon: Icons.leaderboard_rounded,
            items: r.topAll,
            accentColor: const Color(0xFFE91E63),
          ),
        ),
        const SizedBox(height: 16),
        _slide(
          4,
          _TopSellingSection(
            title: 'Top 10 Items',
            icon: Icons.cake_rounded,
            items: r.topItems,
            accentColor: const Color(0xFF7B1FA2),
          ),
        ),
        const SizedBox(height: 16),
        _slide(
          5,
          _TopSellingSection(
            title: 'Top 10 Coffee',
            icon: Icons.local_cafe_rounded,
            items: r.topCoffee,
            accentColor: const Color(0xFF5D4037),
          ),
        ),
        const SizedBox(height: 16),
        _slide(
          6,
          _TopSellingSection(
            title: 'Top 10 Bundles',
            icon: Icons.inventory_2_rounded,
            items: r.topBundles,
            accentColor: const Color(0xFF00796B),
          ),
        ),
        const SizedBox(height: 16),
        _slide(7, _RecentTransactions(transactions: r.transactions)),
      ],
    );
  }
}

// ─── Header Panel ─────────────────────────────────────────────────────────────
class _HeaderPanel extends StatelessWidget {
  final _ReportData report;
  const _HeaderPanel({required this.report});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primary.withOpacity(0.07),
              ),
            ),
          ),
          Positioned(
            right: 20,
            bottom: -30,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primaryGlow.withOpacity(0.08),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE91E63), Color(0xFFAD1457)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: _primary.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.assessment_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sales Overview',
                      style: TextStyle(
                        color: _primaryDeep,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'All completed sales, top sellers & bundle details',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Summary Grid ─────────────────────────────────────────────────────────────
class _SummaryGrid extends StatelessWidget {
  final _ReportData report;
  const _SummaryGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _SummaryCardData(
        icon: Icons.payments_rounded,
        label: 'Net Sales',
        value: _money(report.netSales),
        color: const Color(0xFF2E7D32),
        gradientColors: const [Color(0xFF43A047), Color(0xFF2E7D32)],
      ),
      _SummaryCardData(
        icon: Icons.receipt_long_rounded,
        label: 'Orders',
        value: '${report.completedOrders}',
        color: _primaryDeep,
        gradientColors: const [Color(0xFFE91E63), Color(0xFFAD1457)],
      ),
      _SummaryCardData(
        icon: Icons.shopping_bag_rounded,
        label: 'Sold Qty',
        value: '${report.totalQuantity}',
        color: const Color(0xFF5C6BC0),
        gradientColors: const [Color(0xFF7986CB), Color(0xFF5C6BC0)],
      ),
      _SummaryCardData(
        icon: Icons.undo_rounded,
        label: 'Refunds',
        value: '${report.refunds}',
        color: const Color(0xFFE65100),
        gradientColors: const [Color(0xFFFF7043), Color(0xFFE64A19)],
      ),
      _SummaryCardData(
        icon: Icons.local_cafe_rounded,
        label: 'Coffee Sold',
        value: '${report.coffeeQuantity}',
        color: const Color(0xFF6D4C41),
        gradientColors: const [Color(0xFF8D6E63), Color(0xFF6D4C41)],
      ),
      _SummaryCardData(
        icon: Icons.inventory_2_rounded,
        label: 'Bundle Sold',
        value: '${report.bundleQuantity}',
        color: const Color(0xFF00796B),
        gradientColors: const [Color(0xFF26A69A), Color(0xFF00796B)],
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, index) {
        final card = cards[index];
        return _AnimatedSummaryCard(card: card, delay: index * 60);
      },
    );
  }
}

class _AnimatedSummaryCard extends StatefulWidget {
  final _SummaryCardData card;
  final int delay;
  const _AnimatedSummaryCard({required this.card, required this.delay});

  @override
  State<_AnimatedSummaryCard> createState() => _AnimatedSummaryCardState();
}

class _AnimatedSummaryCardState extends State<_AnimatedSummaryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = _ctrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressed = true);
        _ctrl.reverse();
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        _ctrl.forward();
      },
      onTapCancel: () {
        setState(() => _pressed = false);
        _ctrl.forward();
      },
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnim.value,
          child: child,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: card.color.withOpacity(0.18)),
            boxShadow: [
              BoxShadow(
                color: card.color.withOpacity(0.14),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned(
                  right: -12,
                  bottom: -12,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: card.color.withOpacity(0.08),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: card.gradientColors,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: card.color.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(card.icon, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                card.value,
                                maxLines: 1,
                                style: TextStyle(
                                  color: card.color,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              card.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bar Chart ────────────────────────────────────────────────────────────────
class _SalesBarChart extends StatefulWidget {
  final List<_DailySales> days;
  const _SalesBarChart({required this.days});

  @override
  State<_SalesBarChart> createState() => _SalesBarChartState();
}

class _SalesBarChartState extends State<_SalesBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxValue = widget.days.fold<double>(
      0,
      (max, day) => math.max(max, day.sales.abs()),
    );

    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.bar_chart_rounded,
            title: 'Sales Trend',
            accentColor: _primary,
          ),
          const SizedBox(height: 6),
          Text(
            'Last 7 days performance',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              return SizedBox(
                height: 200,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: widget.days.map((day) {
                    final ratio =
                        maxValue <= 0 ? 0.0 : day.sales / maxValue;
                    final maxBar = 145.0;
                    final barHeight =
                        math.max(8.0, ratio.abs() * maxBar) * _anim.value;
                    final isToday = _isSameDay(day.date, DateTime.now());
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (day.sales > 0)
                              Text(
                                day.sales >= 1000
                                    ? '${(day.sales / 1000).toStringAsFixed(1)}k'
                                    : day.sales.toStringAsFixed(0),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isToday
                                      ? _primaryDeep
                                      : Colors.grey.shade500,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            const SizedBox(height: 5),
                            Container(
                              width: double.infinity,
                              height: barHeight,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: isToday
                                      ? const [
                                          Color(0xFFFF4081),
                                          Color(0xFFE91E63),
                                          Color(0xFFAD1457),
                                        ]
                                      : const [
                                          Color(0xFFF48FB1),
                                          Color(0xFFE91E63),
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: isToday
                                    ? [
                                        BoxShadow(
                                          color: _primary.withOpacity(0.38),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : [],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: isToday
                                  ? BoxDecoration(
                                      color: _primary.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    )
                                  : null,
                              child: Text(
                                _shortDate(day.date),
                                style: TextStyle(
                                  color:
                                      isToday ? _primaryDeep : Colors.grey.shade400,
                                  fontSize: 10,
                                  fontWeight: isToday
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Top Selling Section ──────────────────────────────────────────────────────
class _TopSellingSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<_ItemMetric> items;
  final Color accentColor;

  const _TopSellingSection({
    required this.title,
    required this.icon,
    required this.items,
    required this.accentColor,
  });

  @override
  State<_TopSellingSection> createState() => _TopSellingSectionState();
}

class _TopSellingSectionState extends State<_TopSellingSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
  late final AnimationController _ctrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _expandAnim =
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final medal1 = const Color(0xFFFFD700);
    final medal2 = const Color(0xFFB0BEC5);
    final medal3 = const Color(0xFFFF8A65);

    Color rankColor(int rank) {
      if (rank == 1) return medal1;
      if (rank == 2) return medal2;
      if (rank == 3) return medal3;
      return Colors.grey.shade300;
    }

    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                _SectionTitle(
                  icon: widget.icon,
                  title: widget.title,
                  accentColor: widget.accentColor,
                ),
                AnimatedRotation(
                  turns: _expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          SizeTransition(
            sizeFactor: _expandAnim,
            child: Column(
              children: [
                const SizedBox(height: 14),
                if (widget.items.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.inbox_rounded,
                          color: Colors.grey.shade300,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'No sales data yet.',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...widget.items.asMap().entries.map((entry) {
                    final rank = entry.key + 1;
                    final item = entry.value;
                    final isTop3 = rank <= 3;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: isTop3
                            ? LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  widget.accentColor.withOpacity(0.08),
                                  Colors.white,
                                ],
                              )
                            : null,
                        color: isTop3 ? null : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isTop3
                              ? widget.accentColor.withOpacity(0.25)
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: isTop3
                                  ? LinearGradient(
                                      colors: [
                                        rankColor(rank),
                                        rankColor(rank).withOpacity(0.7),
                                      ],
                                    )
                                  : null,
                              color: isTop3 ? null : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: isTop3
                                  ? [
                                      BoxShadow(
                                        color: rankColor(rank).withOpacity(0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Text(
                              '$rank',
                              style: TextStyle(
                                color: isTop3 ? Colors.white : Colors.grey.shade500,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isTop3
                                        ? _primaryDeep
                                        : Colors.grey.shade700,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                if (item.variant.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.variant,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.accentColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${item.quantity} sold',
                                  style: TextStyle(
                                    color: widget.accentColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _money(item.revenue),
                                style: const TextStyle(
                                  color: Color(0xFF2E7D32),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recent Transactions ──────────────────────────────────────────────────────
class _RecentTransactions extends StatelessWidget {
  final List<_SaleTransaction> transactions;
  const _RecentTransactions({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final latest = transactions.take(12).toList();
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.receipt_long_rounded,
            title: 'Recent Transactions',
            accentColor: _primary,
          ),
          const SizedBox(height: 14),
          ...latest.asMap().entries.map((entry) {
            final sale = entry.value;
            return _TransactionTile(sale: sale);
          }),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final _SaleTransaction sale;
  const _TransactionTile({required this.sale});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: sale.isRefund
              ? const Color(0xFFFFCCBC)
              : const Color(0xFFF8BBD0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                color: sale.isRefund
                    ? const Color(0xFFE65100)
                    : const Color(0xFF2E7D32),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: sale.isRefund
                                  ? const Color(0xFFFBE9E7)
                                  : const Color(0xFFF3E5F5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              sale.isRefund ? 'REFUND' : 'SALE',
                              style: TextStyle(
                                color: sale.isRefund
                                    ? const Color(0xFFE65100)
                                    : _primaryDeep,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              sale.salesId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            _money(sale.total),
                            style: TextStyle(
                              color: sale.isRefund
                                  ? const Color(0xFFE65100)
                                  : const Color(0xFF2E7D32),
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 11,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${_dateTimeLabel(sale.date)}  •  ${sale.itemCount} item(s)',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sale.itemNames,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
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

// ─── Section Title ────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accentColor;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accentColor, accentColor.withOpacity(0.7)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: accentColor.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _primaryDeep,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Glass Panel ──────────────────────────────────────────────────────────────
class _GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
            color: _primaryDeep.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.8),
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─── Loading Shimmer ──────────────────────────────────────────────────────────
class _LoadingShimmer extends StatefulWidget {
  const _LoadingShimmer();

  @override
  State<_LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<_LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final shimmer = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.grey.shade200,
            Colors.grey.shade100,
            Colors.grey.shade200,
          ],
          stops: [
            (_anim.value - 0.3).clamp(0.0, 1.0),
            _anim.value.clamp(0.0, 1.0),
            (_anim.value + 0.3).clamp(0.0, 1.0),
          ],
        );

        return ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.of(context).padding.top + kToolbarHeight + 28,
            16,
            32,
          ),
          children: [
            _shimmerBox(shimmer, height: 80, radius: 24),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _shimmerBox(shimmer, height: 80, radius: 20)),
                const SizedBox(width: 12),
                Expanded(child: _shimmerBox(shimmer, height: 80, radius: 20)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _shimmerBox(shimmer, height: 80, radius: 20)),
                const SizedBox(width: 12),
                Expanded(child: _shimmerBox(shimmer, height: 80, radius: 20)),
              ],
            ),
            const SizedBox(height: 16),
            _shimmerBox(shimmer, height: 220, radius: 24),
            const SizedBox(height: 16),
            _shimmerBox(shimmer, height: 200, radius: 24),
          ],
        );
      },
    );
  }

  Widget _shimmerBox(
    LinearGradient shimmer, {
    required double height,
    required double radius,
  }) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: shimmer,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primary.withOpacity(0.15), _primaryLight.withOpacity(0.1)],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _primary, size: 38),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _primaryDeep,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data Models (unchanged logic) ───────────────────────────────────────────
class _ReportData {
  final double netSales;
  final int completedOrders;
  final int refunds;
  final int totalQuantity;
  final int coffeeQuantity;
  final int bundleQuantity;
  final List<_DailySales> dailySales;
  final List<_ItemMetric> topAll;
  final List<_ItemMetric> topItems;
  final List<_ItemMetric> topCoffee;
  final List<_ItemMetric> topBundles;
  final List<_SaleTransaction> transactions;

  const _ReportData({
    required this.netSales,
    required this.completedOrders,
    required this.refunds,
    required this.totalQuantity,
    required this.coffeeQuantity,
    required this.bundleQuantity,
    required this.dailySales,
    required this.topAll,
    required this.topItems,
    required this.topCoffee,
    required this.topBundles,
    required this.transactions,
  });

  factory _ReportData.fromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    _CoffeeRefs coffeeRefs,
  ) {
    final all = <String, _ItemMetric>{};
    final items = <String, _ItemMetric>{};
    final coffee = <String, _ItemMetric>{};
    final bundles = <String, _ItemMetric>{};
    final daily = <DateTime, double>{};
    final transactions = <_SaleTransaction>[];

    final now = DateTime.now();
    for (var i = 6; i >= 0; i--) {
      final date = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      daily[date] = 0;
    }

    var netSales = 0.0;
    var completedOrders = 0;
    var refunds = 0;
    var totalQuantity = 0;
    var coffeeQuantity = 0;
    var bundleQuantity = 0;

    for (final doc in docs) {
      final data = doc.data();
      final type = data['type']?.toString().toLowerCase() ?? 'sale';
      final status = data['status']?.toString().toLowerCase() ?? '';
      final isRefund = type == 'refund' || status == 'refund';
      final sign = isRefund ? -1 : 1;
      final total = _numValue(data['total']);
      final timestamp = _dateValue(data['timestamp']) ?? DateTime.now();
      final itemsList = (data['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      netSales += total;
      if (isRefund) {
        refunds++;
      } else {
        completedOrders++;
      }

      final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
      if (daily.containsKey(day)) {
        daily[day] = (daily[day] ?? 0) + total;
      }

      final names = <String>[];
      var saleItemCount = 0;

      for (final item in itemsList) {
        final name = item['name']?.toString().trim();
        if (name == null || name.isEmpty) continue;
        final variant = item['variant']?.toString().trim() ?? '';
        final category = item['category']?.toString().toLowerCase() ?? '';
        final sourceId = item['sourceInventoryId']?.toString() ?? '';
        final quantity = _intValue(item['quantity'], fallback: 1);
        final price = _numValue(item['price']);
        final signedQuantity = quantity * sign;
        final signedRevenue = price * quantity * sign;
        final isBundle = item['isBundle'] == true;
        final isCoffee = item['isCoffee'] == true ||
            category.contains('coffee') ||
            coffeeRefs.matches(name: name, sourceId: sourceId);
        final variantLabel = variant.isEmpty ? '' : variant;
        final key = '${name.toLowerCase()}|${variantLabel.toLowerCase()}';

        totalQuantity += signedQuantity;
        saleItemCount += quantity;
        names.add(variantLabel.isEmpty ? name : '$name ($variantLabel)');

        final metric = all.putIfAbsent(
          key,
          () => _ItemMetric(name: name, variant: variantLabel),
        );
        metric.add(quantity: signedQuantity, revenue: signedRevenue);

        if (isBundle) {
          bundleQuantity += signedQuantity;
          final bundleMetric = bundles.putIfAbsent(
            key,
            () => _ItemMetric(name: name, variant: variantLabel),
          );
          bundleMetric.add(quantity: signedQuantity, revenue: signedRevenue);
        } else if (isCoffee) {
          coffeeQuantity += signedQuantity;
          final coffeeMetric = coffee.putIfAbsent(
            key,
            () => _ItemMetric(name: name, variant: variantLabel),
          );
          coffeeMetric.add(quantity: signedQuantity, revenue: signedRevenue);
        } else {
          final itemMetric = items.putIfAbsent(
            key,
            () => _ItemMetric(name: name, variant: variantLabel),
          );
          itemMetric.add(quantity: signedQuantity, revenue: signedRevenue);
        }
      }

      transactions.add(
        _SaleTransaction(
          salesId: data['salesId']?.toString() ?? doc.id,
          date: timestamp,
          total: total,
          itemCount: saleItemCount,
          itemNames: names.isEmpty ? 'No item details' : names.join(', '),
          isRefund: isRefund,
        ),
      );
    }

    transactions.sort((a, b) => b.date.compareTo(a.date));

    return _ReportData(
      netSales: netSales,
      completedOrders: completedOrders,
      refunds: refunds,
      totalQuantity: math.max(0, totalQuantity),
      coffeeQuantity: math.max(0, coffeeQuantity),
      bundleQuantity: math.max(0, bundleQuantity),
      dailySales: daily.entries
          .map((e) => _DailySales(date: e.key, sales: e.value))
          .toList(),
      topAll: _topTen(all),
      topItems: _topTen(items),
      topCoffee: _topTen(coffee),
      topBundles: _topTen(bundles),
      transactions: transactions,
    );
  }
}

class _CoffeeRefs {
  final Set<String> ids;
  final Set<String> names;

  const _CoffeeRefs({required this.ids, required this.names});

  factory _CoffeeRefs.fromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final ids = <String>{};
    final names = <String>{};
    for (final doc in docs) {
      final data = doc.data();
      ids.add(doc.id.toLowerCase());
      final coffeeId = data['coffeeId']?.toString().trim().toLowerCase();
      if (coffeeId != null && coffeeId.isNotEmpty) ids.add(coffeeId);
      final name = data['name']?.toString().trim().toLowerCase();
      if (name != null && name.isNotEmpty) names.add(name);
    }
    return _CoffeeRefs(ids: ids, names: names);
  }

  bool matches({required String name, required String sourceId}) {
    final source = sourceId.trim().toLowerCase();
    final itemName = name.trim().toLowerCase();
    return (source.isNotEmpty && ids.contains(source)) ||
        names.contains(itemName);
  }
}

class _ItemMetric {
  final String name;
  final String variant;
  int quantity = 0;
  double revenue = 0;

  _ItemMetric({required this.name, required this.variant});

  void add({required int quantity, required double revenue}) {
    this.quantity += quantity;
    this.revenue += revenue;
  }
}

class _DailySales {
  final DateTime date;
  final double sales;

  const _DailySales({required this.date, required this.sales});
}

class _SaleTransaction {
  final String salesId;
  final DateTime date;
  final double total;
  final int itemCount;
  final String itemNames;
  final bool isRefund;

  const _SaleTransaction({
    required this.salesId,
    required this.date,
    required this.total,
    required this.itemCount,
    required this.itemNames,
    required this.isRefund,
  });
}

class _SummaryCardData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final List<Color> gradientColors;

  const _SummaryCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.gradientColors,
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
List<_ItemMetric> _topTen(Map<String, _ItemMetric> source) {
  final values = source.values
      .where((item) => item.quantity > 0 || item.revenue > 0)
      .toList();
  values.sort((a, b) {
    final q = b.quantity.compareTo(a.quantity);
    return q != 0 ? q : b.revenue.compareTo(a.revenue);
  });
  return values.take(10).toList();
}

double _numValue(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(
        value?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '',
      ) ??
      0.0;
}

int _intValue(dynamic value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime? _dateValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

String _money(double value) {
  final sign = value < 0 ? '-' : '';
  return '${sign}PHP ${value.abs().toStringAsFixed(2)}';
}

String _shortDate(DateTime date) => '${date.month}/${date.day}';

String _dateTimeLabel(DateTime date) {
  final hour = date.hour == 0
      ? 12
      : date.hour > 12
          ? date.hour - 12
          : date.hour;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '${date.month}/${date.day}/${date.year} $hour:$minute $period';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
