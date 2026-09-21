import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AllSalesAnalyticsPage extends StatefulWidget {
  const AllSalesAnalyticsPage({super.key});
  @override
  State<AllSalesAnalyticsPage> createState() => _AllSalesAnalyticsPageState();
}

class _AllSalesAnalyticsPageState extends State<AllSalesAnalyticsPage> {
  String _period = 'Day';
  String _category = 'All';
  String _ranking = 'All';

  static const _primary = Color(0xFFC2105C);
  static const _primaryLight = Color(0xFFF48FB1);
  static const _accent = Color(0xFFE91E63);
  static const _bg = Color(0xFFFFF3F7);
  static const _textDark = Color(0xFF7A1845);

  double _money(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  bool _isExpired(String value) {
    final expiry = DateTime.tryParse(value.trim());
    if (expiry == null) return false;
    final today = DateTime.now();
    return !expiry.isAfter(DateTime(today.year, today.month, today.day));
  }

  Set<String> _activeItemKeys(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final keys = <String>{};
    for (final doc in docs) {
      final data = doc.data();
      if (data['isDeleted'] == true) continue;
      final sourceId = doc.id.toLowerCase();
      final rootName = data['name']?.toString().trim().toLowerCase() ?? '';
      final variants = (data['items'] as List<dynamic>? ?? []).whereType<Map>();
      if (variants.isEmpty && rootName.isNotEmpty) {
        keys.add('$sourceId|$rootName|');
        keys.add('$rootName|');
      }
      for (final raw in variants) {
        final item = Map<String, dynamic>.from(raw);
        if (_isExpired(item['expirationDate']?.toString() ?? '')) continue;
        final name =
            (item['name']?.toString().trim().isNotEmpty == true
                    ? item['name']
                    : data['name'])
                ?.toString()
                .trim()
                .toLowerCase() ??
            '';
        final variant =
            item['variant']?.toString().trim().toLowerCase() ??
            item['id']?.toString().trim().toLowerCase() ??
            '';
        if (name.isNotEmpty) {
          keys.add('$sourceId|$name|$variant');
          keys.add('$name|$variant');
        }
      }
    }
    return keys;
  }

  bool _isActiveItem(Map<String, dynamic> item, Set<String> activeKeys) {
    if (item['isDeleted'] == true ||
        _isExpired(item['expirationDate']?.toString() ?? '')) {
      return false;
    }
    // Coffee products are stored separately from sales_inventory. Their sale
    // records carry their own marker, so they must not be rejected by the
    // category inventory key check above.
    final isCoffee = item['isCoffee'] == true ||
        (item['coffeeId']?.toString().trim().isNotEmpty ?? false);
    if (isCoffee) return true;
    final source =
        item['sourceInventoryId']?.toString().trim().toLowerCase() ?? '';
    final name = item['name']?.toString().trim().toLowerCase() ?? '';
    final variant = item['variant']?.toString().trim().toLowerCase() ?? '';
    if (source.isEmpty) {
      return activeKeys.contains('$name|$variant') ||
          activeKeys.contains('$name|');
    }
    return activeKeys.contains('$source|$name|$variant') ||
        activeKeys.contains('$name|$variant') ||
        activeKeys.any((key) => key.startsWith('$source|'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(
      elevation: 0,
      centerTitle: false,
      title: const Text(
        'Sales Analytics',
        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
      ),
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_primary, _accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      foregroundColor: Colors.white,
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('completed_sales')
          .snapshots(),
      builder: (context, snapshot) {
        final sales =
            snapshot.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('sales_inventory')
              .snapshots(),
          builder: (context, inventorySnapshot) {
            if (!snapshot.hasData || !inventorySnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: _primary),
              );
            }

            final activeKeys = _activeItemKeys(
              inventorySnapshot.data?.docs ?? const [],
            );
            final now = DateTime.now();
            final items = <String, _SoldItem>{};
            final points = _chartBuckets(now);
            for (final sale in sales) {
              final data = sale.data();
              final timestamp = data['timestamp'] is Timestamp
                  ? (data['timestamp'] as Timestamp).toDate()
                  : null;
              if (timestamp == null ||
                  !_isInSelectedChartRange(timestamp, now)) {
                continue;
              }
              final key = _periodKey(timestamp);
              var saleTotal = 0.0;
              for (final raw
                  in (data['items'] as List<dynamic>? ?? []).whereType<Map>()) {
                final item = Map<String, dynamic>.from(raw);
                if (!_isActiveItem(item, activeKeys)) continue;
                final name = item['variant']?.toString().isNotEmpty == true
                    ? '${item['name']} (${item['variant']})'
                    : item['name']?.toString() ?? 'Item';
                final qty = _money(item['quantity']);
                  saleTotal += _money(item['price']) * qty;
                final kind = item['isBundle'] == true
                    ? 'Bundle'
                    : (item['isCoffee'] == true ? 'Coffee' : 'Categories');
                final current = items[name] ?? _SoldItem(name, 0, 0);
                items[name] = _SoldItem(
                  name,
                  current.quantity + qty,
                  current.revenue + _money(item['price']) * qty,
                  kind,
                );
              }
              if (points.containsKey(key)) {
                points[key] = (points[key] ?? 0) + saleTotal;
              }
            }
            final sorted = items.values.toList()
              ..sort((a, b) => b.quantity.compareTo(a.quantity));
            final categoryItems = sorted
                .where((item) => _category == 'All' || item.kind == _category)
                .toList();
            final filtered = _ranking == 'Top Selling'
                ? categoryItems.take(5).toList()
                : _ranking == 'Low Selling'
                ? (categoryItems.reversed.take(5).toList())
                : categoryItems;
              final chart = points.entries.toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _sectionTitle('Sales', Icons.receipt_long_rounded),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: ['Day', 'Week', 'Month']
                      .map((p) => _chip(p, _period == p, () => setState(() => _period = p)))
                      .toList(),
                ),
                const SizedBox(height: 14),
                _card(
                  child: SizedBox(
                    height: 210,
                    child: _SalesBars(values: chart),
                  ),
                ),
                const SizedBox(height: 16),
                _sectionTitle('Best-Selling Items', Icons.local_fire_department_rounded),
                const SizedBox(height: 14),
                _filterLabel('Item range'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('All', _category == 'All', () => setState(() => _category = 'All'), icon: Icons.apps_rounded),
                    _chip('Categories', _category == 'Categories', () => setState(() => _category = 'Categories'), icon: Icons.category_rounded),
                    _chip('Bundle', _category == 'Bundle', () => setState(() => _category = 'Bundle'), icon: Icons.card_giftcard_rounded),
                    _chip('Coffee', _category == 'Coffee', () => setState(() => _category = 'Coffee'), icon: Icons.coffee_rounded),
                  ],
                ),
                const SizedBox(height: 14),
                _filterLabel('Ranking'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('All', _ranking == 'All', () => setState(() => _ranking = 'All')),
                    _chip('Top Selling', _ranking == 'Top Selling', () => setState(() => _ranking = 'Top Selling'), icon: Icons.trending_up_rounded),
                    _chip('Low Selling', _ranking == 'Low Selling', () => setState(() => _ranking = 'Low Selling'), icon: Icons.trending_down_rounded),
                  ],
                ),
                const SizedBox(height: 16),
                if (filtered.isEmpty)
                  _card(
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No items match this filter yet.',
                          style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  )
                else
                  ...filtered.asMap().entries.map(
                    (entry) => _StaggeredFadeIn(
                      index: entry.key,
                      child: _topTile(entry.key + 1, entry.value),
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );

  Widget _saleTile(Map<String, dynamic> sale) {
    final salesId = sale['salesId']?.toString() ?? 'Receipt';
    final timestamp = sale['timestamp'] is Timestamp
        ? (sale['timestamp'] as Timestamp).toDate().toLocal()
        : null;
    final items = (sale['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final total = _money(sale['total']);
    final discount = _money(sale['discount']);
    final discountType = sale['discountType']?.toString().trim() ?? '';
    final proofId = sale['discountProofId']?.toString().trim() ?? '';
    final payment = sale['paymentMode']?.toString().trim() ?? 'Cash';
    final gcashId = sale['gcashTransactionId']?.toString().trim() ?? '';
    final paid = _money(sale['paidAmount']);
    final change = _money(sale['change']);
    final type = sale['type']?.toString().trim().toLowerCase() ?? '';
    final status = sale['status']?.toString().trim().toLowerCase() ?? '';
    final isRefund = type == 'refund' || status == 'refund';
    final reason = (sale['reason'] ?? sale['refundReason'])?.toString().trim() ?? '';
    final source = sale['source']?.toString().trim() ?? '';
    final hasDiscount = discount > 0.01 && discountType.toLowerCase() != 'none';
    final hasRefund = isRefund || sale['fullyRefunded'] == true ||
        items.any((item) => _money(item['refunded']) > 0);
    final color = hasRefund ? Colors.red.shade700 : Colors.green.shade700;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isRefund ? Icons.replay_rounded : Icons.receipt_long_rounded, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(salesId, style: const TextStyle(color: _textDark, fontWeight: FontWeight.w900)),
                      if (timestamp != null)
                        Text(
                          '${timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12}:${timestamp.minute.toString().padLeft(2, '0')} ${timestamp.hour >= 12 ? 'PM' : 'AM'}',
                          style: const TextStyle(color: Colors.black45, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₱${total.toStringAsFixed(2)}', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
                    Text(isRefund ? 'Refunded' : hasRefund ? 'Refund activity' : 'Completed', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const Divider(height: 22),
              ...items.map((item) {
                final refunded = _money(item['refunded']);
                final name = item['name']?.toString() ?? 'Item';
                final variant = item['variant']?.toString() ?? '';
                final label = '${_money(item['quantity']).toStringAsFixed(0)}x $name${variant.isNotEmpty ? ' ($variant)' : ''}${refunded > 0 ? ' · refunded ${refunded.toStringAsFixed(0)}' : ''}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(label, style: TextStyle(color: refunded > 0 ? Colors.red.shade700 : _textDark, fontWeight: FontWeight.w700))),
                      Text('₱${(_money(item['price']) * _money(item['quantity'])).toStringAsFixed(2)}', style: TextStyle(color: refunded > 0 ? Colors.red.shade700 : Colors.black54, fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  _saleDetail('Payment', payment == 'GCash' && gcashId.isNotEmpty ? 'GCash - $gcashId' : payment),
                  _saleDetail('Customer Paid', '₱${paid.toStringAsFixed(2)}'),
                  if (hasDiscount) _saleDetail('Discount ($discountType)', '-₱${discount.toStringAsFixed(2)}', color: Colors.green.shade700),
                  if (proofId.isNotEmpty) _saleDetail(discountType.isEmpty ? 'Discount ID' : '$discountType ID', proofId),
                  if (hasRefund && reason.isNotEmpty) _saleDetail('Refund Reason${source.isNotEmpty ? ' ($source)' : ''}', reason, color: Colors.red.shade700),
                  _saleDetail('Change', '₱${change.toStringAsFixed(2)}'),
                  _saleDetail(isRefund ? 'Refund Amount' : 'Total', '₱${total.toStringAsFixed(2)}', color: color, strong: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saleDetail(String label, String value, {Color? color, bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: TextStyle(color: Colors.black54, fontSize: strong ? 12 : 11, fontWeight: strong ? FontWeight.w800 : FontWeight.w600))),
          const SizedBox(width: 8),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(color: color ?? _textDark, fontSize: strong ? 13 : 11, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  Widget _sectionTitle(String label, IconData icon) => Row(
    children: [
      Icon(icon, color: _primary, size: 20),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(
          color: _primary,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );

  Widget _filterLabel(String label) => Text(
    label,
    style: const TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w700),
  );

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );

  Widget _chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [_primary, _accent])
              : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFFF3C6D8),
            width: 1.2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _primary.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: selected ? Colors.white : _primary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: selected ? Colors.white : _textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, double> _chartBuckets(DateTime now) {
    final buckets = <String, double>{};
    if (_period == 'Day') {
      for (var hour = 0; hour < 24; hour++) {
        buckets['$hour:00'] = 0;
      }
    } else if (_period == 'Week') {
      final start = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      for (var day = 0; day < 7; day++) {
        final date = start.add(Duration(days: day));
        buckets['${date.month}/${date.day}'] = 0;
      }
    } else {
      final currentMonth = DateTime(now.year, now.month);
      for (var offset = 11; offset >= 0; offset--) {
        final month = DateTime(currentMonth.year, currentMonth.month - offset);
        buckets['${month.year}-${month.month.toString().padLeft(2, '0')}'] = 0;
      }
    }
    return buckets;
  }

  bool _isInSelectedChartRange(DateTime date, DateTime now) {
    if (_period == 'Day') {
      return date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    }
    if (_period == 'Week') {
      final start = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      final day = DateTime(date.year, date.month, date.day);
      return !day.isBefore(start) &&
          day.isBefore(start.add(const Duration(days: 7)));
    }
    final firstMonth = DateTime(now.year, now.month - 11);
    final month = DateTime(date.year, date.month);
    return !month.isBefore(firstMonth) &&
        !month.isAfter(DateTime(now.year, now.month));
  }

  String _periodKey(DateTime date) {
    if (_period == 'Day') return '${date.hour}:00';
    if (_period == 'Month') {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}';
    }
    return '${date.month}/${date.day}';
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'Bundle':
        return Icons.card_giftcard_rounded;
      case 'Coffee':
        return Icons.coffee_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Widget _topTile(int rank, _SoldItem item) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: rank <= 3
                    ? const LinearGradient(colors: [_primary, _accent])
                    : const LinearGradient(colors: [Color(0xFFFFE0EC), Color(0xFFFFE0EC)]),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: rank <= 3 ? Colors.white : _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
        ),
        subtitle: Row(
          children: [
            Icon(_kindIcon(item.kind), size: 13, color: Colors.black45),
            const SizedBox(width: 4),
            Text('${item.quantity.toStringAsFixed(0)} sold · ${item.kind}',
                style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          ],
        ),
        trailing: Text(
          '₱${item.revenue.toStringAsFixed(2)}',
          style: const TextStyle(
            color: _primary,
            fontWeight: FontWeight.w900,
            fontSize: 14.5,
          ),
        ),
      ),
    ),
  );
}

class _SoldItem {
  final String name;
  final double quantity;
  final double revenue;
  final String kind;
  const _SoldItem(
    this.name,
    this.quantity,
    this.revenue, [
    this.kind = 'Categories',
  ]);
}

/// Fades and slides a child in after a short staggered delay based on index.
class _StaggeredFadeIn extends StatefulWidget {
  final Widget child;
  final int index;
  const _StaggeredFadeIn({required this.child, required this.index});

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.08),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _SalesBars extends StatelessWidget {
  final List<MapEntry<String, double>> values;
  const _SalesBars({required this.values});

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Center(
        child: Text('No sales data yet.', style: TextStyle(color: Colors.black45)),
      );
    }
    final max = values.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    const barAreaHeight = 150.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: values.map((entry) {
        final height = max == 0 ? 0.0 : (entry.value / max) * barAreaHeight;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: barAreaHeight,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: height),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (context, animatedHeight, child) => Container(
                        height: animatedHeight,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xFFC2105C), Color(0xFFE91E63)],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8, color: Colors.black54),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}