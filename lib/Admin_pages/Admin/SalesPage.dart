import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/inventory.dart';
import '../../services/inventory_service.dart';
import '../../services/branch_session.dart';
import 'BranchSalesReportPage.dart';

// ─── THEME ──────────────────────────────────────────────────────────
class _C {
  static const espresso = Color(0xFFC2105C);
  static const mocha = Color(0xFFE91E63);
  static const caramel = Color(0xFFF48FB1);
  static const latte = Color(0xFFF5A0C8);
  static const cream = Color(0xFFF7F1EB);
  static const milk = Color(0xFFFDF9F5);
  static const foam = Color(0xFFEDE3D7);
  static const gold = Color(0xFFD4A853);
  static const sage = Color(0xFF7A9E7E); // sold / positive
  static const dustRose = Color(0xFFBF7B6E); // remaining
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
  Set<String> _branchStaffIds = <String>{};
  bool _receiptGroupsLoaded = false;
  Set<String> _receiptPrimaryKeys = <String>{};
  final Map<String, Map<String, dynamic>> _receiptByPrimaryKey = {};
  List<Inventory> _receiptEntries = const [];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    // Initialize InventoryService to load data
    InventoryService()
        .initialize()
        .then((_) => InventoryService().refreshFromCloud())
        .then((_) {
          if (mounted) setState(() {});
        });
    // Listen to changes
    InventoryService().addListener(_onInventoryChanged);
    BranchSession.instance.addListener(_loadBranchStaff);
    _loadBranchStaff();
  }

  Future<void> _loadBranchStaff() async {
    final branchId = BranchSession.instance.branchId;
    if (branchId == null) {
      if (mounted) setState(() => _branchStaffIds = <String>{});
      return;
    }
    final doc = await FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .get();
    final ids = (doc.data()?['staffIds'] as List<dynamic>? ?? [])
        .map((id) => id.toString())
        .toSet();
    if (mounted && BranchSession.instance.branchId == branchId) {
      setState(() {
        _branchStaffIds = ids;
        _receiptGroupsLoaded = false;
      });
    }
  }

  void _onInventoryChanged() {
    if (mounted) {
      setState(() {
        _receiptGroupsLoaded = false;
        _receiptPrimaryKeys = <String>{};
        _receiptByPrimaryKey.clear();
        _receiptEntries = const [];
      });
    }
  }

  String _inventoryEntryKey(Inventory entry) => [
    entry.ownerId ?? '',
    entry.sourceInventoryId ?? entry.safeItem,
    entry.timestamp.millisecondsSinceEpoch.toString(),
  ].join('|');

  Future<void> _groupEntriesByReceipt(List<Inventory> entries) async {
    final sales = await FirebaseFirestore.instance
        .collection('completed_sales')
        .get();
    final receiptByPrimaryKey = <String, Map<String, dynamic>>{};
    final receiptEntries = <Inventory>[];

    // A completed_sale is the receipt source of truth.  Each one is assigned
    // to one inventory row only so a multi-item order can never be split into
    // separate cards or borrow items from a neighbouring receipt.
    final receiptDocs =
        sales.docs.where((doc) {
          final data = doc.data();
          final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
          return timestamp != null &&
              _isSameDay(timestamp, _selectedDate) &&
              (BranchSession.instance.isMainBranch ||
                  _branchStaffIds.contains(data['userId']?.toString())) &&
              (data['items'] as List<dynamic>? ?? [])
                  .whereType<Map>()
                  .isNotEmpty;
        }).toList()..sort((a, b) {
          final aTime = (a.data()['timestamp'] as Timestamp).toDate();
          final bTime = (b.data()['timestamp'] as Timestamp).toDate();
          return bTime.compareTo(aTime);
        });

    for (final doc in receiptDocs) {
      final receipt = doc.data();
      final userId = receipt['userId']?.toString().trim() ?? '';
      final receiptTime = (receipt['timestamp'] as Timestamp).toDate();
      final receiptItems = (receipt['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final query = _searchQuery.trim().toLowerCase();
      final searchableItems = receiptItems
          .map((item) => '${item['name'] ?? ''} ${item['variant'] ?? ''}')
          .join(' ')
          .toLowerCase();
      final staffName = _staffNameCache[userId]?.toLowerCase() ?? '';
      if (query.isNotEmpty &&
          !searchableItems.contains(query) &&
          !userId.toLowerCase().contains(query) &&
          !staffName.contains(query)) {
        continue;
      }

      // Build a display entry for every receipt.  Inventory snapshots are not
      // used to decide which receipts appear; staff history is the source.
      final primary = Inventory(
        item: receiptItems.first['name']?.toString(),
        ownerId: userId,
        sourceInventoryId: 'receipt-${doc.id}',
        items: receiptItems,
        totalSalesRevenue:
            double.tryParse(receipt['total']?.toString() ?? '') ?? 0,
        timestamp: receiptTime,
      );
      receiptEntries.add(primary);
      receiptByPrimaryKey[_inventoryEntryKey(primary)] = {
        ...receipt,
        '_documentId': doc.id,
      };
    }
    if (mounted) {
      setState(() {
        _receiptPrimaryKeys = receiptByPrimaryKey.keys.toSet();
        _receiptByPrimaryKey
          ..clear()
          ..addAll(receiptByPrimaryKey);
        _receiptEntries = receiptEntries;
        _receiptGroupsLoaded = true;
      });
    }
  }

  @override
  void dispose() {
    InventoryService().removeListener(_onInventoryChanged);
    BranchSession.instance.removeListener(_loadBranchStaff);
    _fadeCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  double _calcSoldValue(Inventory inv) {
    // Receipt totals may be negative for refunds; preserve that sign so the
    // summary reflects net revenue instead of treating refunds as new sales.
    if (inv.safeTotalSalesRevenue != 0) return inv.safeTotalSalesRevenue;

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
      if (_staffNameCache.containsKey(uid) ||
          _pendingStaffNameLoads.contains(uid)) {
        continue;
      }
      _pendingStaffNameLoads.add(uid);
      FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(uid)
          .get()
          .then((snapshot) {
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
          })
          .catchError((_) {
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
      if (!BranchSession.instance.isMainBranch &&
          !_branchStaffIds.contains(inv.ownerId))
        return false;
      if (!_isSameDay(inv.timestamp, _selectedDate)) return false;
      return _matchesSearchQuery(inv);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(color: _C.cream, child: _buildSalesContent());
  }

  Widget _buildSalesContent() {
    final entries = InventoryService().entries;

    // Sort by timestamp descending (newest first)
    final sortedEntries = List<Inventory>.from(entries)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _prefetchStaffNamesForEntries(sortedEntries);

    final filteredEntries = _filterEntries(sortedEntries);
    if (!_receiptGroupsLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_receiptGroupsLoaded) _groupEntriesByReceipt(filteredEntries);
      });
    }
    final visibleEntries = _receiptGroupsLoaded
        ? _receiptEntries
        : filteredEntries;

    return FadeTransition(
      opacity: _fadeCtrl,
      child: RefreshIndicator(
        color: _C.caramel,
        backgroundColor: _C.milk,
        onRefresh: () async {
          await InventoryService().refreshFromCloud();
          if (mounted) {
            setState(() {
              _receiptGroupsLoaded = false;
              _receiptEntries = const [];
              _receiptByPrimaryKey.clear();
            });
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // ── Summary banner ──────────────────────────────
            SliverToBoxAdapter(child: _buildSummaryBanner(visibleEntries)),

            // ── Section label ───────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Row(
                  children: [
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
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BranchSalesReportPage(),
                        ),
                      ),
                      icon: const Icon(Icons.assessment_rounded, size: 17),
                      label: const Text('Report'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _C.espresso,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Search Filter ────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  onChanged: (value) => setState(() {
                    _searchQuery = value;
                    _receiptGroupsLoaded = false;
                  }),
                  decoration: InputDecoration(
                    hintText: 'Search staff name or item',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: _C.foam,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
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
                        _receiptGroupsLoaded = false;
                        _receiptPrimaryKeys = <String>{};
                        _receiptByPrimaryKey.clear();
                        _receiptEntries = const [];
                      });
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: _C.foam,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _C.caramel, width: 1.5),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
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
              sliver: visibleEntries.isEmpty
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
                      delegate: SliverChildBuilderDelegate((_, i) {
                        final receipt =
                            _receiptByPrimaryKey[_inventoryEntryKey(
                              visibleEntries[i],
                            )];
                        return receipt == null
                            ? const SizedBox.shrink()
                            : _AdminReceiptCard(data: receipt);
                      }, childCount: visibleEntries.length),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBanner(List<Inventory> entries) {
    double grandTotal = entries.fold(
      0,
      (sum, inv) => sum + _calcSoldValue(inv),
    );

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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: Colors.white,
                  size: 18,
                ),
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
            ],
          ),
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
          Container(height: 1, color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _C.foam,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "${entries.length} entries",
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _C.caramel,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
          child: const Icon(
            Icons.receipt_long_outlined,
            size: 54,
            color: _C.latte,
          ),
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
            style: TextStyle(fontSize: 13, color: _C.latte, height: 1.5),
          ),
        ),
      ],
    ),
  );
}

