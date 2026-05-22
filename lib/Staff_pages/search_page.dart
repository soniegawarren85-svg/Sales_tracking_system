import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'AllCateg.dart';
import '../screens/staff_page.dart';
import '../services/inventory_service.dart';

// ─── Design Tokens (shared with StaffPage) ────────────────────────────────────
class _AC {
  static const cream = Color(0xFFFDF6EE);
  static const parchment = Color(0xFFF5EBD8);
  static const choco = Color(0xFFC2105C);
  static const chocoMid = Color(0xFFE91E63);
  static const chocoLight = Color(0xFFF48FB1);
  static const gold = Color(0xFFD4A853);
  static const goldLight = Color(0xFFE8C97A);
  static const dustyRose = Color(0xFFF8BBD0);
  static const blush = Color(0xFFF9EDE5);
  static const textDark = Color(0xFFC2105C);
  static const textMid = Color(0xFFE91E63);
  static const textLight = Color(0xFFF48FB1);
  static const divider = Color(0xFFE8C4B0);
  static const white = Color(0xFFFFFFFF);
}

class AnalyticsPage extends StatefulWidget {
  final VoidCallback onMessage;

  const AnalyticsPage({super.key, required this.onMessage});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<String> _allItems = [];
  List<String> _filtered = [];
  bool _isLoadingItems = true;

  bool get _hasQuery => _controller.text.trim().isNotEmpty;

