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
    backgroundColor: const Color(0xFFFFF0F5),
    appBar: AppBar(
      title: const Text(
        'All Sales Records',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      backgroundColor: const Color(0xFFC2105C),
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
              if (saleTotal > 0 && points.containsKey(key)) {
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
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFC2105C), Color(0xFFF48FB1)],
                    ),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sales Analytics',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₱${points.values.fold<double>(0, (a, b) => a + b).toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'Current active items only',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Sales Graph',
                  style: TextStyle(
                    color: Color(0xFFC2105C),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['Day', 'Week', 'Month']
                      .map(
                        (p) => ChoiceChip(
                          label: Text(p),
                          selected: _period == p,
                          onSelected: (_) => setState(() => _period = p),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 210,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: _SalesBars(values: chart),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Best-Selling Items',
                  style: TextStyle(
                    color: Color(0xFFC2105C),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Item range',
                  style: TextStyle(
                    color: Color(0xFF7A1845),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['All', 'Categories', 'Bundle', 'Coffee']
                      .map(
                        (value) => ChoiceChip(
                          label: Text(value),
                          selected: _category == value,
                          onSelected: (_) => setState(() => _category = value),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Ranking',
                  style: TextStyle(
                    color: Color(0xFF7A1845),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['All', 'Top Selling', 'Low Selling']
                      .map(
                        (value) => ChoiceChip(
                          label: Text(value),
                          selected: _ranking == value,
                          onSelected: (_) => setState(() => _ranking = value),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
                ...filtered.asMap().entries.map(
                  (entry) => _topTile(entry.key + 1, entry.value),
                ),
              ],
            );
          },
        );
      },
    ),
  );

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

  Widget _topTile(int rank, _SoldItem item) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFFFE0EC),
        child: Text(
          '$rank',
          style: const TextStyle(
            color: Color(0xFFC2105C),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      title: Text(
        item.name,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text('${item.quantity.toStringAsFixed(0)} sold'),
      trailing: Text(
        '₱${item.revenue.toStringAsFixed(2)}',
        style: const TextStyle(
          color: Color(0xFFC2105C),
          fontWeight: FontWeight.w900,
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

class _SalesBars extends StatelessWidget {
  final List<MapEntry<String, double>> values;
  const _SalesBars({required this.values});
  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const Center(child: Text('No sales data yet.'));
    final max = values.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: values.map((entry) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: max == 0 ? 0 : entry.value / max,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFE91E63),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  entry.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