// ── SALES CARD (extracted for animation) ────────────────────────────
class _ReceiptStaffDetails {
  final String name;
  final String staffId;
  final String branch;

  const _ReceiptStaffDetails({
    required this.name,
    required this.staffId,
    required this.branch,
  });
}

class _AdminReceiptCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AdminReceiptCard({required this.data});

  double _money(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  int _quantity(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

  Future<_ReceiptStaffDetails?> _loadStaffDetails() async {
    final userId = data['userId']?.toString().trim() ?? '';
    if (userId.isEmpty) return null;
    try {
      final staffDoc = await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(userId)
          .get();
      final staff = staffDoc.data();
      if (staff == null) return null;

      final name = [
        staff['firstName']?.toString().trim() ?? '',
        staff['middleName']?.toString().trim() ?? '',
        staff['lastName']?.toString().trim() ?? '',
      ].where((part) => part.isNotEmpty).join(' ');
      final staffId = staff['staffId']?.toString().trim() ?? userId;
      final identifiers = <String>{userId, staffId};
      for (final key in ['uid', 'userId']) {
        final value = staff[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) identifiers.add(value);
      }

      final branches = await FirebaseFirestore.instance
          .collection('branches')
          .get();
      String branchName = 'Main Branch';
      for (final branch in branches.docs) {
        if (branch.data()['isVoided'] == true) continue;
        final staffIds = (branch.data()['staffIds'] as List<dynamic>? ?? [])
            .map((id) => id.toString().trim());
        if (staffIds.any(identifiers.contains)) {
          branchName = branch.data()['name']?.toString().trim() ?? 'Branch';
          break;
        }
      }
      return _ReceiptStaffDetails(
        name: name.isEmpty ? 'Staff' : name,
        staffId: staffId,
        branch: branchName.isEmpty ? 'Branch' : branchName,
      );
    } catch (_) {
      return null;
    }
  }

  String _dateTime(DateTime value) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${months[value.month - 1]} ${value.day}, ${value.year} · $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final salesId = data['salesId']?.toString() ?? 'Receipt';
    final timestamp = data['timestamp'] is Timestamp
        ? (data['timestamp'] as Timestamp).toDate().toLocal()
        : DateTime.now();
    final paymentMode = data['paymentMode']?.toString() ?? 'Cash';
    final gcashId = data['gcashTransactionId']?.toString().trim() ?? '';
    final total = _money(data['total']);
    final paid = _money(data['paidAmount']);
    final change = _money(data['change']);
    final items = (data['items'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
    final discount = _money(data['discount']);
    final discountType = data['discountType']?.toString().trim() ?? '';
    final discountProofId = data['discountProofId']?.toString().trim() ?? '';
    final transactionType = data['type']?.toString().trim().toLowerCase() ?? '';
    final status = data['status']?.toString().trim().toLowerCase() ?? '';
    final isRefund = transactionType == 'refund' || status == 'refund';
    final fullyRefunded = data['fullyRefunded'] == true;
    final hasRefundedItem = items.any((item) => _quantity(item['refunded']) > 0);
    final hasRefundActivity = isRefund || fullyRefunded || hasRefundedItem;
    final refundReason = (data['reason'] ?? data['refundReason'])
      ?.toString()
      .trim() ??
      '';
    final refundSource = data['source']?.toString().trim() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _C.mocha.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_C.espresso, _C.caramel],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.receipt_long_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          salesId,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _dateTime(timestamp),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  FutureBuilder<_ReceiptStaffDetails?>(
                    future: _loadStaffDetails(),
                    builder: (context, snapshot) {
                      final details = snapshot.data;
                      if (details == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 9, left: 30),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.person_outline_rounded,
                              color: Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${details.name} (${details.staffId})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Icon(
                              Icons.storefront_outlined,
                              color: Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                details.branch,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ...items.map((item) {
                    final name = item['variant']?.toString().isNotEmpty == true
                        ? '${item['name']} (${item['variant']})'
                        : item['name']?.toString() ?? 'Item';
                    final kind = item['isBundle'] == true
                        ? 'Bundle'
                        : item['isCoffee'] == true
                        ? 'Coffee'
                        : '';
                    final displayName = kind.isEmpty ? name : '$name • $kind';
                    final quantity = _quantity(item['quantity']);
                    final refundedQuantity = _quantity(item['refunded']);
                    final lineTotal = _money(item['price']) * quantity;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${quantity}x $displayName${refundedQuantity > 0 ? ' · refunded $refundedQuantity' : ''}',
                              style: const TextStyle(
                                color: _C.espresso,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '₱${lineTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: _C.espresso,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 18),
                  _adminReceiptLine(
                    'Mode of Payment',
                    paymentMode == 'GCash' && gcashId.isNotEmpty
                        ? 'GCash - $gcashId'
                        : paymentMode,
                  ),
                  if (hasRefundActivity && refundReason.isNotEmpty)
                    _adminReceiptLine(
                      'Refund Reason${refundSource.isNotEmpty ? ' ($refundSource)' : ''}',
                      refundReason,
                    ),
                  if (discount > 0.01 && discountType.toLowerCase() != 'none')
                    _adminReceiptLine(
                      'Discount ($discountType)',
                      '-₱${discount.toStringAsFixed(2)}',
                    ),
                  if (discountProofId.isNotEmpty)
                    _adminReceiptLine(
                      discountType.isEmpty ? 'Discount ID' : '$discountType ID',
                      discountProofId,
                    ),
                  _adminReceiptLine(
                    'Customer Paid',
                    '₱${paid.toStringAsFixed(2)}',
                  ),
                  _adminReceiptLine('Change', '₱${change.toStringAsFixed(2)}'),
                  _adminReceiptLine(
                    isRefund ? 'Refund Amount' : 'Total',
                    '₱${total.toStringAsFixed(2)}',
                    strong: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminReceiptLine(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: _C.mocha,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: strong ? const Color(0xFF388E3C) : _C.espresso,
              fontSize: strong ? 18 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesCard extends StatefulWidget {
  final Inventory inv;
  final Map<String, dynamic>? receipt;
  final String Function(DateTime) formatDate;
  final String Function(DateTime) formatTime;
  final double Function(Inventory) calcSoldValue;
  final Duration animDelay;

  const _SalesCard({
    required this.inv,
    required this.receipt,
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
  bool _expanded = false;
  List<Map<String, dynamic>> _orderedItems = const [];
  String? _receiptSalesId;
  String? _orderedCategory;
  String? _orderedProductName;
  String? _branchName;
  double? _receiptTotal;
  DateTime? _receiptTimestamp;
  bool _hideDuplicateCard = false;
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  late Future<_StaffInfo?> _staffInfo;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _staffInfo = _loadStaffInfo(widget.inv.ownerId);
    _loadOrderedItems();
    _loadBranchName();

    Future.delayed(widget.animDelay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrderedItems() async {
    // The admin record must show the same line items as the staff receipt.
    // Do not infer quantities from stock, and do not merge variants/items.
    final directReceipt = widget.receipt;
    if (directReceipt != null) {
      final receiptItems = (directReceipt['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((raw) {
            final item = Map<String, dynamic>.from(raw);
            final name = item['name']?.toString().trim() ?? 'Item';
            final variant = item['variant']?.toString().trim() ?? '';
            final kind = item['isBundle'] == true
                ? 'Bundle'
                : item['isCoffee'] == true
                ? 'Coffee'
                : '';
            final displayName = [
              variant.isNotEmpty ? '$name ($variant)' : name,
              if (kind.isNotEmpty) kind,
            ].join(' • ');
            return <String, dynamic>{
              'name': displayName,
              'quantity': int.tryParse(item['quantity']?.toString() ?? '') ?? 0,
              'price': double.tryParse(item['price']?.toString() ?? '') ?? 0,
              'isCoffee': item['isCoffee'] == true,
            };
          })
          .toList();
      final rawItems = (directReceipt['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .toList();
      final Map? firstItem = rawItems.isEmpty ? null : rawItems.first;
      final firstVariant = firstItem == null
          ? ''
          : firstItem['variant']?.toString().trim() ?? '';
      final firstName = firstItem == null
          ? ''
          : firstItem['name']?.toString().trim() ?? '';
      final firstCategory = firstItem == null
          ? ''
          : firstItem['category']?.toString().trim() ?? '';
      final firstIsCoffee = firstItem != null && firstItem['isCoffee'] == true;
      final firstIsBundle = firstItem != null && firstItem['isBundle'] == true;
      final timestamp = directReceipt['timestamp'] is Timestamp
          ? (directReceipt['timestamp'] as Timestamp).toDate()
          : null;
      if (mounted) {
        setState(() {
          _receiptSalesId = directReceipt['salesId']?.toString().trim();
          _receiptTotal = double.tryParse(
            directReceipt['total']?.toString() ?? '',
          );
          _receiptTimestamp = timestamp;
          _orderedItems = receiptItems;
          _orderedCategory = firstIsCoffee
              ? 'Coffee'
              : firstIsBundle
              ? 'Bundle'
              : firstCategory;
          _orderedProductName = firstVariant.isNotEmpty
              ? firstVariant
              : firstName;
          _hideDuplicateCard = false;
        });
      }
      return;
    }

    final staffId = widget.inv.ownerId;
    if (staffId == null || staffId.isEmpty) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('completed_sales')
          .where('userId', isEqualTo: staffId)
          .get();
      final candidates = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final sale = doc.data();
        final timestamp = (sale['timestamp'] as Timestamp?)?.toDate();
        if (timestamp == null ||
            timestamp.year != widget.inv.timestamp.year ||
            timestamp.month != widget.inv.timestamp.month ||
            timestamp.day != widget.inv.timestamp.day) {
          continue;
        }
        final saleItems = sale['items'] as List<dynamic>? ?? [];
        if (saleItems.whereType<Map>().isNotEmpty) {
          candidates.add({
            'data': sale,
            'timestamp': timestamp,
            'fallbackId': doc.id,
          });
        }
      }

      candidates.sort((a, b) {
        final aTime = a['timestamp'] as DateTime;
        final bTime = b['timestamp'] as DateTime;
        final aDistance = aTime.difference(widget.inv.timestamp).abs();
        final bDistance = bTime.difference(widget.inv.timestamp).abs();
        return aDistance.compareTo(bDistance);
      });

      final grouped = <String, Map<String, dynamic>>{};
      String? orderedCategory;
      String? orderedProductName;
      if (candidates.isNotEmpty) {
        final selected = candidates.first;
        final sale = selected['data'] as Map<String, dynamic>;
        final selectedItems = sale['items'] as List<dynamic>? ?? [];
        final firstReceiptItem = selectedItems.whereType<Map>().isNotEmpty
            ? Map<String, dynamic>.from(selectedItems.whereType<Map>().first)
            : <String, dynamic>{};
        for (final rawItem in selectedItems.whereType<Map>()) {
          final item = Map<String, dynamic>.from(rawItem);
          final name = item['name']?.toString().trim() ?? 'Item';
          final variant = item['variant']?.toString().trim() ?? '';
          final coffeeSize = item['coffeeSize']?.toString().trim() ?? '';
          orderedCategory ??= item['isCoffee'] == true
              ? 'Coffee'
              : item['isBundle'] == true
              ? 'Bundle'
              : (item['category']?.toString().trim().isNotEmpty == true
                    ? item['category']?.toString().trim()
                    : widget.inv.safeItem);
          orderedProductName ??= item['isCoffee'] == true
              ? name
              : (variant.isNotEmpty ? variant : name);
          final displayName = item['isCoffee'] == true && coffeeSize.isNotEmpty
              ? coffeeSize
              : (variant.isNotEmpty ? variant : name);
          final key = '$displayName|$variant';
          final quantity =
              int.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
          final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
          final existing = grouped[key];
          grouped[key] = {
            'name': displayName,
            'quantity': (existing?['quantity'] as int? ?? 0) + quantity,
            'price': price > 0 ? price : (existing?['price'] ?? 0),
            'isCoffee': item['isCoffee'] == true,
          };
        }

        final receiptId = sale['salesId']?.toString().trim();
        final receiptTotal = double.tryParse(sale['total']?.toString() ?? '');
        if (mounted) {
          setState(() {
            _receiptSalesId = receiptId?.isNotEmpty == true
                ? receiptId
                : selected['fallbackId']?.toString();
            _orderedCategory = orderedCategory;
            _orderedProductName = orderedProductName;
            _orderedItems = grouped.values.toList();
            _receiptTotal = receiptTotal;
            final currentInventoryName = widget.inv.safeItem
                .trim()
                .toLowerCase();
            final firstItemName =
                firstReceiptItem['name']?.toString().trim().toLowerCase() ?? '';
            final firstItemCategory =
                firstReceiptItem['category']?.toString().trim().toLowerCase() ??
                '';
            final firstItemSource =
                firstReceiptItem['sourceInventoryId']?.toString().trim() ?? '';
            final currentSource = widget.inv.sourceInventoryId?.trim() ?? '';
            final itemMatchesCategory =
                firstItemCategory.isNotEmpty &&
                (currentInventoryName == firstItemCategory ||
                    firstItemCategory.contains(currentInventoryName) ||
                    currentInventoryName.contains(firstItemCategory));
            final itemNameMatches =
                firstItemName.isNotEmpty &&
                (currentInventoryName == firstItemName ||
                    firstItemName.contains(currentInventoryName));
            final isPrimaryReceiptCard =
                (currentSource.isNotEmpty &&
                    firstItemSource.isNotEmpty &&
                    currentSource == firstItemSource) ||
                itemMatchesCategory ||
                itemNameMatches;
            _hideDuplicateCard =
                firstReceiptItem.isNotEmpty && !isPrimaryReceiptCard;
          });
        }
      }
    } catch (_) {
      // The stock snapshot remains available if receipt history is unavailable.
    }
  }

  Future<void> _loadBranchName() async {
    final staffId = widget.inv.ownerId?.trim() ?? '';
    if (staffId.isEmpty) return;

    try {
      final identifiers = <String>{staffId};
      final staffDoc = await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(staffId)
          .get();
      final staffData = staffDoc.data();
      if (staffData != null) {
        for (final key in ['uid', 'userId', 'staffId']) {
          final value = staffData[key]?.toString().trim() ?? '';
          if (value.isNotEmpty) identifiers.add(value);
        }
      }

      final branches = await FirebaseFirestore.instance
          .collection('branches')
          .get();
      for (final branch in branches.docs) {
        if (branch.data()['isVoided'] == true) continue;
        final branchStaffIds =
            (branch.data()['staffIds'] as List<dynamic>? ?? [])
                .map((id) => id.toString().trim())
                .toSet();
        if (!branchStaffIds.any(identifiers.contains)) continue;
        final name = branch.data()['name']?.toString().trim() ?? '';
        if (mounted)
          setState(() => _branchName = name.isEmpty ? 'Branch' : name);
        return;
      }

      if (mounted) setState(() => _branchName = 'Main Branch');
    } catch (_) {
      if (mounted) setState(() => _branchName = 'Main Branch');
    }
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
      final nameParts = [
        firstName,
        middleName,
        lastName,
      ].where((part) => part.isNotEmpty).toList();
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
    final datePart =
        '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';
    final timePart =
        '${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}';
    final ownerSegment = (inv.ownerId ?? '').replaceAll(
      RegExp(r'[^A-Za-z0-9]'),
      '',
    );
    final ownerCode = ownerSegment.length >= 4
        ? ownerSegment.substring(0, 4).toUpperCase()
        : ownerSegment.toUpperCase().padRight(4, 'X');
    return 'SALE-$datePart-$timePart-$ownerCode';
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.inv;
    final itemsList = inv.safeItems;
    final soldValue = _receiptTotal ?? widget.calcSoldValue(inv);
    final dt = (_receiptTimestamp ?? inv.timestamp).toLocal();

    if (_hideDuplicateCard) return const SizedBox.shrink();

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
                if (_branchName != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.storefront_rounded,
                          size: 16,
                          color: _C.caramel,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Branches: $_branchName',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _C.caramel,
                          ),
                        ),
                      ],
                    ),
                  ),

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
                        child: const Icon(
                          Icons.bakery_dining_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Product name
                            Text(
                              _orderedCategory != null &&
                                      _orderedProductName != null
                                  ? '$_orderedCategory - $_orderedProductName'
                                  : (inv.safeItem.isNotEmpty
                                        ? inv.safeItem
                                        : 'Product Sale'),
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
                              'ID: ${_receiptSalesId ?? _buildSalesId(inv)}',
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
                                    const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 11,
                                      color: _C.latte,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.formatDate(dt),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: _C.latte,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.access_time_rounded,
                                      size: 11,
                                      color: _C.latte,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.formatTime(dt),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: _C.latte,
                                        fontWeight: FontWeight.w500,
                                      ),
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
                                if (!snapshot.hasData ||
                                    snapshot.data == null) {
                                  return const SizedBox.shrink();
                                }
                                final staff = snapshot.data!;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.person_rounded,
                                          size: 13,
                                          color: _C.espresso,
                                        ),
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
                      // Revenue
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
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
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── DIVIDER ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Container(height: 1, color: _C.foam),
                ),

                // ── ORDERED ITEMS ──────────────────────────────────
                if (itemsList.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.receipt_long_rounded,
                            size: 15,
                            color: _C.caramel,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _orderedItems.any(
                                  (item) => item['isCoffee'] == true,
                                )
                                ? 'Ordered sizes'
                                : 'Ordered items',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _C.caramel,
                            ),
                          ),
                          const Spacer(),
                          AnimatedRotation(
                            turns: _expanded ? 0 : 0.5,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                              Icons.keyboard_arrow_up_rounded,
                              color: _C.latte,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox(height: 0),
                    secondChild: _buildItemsList(inv),
                    crossFadeState: _expanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
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
        SnackBar(
          content: Text('Error loading reduced items: ${error.toString()}'),
        ),
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
      final unitPrice =
          double.tryParse(
            data['unitPrice']?.toString() ?? data['price']?.toString() ?? '0',
          ) ??
          0;
      final lossAmount =
          double.tryParse(data['lossAmount']?.toString() ?? '0') ?? 0;
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

            final filteredTotalLoss = filteredDocs.fold<double>(0.0, (
              sum,
              doc,
            ) {
              final data = doc.data();
              final quantity =
                  int.tryParse(data['quantity']?.toString() ?? '0') ?? 0;
              final unitPrice =
                  double.tryParse(
                    data['unitPrice']?.toString() ??
                        data['price']?.toString() ??
                        '0',
                  ) ??
                  0;
              final lossAmount =
                  double.tryParse(data['lossAmount']?.toString() ?? '0') ?? 0;
              final effectiveLoss = lossAmount > 0
                  ? lossAmount
                  : (unitPrice > 0 ? unitPrice * quantity : 0.0);
              return sum + effectiveLoss;
            });

            return AlertDialog(
              title: Text(
                'Reduced items - ${widget.formatDate(widget.inv.timestamp)}',
              ),
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
                                onPressed: () =>
                                    setState(() => filterQuery = ''),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
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
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final data = filteredDocs[index].data();
                            final itemName =
                                data['itemName']?.toString() ?? 'Unknown';
                            final variant = data['variant']?.toString();
                            final displayQuantity =
                                data['quantity']?.toString() ?? '0';
                            final reason =
                                data['reason']?.toString() ?? 'No reason';
                            final comment = data['comment']?.toString() ?? '';
                            final createdAt = (data['createdAt'] as Timestamp?)
                                ?.toDate();
                            final quantity =
                                int.tryParse(
                                  data['quantity']?.toString() ?? '0',
                                ) ??
                                0;
                            final unitPrice =
                                double.tryParse(
                                  data['unitPrice']?.toString() ??
                                      data['price']?.toString() ??
                                      '0',
                                ) ??
                                0;
                            final lossAmount =
                                double.tryParse(
                                  data['lossAmount']?.toString() ?? '0',
                                ) ??
                                0;
                            final effectiveLoss = lossAmount > 0
                                ? lossAmount
                                : (unitPrice > 0 ? unitPrice * quantity : 0.0);
                            final rowLabel =
                                variant != null && variant.isNotEmpty
                                ? '$itemName ($variant)'
                                : itemName;

                            return Container(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                14,
                                14,
                                14,
                              ),
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
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
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

      refunds = snapshot.docs.map((doc) => doc.data()).where((data) {
        final type = data['type']?.toString().toLowerCase();
        final status = data['status']?.toString().toLowerCase();
        return (type == 'refund' || status == 'refund') &&
            _isSameDay(
              (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime(0),
              widget.inv.timestamp,
            );
      }).toList();

      refunds.sort((a, b) {
        final aTs = (a['timestamp'] as Timestamp?)?.toDate();
        final bTs = (b['timestamp'] as Timestamp?)?.toDate();
        if (aTs == null || bTs == null) return 0;
        return bTs.compareTo(aTs);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading refund items: ${error.toString()}'),
        ),
      );
      return;
    }

    if (!mounted) return;

    final totalRefundAmount = refunds.fold<double>(0.0, (sum, data) {
      final total = double.tryParse(data['total']?.toString() ?? '0') ?? 0;
      final delta =
          double.tryParse(data['cashDrawerDelta']?.toString() ?? '0') ?? 0;
      final subtotal =
          double.tryParse(data['subtotal']?.toString() ?? '0') ?? 0;
      return sum +
          (total.abs() > 0
              ? total.abs()
              : delta.abs() > 0
              ? delta.abs()
              : subtotal.abs());
    });

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Refund items - ${widget.formatDate(widget.inv.timestamp)}',
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: refunds.isEmpty ? 260 : 500,
            child: refunds.isEmpty
                ? const Center(
                    child: Text(
                      'No refund items found for this staff on this date.',
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
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
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final data = refunds[index];
                            final salesId =
                                data['salesId']?.toString() ?? 'Refund';
                            final reason =
                                data['reason']?.toString() ?? 'No reason';
                            final source = data['source']?.toString() ?? '';
                            final createdAt = (data['timestamp'] as Timestamp?)
                                ?.toDate();
                            final items =
                                (data['items'] as List<dynamic>? ?? [])
                                    .whereType<Map<String, dynamic>>()
                                    .toList();
                            final itemCount = items.fold<int>(0, (sum, item) {
                              return sum +
                                  (int.tryParse(
                                        item['quantity']?.toString() ?? '0',
                                      ) ??
                                      0);
                            });

                            return Container(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                14,
                                14,
                                14,
                              ),
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
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _C.espresso,
                                    ),
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
                                      final itemName =
                                          item['name']?.toString() ?? 'Item';
                                      final quantity =
                                          int.tryParse(
                                            item['quantity']?.toString() ?? '0',
                                          ) ??
                                          0;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
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
    final receiptItems = _orderedItems.isNotEmpty
        ? _orderedItems
        : items
              .asMap()
              .entries
              .where((entry) {
                final index = entry.key;
                if (index >= starts.length || index >= rems.length)
                  return false;
                final reduced =
                    int.tryParse(
                      entry.value['reducedQuantity']?.toString() ?? '',
                    ) ??
                    0;
                final sold = (starts[index] - rems[index] - reduced)
                    .clamp(0, starts[index])
                    .toInt();
                return sold > 0;
              })
              .map((entry) {
                final index = entry.key;
                final item = entry.value;
                final reduced =
                    int.tryParse(item['reducedQuantity']?.toString() ?? '') ??
                    0;
                return <String, dynamic>{
                  'name': item['name']?.toString() ?? 'Item',
                  'quantity': (starts[index] - rems[index] - reduced)
                      .clamp(0, starts[index])
                      .toInt(),
                  'price':
                      double.tryParse(item['price']?.toString() ?? '0') ?? 0,
                  'isCoffee': item['isCoffee'] == true,
                };
              })
              .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Column(
        children: [
          Container(height: 1, color: _C.foam),
          const SizedBox(height: 12),
          ...receiptItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final name = item['name']?.toString() ?? 'Item';
            final quantity =
                int.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
            final price =
                double.tryParse(item['price']?.toString() ?? '0') ?? 0;
            final lineTotal = quantity * price;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _C.cream,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _C.latte.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
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
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _C.espresso,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    if (quantity > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _C.caramel.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "x$quantity",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _C.caramel,
                          ),
                        ),
                      ),
                    if (quantity > 0) const SizedBox(width: 10),
                    Text(
                      "₱${lineTotal.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _C.mocha,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
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