  late AnimationController _pulseCtrl;
  Animation<double>? _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _loadItems();
    _controller.addListener(_onSearchChanged);
    InventoryService().addListener(_onInventoryUpdated);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _controller.removeListener(_onSearchChanged);
    _controller.dispose();
    _focusNode.dispose();
    InventoryService().removeListener(_onInventoryUpdated);
    super.dispose();
  }

  void _onInventoryUpdated() => _loadItems();

  bool _isExpiredInventoryItem(String expirationDate) {
    try {
      final expiryDate = DateTime.parse(expirationDate);
      final today = DateTime.now();
      return expiryDate.isBefore(
        DateTime(today.year, today.month, today.day + 1),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadItems() async {
    if (!mounted) return;
    setState(() => _isLoadingItems = true);

    List<String> assignedInventoryNames = [];
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        _allItems = [];
        _filtered = [];
        if (mounted) setState(() => _isLoadingItems = false);
        return;
      }

      final ids = <String>{userId};
      var publicStaffId = '';
      try {
        final staffDoc = await FirebaseFirestore.instance
            .collection('staff_requests')
            .doc(userId)
            .get();
        final staffData = staffDoc.data();
        publicStaffId = staffData?['staffId']?.toString().trim() ?? '';
        if (publicStaffId.isNotEmpty) ids.add(publicStaffId);
        final branchIds = (staffData?['branchIds'] as List<dynamic>? ?? [])
            .map((id) => id.toString().trim())
            .where((id) => id.isNotEmpty);
        ids.addAll(branchIds);
      } catch (_) {}

      try {
        final byUid = await FirebaseFirestore.instance
            .collection('branches')
            .where('staffIds', arrayContains: userId)
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

      final query = FirebaseFirestore.instance.collection('staff_inventory');
      final snapshot = ids.length == 1
          ? await query.where('staffId', isEqualTo: ids.first).get()
          : await query.where('staffId', whereIn: ids.take(10).toList()).get();
      final rootSnapshot = await FirebaseFirestore.instance
          .collection('sales_inventory')
          .get();
      final activeRootById = <String, Map<String, dynamic>>{};
      final activeRootByName = <String, Map<String, dynamic>>{};
      for (final rootDoc in rootSnapshot.docs) {
        final rootData = rootDoc.data();
        if (rootData['isDeleted'] == true || rootData['deletedAt'] != null) {
          continue;
        }
        activeRootById[rootDoc.id] = rootData;
        final rootName = rootData['name']?.toString().trim().toLowerCase();
        if (rootName != null && rootName.isNotEmpty) {
          activeRootByName[rootName] = rootData;
        }
      }

      String itemKey(Map<String, dynamic> item) =>
          '${item['name'] ?? ''}|${item['price'] ?? ''}'.toLowerCase();

      final names = <String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['isDeleted'] == true) continue;

        final categoryName = data['name']?.toString().trim() ?? '';
        final sourceId = data['sourceInventoryId']?.toString() ?? '';
        final isCoffee = data['isCoffee'] == true;
        final rootData =
            activeRootById[sourceId] ??
            activeRootByName[categoryName.toLowerCase()] ??
            (isCoffee ? data : null);
        if (rootData == null) continue;

        final isBundle = data['isBundle'] == true;
        final bundleCount =
            int.tryParse(data['bundleCount']?.toString() ?? '') ?? 0;

        if (isBundle) {
          if (categoryName.isNotEmpty && bundleCount > 0) {
            names.add(categoryName);
          }
          continue;
        }

        if (isCoffee) {
          final sizes = data['sizes'] as List<dynamic>? ?? [];
          if (categoryName.isNotEmpty && sizes.isNotEmpty) {
            names.add(categoryName);
          }
          continue;
        }

        final rootKeys = ((rootData['items'] as List<dynamic>?) ?? [])
            .whereType<Map>()
            .map((item) => itemKey(Map<String, dynamic>.from(item)))
            .toSet();
        final items = data['items'] as List<dynamic>? ?? [];
        final hasAvailableItem = items.any((raw) {
          if (raw is! Map) return false;
          final item = Map<String, dynamic>.from(raw);
          final expirationDate = item['expirationDate']?.toString() ?? '';
          if (_isExpiredInventoryItem(expirationDate)) return false;
          if (rootKeys.isNotEmpty && !rootKeys.contains(itemKey(item))) {
            return false;
          }
          final stock =
              int.tryParse(
                (item['stock'] ?? item['startingStock'] ?? '0').toString(),
              ) ??
              0;
          return stock > 0;
        });

        if (categoryName.isNotEmpty && hasAvailableItem) {
          names.add(categoryName);
        }
      }
      assignedInventoryNames = names.toList();
    } catch (e) {
      debugPrint('Error loading staff_inventory names: $e');
    }

    _allItems = assignedInventoryNames
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _filtered = [];

    if (mounted) setState(() => _isLoadingItems = false);
  }

  void _onSearchChanged() {
    final query = _controller.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? []
          : _allItems
                .where((item) => item.toLowerCase().contains(query))
                .toList();
    });
  }

  // ── Navigate to StaffPage ─────────────────────────────────────────────────
  Future<void> _openItem(String item) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('staff_inventory')
          .where('name', isEqualTo: item)
          .get();
      QueryDocumentSnapshot<Map<String, dynamic>>? coffeeDoc;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['isCoffee'] == true && data['isDeleted'] != true) {
          coffeeDoc = doc;
          break;
        }
      }
      if (coffeeDoc != null) {
        if (!mounted) return;
        final data = coffeeDoc.data();
        final sourceId = data['sourceInventoryId']?.toString().trim() ?? '';
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => AllCategPage(
              selectedCategoryName: item,
              selectedSourceInventoryId: sourceId.isNotEmpty
                  ? sourceId
                  : coffeeDoc!.id,
              selectedIsCoffee: true,
            ),
            transitionsBuilder: (_, animation, __, child) {
              final tween = Tween(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeOut));
              return SlideTransition(
                position: animation.drive(tween),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 380),
          ),
        );
        return;
      }
    } catch (_) {}

    final isRemain = InventoryService().hasAnyEntryForItemToday(item);
    if (!mounted) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            StaffPage(selectedItem: item, isRemaining: isRemain),
        transitionsBuilder: (_, animation, __, child) {
          final tween = Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOut));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _AC.cream,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Search Bar ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _SearchBar(
              controller: _controller,
              focusNode: _focusNode,
              onClear: () {
                _controller.clear();
                _focusNode.unfocus();
              },
            ),
          ),

          // ── Results / States ──────────────────────────────────────────────
          Expanded(
            child: _isLoadingItems
                ? _buildLoadingState()
                : !_hasQuery
                ? _buildIdleState()
                : _filtered.isEmpty
                ? _buildNoResultsState()
                : _buildResultsList(),
          ),
        ],
      ),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: const AlwaysStoppedAnimation(_AC.chocoMid),
            strokeWidth: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'Loading items…',
            style: GoogleFonts.dmSans(color: _AC.textLight, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Idle State (no query) ─────────────────────────────────────────────────
  Widget _buildIdleState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _pulseAnim ?? const AlwaysStoppedAnimation<double>(1.0),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: _AC.parchment,
                  shape: BoxShape.circle,
                  border: Border.all(color: _AC.dustyRose, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _AC.choco.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.manage_search_rounded,
                  size: 46,
                  color: _AC.chocoLight,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Search for an item',
              style: GoogleFonts.playfairDisplay(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _AC.choco,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Type a product name above to find\nits inventory entry for today.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: _AC.textLight,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            // Item count pill
            if (_allItems.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _AC.blush,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _AC.dustyRose),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 15,
                      color: _AC.chocoLight,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_allItems.length} product${_allItems.length == 1 ? '' : 's'} available',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _AC.chocoLight,
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

  // ── No Results ────────────────────────────────────────────────────────────
  Widget _buildNoResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: _AC.blush,
                shape: BoxShape.circle,
                border: Border.all(color: _AC.dustyRose, width: 1.5),
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 40,
                color: _AC.chocoLight,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No items found',
              style: GoogleFonts.playfairDisplay(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _AC.choco,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different keyword or\ncheck your spelling.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: _AC.textLight,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Results List ──────────────────────────────────────────────────────────
  Widget _buildResultsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Results count label
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: _AC.gold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_filtered.length} result${_filtered.length == 1 ? '' : 's'} found',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _AC.textMid,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
            itemCount: _filtered.length,
            itemBuilder: (context, index) {
              final item = _filtered[index];
              final hasEntry = InventoryService().hasAnyEntryForItemToday(item);

              return _ItemResultCard(
                itemName: item,
                hasEntry: hasEntry,
                query: _controller.text.trim(),
                onTap: () => _openItem(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Search Bar Widget ────────────────────────────────────────────────────────
class _SearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onClear,
  });

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() {
      if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _AC.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _focused ? _AC.chocoLight : _AC.divider,
          width: _focused ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: _focused
                ? _AC.choco.withOpacity(0.12)
                : _AC.choco.withOpacity(0.05),
            blurRadius: _focused ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        style: GoogleFonts.dmSans(
          fontSize: 16,
          color: _AC.textDark,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search all items…',
          hintStyle: GoogleFonts.dmSans(color: _AC.textLight, fontSize: 15),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              Icons.search_rounded,
              color: _focused ? _AC.chocoMid : _AC.textLight,
              size: 24,
            ),
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (_, value, __) {
              return value.text.isEmpty
                  ? const SizedBox.shrink()
                  : GestureDetector(
                      onTap: widget.onClear,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _AC.parchment,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          color: _AC.chocoLight,
                          size: 18,
                        ),
                      ),
                    );
            },
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
        ),
      ),
    );
  }
}

