import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/inventory.dart';
import '../../services/inventory_service.dart';

// ─── THEME ──────────────────────────────────────────────────────────
class _C {
  static const espresso   = Color(0xFFC2105C);
  static const mocha      = Color(0xFFE91E63);
  static const caramel    = Color(0xFFF48FB1);
  static const latte      = Color(0xFFF5A0C8);
  static const cream      = Color(0xFFF7F1EB);
  static const milk       = Color(0xFFFDF9F5);
  static const foam       = Color(0xFFEDE3D7);
  static const gold       = Color(0xFFD4A853);
  static const sage       = Color(0xFF7A9E7E);   // sold / positive
  static const dustRose   = Color(0xFFBF7B6E);   // remaining
}
// ────────────────────────────────────────────────────────────────────

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  DateTime _selectedDate = DateTime.now();
  String _searchQuery = '';
  final Map<String, String> _staffNameCache = {};
  final Set<String> _pendingStaffNameLoads = {};

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    // Initialize InventoryService to load data
    InventoryService().initialize().then((_) => InventoryService().refreshFromCloud()).then((_) {
      if (mounted) setState(() {});
    });
    // Listen to changes
    InventoryService().addListener(_onInventoryChanged);
  }

  void _onInventoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    InventoryService().removeListener(_onInventoryChanged);
    _fadeCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  double _calcSoldValue(Inventory inv) {
    if (inv.safeTotalSalesRevenue > 0) return inv.safeTotalSalesRevenue;

    double total = 0;
    final items = inv.safeItems;
    final starts = [inv.safeStartingA, inv.safeStartingB, inv.safeStartingC];
    final rems = [inv.safeRemainingA, inv.safeRemainingB, inv.safeRemainingC];
    final soldQuantities = [
      for (var i = 0; i < starts.length; i++)
        (starts[i] - rems[i] - _reducedQtyAt(items, i))
            .clamp(0, starts[i])
            .toInt(),
    ];

    for (var i = 0; i < items.length && i < soldQuantities.length; i++) {
      final price = double.tryParse(items[i]['price']?.toString() ?? '0') ?? 0;
      final qty = soldQuantities[i];
      total += qty * price;
    }
    return total;
  }

  int _reducedQtyAt(List<Map<String, dynamic>> items, int index) {
    if (index < 0 || index >= items.length) return 0;
    return int.tryParse(items[index]['reducedQuantity']?.toString() ?? '') ?? 0;
  }

  int _soldQtyAt(Inventory inv, int index) {
    final starts = [inv.safeStartingA, inv.safeStartingB, inv.safeStartingC];
    final rems = [inv.safeRemainingA, inv.safeRemainingB, inv.safeRemainingC];
    if (index < 0 || index >= starts.length) return 0;
    return (starts[index] - rems[index] - _reducedQtyAt(inv.safeItems, index))
        .clamp(0, starts[index])
        .toInt();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _prefetchStaffNamesForEntries(List<Inventory> entries) {
    final uniqueIds = entries
        .map((inv) => inv.ownerId)
        .whereType<String>()
        .toSet();

    for (final uid in uniqueIds) {
      if (_staffNameCache.containsKey(uid) || _pendingStaffNameLoads.contains(uid)) {
        continue;
      }
      _pendingStaffNameLoads.add(uid);
      FirebaseFirestore.instance.collection('staff_requests').doc(uid).get().then((snapshot) {
        final data = snapshot.data();
        final name = data == null
            ? ''
            : [
                (data['firstName'] as String?)?.trim() ?? '',
                (data['middleName'] as String?)?.trim() ?? '',
                (data['lastName'] as String?)?.trim() ?? '',
              ].where((part) => part.isNotEmpty).join(' ');
        if (mounted) {
          setState(() {
            _staffNameCache[uid] = name.isEmpty ? uid : name;
            _pendingStaffNameLoads.remove(uid);
          });
        }
      }).catchError((_) {
        if (mounted) {
          setState(() {
            _staffNameCache[uid] = uid;
            _pendingStaffNameLoads.remove(uid);
          });
        }
      });
    }
  }

  bool _matchesSearchQuery(Inventory inv) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final itemName = inv.safeItem.toLowerCase();
    if (itemName.contains(query)) return true;

    final ownerId = inv.ownerId?.toLowerCase() ?? '';
    if (ownerId.contains(query)) return true;

    final staffName = _staffNameCache[inv.ownerId]?.toLowerCase() ?? '';
    if (staffName.contains(query)) return true;

    return false;
  }

  List<Inventory> _filterEntries(List<Inventory> entries) {
    return entries.where((inv) {
      if (!_isSameDay(inv.timestamp, _selectedDate)) return false;
      return _matchesSearchQuery(inv);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.cream,
      child: _buildSalesContent(),
    );
  }

  Widget _buildSalesContent() {
    final entries = InventoryService().entries;

    if (entries.isEmpty) {
      return FadeTransition(
        opacity: _fadeCtrl,
        child: _buildEmptyState(),
      );
    }

    // Sort by timestamp descending (newest first)
    final sortedEntries = List<Inventory>.from(entries)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _prefetchStaffNamesForEntries(sortedEntries);

    final filteredEntries = _filterEntries(sortedEntries);

    return FadeTransition(
      opacity: _fadeCtrl,
      child: RefreshIndicator(
        color: _C.caramel,
        backgroundColor: _C.milk,
        onRefresh: () async {
          await InventoryService().refreshFromCloud();
          if (mounted) setState(() {});
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // ── Summary banner ──────────────────────────────
            SliverToBoxAdapter(child: _buildSummaryBanner(filteredEntries)),

            // ── Section label ───────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Row(children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_C.caramel, _C.gold],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "Sales Records",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _C.espresso,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _C.foam,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "${filteredEntries.length} entries",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _C.caramel,
                      ),
                    ),
                  ),
                ]),
              ),
            ),

            // ── Search Filter ────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Search staff name or item',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: _C.foam,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _C.foam),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _C.foam),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _C.caramel, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
            // ── Date Filter ──────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null && picked != _selectedDate) {
                      setState(() {
                        _selectedDate = picked;
                      });
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: _C.foam,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _C.caramel, width: 1.5),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: _C.caramel, size: 18),
                        const SizedBox(width: 12),
                        Text(
                          _searchQuery.trim().isEmpty
                              ? "Filter: ${_selectedDate.toString().split(' ')[0]}"
                              : "Filter: ${_selectedDate.toString().split(' ')[0]} · ${filteredEntries.length} match${filteredEntries.length == 1 ? '' : 'es'}",
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _C.caramel,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Cards ───────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: filteredEntries.isEmpty
                  ? SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Text(
                            'No records found',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ),
                    )
                  : SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _SalesCard(
                    inv: filteredEntries[i],
                    formatDate: _formatDate,
                    formatTime: _formatTime,
                    calcSoldValue: _calcSoldValue,
                    animDelay: Duration(milliseconds: i * 60),
                  ),
                  childCount: filteredEntries.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBanner(List<Inventory> entries) {
    double grandTotal = entries.fold(0, (sum, inv) => sum + _calcSoldValue(inv));
    int totalItems = entries.fold(0, (sum, inv) {
      final sold = _soldQtyAt(inv, 0) + _soldQtyAt(inv, 1) + _soldQtyAt(inv, 2);
      return sum + sold;
    });

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_C.espresso, _C.mocha, _C.caramel],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _C.espresso.withOpacity(0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.trending_up_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              "Total Revenue",
              style: TextStyle(
                fontSize: 13,
                color: Colors.white60,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            "₱${grandTotal.toStringAsFixed(2)}",
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1,
              height: 1,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 14),
          Row(children: [
            _bannerStat(Icons.inventory_2_outlined,
                "${entries.length}", "Batches"),
            const SizedBox(width: 20),
            _bannerStat(Icons.shopping_bag_outlined,
                "$totalItems", "Units Sold"),
          ]),
        ],
      ),
    );
  }

  Widget _bannerStat(IconData icon, String value, String label) => Row(
    children: [
      Icon(icon, color: Colors.white54, size: 15),
      const SizedBox(width: 6),
      Text(value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          )),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white54,
            fontWeight: FontWeight.w500,
          )),
    ],
  );

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _C.caramel.withOpacity(0.12),
                _C.latte.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.receipt_long_outlined,
              size: 54, color: _C.latte),
        ),
        const SizedBox(height: 20),
        const Text(
          "No Sales Records Yet",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _C.mocha,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 48),
          child: Text(
            "When staff complete their input, recorded sales will appear here.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _C.latte,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}

// ── SALES CARD (extracted for animation) ────────────────────────────
class _SalesCard extends StatefulWidget {
  final Inventory inv;
  final String Function(DateTime) formatDate;
  final String Function(DateTime) formatTime;
  final double Function(Inventory) calcSoldValue;
  final Duration animDelay;

  const _SalesCard({
    required this.inv,
    required this.formatDate,
    required this.formatTime,
    required this.calcSoldValue,
    required this.animDelay,
  });

  @override
  State<_SalesCard> createState() => _SalesCardState();
}

class _StaffInfo {
  final String displayName;
  final String displayId;

  const _StaffInfo({required this.displayName, required this.displayId});
}

class _SalesCardState extends State<_SalesCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  late Future<_StaffInfo?> _staffInfo;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _staffInfo = _loadStaffInfo(widget.inv.ownerId);

    Future.delayed(widget.animDelay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<_StaffInfo?> _loadStaffInfo(String? uid) async {
    if (uid == null || uid.isEmpty) return null;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(uid)
          .get();

      if (!snapshot.exists) return null;
      final data = snapshot.data();
      if (data == null) return null;

      final firstName = (data['firstName'] as String?)?.trim() ?? '';
      final middleName = (data['middleName'] as String?)?.trim() ?? '';
      final lastName = (data['lastName'] as String?)?.trim() ?? '';
      final nameParts = [firstName, middleName, lastName]
          .where((part) => part.isNotEmpty)
          .toList();
      final displayName = nameParts.isEmpty ? 'Staff' : nameParts.join(' ');

      final role = (data['role'] as String?)?.trim().toLowerCase();
      final displayId = role == 'admin'
          ? (data['adminId'] as String?) ?? (data['staffId'] as String?) ?? ''
          : (data['staffId'] as String?) ?? (data['adminId'] as String?) ?? '';

      return _StaffInfo(
        displayName: displayName,
        displayId: displayId.isEmpty ? 'ID unavailable' : displayId,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _buildSalesId(Inventory inv) {
    final dt = inv.timestamp.toLocal();
    final datePart = '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';
    final timePart = '${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}';
    final ownerSegment = (inv.ownerId ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final ownerCode = ownerSegment.length >= 4
        ? ownerSegment.substring(0, 4).toUpperCase()
        : ownerSegment.toUpperCase().padRight(4, 'X');
    return 'SALE-$datePart-$timePart-$ownerCode';
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.inv;
    final startA = inv.safeStartingA;
    final startB = inv.safeStartingB;
    final startC = inv.safeStartingC;
    final remA = inv.safeRemainingA;
    final remB = inv.safeRemainingB;
    final remC = inv.safeRemainingC;
    final totalStart = startA + startB + startC;
    final totalRem   = remA + remB + remC;
    final itemsList  = inv.safeItems;
    final totalReduced = itemsList.fold<int>(
      0,
      (sum, item) =>
          sum + (int.tryParse(item['reducedQuantity']?.toString() ?? '') ?? 0),
    );
    final totalSold =
        (totalStart - totalRem - totalReduced).clamp(0, totalStart).toInt();
    final soldValue  = widget.calcSoldValue(inv);
    final dt         = inv.timestamp.toLocal();
    
    // Calculate sold percentage based on items' starting quantities
    final quantities = [startA, startB, startC];
    int totalItemsCount = 0;
    for (var i = 0; i < itemsList.length && i < quantities.length; i++) {
      totalItemsCount += quantities[i];
    }
    
    final soldPct = totalItemsCount > 0 ? totalSold / totalItemsCount : 0.0;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            decoration: BoxDecoration(
              color: _C.milk,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _C.espresso.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: _C.espresso.withOpacity(0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── CARD HEADER ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product icon
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_C.latte, _C.caramel],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.bakery_dining_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Product name
                            Text(
                              inv.safeItem.isNotEmpty
                                  ? inv.safeItem
                                  : 'Product Sale',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: _C.espresso,
                                letterSpacing: -0.3,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Sales ID
                            Text(
                              'ID: ${_buildSalesId(inv)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: _C.dustRose,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Date and Time
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.calendar_today_outlined,
                                        size: 11, color: _C.latte),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.formatDate(dt),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: _C.latte,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.access_time_rounded,
                                        size: 11, color: _C.latte),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.formatTime(dt),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: _C.latte,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Staff Info
                            FutureBuilder<_StaffInfo?>(
                              future: _staffInfo,
                              builder: (context, snapshot) {
                                if (!snapshot.hasData || snapshot.data == null) {
                                  return const SizedBox.shrink();
                                }
                                final staff = snapshot.data!;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.person_rounded,
                                            size: 13, color: _C.espresso),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            staff.displayName,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: _C.espresso,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _C.caramel.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Staff ID: ${staff.displayId}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: _C.caramel,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      // Revenue badge
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 112),
                        child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_C.sage, Color(0xFF5A8260)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: _C.sage.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                          child: Text(
                          "₱${soldValue.toStringAsFixed(2)}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── PROGRESS BAR ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Sold ${(soldPct * 100).toStringAsFixed(0)}% of stock",
                            style: const TextStyle(
                              fontSize: 11,
                              color: _C.latte,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            "$totalSold / $totalStart",
                            style: const TextStyle(
                              fontSize: 11,
                              color: _C.caramel,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            Container(height: 6, color: _C.foam),
                            FractionallySizedBox(
                              widthFactor: soldPct.toDouble(),
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [_C.gold, _C.caramel],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── STAT CHIPS ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(children: [
                    _statChip(
                      label: "Started",
                      value: "$totalStart",
                      icon: Icons.play_circle_outline_rounded,
                      bg: _C.foam,
                      fg: _C.mocha,
                    ),
                    const SizedBox(width: 8),
                    _statChip(
                      label: "Remaining",
                      value: "$totalRem",
                      icon: Icons.inventory_outlined,
                      bg: _C.dustRose.withOpacity(0.1),
                      fg: _C.dustRose,
                    ),
                    const SizedBox(width: 8),
                    _statChip(
                      label: "Sold",
                      value: "$totalSold",
                      icon: Icons.check_circle_outline_rounded,
                      bg: _C.sage.withOpacity(0.1),
                      fg: _C.sage,
                    ),
                  ]),
                ),

                const SizedBox(height: 14),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showReducedItemsDialog,
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('View reduced items'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _C.espresso,
                            side: BorderSide(color: _C.foam),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showRefundItemsDialog,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('View refund items'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _C.espresso,
                            side: BorderSide(color: _C.foam),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── DIVIDER ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Container(height: 1, color: _C.foam),
                ),

                // ── ITEMS SECTION (expandable) ─────────────────────
                if (itemsList.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                      child: Row(children: [
                        const Icon(Icons.layers_rounded,
                            size: 15, color: _C.caramel),
                        const SizedBox(width: 8),
                        Text(
                          "Variants  (${itemsList.length})",
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _C.caramel,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 250),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: _C.latte,
                            size: 20,
                          ),
                        ),
                      ]),
                    ),
                  ),

                  AnimatedCrossFade(
                    firstChild: const SizedBox(height: 0),
                    secondChild: _buildItemsList(inv),
                    crossFadeState: _expanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 280),
                    sizeCurve: Curves.easeInOutCubic,
                  ),
                ],

                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showReducedItemsDialog() async {
    final staffId = widget.inv.ownerId;
    if (staffId == null || staffId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff information unavailable.')),
      );
      return;
    }

    final allDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    try {
      final staffIdQuery = await FirebaseFirestore.instance
          .collection('stock_adjustments')
          .where('staffId', isEqualTo: staffId)
          .get();
      final userIdQuery = await FirebaseFirestore.instance
          .collection('stock_adjustments')
          .where('userId', isEqualTo: staffId)
          .get();

      for (final doc in [...staffIdQuery.docs, ...userIdQuery.docs]) {
        final data = doc.data();
        final docUserId = data['userId']?.toString();
        final docStaffId = data['staffId']?.toString();
        final createdAt = data['createdAt'] as Timestamp?;
        if ((docUserId == staffId || docStaffId == staffId) &&
            createdAt != null &&
            _isSameDay(createdAt.toDate(), widget.inv.timestamp)) {
          allDocs[doc.id] = doc;
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading reduced items: ${error.toString()}')),
      );
      return;
    }

    if (!mounted) return;

    final docs = allDocs.values.toList()
      ..sort((a, b) {
        final aTs = (a.data()['createdAt'] as Timestamp?)?.toDate();
        final bTs = (b.data()['createdAt'] as Timestamp?)?.toDate();
        if (aTs == null || bTs == null) return 0;
        return bTs.compareTo(aTs);
      });

    final totalLoss = docs.fold<double>(0.0, (sum, doc) {
      final data = doc.data();
      final quantity = int.tryParse(data['quantity']?.toString() ?? '0') ?? 0;
      final unitPrice = double.tryParse(
          data['unitPrice']?.toString() ?? data['price']?.toString() ?? '0') ?? 0;
      final lossAmount = double.tryParse(data['lossAmount']?.toString() ?? '0') ?? 0;
      final effectiveLoss = lossAmount > 0
          ? lossAmount
          : (unitPrice > 0 ? unitPrice * quantity : 0.0);
      return sum + effectiveLoss;
    });

    String filterQuery = '';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final query = filterQuery.trim().toLowerCase();
            final filteredDocs = docs.where((doc) {
              final data = doc.data();
              final itemName = data['itemName']?.toString().toLowerCase() ?? '';
              final variant = data['variant']?.toString().toLowerCase() ?? '';
              final reason = data['reason']?.toString().toLowerCase() ?? '';
              final comment = data['comment']?.toString().toLowerCase() ?? '';
              return query.isEmpty ||
                  itemName.contains(query) ||
                  variant.contains(query) ||
                  reason.contains(query) ||
                  comment.contains(query);
            }).toList();

            final filteredTotalLoss = filteredDocs.fold<double>(0.0, (sum, doc) {
              final data = doc.data();
              final quantity = int.tryParse(data['quantity']?.toString() ?? '0') ?? 0;
              final unitPrice = double.tryParse(
                      data['unitPrice']?.toString() ?? data['price']?.toString() ?? '0') ??
                  0;
              final lossAmount = double.tryParse(data['lossAmount']?.toString() ?? '0') ?? 0;
              final effectiveLoss = lossAmount > 0
                  ? lossAmount
                  : (unitPrice > 0 ? unitPrice * quantity : 0.0);
              return sum + effectiveLoss;
            });

            return AlertDialog(
              title: Text('Reduced items - ${widget.formatDate(widget.inv.timestamp)}'),
              content: SizedBox(
                width: double.maxFinite,
                height: filteredDocs.isEmpty ? 260 : 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Filter by item, reason, or note',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: filterQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() => filterQuery = ''),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: _C.foam),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) => setState(() => filterQuery = value),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: _C.milk,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _C.foam),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total loss',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _C.espresso,
                                ),
                              ),
                              if (query.isNotEmpty)
                                Text(
                                  '${filteredDocs.length} matching item${filteredDocs.length == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _C.espresso,
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            '₱${filteredTotalLoss.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: _C.caramel,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (filteredDocs.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            query.isEmpty
                                ? 'No reduced items found for this staff on this date.'
                                : 'No reduced items match your filter.',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: filteredDocs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final data = filteredDocs[index].data() as Map<String, dynamic>;
                            final itemName = data['itemName']?.toString() ?? 'Unknown';
                            final variant = data['variant']?.toString();
                            final displayQuantity = data['quantity']?.toString() ?? '0';
                            final reason = data['reason']?.toString() ?? 'No reason';
                            final comment = data['comment']?.toString() ?? '';
                            final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                            final quantity = int.tryParse(data['quantity']?.toString() ?? '0') ?? 0;
                            final unitPrice = double.tryParse(
                                data['unitPrice']?.toString() ?? data['price']?.toString() ?? '0') ?? 0;
                            final lossAmount = double.tryParse(
                                data['lossAmount']?.toString() ?? '0') ?? 0;
                            final effectiveLoss = lossAmount > 0
                                ? lossAmount
                                : (unitPrice > 0 ? unitPrice * quantity : 0.0);
                            final rowLabel = variant != null && variant.isNotEmpty
                                ? '$itemName ($variant)'
                                : itemName;

                            return Container(
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                                border: Border.all(color: _C.foam),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rowLabel,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: _C.espresso,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Qty reduced: $displayQuantity',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: _C.espresso,
                                          ),
                                        ),
                                      ),
                                      if (unitPrice > 0)
                                        Text(
                                          'Unit ₱${unitPrice.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: _C.dustRose,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Loss: ₱${effectiveLoss.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _C.caramel,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Reason: $reason',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (comment.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Note: $comment',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                  if (createdAt != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Date: ${createdAt.toLocal().toString().split('.').first}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRefundItemsDialog() async {
    final staffId = widget.inv.ownerId;
    if (staffId == null || staffId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff information unavailable.')),
      );
      return;
    }

    List<Map<String, dynamic>> refunds = [];
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('completed_sales')
          .where('userId', isEqualTo: staffId)
          .get();

      refunds = snapshot.docs
          .map((doc) => doc.data())
          .where((data) {
            final type = data['type']?.toString().toLowerCase();
            final status = data['status']?.toString().toLowerCase();
            return (type == 'refund' || status == 'refund') &&
                _isSameDay((data['timestamp'] as Timestamp?)?.toDate() ?? DateTime(0), widget.inv.timestamp);
          })
          .toList();

      refunds.sort((a, b) {
        final aTs = (a['timestamp'] as Timestamp?)?.toDate();
        final bTs = (b['timestamp'] as Timestamp?)?.toDate();
        if (aTs == null || bTs == null) return 0;
        return bTs.compareTo(aTs);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading refund items: ${error.toString()}')),
      );
      return;
    }

    if (!mounted) return;

    final totalRefundAmount = refunds.fold<double>(0.0, (sum, data) {
      final total = double.tryParse(data['total']?.toString() ?? '0') ?? 0;
      final delta = double.tryParse(data['cashDrawerDelta']?.toString() ?? '0') ?? 0;
      final subtotal = double.tryParse(data['subtotal']?.toString() ?? '0') ?? 0;
      return sum + (total.abs() > 0 ? total.abs() : delta.abs() > 0 ? delta.abs() : subtotal.abs());
    });

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Refund items - ${widget.formatDate(widget.inv.timestamp)}'),
          content: SizedBox(
            width: double.maxFinite,
            height: refunds.isEmpty ? 260 : 500,
            child: refunds.isEmpty
                ? const Center(
                    child: Text('No refund items found for this staff on this date.'),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: _C.milk,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _C.foam),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total refund',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _C.espresso,
                              ),
                            ),
                            Text(
                              '₱${totalRefundAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: _C.sage,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: refunds.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final data = refunds[index];
                            final salesId = data['salesId']?.toString() ?? 'Refund';
                            final reason = data['reason']?.toString() ?? 'No reason';
                            final source = data['source']?.toString() ?? '';
                            final createdAt = (data['timestamp'] as Timestamp?)?.toDate();
                            final items = (data['items'] as List<dynamic>? ?? [])
                                .whereType<Map<String, dynamic>>()
                                .toList();
                            final itemCount = items.fold<int>(0, (sum, item) {
                              return sum + (int.tryParse(item['quantity']?.toString() ?? '0') ?? 0);
                            });

                            return Container(
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                                border: Border.all(color: _C.foam),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    salesId,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: _C.espresso,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Refunded items: $itemCount',
                                    style: const TextStyle(fontSize: 12, color: _C.espresso),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Reason: $reason${source.isNotEmpty ? ' ($source)' : ''}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (createdAt != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Date: ${createdAt.toLocal().toString().split('.').first}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  if (items.isNotEmpty)
                                    ...items.map((item) {
                                      final itemName = item['name']?.toString() ?? 'Item';
                                      final quantity = int.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          '• $itemName x$quantity',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      );
                                    }),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildItemsList(Inventory inv) {
    final items = inv.safeItems;
    final starts = [inv.safeStartingA, inv.safeStartingB, inv.safeStartingC];
    final rems = [inv.safeRemainingA, inv.safeRemainingB, inv.safeRemainingC];

    return Padding(
    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
    child: Column(
      children: [
        Container(height: 1, color: _C.foam),
        const SizedBox(height: 12),
        ...items.asMap().entries.map((e) {
          final i     = e.key;
          final item  = e.value;
          final name  = item['name']?.toString() ?? 'Item';
          final price = double.tryParse(
                  item['price']?.toString() ?? '0') ??
              0;
          final startQty = i < starts.length ? starts[i] : 0;
          final remQty = i < rems.length ? rems[i] : 0;
          final reducedQty =
              int.tryParse(item['reducedQuantity']?.toString() ?? '') ?? 0;
          final soldQty = (startQty - remQty - reducedQty)
              .clamp(0, startQty)
              .toInt();
          final lineTotal = soldQty * price;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _C.cream,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _C.latte.withOpacity(0.2)),
              ),
              child: Row(children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_C.latte, _C.caramel],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _C.espresso,
                        letterSpacing: 0.1,
                      )),
                ),
                if (soldQty > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _C.caramel.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text("x$soldQty",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _C.caramel,
                        )),
                  ),
                if (soldQty > 0) const SizedBox(width: 10),
                if (reducedQty > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _C.dustRose.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '-$reducedQty reduced',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _C.dustRose,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  "₱${lineTotal.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _C.mocha,
                  ),
                ),
              ]),
            ),
          );
        }).toList(),
      ],
    ),
  );
  }

  Widget _statChip({
    required String label,
    required String value,
    required IconData icon,
    required Color bg,
    required Color fg,
  }) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: fg,
                    height: 1,
                  )),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: fg.withOpacity(0.7),
                    letterSpacing: 0.3,
                  )),
            ],
          ),
        ),
      );
}

extension ColorDarken on Color {
  Color darken(double amount) {
    final f = 1 - amount;
    return Color.fromARGB(
      alpha,
      (red * f).clamp(0, 255).toInt(),
      (green * f).clamp(0, 255).toInt(),
      (blue * f).clamp(0, 255).toInt(),
    );
  }
}
