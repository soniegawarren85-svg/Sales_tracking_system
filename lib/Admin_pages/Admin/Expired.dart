import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pink_theme.dart';

// ──────────────────────────────────────────────────────────────────────────────
// FADE + SLIDE ANIMATION WRAPPER
// ──────────────────────────────────────────────────────────────────────────────

class _FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  const _FadeSlideIn({required this.child, required this.index});

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.16),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// PULSING WARNING ICON
// ──────────────────────────────────────────────────────────────────────────────

class _PulsingWarning extends StatefulWidget {
  const _PulsingWarning();

  @override
  State<_PulsingWarning> createState() => _PulsingWarningState();
}

class _PulsingWarningState extends State<_PulsingWarning>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.88,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _opacity = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF5252).withOpacity(0.45),
                blurRadius: 12,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// MAIN PAGE
// ──────────────────────────────────────────────────────────────────────────────

class ExpiredPage extends StatefulWidget {
  const ExpiredPage({super.key});

  @override
  State<ExpiredPage> createState() => _ExpiredPageState();
}

class _ExpiredPageState extends State<ExpiredPage>
    with TickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;

  late AnimationController _headerAnim;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _headerFade = CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _headerAnim, curve: Curves.easeOutCubic));
    _headerAnim.forward();
  }

  @override
  void dispose() {
    _headerAnim.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  int _getDaysOverdue(String expirationDate) {
    try {
      final expiryDate = DateTime.parse(expirationDate);
      final today = DateTime.now();
      return today.difference(expiryDate).inDays;
    } catch (e) {
      return 0;
    }
  }

  bool _isExpired(String expirationDate) {
    try {
      final expiryDate = DateTime.parse(expirationDate);
      final today = DateTime.now();
      return expiryDate.isBefore(today) ||
          (expiryDate.year == today.year &&
              expiryDate.month == today.month &&
              expiryDate.day == today.day);
    } catch (e) {
      return false;
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  String _overdueLabel(int days) {
    if (days == 0) return 'Expired Today';
    if (days == 1) return 'Expired';
    return '$days Days Overdue';
  }

  Color _overdueColor(int days) {
    if (days == 0) return const Color(0xFFFF9800);
    if (days <= 3) return const Color(0xFFFF5722);
    return const Color(0xFFD32F2F);
  }

  Future<void> _restoreVariant(Map<String, dynamic> variant) async {
    try {
      final categoryId = variant['categoryId']?.toString() ?? '';
      if (categoryId.isEmpty) return;
      await _firestore.collection('sales_inventory').doc(categoryId).update({
        'expiredItems': FieldValue.arrayRemove([variant]),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text(
                  'Item restored to active inventory.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            backgroundColor: PinkTheme.successGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error restoring variant: $e');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PinkTheme.scaffoldBg,
      body: Column(
        children: [
          // ── ANIMATED GRADIENT HEADER ────────────────────────────────────────
          SlideTransition(
            position: _headerSlide,
            child: FadeTransition(
              opacity: _headerFade,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFB71C1C), Color(0xFFFF5252)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(34),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x55D32F2F),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back + Title Row
                        Row(
                          children: [
                            Material(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap: () => Navigator.pop(context),
                                borderRadius: BorderRadius.circular(14),
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Expired Items',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Track and manage expired products',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.75),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Header badge icon
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // ── Stats Row ──────────────────────────────────────────
                        StreamBuilder<QuerySnapshot>(
                          stream: _firestore
                              .collection('sales_inventory')
                              .snapshots(),
                          builder: (context, snapshot) {
                            int total = 0;
                            int todayCount = 0;
                            if (snapshot.hasData) {
                              for (var doc in snapshot.data!.docs) {
                                final data = doc.data() as Map<String, dynamic>;
                                if (data['isDeleted'] == true) continue;
                                final items =
                                    (data['items'] as List<dynamic>?) ?? [];
                                for (var item in items) {
                                  final itemData = item as Map<String, dynamic>;
                                  final expiry =
                                      itemData['expirationDate']?.toString() ??
                                      '';
                                  if (_isExpired(expiry)) {
                                    total++;
                                    final days = _getDaysOverdue(expiry);
                                    if (days == 0) todayCount++;
                                  }
                                }
                              }
                            }
                            return Row(
                              children: [
                                _headerStatChip(
                                  icon: Icons.inventory_2_rounded,
                                  label: '$total Total Expired',
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 10),
                                if (todayCount > 0)
                                  _headerStatChip(
                                    icon: Icons.today_rounded,
                                    label: '$todayCount Expired Today',
                                    color: const Color(0xFFFFE082),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── BODY ────────────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('sales_inventory').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 52,
                          height: 52,
                          child: CircularProgressIndicator(
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFFFF5252),
                            ),
                            strokeWidth: 3.5,
                            backgroundColor: const Color(
                              0xFFFF5252,
                            ).withOpacity(0.12),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Scanning inventory...',
                          style: TextStyle(
                            color: PinkTheme.textMid,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: PinkTheme.deleteRed.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.error_rounded,
                            color: PinkTheme.deleteRed,
                            size: 44,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(
                            color: PinkTheme.deleteRed,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                // Build expired list
                List<Map<String, dynamic>> expiredVariants = [];
                final docs = snapshot.data?.docs ?? [];

                for (var doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['isDeleted'] == true) continue;
                  final categoryName = data['name']?.toString() ?? '';
                  final categoryId = doc.id;
                  final items = (data['items'] as List<dynamic>?) ?? [];
                  for (var item in items) {
                    final itemData = item as Map<String, dynamic>;
                    final expiryDate =
                        itemData['expirationDate']?.toString() ?? '';
                    if (_isExpired(expiryDate)) {
                      expiredVariants.add({
                        'categoryId': categoryId,
                        'categoryName': categoryName,
                        'id': itemData['id']?.toString() ?? '',
                        'name': itemData['name']?.toString() ?? '',
                        'price': itemData['price']?.toString() ?? '0',
                        'stock': itemData['stock']?.toString() ?? '0',
                        'startingStock':
                            itemData['startingStock']?.toString() ?? '0',
                        'expirationDate': expiryDate,
                      });
                    }
                  }
                }

                // ── EMPTY STATE ────────────────────────────────────────────────
                if (expiredVariants.isEmpty) {
                  return _EmptyExpiredState();
                }

                // ── LIST ───────────────────────────────────────────────────────
                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  itemCount: expiredVariants.length,
                  itemBuilder: (context, index) {
                    final variant = expiredVariants[index];
                    final daysOverdue = _getDaysOverdue(
                      variant['expirationDate'],
                    );
                    final overdueBadgeColor = _overdueColor(daysOverdue);
                    final overdueText = _overdueLabel(daysOverdue);

                    return _FadeSlideIn(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _ExpiredCard(
                          variant: variant,
                          daysOverdue: daysOverdue,
                          overdueBadgeColor: overdueBadgeColor,
                          overdueText: overdueText,
                          formatDate: _formatDate,
                          onRestore: () => _restoreVariant(variant),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerStatChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// EXPIRED CARD WIDGET
// ──────────────────────────────────────────────────────────────────────────────

class _ExpiredCard extends StatefulWidget {
  final Map<String, dynamic> variant;
  final int daysOverdue;
  final Color overdueBadgeColor;
  final String overdueText;
  final String Function(String) formatDate;
  final VoidCallback onRestore;

  const _ExpiredCard({
    required this.variant,
    required this.daysOverdue,
    required this.overdueBadgeColor,
    required this.overdueText,
    required this.formatDate,
    required this.onRestore,
  });

  @override
  State<_ExpiredCard> createState() => _ExpiredCardState();
}

class _ExpiredCardState extends State<_ExpiredCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverCtrl;
  late Animation<double> _elevation;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _elevation = Tween<double>(begin: 0, end: 1).animate(_hoverCtrl);
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.variant['name']?.toString() ?? '';
    final categoryName = widget.variant['categoryName']?.toString() ?? '';
    final price = widget.variant['price']?.toString() ?? '0';
    final stock = widget.variant['stock']?.toString() ?? '0';
    final startingStock = widget.variant['startingStock']?.toString() ?? '0';
    final expiryDate = widget.variant['expirationDate']?.toString() ?? '';
    final variantId = widget.variant['id']?.toString() ?? '';

    return GestureDetector(
      onTapDown: (_) => _hoverCtrl.forward(),
      onTapUp: (_) => _hoverCtrl.reverse(),
      onTapCancel: () => _hoverCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _elevation,
        builder: (context, child) => Transform.scale(
          scale: 1.0 - (_elevation.value * 0.015),
          child: child,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: widget.overdueBadgeColor.withOpacity(0.28),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.overdueBadgeColor.withOpacity(0.12),
                blurRadius: 20,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── CARD HEADER ─────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.overdueBadgeColor.withOpacity(0.12),
                      widget.overdueBadgeColor.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(25),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: widget.overdueBadgeColor.withOpacity(0.14),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Pulsing icon
                    const _PulsingWarning(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: PinkTheme.textDark,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.folder_rounded,
                                size: 11,
                                color: PinkTheme.textLight,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  categoryName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: PinkTheme.textLight,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Overdue badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: widget.overdueBadgeColor,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: widget.overdueBadgeColor.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        widget.overdueText,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── CARD BODY ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Stats Grid ─────────────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _statTile(
                            icon: Icons.inventory_2_rounded,
                            label: 'Remaining',
                            value: '$stock pcs',
                            iconColor: const Color(0xFF1565C0),
                            bgColor: const Color(0xFFE3F2FD),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statTile(
                            icon: Icons.shopping_bag_rounded,
                            label: 'Starting',
                            value: '$startingStock pcs',
                            iconColor: const Color(0xFF6A1B9A),
                            bgColor: const Color(0xFFF3E5F5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _statTile(
                            icon: Icons.payments_rounded,
                            label: 'Price',
                            value: '₱$price',
                            iconColor: const Color(0xFF2E7D32),
                            bgColor: const Color(0xFFE8F5E9),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statTile(
                            icon: Icons.event_rounded,
                            label: 'Expired On',
                            value: widget.formatDate(expiryDate),
                            iconColor: widget.overdueBadgeColor,
                            bgColor: widget.overdueBadgeColor.withOpacity(0.10),
                          ),
                        ),
                      ],
                    ),

                    if (variantId.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: PinkTheme.scaffoldBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: PinkTheme.divider,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.fingerprint_rounded,
                              size: 13,
                              color: PinkTheme.textLight,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'ID: $variantId',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: PinkTheme.textMid,
                                  letterSpacing: 0.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // ── Notice Banner ─────────────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.overdueBadgeColor.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: widget.overdueBadgeColor.withOpacity(0.22),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: widget.overdueBadgeColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This item has expired and is hidden from active inventory. It is only visible here.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: widget.overdueBadgeColor.withOpacity(
                                  0.85,
                                ),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Divider ───────────────────────────────────────────────
                    Divider(
                      color: PinkTheme.divider.withOpacity(0.6),
                      height: 1,
                    ),

                    const SizedBox(height: 14),

                    // ── Action Row ────────────────────────────────────────────
                    Row(
                      children: [
                        // Loss indicator chip
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: PinkTheme.scaffoldBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: PinkTheme.divider,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.trending_down_rounded,
                                  size: 15,
                                  color: Color(0xFFD32F2F),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Est. Loss',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: PinkTheme.textLight,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '₱${(double.tryParse(price) ?? 0) * (int.tryParse(stock) ?? 0)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFD32F2F),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 13, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: iconColor.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: iconColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// ANIMATED EMPTY STATE
// ──────────────────────────────────────────────────────────────────────────────

class _EmptyExpiredState extends StatefulWidget {
  @override
  State<_EmptyExpiredState> createState() => _EmptyExpiredStateState();
}

class _EmptyExpiredStateState extends State<_EmptyExpiredState>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scale,
                child: Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withOpacity(0.22),
                        blurRadius: 28,
                        spreadRadius: 4,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    color: Color(0xFF2E7D32),
                    size: 58,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'All Clear!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: PinkTheme.textDark,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'No Expired Items Found',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF4CAF50).withOpacity(0.3),
                  ),
                ),
                child: const Text(
                  'All your products are within their expiration dates. Keep it up!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF388E3C),
                    fontWeight: FontWeight.w500,
                    height: 1.5,
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
