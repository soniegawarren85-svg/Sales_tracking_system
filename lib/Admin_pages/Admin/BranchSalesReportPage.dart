import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'AllSalesAnalyticsPage.dart';

class BranchSalesReportPage extends StatefulWidget {
  const BranchSalesReportPage({super.key});

  @override
  State<BranchSalesReportPage> createState() => _BranchSalesReportPageState();
}

class _BranchSalesReportPageState extends State<BranchSalesReportPage> {
  String? _branchId;
  String _category = 'All';
  String _query = '';
  DateTime _selectedDate = DateTime.now();

  bool _isSelectedDate(dynamic value) {
    final date = value is Timestamp ? value.toDate() : null;
    if (date == null) return false;
    return date.year == _selectedDate.year &&
        date.month == _selectedDate.month &&
        date.day == _selectedDate.day;
  }

  double _money(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  String _categoryFor(Map<String, dynamic> item) {
    if (item['isCoffee'] == true) return 'Coffee';
    if (item['isBundle'] == true) return 'Bundle';
    return 'Categories';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F5),
      appBar: AppBar(
        title: const Text(
          'Branch Sales Report',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFFC2105C),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('branches').snapshots(),
        builder: (context, branchSnapshot) {
          final branches = (branchSnapshot.data?.docs ?? [])
              .where((doc) => doc.data()['isVoided'] != true)
              .toList();
          final selectedMatches = branches
              .where((doc) => doc.id == _branchId)
              .toList();
          final selected = selectedMatches.isEmpty
              ? null
              : selectedMatches.first;
          final staffIds = selected == null
              ? <String>{}
              : (selected.data()['staffIds'] as List<dynamic>? ?? [])
                    .map((id) => id.toString())
                    .toSet();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('completed_sales')
                .snapshots(),
            builder: (context, salesSnapshot) {
              final todaySales = (salesSnapshot.data?.docs ?? []).where((doc) {
                final sale = doc.data();
                return _isSelectedDate(sale['timestamp']) &&
                    (_branchId == null ||
                        sale['branchId']?.toString() == _branchId ||
                        staffIds.contains(sale['userId']?.toString()));
              }).toList();
              final categories = <String>{
                'All',
                if (_branchId != null) 'Categories',
                if (_branchId != null) 'Coffee',
                if (_branchId != null) 'Bundle',
                if (todaySales.any(
                  (sale) => (sale.data()['items'] as List<dynamic>? ?? [])
                      .whereType<Map>()
                      .any(
                        (item) =>
                            _categoryFor(Map<String, dynamic>.from(item)) ==
                            'Coffee',
                      ),
                ))
                  'Coffee',
                if (todaySales.any(
                  (sale) => (sale.data()['items'] as List<dynamic>? ?? [])
                      .whereType<Map>()
                      .any(
                        (item) =>
                            _categoryFor(Map<String, dynamic>.from(item)) ==
                            'Bundle',
                      ),
                ))
                  'Bundle',
              };
              if (!categories.contains(_category)) _category = 'All';
              final filteredSales = todaySales
                  .where((sale) {
                    if (_category == 'All') return true;
                    return (sale.data()['items'] as List<dynamic>? ?? [])
                        .whereType<Map>()
                        .any(
                          (item) =>
                              _categoryFor(Map<String, dynamic>.from(item)) ==
                              _category,
                        );
                  })
                  .where((sale) {
                    final query = _query.trim().toLowerCase();
                    if (query.isEmpty) return true;
                    final data = sale.data();
                    final items = (data['items'] as List<dynamic>? ?? [])
                        .whereType<Map>()
                        .map(
                          (item) =>
                              '${item['name'] ?? ''} ${item['variant'] ?? ''}',
                        )
                        .join(' ')
                        .toLowerCase();
                    return (data['salesId']?.toString().toLowerCase().contains(
                              query,
                            ) ??
                            false) ||
                        items.contains(query);
                  })
                  .toList();
              final revenue = _category == 'All'
                  ? filteredSales.fold<double>(
                      0,
                      (sum, sale) => sum + _money(sale.data()['total']),
                    )
                  : filteredSales.fold<double>(
                      0,
                      (sum, sale) =>
                          sum +
                          (sale.data()['items'] as List<dynamic>? ?? [])
                              .whereType<Map>()
                              .where(
                                (item) =>
                                    _categoryFor(
                                      Map<String, dynamic>.from(item),
                                    ) ==
                                    _category,
                              )
                              .fold<double>(
                                0,
                                (itemSum, item) =>
                                    itemSum +
                                    _money(item['price']) *
                                        _money(item['quantity']),
                              ),
                    );

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('staff_cash_drawer')
                    .snapshots(),
                builder: (context, drawerSnapshot) {
                  final drawer = (drawerSnapshot.data?.docs ?? [])
                      .where((doc) {
                        final data = doc.data();
                        return _branchId != null &&
                            (doc.id == _branchId ||
                                data['branchId']?.toString() == _branchId ||
                                staffIds.contains(doc.id) ||
                                staffIds.contains(
                                  data['staffId']?.toString(),
                                ) ||
                                staffIds.contains(data['userId']?.toString()));
                      })
                      .fold<double>(0, (sum, doc) {
                        final data = doc.data();
                        return sum +
                            _money(
                              data['balance'] ??
                                  data['cashDrawer'] ??
                                  data['dailyOpeningCash'],
                            );
                      });
                  return _buildContent(
                    branches,
                    todaySales,
                    filteredSales,
                    categories,
                    revenue,
                    drawer,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> branches,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allSales,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sales,
    Set<String> categories,
    double revenue,
    double drawer,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFC2105C), Color(0xFFF48FB1)],
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.trending_up_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text(
                    'Total Revenue Today',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '₱${revenue.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Divider(color: Colors.white30, height: 28),
              Text(
                '${sales.length} receipt${sales.length == 1 ? '' : 's'} • ${_branchId == null ? 'All branches' : 'Selected branch'}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AllSalesAnalyticsPage(),
                    ),
                  ),
                  icon: const Icon(Icons.insights_rounded, size: 18),
                  label: const Text('View all records'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Branches',
          style: TextStyle(
            color: Color(0xFFC2105C),
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _branchId == null,
              onSelected: (_) => setState(() {
                _branchId = null;
                _category = 'All';
              }),
            ),
            ...branches.map(
              (branch) => ChoiceChip(
                label: Text(branch.data()['name']?.toString() ?? 'Branch'),
                selected: _branchId == branch.id,
                onSelected: (_) => setState(() {
                  _branchId = branch.id;
                  _category = 'All';
                }),
              ),
            ),
          ],
        ),
        if (_branchId != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Color(0xFFC2105C),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Cash Drawer',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '₱${drawer.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFFC2105C),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Categories',
            style: TextStyle(
              color: Color(0xFFC2105C),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories
                .map(
                  (value) => ChoiceChip(
                    label: Text(value),
                    selected: _category == value,
                    onSelected: (_) => setState(() => _category = value),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search receipt ID or item',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
            icon: const Icon(Icons.calendar_today_rounded),
            label: Text(
              'Date: ${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          _branchId == null ? 'Sales — All Branches' : 'Sales Records',
          style: const TextStyle(
            color: Color(0xFFC2105C),
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        if (sales.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No sales record for this selection.')),
          ),
        ...sales.map((sale) => _saleTile(sale.data(), _category)),
      ],
    );
  }

  Widget _saleTile(Map<String, dynamic> sale, String category) {
    final items = (sale['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => category == 'All' || _categoryFor(item) == category)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sale['salesId']?.toString() ?? 'Receipt',
              style: const TextStyle(
                color: Color(0xFFC2105C),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            ...items.map((item) {
              final variant = item['variant']?.toString() ?? '';
              final description =
                  '${item['quantity'] ?? 0}x ${item['name'] ?? 'Item'}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  variant.isEmpty ? description : '$description ($variant)',
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
