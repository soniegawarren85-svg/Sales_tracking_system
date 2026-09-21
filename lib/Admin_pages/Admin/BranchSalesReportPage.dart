import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'AllSalesAnalyticsPage.dart';

// ─────────────────────────────────────────────────────────────
//  Design tokens
// ─────────────────────────────────────────────────────────────
class _C {
  static const primary = Color(0xFFC2105C);
  static const deep = Color(0xFF9C1650);
  static const soft = Color(0xFFF48FB1);
  static const bg = Color(0xFFFDF4F8);
  static const ink = Color(0xFF2B1A22);
  static const muted = Color(0xFF8A7480);
  static const line = Color(0xFFF3DCE6);
  static const danger = Color(0xFFC62828);
  static const dangerBg = Color(0xFFFDECEC);
  static const amber = Color(0xFFB26A00);
  static const amberBg = Color(0xFFFFF3DC);
  static const ok = Color(0xFF1B7F4B);
  static const okBg = Color(0xFFE6F6EE);
}

const _months = [
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

class BranchSalesReportPage extends StatefulWidget {
  const BranchSalesReportPage({super.key});

  @override
  State<BranchSalesReportPage> createState() => _BranchSalesReportPageState();
}

class _BranchSalesReportPageState extends State<BranchSalesReportPage> {
  String? _branchId;
  String _category = 'All';
  String _paymentFilter = 'All';
  String _query = '';
  String _activityFilter = 'Sales';
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ───────────────────────── helpers ─────────────────────────
  bool _isSelectedDate(dynamic value) {
    final date = value is Timestamp ? value.toDate() : null;
    if (date == null) return false;
    return date.year == _selectedDate.year &&
        date.month == _selectedDate.month &&
        date.day == _selectedDate.day;
  }

  bool get _isToday {
    final now = DateTime.now();
    return now.year == _selectedDate.year &&
        now.month == _selectedDate.month &&
        now.day == _selectedDate.day;
  }

  String get _dateLabel =>
      '${_months[_selectedDate.month - 1]} ${_selectedDate.day}, ${_selectedDate.year}';

  double _money(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  String _peso(double v) {
    final parts = v.toStringAsFixed(2).split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );
    return '₱$whole.${parts[1]}';
  }

  String _time(dynamic v) {
    if (v is! Timestamp) return '';
    final d = v.toDate();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _categoryFor(Map<String, dynamic> item) {
    if (item['isCoffee'] == true) return 'Coffee';
    if (item['isBundle'] == true) return 'Bundle';
    return 'Categories';
  }

  IconData _categoryIcon(String c) {
    switch (c) {
      case 'Coffee':
        return Icons.coffee_rounded;
      case 'Bundle':
        return Icons.inventory_2_rounded;
      case 'Categories':
        return Icons.category_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  bool _isRefund(Map<String, dynamic> sale) {
    final type = sale['type']?.toString().toLowerCase();
    final salesId = sale['salesId']?.toString().toLowerCase() ?? '';
    return type == 'refund' ||
        salesId.startsWith('r-') ||
        sale['fullyRefunded'] == true;
  }

  bool _hasReduced(Map<String, dynamic> sale) =>
      (sale['items'] as List<dynamic>? ?? []).whereType<Map>().any(
        (item) => _money(item['reducedQuantity']) > 0,
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: _C.primary,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  // ───────────────────────── bottom sheet ─────────────────────────
  void _showActivityDialog(
    String title,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> records,
  ) {
    final isRefund = title.toLowerCase().contains('refund');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: _C.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: _C.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isRefund ? _C.dangerBg : _C.amberBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isRefund
                            ? Icons.replay_circle_filled_rounded
                            : Icons.remove_circle_rounded,
                        color: isRefund ? _C.danger : _C.amber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: _C.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${records.length} record${records.length == 1 ? '' : 's'} • $_dateLabel',
                            style: const TextStyle(
                              color: _C.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded, color: _C.muted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: records.isEmpty
                    ? const _EmptyState(
                        icon: Icons.inbox_rounded,
                        title: 'No records found',
                        message: 'Nothing for this branch and date.',
                      )
                    : ListView.builder(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: records.length,
                        itemBuilder: (_, index) => _FadeSlideIn(
                          key: ValueKey('sheet_${records[index].id}'),
                          index: index,
                          child: _saleTile(records[index].data(), _category),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── build ─────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        titleSpacing: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_C.deep, _C.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Branch Sales Report',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
            ),
            Text(
              _isToday ? 'Today • $_dateLabel' : _dateLabel,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('branches').snapshots(),
        builder: (context, branchSnapshot) {
          if (branchSnapshot.hasError) {
            return const _EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Could not load branches',
              message: 'Check your connection and try again.',
            );
          }
          if (!branchSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _C.primary),
            );
          }
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
              final allTodaySales = (salesSnapshot.data?.docs ?? []).where((doc) {
                final sale = doc.data();
                return _isSelectedDate(sale['timestamp']) &&
                    (_branchId == null ||
                        sale['branchId']?.toString() == _branchId ||
                        staffIds.contains(sale['userId']?.toString()));
              }).toList();
              final todaySales = allTodaySales.where((doc) {
                if (_paymentFilter == 'All') return true;
                final mode = doc.data()['paymentMode']?.toString().trim().toLowerCase() ?? 'cash';
                return mode == _paymentFilter.toLowerCase();
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
                    final data = sale.data();
                    final refund = _isRefund(data);
                    final reduced = _hasReduced(data);
                    if (_activityFilter == 'Refunds') return refund;
                    if (_activityFilter == 'Reduced') return reduced && !refund;
                    return true;
                  })
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
                  ? filteredSales.fold<double>(0, (sum, sale) {
                    // Completed sales and refund receipts already store
                    // their signed net total. Keep each transaction's sign
                    // so a fully refunded original receipt is not deducted
                    // twice alongside its negative refund receipt.
                    return sum + _money(sale.data()['total']);
                    })
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
                  var drawer = 0.0;
                  final drawerDocs = drawerSnapshot.data?.docs ?? const [];
                  if (_branchId != null) {
                    // Show the cash actually held by this branch's assigned
                    // staff. The branch document can be an old aggregate and
                    // must only be used when no staff drawer is available.
                    var branchFallback = 0.0;
                    var hasStaffDrawer = false;
                    for (final doc in drawerDocs) {
                      final data = doc.data();
                      final identifiers = <String>{
                        doc.id,
                        data['staffId']?.toString() ?? '',
                        data['employeeId']?.toString() ?? '',
                        data['staffCode']?.toString() ?? '',
                        data['userId']?.toString() ?? '',
                        data['uid']?.toString() ?? '',
                      }..removeWhere((id) => id.trim().isEmpty);
                      final balance = _money(
                        data['balance'] ??
                            data['cashDrawer'] ??
                            data['dailyOpeningCash'],
                      );
                      if (identifiers.any(staffIds.contains)) {
                        hasStaffDrawer = true;
                        drawer += balance;
                      } else if (doc.id == _branchId &&
                          data['branchId']?.toString() == _branchId) {
                        branchFallback = balance;
                      }
                    }
                    if (!hasStaffDrawer) drawer = branchFallback;

                    // The device dashboard rebuilds this value from today's
                    // completed cash receipts. Do the same here so a stale
                    // server aggregate cannot show another branch's total.
                    final cashReceipts = allTodaySales.where(
                      (sale) =>
                          sale.data()['paymentMode']?.toString().toLowerCase() ==
                          'cash',
                    );
                    if (cashReceipts.isNotEmpty) {
                      drawer = cashReceipts.fold<double>(0.0, (sum, sale) {
                        final data = sale.data();
                        final delta = data['cashDrawerDelta'];
                        return sum +
                            (delta == null
                                ? _money(data['paidAmount']) -
                                    _money(data['change'])
                                : _money(delta));
                      });
                    }
                  } else {
                    final activeBranchIds = branches.map((branch) => branch.id).toSet();
                    for (final doc in drawerDocs) {
                      final data = doc.data();
                      final branchKey = data['branchId']?.toString() ?? doc.id;
                      if (activeBranchIds.contains(branchKey)) {
                        drawer += _money(data['balance']);
                      }
                    }
                  }
                  if (_branchId != null) {
                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('staff_budget')
                          .doc(_branchId)
                          .snapshots(),
                      builder: (context, allocationSnapshot) {
                        final openingCash = _money(
                          allocationSnapshot.data?.data()?['allocatedBudget'],
                        );
                        return _buildContent(
                          branches,
                          todaySales,
                          filteredSales,
                          categories,
                          revenue,
                          drawer + openingCash,
                        );
                      },
                    );
                  }
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

  // ───────────────────────── content ─────────────────────────
  Widget _buildContent(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> branches,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allSales,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sales,
    Set<String> categories,
    double revenue,
    double drawer,
  ) {
    final refundRecords = allSales
        .where((sale) => _isRefund(sale.data()))
        .toList();
    final reducedRecords = allSales
        .where((sale) => _hasReduced(sale.data()))
        .toList();

    String branchName = 'All branches';
    for (final b in branches) {
      if (b.id == _branchId) {
        branchName = b.data()['name']?.toString() ?? 'Selected branch';
      }
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _FadeSlideIn(
          index: 0,
          child: _heroCard(
            revenue: revenue,
            receipts: sales.length,
            refunds: refundRecords.length,
            reduced: reducedRecords.length,
            branchName: branchName,
          ),
        ),
        const SizedBox(height: 22),
        const _SectionTitle('Branches'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PillChip(
              label: 'All',
              icon: Icons.storefront_rounded,
              selected: _branchId == null,
              onTap: () => setState(() {
                _branchId = null;
                _category = 'All';
              }),
            ),
            ...branches.map(
              (branch) => _PillChip(
                label: branch.data()['name']?.toString() ?? 'Branch',
                selected: _branchId == branch.id,
                onTap: () => setState(() {
                  _branchId = branch.id;
                  _category = 'All';
                }),
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _branchId == null
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    _drawerCard(drawer),
                    const SizedBox(height: 22),
                    const _SectionTitle('Categories'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories
                          .map(
                            (value) => _PillChip(
                              label: value,
                              icon: _categoryIcon(value),
                              selected: _category == value,
                              onTap: () => setState(() => _category = value),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                style: const TextStyle(color: _C.ink),
                decoration: InputDecoration(
                  hintText: 'Search receipt ID or item',
                  hintStyle: const TextStyle(color: _C.muted),
                  prefixIcon: const Icon(Icons.search_rounded, color: _C.muted),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: _C.muted,
                            size: 20,
                          ),
                          onPressed: () => setState(() {
                            _query = '';
                            _searchController.clear();
                          }),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _C.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _C.primary, width: 1.6),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _pickDate,
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _C.line),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_rounded,
                        color: _C.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_months[_selectedDate.month - 1]} ${_selectedDate.day}',
                        style: const TextStyle(
                          color: _C.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: _SectionTitle(
                _branchId == null ? 'Sales — All Branches' : 'Sales Records',
              ),
            ),
            const SizedBox(width: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: ['All', 'Cash', 'GCash'].map((label) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _PillChip(
                      label: label,
                      icon: label == 'Cash'
                          ? Icons.payments_rounded
                          : label == 'GCash'
                          ? Icons.phone_android_rounded
                          : Icons.all_inclusive_rounded,
                      selected: _paymentFilter == label,
                      onTap: () => setState(() => _paymentFilter = label),
                    ),
                  );
                }).toList(),
              ),
            ),
            _CountBadge(sales.length),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActivityButton(
                icon: Icons.replay_circle_filled_rounded,
                label: 'Refund',
                count: refundRecords.length,
                fg: _C.danger,
                bg: _C.dangerBg,
                onTap: () =>
                    _showActivityDialog('Refund Records', refundRecords),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActivityButton(
                icon: Icons.remove_circle_rounded,
                label: 'Reduce',
                count: reducedRecords.length,
                fg: _C.amber,
                bg: _C.amberBg,
                onTap: () =>
                    _showActivityDialog('Reduced Records', reducedRecords),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (sales.isEmpty)
          const _EmptyState(
            icon: Icons.receipt_long_rounded,
            title: 'No sales record',
            message: 'Try another branch, category or date.',
          )
        else
          ...List.generate(
            sales.length,
            (i) => _FadeSlideIn(
              key: ValueKey('sale_${sales[i].id}'),
              index: i,
              child: _saleTile(sales[i].data(), _category),
            ),
          ),
      ],
    );
  }

  // ───────────────────────── hero ─────────────────────────
  Widget _heroCard({
    required double revenue,
    required int receipts,
    required int refunds,
    required int reduced,
    required String branchName,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [_C.deep, _C.primary, Color(0xFFE8508A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _C.primary.withAlpha(70),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(24),
                ),
              ),
            ),
            Positioned(
              right: 40,
              bottom: -60,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.trending_up_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _isToday ? 'Total Revenue Today' : 'Total Revenue',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(36),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          branchName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: revenue),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, __) => FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _peso(value),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        _heroStat('Receipts', '$receipts'),
                        _heroDivider(),
                        _heroStat('Refunds', '$refunds'),
                        _heroDivider(),
                        _heroStat('Reduced', '$reduced'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: sales_isEmpty(receipts)
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AllSalesAnalyticsPage(),
                              ),
                            ),
                      icon: const Icon(Icons.insights_rounded, size: 18),
                      label: Text(
                        receipts == 0
                            ? (_isToday ? 'No records today' : 'No records')
                            : 'View all records',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _C.primary,
                        disabledBackgroundColor: Colors.white24,
                        disabledForegroundColor: Colors.white60,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool sales_isEmpty(int receipts) => receipts == 0;

  Widget _heroStat(String label, String value) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _heroDivider() =>
      Container(width: 1, height: 30, color: Colors.white24);

  // ───────────────────────── cash drawer ─────────────────────────
  Widget _drawerCard(double drawer) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.line),
        boxShadow: [
          BoxShadow(
            color: _C.primary.withAlpha(14),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE4EE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: _C.primary,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cash Drawer',
                  style: TextStyle(
                    color: _C.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'Current balance',
                  style: TextStyle(color: _C.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: drawer),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(
              _peso(v),
              style: const TextStyle(
                color: _C.primary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── sale tile ─────────────────────────
  Widget _saleTile(Map<String, dynamic> sale, String category) {
    final items = (sale['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => category == 'All' || _categoryFor(item) == category)
        .toList();

    final saleIsRefund = _isRefund(sale);
    final saleHasReduced = _hasReduced(sale);
    final discount = _money(sale['discount']);
    final discountType = sale['discountType']?.toString().trim() ?? '';
    final discountProofId = sale['discountProofId']?.toString().trim() ?? '';
    final paymentMode = sale['paymentMode']?.toString().trim() ?? 'Cash';
    final gcashId = sale['gcashTransactionId']?.toString().trim() ?? '';
    final paidAmount = _money(sale['paidAmount']);
    final change = _money(sale['change']);
    final refundReason = (sale['reason'] ?? sale['refundReason'])
      ?.toString()
      .trim() ??
      '';
    final refundSource = sale['source']?.toString().trim() ?? '';
    final hasDiscount = discount > 0.01 && discountType.toLowerCase() != 'none';
    final hasRefundActivity = saleIsRefund ||
      sale['fullyRefunded'] == true ||
      items.any((item) => _money(item['refunded']) > 0);
    final total = category == 'All'
        ? _money(sale['total'])
        : items.fold<double>(
            0,
            (s, i) => s + _money(i['price']) * _money(i['quantity']),
          );

    final Color accent = saleIsRefund
        ? _C.danger
        : saleHasReduced
        ? _C.amber
        : _C.primary;
    final Color accentBg = saleIsRefund
        ? _C.dangerBg
        : saleHasReduced
        ? _C.amberBg
        : const Color(0xFFFCE4EE);
    final IconData icon = saleIsRefund
        ? Icons.replay_rounded
        : saleHasReduced
        ? Icons.remove_rounded
        : Icons.receipt_long_rounded;
    final time = _time(sale['timestamp']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.line),
        boxShadow: [
          BoxShadow(
            color: _C.primary.withAlpha(12),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentBg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sale['salesId']?.toString() ?? 'Receipt',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _C.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      if (time.isNotEmpty)
                        Text(
                          time,
                          style: const TextStyle(color: _C.muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _peso(total),
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (saleIsRefund)
                      const _Tag('Refunded', _C.danger, _C.dangerBg)
                    else if (saleHasReduced)
                      const _Tag('Reduced', _C.amber, _C.amberBg)
                    else
                      const _Tag('Completed', _C.ok, _C.okBg),
                  ],
                ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: _C.line),
              const SizedBox(height: 10),
            ],
            ...items.map((item) {
              final variant = item['variant']?.toString() ?? '';
              final qty = _money(item['quantity']);
              final refunded = saleIsRefund || _money(item['refunded']) > 0;
              final reducedQty = _money(item['reducedQuantity']);
              final lineTotal = _money(item['price']) * qty;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: refunded ? _C.dangerBg : const Color(0xFFFCE4EE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${qty % 1 == 0 ? qty.toInt() : qty}x',
                        style: TextStyle(
                          color: refunded ? _C.danger : _C.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name']?.toString() ?? 'Item',
                            style: TextStyle(
                              color: refunded ? _C.danger : _C.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          if (variant.isNotEmpty)
                            Text(
                              variant,
                              style: const TextStyle(
                                color: _C.muted,
                                fontSize: 12,
                              ),
                            ),
                          if (refunded || reducedQty > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: refunded
                                  ? const _Tag(
                                      'REFUNDED',
                                      _C.danger,
                                      _C.dangerBg,
                                    )
                                  : _Tag(
                                      'REDUCED (${reducedQty.toInt()})',
                                      _C.amber,
                                      _C.amberBg,
                                    ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      _peso(lineTotal),
                      style: TextStyle(
                        color: refunded ? _C.danger : _C.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _C.line),
              ),
              child: Column(
                children: [
                  _reportDetailRow(
                    'Payment',
                    paymentMode == 'GCash' && gcashId.isNotEmpty
                        ? 'GCash - $gcashId'
                        : paymentMode,
                  ),
                  _reportDetailRow(
                    'Customer Paid',
                    _peso(paidAmount),
                  ),
                  if (hasDiscount)
                    _reportDetailRow(
                      'Discount ($discountType)',
                      '-₱${discount.toStringAsFixed(2)}',
                      valueColor: _C.ok,
                    ),
                  if (discountProofId.isNotEmpty)
                    _reportDetailRow(
                      discountType.isEmpty ? 'Discount ID' : '$discountType ID',
                      discountProofId,
                    ),
                  if (hasRefundActivity && refundReason.isNotEmpty)
                    _reportDetailRow(
                      'Refund Reason${refundSource.isNotEmpty ? ' ($refundSource)' : ''}',
                      refundReason,
                      valueColor: _C.danger,
                    ),
                  _reportDetailRow('Change', _peso(change)),
                  _reportDetailRow(
                    saleIsRefund ? 'Refund Amount' : 'Total',
                    _peso(total),
                    strong: true,
                    valueColor: saleIsRefund ? _C.danger : _C.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportDetailRow(
    String label,
    String value, {
    Color? valueColor,
    bool strong = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: _C.muted,
                fontSize: strong ? 12 : 11,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? _C.ink,
                fontSize: strong ? 13 : 11,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Reusable widgets
// ─────────────────────────────────────────────────────────────

/// Fade + slide-up entrance, slightly staggered by [index].
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = (index.clamp(0, 8)) * 60;
    final total = 420 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - v)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 4,
        height: 18,
        decoration: BoxDecoration(
          color: _C.primary,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _C.ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _C.primary : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: selected ? _C.primary : _C.line),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _C.primary.withAlpha(70),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? Colors.white : _C.primary),
              const SizedBox(width: 6),
            ],
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 240),
              style: TextStyle(
                color: selected ? Colors.white : _C.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityButton extends StatelessWidget {
  const _ActivityButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.fg,
    required this.bg,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color fg;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.line),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: fg, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _C.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Container(
                  key: ValueKey(count),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
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

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);
  final int count;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 250),
    transitionBuilder: (child, anim) =>
        ScaleTransition(scale: anim, child: child),
    child: Container(
      key: ValueKey(count),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFCE4EE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count receipt${count == 1 ? '' : 's'}',
        style: const TextStyle(
          color: _C.primary,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.fg, this.bg);
  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 3),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w800),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.85, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.scale(scale: v, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFFCE4EE),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 36, color: _C.primary),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: _C.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _C.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
