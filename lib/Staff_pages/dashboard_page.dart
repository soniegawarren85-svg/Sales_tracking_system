// dashboard_page.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/inventory_service.dart';
import 'AllCateg.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

String _formatDate(DateTime dt) {
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
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

String _formatTime(DateTime dt) {
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $ampm';
}

String _formatDateTime(DateTime dt) =>
    '${_formatDate(dt)} · ${_formatTime(dt)}';

bool _isExpiredInventoryItem(String expirationDate) {
  try {
    final expiryDate = DateTime.parse(expirationDate);
    final today = DateTime.now();
    return expiryDate.isBefore(
      DateTime(today.year, today.month, today.day + 1),
    );
  } catch (e) {
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
int _parseStockValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int _availableStockForInventoryItem(Map<String, dynamic> item) {
  final hasStockField = item.containsKey('stock') && item['stock'] != null;
  if (hasStockField) return _parseStockValue(item['stock']);
  return _parseStockValue(item['startingStock']);
}

// Brand Colours (shared)
// ═══════════════════════════════════════════════════════════════════════════

List<String> _inventoryImageUrls(Map<String, dynamic> data) {
  final urls = <String>[];
  final seen = <String>{};
  final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  for (final item in items) {
    final url = item['imageUrl']?.toString().trim() ?? '';
    if (url.isNotEmpty && seen.add(url)) urls.add(url);
  }
  final categoryUrl = data['imageUrl']?.toString().trim() ?? '';
  if (categoryUrl.isNotEmpty && seen.add(categoryUrl)) urls.add(categoryUrl);
  return urls;
}

class _C {
  static const primary = Color(0xFFE91E63);
  static const primaryLight = Color(0xFFF48FB1);
  static const primaryDark = Color(0xFFC2105C);
  static const accent = Color(0xFFFF8C42);
  static const gold = Color(0xFFFFD166);
  static const surface = Color(0xFFFFF8F5);
}

// ═══════════════════════════════════════════════════════════════════════════
// DashboardPage
// ═══════════════════════════════════════════════════════════════════════════

class DashboardPage extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback onMessage;
  final VoidCallback? onNotification;

  const DashboardPage({
    super.key,
    required this.scrollController,
    required this.onMessage,
    this.onNotification,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  List inventoryEntries = [];
  String _inventoryView = 'categories';
  List<String> _staffInventoryIds = const [];

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if ((uid ?? '').isNotEmpty) {
      _staffInventoryIds = const [];
      _loadStaffInventoryIds(uid!);
    }
    InventoryService().addListener(_onInventoryChanged);

    InventoryService().initialize().then((_) => InventoryService().refreshFromCloud()).then((_) {
      if (!mounted) return;
      setState(() {
        inventoryEntries = InventoryService().currentUserEntries;
      });
    });
  }

  @override
  void dispose() {
    InventoryService().removeListener(_onInventoryChanged);
    super.dispose();
  }

  void _onInventoryChanged() {
    if (mounted)
      setState(() => inventoryEntries = InventoryService().currentUserEntries);
  }

  Future<void> _loadStaffInventoryIds(String uid) async {
    final ids = <String>{};
    try {
      final doc = await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(uid)
          .get();
      final data = doc.data();
      final publicStaffId = data?['staffId']?.toString().trim() ?? '';
      final branchIds = (data?['branchIds'] as List<dynamic>? ?? [])
          .map((id) => id.toString().trim())
          .where((id) => id.isNotEmpty);
      ids.addAll(branchIds);
      final byUid = await FirebaseFirestore.instance
          .collection('branches')
          .where('staffIds', arrayContains: uid)
          .get();
      ids.addAll(byUid.docs.map((doc) => doc.id));
      if (publicStaffId.isNotEmpty) {
        final byPublicId = await FirebaseFirestore.instance
            .collection('branches')
            .where('staffIds', arrayContains: publicStaffId)
            .get();
        ids.addAll(byPublicId.docs.map((doc) => doc.id));
      }
    } catch (_) {}

    if (mounted) setState(() => _staffInventoryIds = ids.toList());
  }

  Stream<QuerySnapshot> _staffInventoryStream() {
    final ids = _staffInventoryIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .take(10)
        .toList();
    final query = FirebaseFirestore.instance.collection('staff_inventory');
    if (ids.isEmpty) {
      return query.where('staffId', isEqualTo: '').snapshots();
    }
    return ids.length == 1
        ? query.where('staffId', isEqualTo: ids.first).snapshots()
        : query.where('staffId', whereIn: ids).snapshots();
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HistorySheet(inventoryEntries: inventoryEntries),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: widget.scrollController,
      slivers: [
        // ── Header ────────────────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 370,
          collapsedHeight: 60,
          pinned: true,
          elevation: 0,
          backgroundColor: _C.primary,
          foregroundColor: Colors.white,
          centerTitle: false,
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: _Header(
              onMessage: widget.onMessage,
              onNotification: widget.onNotification,
              drawerIds: _staffInventoryIds,
            ),
          ),
        ),

        // ── "Dashboard" label ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            color: _C.surface,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: _SectionLabel(title: 'Dashboard'),
          ),
        ),

        // ── Inventory list ────────────────────────────────────────────────
        SliverSafeArea(
          top: false,
          sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(child: _buildAdminInventoryList()),
          ),
        ),

        // ── "Performance" label + History ─────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            color: _C.surface,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SectionLabel(title: 'Performance'),
                _HistoryButton(onTap: _showHistory),
              ],
            ),
          ),
        ),

        // ── Performance cards ─────────────────────────────────────────────
        SliverSafeArea(
          top: false,
          bottom: true,
          sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            sliver: SliverToBoxAdapter(child: _buildPerformanceData()),
          ),
        ),
      ],
    );
  }

  // ── Admin inventory list ──────────────────────────────────────────────────
  Widget _buildAdminInventoryList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _staffInventoryStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorCard(message: 'Error loading inventory');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: _C.primaryLight),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _EmptyState(
            icon: Icons.inventory_2_outlined,
            label: 'No inventory items found.',
          );
        }

        // ── Filter out sales transactions (status='completed') to show only inventory ──────────────────
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('sales_inventory')
              .snapshots(),
          builder: (context, rootSnapshot) {
            if (rootSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: _C.primaryLight),
                ),
              );
            }
            final activeRootById = <String, Map<String, dynamic>>{};
            final activeRootByName = <String, Map<String, dynamic>>{};
            for (final rootDoc in rootSnapshot.data?.docs ?? []) {
              final rootData = rootDoc.data() as Map<String, dynamic>?;
              if (rootData == null || rootData['isDeleted'] == true) continue;
              activeRootById[rootDoc.id] = rootData;
              final rootName = rootData['name']
                  ?.toString()
                  .trim()
                  .toLowerCase();
              if (rootName != null && rootName.isNotEmpty) {
                activeRootByName[rootName] = rootData;
              }
            }

            String itemKey(Map<String, dynamic> item) =>
                '${item['name'] ?? ''}|${item['price'] ?? ''}'.toLowerCase();

            List<Map<String, dynamic>> activeStaffItems(
              Map<String, dynamic> staffData,
              Map<String, dynamic> rootData,
            ) {
              final rootKeys = ((rootData['items'] as List<dynamic>?) ?? [])
                  .whereType<Map>()
                  .map((item) => itemKey(Map<String, dynamic>.from(item)))
                  .toSet();
              final staffItems = ((staffData['items'] as List<dynamic>?) ?? [])
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .where((item) {
                    final expirationDate =
                        item['expirationDate']?.toString() ?? '';
                    return !_isExpiredInventoryItem(expirationDate) &&
                        (rootKeys.isEmpty || rootKeys.contains(itemKey(item)));
                  })
                  .toList();
              return staffItems;
            }

            final inventoryDocs = <Map<String, dynamic>>[];
            for (final doc in docs) {
              final data = doc.data() as Map<String, dynamic>?;
              if (data == null ||
                  data['isDeleted'] == true ||
                  data['status'] == 'completed' ||
                  data['salesId'] != null) {
                continue;
              }

              final sourceId = data['sourceInventoryId']?.toString() ?? '';
              final name = data['name']?.toString().trim().toLowerCase() ?? '';
              final isCoffee = data['isCoffee'] == true;
              final rootData = isCoffee
                  ? data
                  : (activeRootById[sourceId] ?? activeRootByName[name]);
              if (rootData == null) continue;

              final items = isCoffee
                  ? [
                      {
                        'name': data['name'] ?? 'Coffee',
                        'price': data['basePrice'] ?? 0,
                        'stock': 999,
                        'startingStock': 999,
                        'isCoffee': true,
                      },
                    ]
                  : data['isBundle'] == true
                  ? (data['items'] as List<dynamic>? ?? [])
                  : activeStaffItems(data, rootData);
              if (!isCoffee && data['isBundle'] != true && items.isEmpty) {
                continue;
              }

              inventoryDocs.add({
                ...data,
                'staffDocId': doc.id,
                'sourceInventoryId': sourceId,
                'name': rootData['name'] ?? data['name'],
                'imageUrl': rootData['imageUrl'] ?? data['imageUrl'],
                'items': items,
                'isCoffee': isCoffee,
              });
            }

            if (inventoryDocs.isEmpty) {
              return const _EmptyState(
                icon: Icons.inventory_2_outlined,
                label: 'No inventory items found.',
              );
            }

            // ── Group documents by name to eliminate duplicates ──────────────────
            final Map<String, Map<String, dynamic>> uniqueItems = {};
            for (final data in inventoryDocs) {
              final name = (data['name']?.toString() ?? '').toLowerCase();
              final sourceId =
                  (data['sourceInventoryId']?.toString().trim().isNotEmpty ==
                      true)
                  ? data['sourceInventoryId'].toString()
                  : (data['staffDocId']?.toString() ?? name);
              final uniqueKey = data['isBundle'] == true
                  ? 'bundle:$sourceId'
                  : 'category:$sourceId';
              final items =
                  (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

              // Keep only active variants and ignore categories with none
              final activeVariants = items.where((item) {
                final expirationDate = item['expirationDate']?.toString() ?? '';
                return !_isExpiredInventoryItem(expirationDate);
              }).toList();

              if (activeVariants.isEmpty) continue;

              // Keep source inventory IDs separate even when categories share a name.
              if (!uniqueItems.containsKey(uniqueKey)) {
                uniqueItems[uniqueKey] = data;
              }
            }

            final sortedDocs = uniqueItems.values.toList();
            sortedDocs.sort((a, b) {
              final nameA = (a['name']?.toString() ?? '').toLowerCase();
              final nameB = (b['name']?.toString() ?? '').toLowerCase();
              return nameA.compareTo(nameB);
            });

            final filteredDocs = sortedDocs.where((data) {
              final isBundle = data['isBundle'] == true;
              final isCoffee = data['isCoffee'] == true;
              if (_inventoryView == 'bundle') return isBundle;
              if (_inventoryView == 'coffee') return isCoffee;
              return !isBundle && !isCoffee;
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AllCategPage(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.view_list_rounded,
                        color: _C.primaryDark,
                      ),
                      label: const Text(
                        'View All Items',
                        style: TextStyle(
                          color: _C.primaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _C.primaryDark),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _InventoryViewSelector(
                    selected: _inventoryView,
                    onSelected: (value) => setState(() {
                      _inventoryView = value;
                    }),
                  ),
                ),
                if (filteredDocs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: _EmptyState(
                      icon: _inventoryView == 'categories'
                          ? Icons.category_rounded
                          : Icons.inventory_2_rounded,
                      label: _inventoryView == 'bundle'
                          ? 'No bundles found.'
                          : _inventoryView == 'coffee'
                          ? 'No coffee items found.'
                          : 'No category items found.',
                    ),
                  )
                else
                  ...filteredDocs.map((data) {
                    final name = data['name']?.toString().trim() ?? '';
                    final rawSourceId =
                        data['sourceInventoryId']?.toString().trim() ?? '';
                    final sourceId = rawSourceId.isNotEmpty
                        ? rawSourceId
                        : data['staffDocId']?.toString().trim() ?? '';

                    // Skip if name is empty or it's "Unnamed Item"
                    if (name.isEmpty) return const SizedBox.shrink();

                    final isBundle = data['isBundle'] == true;
                    final items =
                        (data['items'] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        [];
                    final imageUrls = _inventoryImageUrls(data);
                    final availableStock = isBundle
                        ? (data['bundleCount'] is num
                              ? (data['bundleCount'] as num).toInt()
                              : int.tryParse(
                                      data['bundleCount']?.toString() ?? '',
                                    ) ??
                                    0)
                        : items.fold<int>(0, (sum, item) {
                            if (_isExpiredInventoryItem(
                              item['expirationDate']?.toString() ?? '',
                            )) {
                              return sum;
                            }
                            final itemStock = _availableStockForInventoryItem(
                              item,
                            );
                            return sum + (itemStock > 0 ? itemStock : 0);
                          });
                    final isLocked = availableStock <= 0;

                    // Derive a friendly category label
                    final nameLower = name.toLowerCase();
                    final coffeeId =
                        data['coffeeId']?.toString().trim() ?? '';
                    String category = 'Cupcakes';
                    if (data['isCoffee'] == true) {
                      category = coffeeId.isNotEmpty
                          ? 'Coffee - $coffeeId'
                          : 'Coffee';
                    } else if (nameLower.contains('cupcake') ||
                        nameLower.contains('cupcakes')) {
                      category = 'Cupcakes Set';
                    } else if (nameLower.contains('cake')) {
                      category = 'Cakes';
                    } else if (nameLower.contains('drink') ||
                        nameLower.contains('juice')) {
                      category = 'Beverages';
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ItemCard(
                        itemName: name,
                        category: category,
                        imageAsset: imageUrls.isNotEmpty
                            ? imageUrls.first
                            : 'Assets/Image/T.jpg',
                        imageAssets: imageUrls,
                        isLocked: isLocked,
                        onTap: () {
                          if (isLocked) {
                            _showLockedDialog();
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AllCategPage(
                                selectedCategoryName: name,
                                selectedSourceInventoryId: sourceId,
                                selectedIsBundle: data['isBundle'] == true,
                                selectedIsCoffee: data['isCoffee'] == true,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }).toList(),
              ],
            );
          },
        );
      },
    );
  }

  void _showLockedDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFF0E8), Color(0xFFFFE4CC)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.block_rounded,
                      color: _C.primaryLight,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Item Unavailable',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: _C.primaryDark,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: const Color(0xFFFFF5EE),
                  border: Border.all(color: const Color(0xFFE8C5B0)),
                ),
                child: const Text(
                  'This item has no available stock. Staff cannot open unavailable items. Please contact admin.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFFE91E63),
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Got it',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Contact Admin',
                    style: TextStyle(
                      color: _C.primaryLight,
                      fontWeight: FontWeight.w600,
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

  // ── Performance data ───────────────────────────────────────────────────────
  Widget _buildPerformanceData() {
    if (inventoryEntries.isEmpty) {
      return const _EmptyState(
        icon: Icons.bar_chart_rounded,
        label: 'No performance data yet.',
        sublabel: 'Start recording sales to see results here.',
      );
    }

    final sorted = [...inventoryEntries];
    bool isCoffeePerformanceEntry(
      List<Map<String, dynamic>> items,
      String title,
    ) {
      final titleLower = title.toLowerCase();
      return titleLower.contains('coffee') ||
          titleLower.contains('smoothie') ||
          titleLower.contains('latte') ||
          titleLower.contains('espresso') ||
          items.any((item) {
            return item['isCoffee'] == true ||
                (item['coffeeId']?.toString().trim().isNotEmpty ?? false) ||
                (item['coffeeSize']?.toString().trim().isNotEmpty ?? false) ||
                (item['addonName']?.toString().trim().isNotEmpty ?? false);
          });
    }

    sorted.sort((a, b) {
      final nameA = a is Map ? (a['item']?.toString() ?? '') : a.safeItem;
      final nameB = b is Map ? (b['item']?.toString() ?? '') : b.safeItem;
      final itemsA = a is Map
          ? (a['items'] as List?)?.cast<Map<String, dynamic>>() ?? []
          : a.safeItems;
      final itemsB = b is Map
          ? (b['items'] as List?)?.cast<Map<String, dynamic>>() ?? []
          : b.safeItems;
      final salesOnlyA = isCoffeePerformanceEntry(itemsA, nameA);
      final salesOnlyB = isCoffeePerformanceEntry(itemsB, nameB);
      if (!salesOnlyA && salesOnlyB) return -1;
      if (salesOnlyA && !salesOnlyB) return 1;
      final isCardA = nameA.toLowerCase().contains('cardboard sales');
      final isCardB = nameB.toLowerCase().contains('cardboard sales');
      if (isCardA && !isCardB) return -1;
      if (!isCardA && isCardB) return 1;
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    });

    return Column(
      children: sorted.map((inv) => _PerformanceCard(inv: inv)).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section Label
// ═══════════════════════════════════════════════════════════════════════════

class _InventoryViewSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _InventoryViewSelector({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      ('categories', Icons.category_outlined, 'Categories'),
      ('bundle', Icons.inventory_2_outlined, 'Bundle'),
      ('coffee', Icons.coffee_outlined, 'Coffee'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((option) {
          final isSelected = selected == option.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              selected: isSelected,
              avatar: Icon(
                option.$2,
                size: 18,
                color: isSelected ? Colors.white : _C.primaryDark,
              ),
              label: Text(option.$3),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : _C.primaryDark,
                fontWeight: FontWeight.w800,
              ),
              selectedColor: _C.primary,
              backgroundColor: Colors.white,
              side: const BorderSide(color: _C.primaryDark),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              onSelected: (_) => onSelected(option.$1),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_C.accent, Color(0xFFFF5722)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: _C.primaryDark,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// History Button
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HistoryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_C.primaryLight, _C.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _C.primary.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.history_rounded, color: Colors.white, size: 16),
            SizedBox(width: 6),
            Text(
              'History',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HEADER WIDGET  (upgraded — keeps all existing pictures)
// ═══════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final VoidCallback onMessage;
  final VoidCallback? onNotification;
  final List<String> drawerIds;
  const _Header({
    required this.onMessage,
    this.onNotification,
    required this.drawerIds,
  });

  Stream<QuerySnapshot<Map<String, dynamic>>> _cashDrawerStream() {
    final ids = drawerIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .take(10)
        .toList();
    final query = FirebaseFirestore.instance.collection('staff_cash_drawer');
    if (ids.isEmpty) {
      return query
          .where(FieldPath.documentId, isEqualTo: '__missing_drawer__')
          .snapshots();
    }
    return ids.length == 1
        ? query.where(FieldPath.documentId, isEqualTo: ids.first).snapshots()
        : query.where(FieldPath.documentId, whereIn: ids).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<DocumentSnapshot>(
      stream: user == null
          ? const Stream.empty()
          : FirebaseFirestore.instance
                .collection('staff_requests')
                .doc(user.uid)
                .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final firstName = data['firstName']?.toString().trim();
        final lastName = data['lastName']?.toString().trim();
        final name =
            ((firstName?.isNotEmpty ?? false) ||
                (lastName?.isNotEmpty ?? false))
            ? '${firstName ?? ''} ${lastName ?? ''}'.trim()
            : data['name']?.toString().trim() ?? 'Staff Name';
        final staffId = data['staffId']?.toString().trim() ?? '#0000';
        final role = data['role']?.toString().trim() ?? 'Staff Member';
        final photoUrl = data['photoUrl'] as String?;

        return Stack(
          fit: StackFit.expand,
          children: [
            // ── Background image (unchanged — your existing asset) ────────
            Image.asset(
              'Assets/Image/Bg.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: _C.primaryDark),
            ),

            // ── Rich layered overlay ──────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.fromARGB(221, 75, 0, 40),
                    Color.fromARGB(185, 255, 152, 217),
                    Color.fromARGB(235, 116, 1, 64),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),

            // ── Subtle diagonal stripe texture ────────────────────────────
            Opacity(
              opacity: 0.05,
              child: CustomPaint(
                painter: _StripePainter(),
                size: Size.infinite,
              ),
            ),

            // ── Decorative bottom arc ─────────────────────────────────────
            Positioned(
              bottom: -1,
              left: 0,
              right: 0,
              child: CustomPaint(
                painter: _ArcPainter(),
                child: const SizedBox(height: 15),
              ),
            ),

            // ── Main content ──────────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 66),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Top bar ─────────────────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo (unchanged picture, upgraded frame)
                        _LogoFrame(),

                        const SizedBox(width: 14),

                        // Brand name + tagline
                        Expanded(child: _BrandTitle()),

                        // Notification + Message buttons
                        Row(
                          children: [
                            _NotificationButton(
                              onTap:
                                  onNotification ??
                                  () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('No notifications yet.'),
                                      ),
                                    );
                                  },
                            ),
                            const SizedBox(width: 12),
                            _MessageButton(onTap: onMessage),
                          ],
                        ),
                      ],
                    ),

                    const Spacer(),

                    // ── Staff Profile Card ───────────────────────────────
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _cashDrawerStream(),
                      builder: (context, cashDrawerSnapshot) {
                        final cashDrawerBalance =
                            cashDrawerSnapshot.data?.docs.fold<double>(
                              0.0,
                              (sum, doc) =>
                                  sum +
                                  ((doc.data()['balance'] as num?)
                                          ?.toDouble() ??
                                      0.0),
                            ) ??
                            0.0;
                        return _StaffProfileCard(
                          name: name,
                          staffId: staffId,
                          role: role,
                          photoUrl: photoUrl,
                          cashDrawerBalance: cashDrawerBalance,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Logo frame ───────────────────────────────────────────────────────────────
class _LogoFrame extends StatelessWidget {
  const _LogoFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD166), Color(0xFFFF8C42)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _C.accent.withOpacity(0.55),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: ClipOval(
        child: Image.asset(
          'Assets/Image/ob.jpg',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: _C.primaryLight,
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Brand title ───────────────────────────────────────────────────────────────
class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFFFD166), Color(0xFFFF8C42)],
          ).createShader(bounds),
          child: const Text(
            "Angel Bite'z",
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _C.accent,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'Cupcakes',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFFFD8B5),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Message button ────────────────────────────────────────────────────────────
class _NotificationButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NotificationButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.28), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.notifications_none_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

// ── Message button ────────────────────────────────────────────────────────────
class _MessageButton extends StatelessWidget {
  final VoidCallback onTap;
  const _MessageButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.28), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.mail_outline_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAFF PROFILE CARD  ← KEY UPGRADE
// ═══════════════════════════════════════════════════════════════════════════

class _StaffProfileCard extends StatelessWidget {
  final String name;
  final String staffId;
  final String role;
  final String? photoUrl;
  final double cashDrawerBalance;

  const _StaffProfileCard({
    required this.name,
    required this.staffId,
    required this.role,
    this.photoUrl,
    required this.cashDrawerBalance,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 380;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withOpacity(0.11),
            border: Border.all(
              color: Colors.white.withOpacity(0.20),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.20),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _StaffAvatar(photoUrl: photoUrl),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RoleBadge(role: role),
                              const SizedBox(height: 6),
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.4,
                                  height: 1.1,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _StaffIdChip(staffId: staffId),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.18),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cash Drawer',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₱${cashDrawerBalance.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    // ── Avatar (picture unchanged, frame upgraded) ───────────────
                    _StaffAvatar(photoUrl: photoUrl),

                    const SizedBox(width: 16),

                    // ── Staff info ───────────────────────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Role / Title badge
                          _RoleBadge(role: role),

                          const SizedBox(height: 7),

                          // Staff name  ← UPGRADED
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.4,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                          const SizedBox(height: 8),

                          // Staff ID chip  ← UPGRADED
                          _StaffIdChip(staffId: staffId),
                        ],
                      ),
                    ),

                    Container(
                      width: 118,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.18),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Cash Drawer',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '₱${cashDrawerBalance.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

// ── Staff avatar ──────────────────────────────────────────────────────────────
class _StaffAvatar extends StatelessWidget {
  final String? photoUrl;
  const _StaffAvatar({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Gold gradient ring
        Container(
          width: 74,
          height: 74,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFFFD166), Color(0xFFFF8C42)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x77FF8C42),
                blurRadius: 18,
                spreadRadius: 3,
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: ClipOval(child: _buildPhoto()),
        ),
        // Online status dot
        Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: const Color(0xFF43A047),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(color: Colors.green.withOpacity(0.55), blurRadius: 6),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhoto() {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Image.network(
        photoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
    color: const Color(0xFFC2105C),
    child: const Icon(Icons.person_rounded, color: Color(0xFFFFD8B5), size: 38),
  );
}

// ── Role badge ────────────────────────────────────────────────────────────────
class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _C.gold.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.gold.withOpacity(0.50), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium_rounded, color: _C.gold, size: 12),
          const SizedBox(width: 5),
          Text(
            role.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: _C.gold,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Staff ID chip ─────────────────────────────────────────────────────────────
class _StaffIdChip extends StatelessWidget {
  final String staffId;
  const _StaffIdChip({required this.staffId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.badge_outlined, color: Color(0xFFFFD8B5), size: 14),
          const SizedBox(width: 6),
          // "ID" label
          const Text(
            'ID',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFFB380),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 5),
          // Thin divider
          Container(
            width: 1,
            height: 12,
            color: Colors.white.withOpacity(0.25),
          ),
          const SizedBox(width: 5),
          // Actual ID value
          Text(
            staffId,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFFFFD8B5),
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ITEM CARD WIDGET  (upgraded — keeps picture unchanged)
// ═══════════════════════════════════════════════════════════════════════════

class _ItemCard extends StatefulWidget {
  final String imageAsset;
  final List<String> imageAssets;
  final String itemName;
  final String category;
  final bool isLocked;
  final VoidCallback onTap;

  const _ItemCard({
    required this.imageAsset,
    this.imageAssets = const [],
    required this.itemName,
    required this.category,
    required this.isLocked,
    required this.onTap,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool _pressed = false;
  late final PageController _imageController;
  Timer? _imageTimer;
  int _imageIndex = 0;

  List<String> get _imageSources {
    final sources = widget.imageAssets
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();
    if (sources.isEmpty) sources.add(widget.imageAsset);
    return sources;
  }

  @override
  void initState() {
    super.initState();
    _imageController = PageController();
    _startImageTimer();
  }

  @override
  void didUpdateWidget(covariant _ItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageAssets.length != widget.imageAssets.length ||
        oldWidget.imageAsset != widget.imageAsset) {
      _imageIndex = 0;
      _imageTimer?.cancel();
      if (_imageController.hasClients) _imageController.jumpToPage(0);
      _startImageTimer();
    }
  }

  void _startImageTimer() {
    if (_imageSources.length < 2) return;
    _imageTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_imageController.hasClients) return;
      _imageIndex = (_imageIndex + 1) % _imageSources.length;
      _imageController.animateToPage(
        _imageIndex,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _imageTimer?.cancel();
    _imageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _C.primary.withOpacity(widget.isLocked ? 0.06 : 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Left accent bar (gradient) ────────────────────────
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: widget.isLocked
                            ? [Colors.grey.shade300, Colors.grey.shade200]
                            : [_C.gold, _C.accent, _C.primary],
                        stops: widget.isLocked ? null : const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),

                  // ── Item image (picture unchanged) ────────────────────
                  Container(
                    width: 84,
                    height: 84,
                    margin: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: _C.primary.withOpacity(0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _buildImageCarousel(),
                    ),
                  ),

                  // ── Text section ──────────────────────────────────────
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(2, 13, 4, 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Category label
                          Text(
                            widget.category.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: widget.isLocked
                                  ? Colors.grey.shade400
                                  : _C.accent.withOpacity(0.9),
                              letterSpacing: 1.2,
                            ),
                          ),

                          const SizedBox(height: 3),

                          // Item name  ← UPGRADED
                          Text(
                            widget.itemName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: widget.isLocked
                                  ? Colors.grey.shade500
                                  : _C.primaryDark,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          const SizedBox(height: 8),

                          // Status badge
                          _ItemStatusBadge(isLocked: widget.isLocked),
                        ],
                      ),
                    ),
                  ),

                  // ── Arrow / Lock button ───────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: widget.isLocked
                              ? LinearGradient(
                                  colors: [
                                    Colors.grey.shade200,
                                    Colors.grey.shade300,
                                  ],
                                )
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFFC2105C),
                                    Color(0xFFF48FB1),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: widget.isLocked
                              ? []
                              : [
                                  BoxShadow(
                                    color: _C.primary.withOpacity(0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Icon(
                          widget.isLocked
                              ? Icons.block_rounded
                              : Icons.chevron_right_rounded,
                          color: widget.isLocked
                              ? Colors.grey.shade500
                              : Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemImage() {
    return _buildImageSource(widget.imageAsset);
  }

  Widget _buildImageCarousel() {
    final sources = _imageSources;
    if (sources.length < 2) return _buildImageSource(sources.first);
    return PageView.builder(
      controller: _imageController,
      physics: const BouncingScrollPhysics(),
      itemCount: sources.length,
      onPageChanged: (page) => _imageIndex = page,
      itemBuilder: (context, index) => _buildImageSource(sources[index]),
    );
  }

  Widget _buildImageSource(String src) {
    if (src.startsWith('data:image/')) {
      final commaIndex = src.indexOf(',');
      if (commaIndex != -1) {
        try {
          return Image.memory(
            base64Decode(src.substring(commaIndex + 1)),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _imageFallback(),
          );
        } catch (_) {
          return _imageFallback();
        }
      }
    }
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(
        src,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imageFallback(),
      );
    }
    return Image.asset(
      src,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _imageFallback(),
    );
  }

  Widget _imageFallback() => Container(
    color: const Color(0xFFFFF0E4),
    child: const Icon(Icons.cake_rounded, color: _C.accent, size: 34),
  );
}

// ── Item status badge ─────────────────────────────────────────────────────────
class _ItemStatusBadge extends StatelessWidget {
  final bool isLocked;
  const _ItemStatusBadge({required this.isLocked});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isLocked ? Colors.grey.shade100 : const Color(0xFFFFF0E4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLocked ? Colors.grey.shade300 : _C.accent.withOpacity(0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLocked ? Icons.block_rounded : Icons.edit_note_rounded,
            size: 11,
            color: isLocked ? Colors.grey.shade500 : _C.primaryLight,
          ),
          const SizedBox(width: 4),
          Text(
            isLocked ? 'Unavailable' : 'Tap to view',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isLocked ? Colors.grey.shade500 : _C.primaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// History Bottom Sheet
// ═══════════════════════════════════════════════════════════════════════════

class _HistorySheet extends StatefulWidget {
  final List inventoryEntries;
  const _HistorySheet({required this.inventoryEntries});

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  String _selectedDate = '';

  Map<String, List<dynamic>> _groupByDate() {
    final Map<String, List<dynamic>> grouped = {};
    for (final inv in widget.inventoryEntries) {
      DateTime dt;
      try {
        dt = inv is Map
            ? (inv['timestamp']?.toDate() ?? DateTime.now()).toLocal()
            : inv.timestamp.toLocal();
      } catch (_) {
        dt = DateTime.now();
      }
      grouped.putIfAbsent(_formatDate(dt), () => []).add(inv);
    }
    return grouped;
  }

  @override
  void initState() {
    super.initState();
    final grouped = _groupByDate();
    if (grouped.isNotEmpty) _selectedDate = grouped.keys.first;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate();
    final dates = grouped.keys.toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFF8F5),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.pink.shade200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _C.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: _C.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Sales History',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _C.primaryDark,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Filter date',
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = _formatDate(picked));
                      }
                    },
                    icon: const Icon(
                      Icons.calendar_today_rounded,
                      color: _C.primary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: _C.primary),
                  ),
                ],
              ),
            ),

            // Date chips
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: dates.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final d = dates[i];
                  final selected = d == _selectedDate;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedDate = d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? _C.primary : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? _C.primary : Colors.pink.shade200,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: _C.primary.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : [],
                      ),
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : Colors.pink.shade600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 1, color: Color(0xFFEDD9C8)),

            Expanded(
              child: grouped.isEmpty
                  ? Center(
                      child: Text(
                        'No history available.',
                        style: TextStyle(
                          color: Colors.pink.shade400,
                          fontSize: 15,
                        ),
                      ),
                    )
                  : (grouped[_selectedDate]?.isEmpty ?? true)
                  ? Center(
                      child: Text(
                        'No history record',
                        style: TextStyle(
                          color: Colors.pink.shade400,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                      itemCount: grouped[_selectedDate]?.length ?? 0,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final inv = grouped[_selectedDate]![i];
                        return _HistoryEntryCard(inv: inv);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// History Entry Card
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryEntryCard extends StatelessWidget {
  final dynamic inv;
  const _HistoryEntryCard({required this.inv});

  int _startingAt(int index, int startA, int startB, int startC) {
    if (index == 0) return startA;
    if (index == 1) return startB;
    if (index == 2) return startC;
    return 0;
  }

  int _remainingAt(int index, int remA, int remB, int remC) {
    if (index == 0) return remA;
    if (index == 1) return remB;
    if (index == 2) return remC;
    return 0;
  }

  bool _isCoffeePerformanceEntry(
    List<Map<String, dynamic>> items,
    String title,
  ) {
    final titleLower = title.toLowerCase();
    return titleLower.contains('coffee') ||
        titleLower.contains('smoothie') ||
        titleLower.contains('latte') ||
        titleLower.contains('espresso') ||
        items.any((item) {
          return item['isCoffee'] == true ||
              (item['coffeeId']?.toString().trim().isNotEmpty ?? false) ||
              (item['coffeeSize']?.toString().trim().isNotEmpty ?? false) ||
              (item['addonName']?.toString().trim().isNotEmpty ?? false);
        });
  }

  @override
  Widget build(BuildContext context) {
    final String item = inv is Map
        ? (inv['item']?.toString() ?? 'Unknown')
        : (inv.safeItem.isNotEmpty ? inv.safeItem : 'Unknown');

    DateTime dt;
    try {
      dt = inv is Map
          ? (inv['timestamp']?.toDate() ?? DateTime.now()).toLocal()
          : inv.timestamp.toLocal();
    } catch (_) {
      dt = DateTime.now();
    }
    final timeStr = _formatTime(dt);
    final int startA = inv is Map
        ? (inv['startingA'] ?? 0) as int
        : inv.safeStartingA;
    final int startB = inv is Map
        ? (inv['startingB'] ?? 0) as int
        : inv.safeStartingB;
    final int startC = inv is Map
        ? (inv['startingC'] ?? 0) as int
        : inv.safeStartingC;
    final int remA = inv is Map
        ? (inv['remainingA'] ?? 0) as int
        : inv.safeRemainingA;
    final int remB = inv is Map
        ? (inv['remainingB'] ?? 0) as int
        : inv.safeRemainingB;
    final int remC = inv is Map
        ? (inv['remainingC'] ?? 0) as int
        : inv.safeRemainingC;

    final int totalStart = startA + startB + startC;
    final int totalRemaining = remA + remB + remC;
    final List<Map<String, dynamic>> itemsList = inv is Map
        ? (inv['items'] as List?)?.cast<Map<String, dynamic>>() ?? []
        : inv.safeItems;
    final isBundle = itemsList.any((item) => item['isBundle'] == true);
    final isCoffee = itemsList.any((item) => item['isCoffee'] == true);
    final salesOnly = _isCoffeePerformanceEntry(itemsList, item);
    final coffeeId = itemsList
        .map((item) => item['coffeeId']?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    final totalReduced = itemsList.fold<int>(
      0,
      (sum, item) =>
          sum + (int.tryParse(item['reducedQuantity']?.toString() ?? '') ?? 0),
    );
    final int totalSold = (totalStart - totalRemaining - totalReduced)
        .clamp(0, totalStart)
        .toInt();

    final double storedRevenue = inv is Map
        ? (inv['totalSalesRevenue'] as num?)?.toDouble() ?? 0.0
        : inv.safeTotalSalesRevenue;
    double totalSoldValue = storedRevenue;

    if (totalSoldValue <= 0) {
      for (var i = 0; i < itemsList.length; i++) {
        final d = itemsList[i];
        final startQty = _startingAt(i, startA, startB, startC);
        final remQty = _remainingAt(i, remA, remB, remC);
        final price = double.tryParse(d['price']?.toString() ?? '0') ?? 0;
        final reducedQty =
            int.tryParse(d['reducedQuantity']?.toString() ?? '') ?? 0;
        final soldQty = (startQty - remQty - reducedQty)
            .clamp(0, startQty)
            .toInt();
        totalSoldValue += soldQty * price;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.pink.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _C.primary.withOpacity(0.08),
                  _C.primary.withOpacity(0.02),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _C.primaryDark,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _C.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _C.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Stats + breakdown
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    _StatChip(
                      label: 'Starting',
                      value: '$totalStart',
                      icon: Icons.inventory_2_outlined,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: 'Remaining',
                      value: '$totalRemaining',
                      icon: Icons.layers_outlined,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: 'Sold',
                      value: '$totalSold',
                      icon: Icons.shopping_bag_outlined,
                      color: Colors.green.shade700,
                    ),
                  ],
                ),
                if (totalSoldValue > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFC2105C), Color(0xFFF48FB1)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.payments_outlined,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Total Sales',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '₱${totalSoldValue.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (itemsList.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFF0E0D6)),
                  const SizedBox(height: 8),
                  ...itemsList.asMap().entries.map((entry) {
                    final index = entry.key;
                    final d = entry.value;
                    final iName = d['name'] ?? 'Unknown';
                    final startQty = _startingAt(index, startA, startB, startC);
                    final remQty = _remainingAt(index, remA, remB, remC);
                      final reducedQty =
                          int.tryParse(d['reducedQuantity']?.toString() ?? '') ??
                          0;
                    final soldQty = (startQty - remQty - reducedQty)
                        .clamp(0, startQty)
                        .toInt();
                    final progress = startQty > 0 ? soldQty / startQty : 0.0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  iName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFE91E63),
                                  ),
                                ),
                              ),
                              Text(
                                '$soldQty / $startQty sold',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.pink.shade400,
                                ),
                              ),
                            ],
                          ),
                          if (reducedQty > 0) ...[
                            const SizedBox(height: 3),
                            Text(
                              '$reducedQty reduced',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress.toDouble(),
                              minHeight: 6,
                              backgroundColor: Colors.pink.shade100,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                progress > 0.7
                                    ? Colors.green.shade500
                                    : progress > 0.3
                                    ? _C.accent
                                    : Colors.red.shade400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Performance Card
// ═══════════════════════════════════════════════════════════════════════════

class _PerformanceCard extends StatelessWidget {
  final dynamic inv;
  const _PerformanceCard({required this.inv});

  bool _isCoffeePerformanceEntry(
    List<Map<String, dynamic>> items,
    String title,
  ) {
    final titleLower = title.toLowerCase();
    return titleLower.contains('coffee') ||
        titleLower.contains('smoothie') ||
        titleLower.contains('latte') ||
        titleLower.contains('espresso') ||
        items.any((item) {
          return item['isCoffee'] == true ||
              (item['coffeeId']?.toString().trim().isNotEmpty ?? false) ||
              (item['coffeeSize']?.toString().trim().isNotEmpty ?? false) ||
              (item['addonName']?.toString().trim().isNotEmpty ?? false);
        });
  }

  @override
  Widget build(BuildContext context) {
    final String item = inv is Map
        ? (inv['item']?.toString() ?? 'Unknown')
        : (inv.safeItem.isNotEmpty ? inv.safeItem : 'Unknown');

    DateTime dt;
    try {
      dt = inv is Map
          ? (inv['timestamp']?.toDate() ?? DateTime.now()).toLocal()
          : inv.timestamp.toLocal();
    } catch (_) {
      dt = DateTime.now();
    }
    final timestamp = _formatDateTime(dt);

    final int startA = inv is Map
        ? (inv['startingA'] ?? 0) as int
        : inv.safeStartingA;
    final int startB = inv is Map
        ? (inv['startingB'] ?? 0) as int
        : inv.safeStartingB;
    final int startC = inv is Map
        ? (inv['startingC'] ?? 0) as int
        : inv.safeStartingC;
    final int remA = inv is Map
        ? (inv['remainingA'] ?? 0) as int
        : inv.safeRemainingA;
    final int remB = inv is Map
        ? (inv['remainingB'] ?? 0) as int
        : inv.safeRemainingB;
    final int remC = inv is Map
        ? (inv['remainingC'] ?? 0) as int
        : inv.safeRemainingC;

    final int totalStart = startA + startB + startC;
    final int totalRemaining = remA + remB + remC;

    final List<Map<String, dynamic>> itemsList = inv is Map
        ? (inv['items'] as List?)?.cast<Map<String, dynamic>>() ?? []
        : inv.safeItems;
    final isBundle = itemsList.any((item) => item['isBundle'] == true);
    final isCoffee = itemsList.any((item) => item['isCoffee'] == true);
    final salesOnly = _isCoffeePerformanceEntry(itemsList, item);
    final coffeeId = itemsList
        .map((item) => item['coffeeId']?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    final double storedRevenue = inv is Map
        ? (inv['totalSalesRevenue'] as num?)?.toDouble() ?? 0.0
        : inv.safeTotalSalesRevenue;
    double totalSoldValue = storedRevenue;
    if (totalSoldValue <= 0) {
      for (var i = 0; i < itemsList.length; i++) {
        final d = itemsList[i];
        final startQty = i == 0
            ? startA
            : i == 1
            ? startB
            : i == 2
            ? startC
            : 0;
        final remQty = i == 0
            ? remA
            : i == 1
            ? remB
            : i == 2
            ? remC
            : 0;
        final price = double.tryParse(d['price']?.toString() ?? '0') ?? 0;
        final reducedQty =
            int.tryParse(d['reducedQuantity']?.toString() ?? '') ?? 0;
        final soldQty = (startQty - remQty - reducedQty)
            .clamp(0, startQty)
            .toInt();
        totalSoldValue += soldQty * price;
      }
    }

    final totalReduced = itemsList.fold<int>(
      0,
      (sum, item) =>
          sum + (int.tryParse(item['reducedQuantity']?.toString() ?? '') ?? 0),
    );
    final int totalSold = (totalStart - totalRemaining - totalReduced)
        .clamp(0, totalStart)
        .toInt();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withOpacity(0.10),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gradient header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFC2105C), Color(0xFFF48FB1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isBundle) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inventory_2_rounded,
                                color: Colors.white,
                                size: 12,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Bundle',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (isCoffee) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.local_cafe_rounded,
                                color: Colors.white,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                coffeeId.isNotEmpty ? coffeeId : 'Coffee',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          color: Colors.white70,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timestamp,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (itemsList.isNotEmpty) ...[
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Item',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE91E63),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Text(
                          salesOnly ? 'Sold' : 'Start',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: salesOnly
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                          ),
                        ),
                        if (!salesOnly) ...[
                          const SizedBox(width: 20),
                          Text(
                            'Rem.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(height: 1, color: const Color(0xFFF0E0D6)),
                    const SizedBox(height: 8),
                    ...itemsList.asMap().entries.map((entry) {
                      final index = entry.key;
                      final d = entry.value;
                      final iName = d['name'] ?? 'Unknown';
                      final startQty = index == 0
                          ? startA
                          : index == 1
                          ? startB
                          : index == 2
                          ? startC
                          : 0;
                      final remQty = index == 0
                          ? remA
                          : index == 1
                          ? remB
                          : index == 2
                          ? remC
                          : 0;
                      final reducedQty =
                          int.tryParse(
                            d['reducedQuantity']?.toString() ?? '',
                          ) ??
                          0;
                      final soldQty = (startQty - remQty - reducedQty)
                          .clamp(0, startQty)
                          .toInt();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    iName,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFFC2105C),
                                    ),
                                  ),
                                ),
                                if (salesOnly)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${soldQty == 0 ? 1 : soldQty} sold',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  )
                                else ...[
                                  Text(
                                    '$startQty',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      '$remQty',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (reducedQty > 0)
                              Text(
                                '$reducedQty reduced',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Container(height: 1, color: const Color(0xFFF0E0D6)),
                    const SizedBox(height: 12),

                    if (totalStart > 0 ||
                        totalRemaining > 0 ||
                        totalSoldValue > 0) ...[
                      if (!salesOnly) ...[
                        _SummaryRow(
                          label: 'Total Starting',
                          value: '$totalStart',
                          valueColor: Colors.blue.shade700,
                        ),
                        const SizedBox(height: 4),
                        _SummaryRow(
                          label: 'Total Remaining',
                          value: '$totalRemaining',
                          valueColor: Colors.orange.shade700,
                        ),
                        const SizedBox(height: 4),
                      ],
                      _SummaryRow(
                        label: 'Total Sold',
                        value: salesOnly && totalSold == 0
                            ? '1'
                            : '$totalSold',
                        valueColor: Colors.green.shade700,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.payments_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Total Sales',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '₱${totalSoldValue.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.hourglass_empty_rounded,
                              color: Colors.orange.shade600,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Remaining not yet recorded.',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reusable small widgets
// ═══════════════════════════════════════════════════════════════════════════

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: color.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFFE91E63),
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade600),
          const SizedBox(width: 10),
          Text(
            message,
            style: TextStyle(color: Colors.red.shade700, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;

  const _EmptyState({required this.icon, required this.label, this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.pink.shade200),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                color: Colors.pink.shade400,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (sublabel != null) ...[
              const SizedBox(height: 4),
              Text(
                sublabel!,
                style: TextStyle(color: Colors.pink.shade300, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Custom Painters
// ═══════════════════════════════════════════════════════════════════════════

/// Subtle diagonal stripe pattern for header background texture
class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2;
    const spacing = 22.0;
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Soft arc at bottom of header to blend into content area
class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFF8F5)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(
        size.width / 2,
        -size.height * 0.5,
        size.width,
        size.height,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