// ─── Item Result Card ─────────────────────────────────────────────────────────
class _ItemResultCard extends StatelessWidget {
  final String itemName;
  final bool hasEntry;
  final String query;
  final VoidCallback onTap;

  const _ItemResultCard({
    required this.itemName,
    required this.hasEntry,
    required this.query,
    required this.onTap,
  });

  // Highlight matching text
  List<TextSpan> _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return [
        TextSpan(
          text: text,
          style: GoogleFonts.dmSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _AC.textDark,
          ),
        ),
      ];
    }

    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final lowerQ = query.toLowerCase();
    int start = 0;

    while (true) {
      final idx = lower.indexOf(lowerQ, start);
      if (idx == -1) {
        spans.add(
          TextSpan(
            text: text.substring(start),
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _AC.textDark,
            ),
          ),
        );
        break;
      }
      if (idx > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, idx),
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _AC.textDark,
            ),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + query.length),
          style: GoogleFonts.dmSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _AC.chocoMid,
            backgroundColor: _AC.goldLight.withOpacity(0.3),
          ),
        ),
      );
      start = idx + query.length;
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _AC.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _AC.divider, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: _AC.choco.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left accent bar
            Container(
              width: 5,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_AC.gold, _AC.chocoLight],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
              ),
            ),

            // Icon
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _AC.blush,
                shape: BoxShape.circle,
                border: Border.all(color: _AC.dustyRose),
              ),
              child: Icon(
                Icons.inventory_2_rounded,
                size: 20,
                color: _AC.chocoLight,
              ),
            ),

            // Text content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: _buildHighlightedText(itemName, query),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: hasEntry
                                ? const Color(0xFFE8F5EC)
                                : _AC.parchment,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: hasEntry
                                  ? const Color(0xFF4A7C59).withOpacity(0.4)
                                  : _AC.divider,
                            ),
                          ),
                          child: Text(
                            hasEntry ? '✓ Entry today' : 'No entry today',
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: hasEntry
                                  ? const Color(0xFF4A7C59)
                                  : _AC.textLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Arrow
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _AC.parchment,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: _AC.chocoLight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
