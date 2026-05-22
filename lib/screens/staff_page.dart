import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/inventory.dart';
import '../services/inventory_service.dart';
import '../bones/bottom_nav.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _AppColors {
  static const cream = Color(0xFFFDF6EE);
  static const parchment = Color(0xFFFCE8F2);
  static const choco = Color(0xFFE91E63);
  static const chocoMid = Color(0xFFF48FB1);
  static const chocoLight = Color(0xFFF8BBD0);
  static const gold = Color(0xFFFFC1E3);
  static const goldLight = Color(0xFFFFE4ED);
  static const dustyRose = Color(0xFFF8BBD0);
  static const blush = Color(0xFFFFEBF0);
  static const textMid = Color(0xFFAD1457);
  static const textLight = Color(0xFFAD1457);
  static const divider = Color(0xFFF5C2D0);
  static const success = Color(0xFF4A7C59);
  static const white = Color(0xFFFFFFFF);
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: _AppColors.gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: GoogleFonts.playfairDisplay(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _AppColors.choco,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _ReminderBanner extends StatelessWidget {
  final String message;
  const _ReminderBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _AppColors.parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _AppColors.gold.withOpacity(0.5), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: _AppColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: _AppColors.textMid,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stepper QTY Input ────────────────────────────────────────────────────────
class _QtyStepperField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _QtyStepperField({required this.controller, required this.focusNode});

  void _step(int delta) {
    final current = int.tryParse(controller.text.trim()) ?? 0;
    final next = (current + delta).clamp(0, 9999);
    controller.text = '$next';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _AppColors.divider, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _AppColors.choco.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _StepBtn(icon: Icons.remove_rounded, onTap: () => _step(-1)),
          Expanded(
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _AppColors.choco,
              ),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: GoogleFonts.dmSans(
                  color: _AppColors.divider,
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          _StepBtn(icon: Icons.add_rounded, onTap: () => _step(1)),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 52,
        decoration: BoxDecoration(
          color: _AppColors.parchment,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 22, color: _AppColors.chocoMid),
      ),
    );
  }
}

// ─── Item Card ────────────────────────────────────────────────────────────────
class _ItemCard extends StatelessWidget {
  final String itemName;
  final String price;
  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String startingStock;
  final String bottomLabel;

  const _ItemCard({
    required this.itemName,
    required this.price,
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.startingStock,
    required this.bottomLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isCoffeeInfo = startingStock == 'Coffee';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AppColors.divider, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _AppColors.choco.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left accent bar
          Container(
            width: 5,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_AppColors.gold, _AppColors.chocoLight],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                bottomLeft: Radius.circular(18),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          itemName,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _AppColors.choco,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _AppColors.dustyRose.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _AppColors.gold.withOpacity(0.5),
                          ),
                        ),
                        child: Text(
                          '₱$price',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _AppColors.choco,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _AppColors.parchment.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _AppColors.gold.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isCoffeeInfo
                              ? 'Available add-ons'
                              : 'Starting Stock (Admin Set)',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _AppColors.textLight,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _AppColors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _AppColors.gold.withOpacity(0.4),
                            ),
                          ),
                          child: Text(
                            isCoffeeInfo ? 'Menu' : '$startingStock pcs',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _AppColors.choco,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (bottomLabel.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      bottomLabel,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _AppColors.textMid,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _QtyStepperField(
                    controller: controller,
                    focusNode: focusNode,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── StaffPage ────────────────────────────────────────────────────────────────
class StaffPage extends StatefulWidget {
  final String? selectedItem;
  final String? selectedInventoryId;
  final bool isRemaining;

  const StaffPage({
    super.key,
    this.selectedItem,
    this.selectedInventoryId,
    this.isRemaining = false,
  });

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> with TickerProviderStateMixin {
  final List<TextEditingController> itemControllers = [];
  final List<FocusNode> itemFocusNodes = [];
  List<Map<String, dynamic>> productItems = [];
  bool isLoading = true;
  bool isRemainingLocked = false;
  bool _forceRemainingMode = false;
  bool _isBundle = false;
  bool _isCoffee = false;
  String _bundlePrice = '0';
  int _bundleCount = 0;
  String _staffInventoryDocId = '';
  List<int> _adminStartingStock = [0, 0, 0];
  List<int> _suggestedRemainingStock = [0, 0, 0];

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fetchProductItems();
  }

  Future<void> _fetchProductItems() async {
    try {
      _isBundle = false;
      _isCoffee = false;
      _bundlePrice = '0';
      _bundleCount = 0;
      _staffInventoryDocId = '';
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        setState(() => isLoading = false);
        _fadeCtrl.forward();
        return;
      }

      final ids = <String>{currentUserId};
      try {
        final staffDoc = await FirebaseFirestore.instance
            .collection('staff_requests')
            .doc(currentUserId)
            .get();
        final staffData = staffDoc.data();
        final publicStaffId = staffData?['staffId']?.toString().trim() ?? '';
        if (publicStaffId.isNotEmpty) ids.add(publicStaffId);
        ids.addAll(
          (staffData?['branchIds'] as List<dynamic>? ?? [])
              .map((id) => id.toString().trim())
              .where((id) => id.isNotEmpty),
        );
      } catch (_) {}
      final query = FirebaseFirestore.instance.collection('staff_inventory');
      final snapshot = ids.length == 1
          ? await query.where('staffId', isEqualTo: ids.first).get()
          : await query.where('staffId', whereIn: ids.take(10).toList()).get();

      final validDocs = snapshot.docs.where((doc) {
        final data = doc.data();
        final sourceId = data['sourceInventoryId']?.toString() ?? doc.id;
        final selectedId = widget.selectedInventoryId?.trim() ?? '';
        return data['isDeleted'] != true &&
            data['name']?.toString() == widget.selectedItem &&
            (selectedId.isEmpty ||
                sourceId == selectedId ||
                doc.id == selectedId);
      }).toList();

      validDocs.sort((a, b) {
        final aTime =
            (a.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final bTime =
            (b.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });

      if (validDocs.isNotEmpty) {
        final data = validDocs.first.data();
        _staffInventoryDocId = validDocs.first.id;
        _isBundle = data['isBundle'] == true;
        _isCoffee = data['isCoffee'] == true;
        _bundlePrice = data['price']?.toString() ?? '0';
        _bundleCount = data['bundleCount'] is int
            ? data['bundleCount'] as int
            : int.tryParse(data['bundleCount']?.toString() ?? '') ?? 0;
        final rawItems = data['items'] as List? ?? [];
        final items = _isCoffee ? _coffeeDisplayItems(data) : rawItems;

        var existingEntry =
            widget.isRemaining && (widget.selectedItem?.isNotEmpty ?? false)
            ? InventoryService().getEntryForItemToday(
                widget.selectedItem!,
                sourceInventoryId: widget.selectedInventoryId,
              )
            : null;

        final adminStarting = <int>[];
        for (int i = 0; i < items.length; i++) {
          final startQty = _isBundle && _bundleCount > 0
              ? _bundleCount
              : int.tryParse(items[i]['startingStock']?.toString() ?? '0') ?? 0;
          adminStarting.add(startQty);
        }

        final hasAdminStarting =
            adminStarting.any((qty) => qty > 0) ||
            (_isBundle && _bundleCount > 0);
        if (hasAdminStarting) {
          _forceRemainingMode = true;
          _adminStartingStock = [
            if (adminStarting.length > 0) adminStarting[0] else 0,
            if (adminStarting.length > 1) adminStarting[1] else 0,
            if (adminStarting.length > 2) adminStarting[2] else 0,
          ];

          // Do not create a new entry just by opening the category.
          // Existing stock records should only be saved when the staff presses Save.
        }

        // Pre-calculate suggested remaining if needed (async operation)
        List<int> suggestedQtys = _adminStartingStock;
        final remainingSum = existingEntry != null
            ? (existingEntry.safeRemainingA +
                  existingEntry.safeRemainingB +
                  existingEntry.safeRemainingC)
            : 0;

        if ((widget.isRemaining || _forceRemainingMode) &&
            remainingSum == 0 &&
            hasAdminStarting) {
          // Calculate suggested remaining from Firebase if no manual entry yet
          final variantsList = items.cast<Map<String, dynamic>>();
          suggestedQtys = await _calculateSuggestedRemaining(
            widget.selectedItem ?? '',
            _adminStartingStock,
            variantsList,
          );
        }

        setState(() {
          productItems = items.cast<Map<String, dynamic>>();
          itemControllers.clear();
          itemFocusNodes.clear();
          for (int i = 0; i < productItems.length; i++) {
            itemControllers.add(TextEditingController());
            itemFocusNodes.add(FocusNode());
          }

          // Store suggested remaining for display
          _suggestedRemainingStock = [
            if (suggestedQtys.length > 0) suggestedQtys[0] else 0,
            if (suggestedQtys.length > 1) suggestedQtys[1] else 0,
            if (suggestedQtys.length > 2) suggestedQtys[2] else 0,
          ];

          if ((widget.isRemaining || _forceRemainingMode)) {
            if (existingEntry != null && remainingSum > 0) {
              // If remaining has already been entered, prefill with those values
              if (itemControllers.isNotEmpty) {
                itemControllers[0].text = existingEntry.safeRemainingA
                    .toString();
              }
              if (itemControllers.length > 1) {
                itemControllers[1].text = existingEntry.safeRemainingB
                    .toString();
              }
              if (itemControllers.length > 2) {
                itemControllers[2].text = existingEntry.safeRemainingC
                    .toString();
              }
              isRemainingLocked = true;
            } else {
              // Prefill with suggested remaining values from Firebase/current stock
              if (itemControllers.isNotEmpty) {
                itemControllers[0].text = suggestedQtys[0].toString();
              }
              if (itemControllers.length > 1) {
                itemControllers[1].text = suggestedQtys[1].toString();
              }
              if (itemControllers.length > 2) {
                itemControllers[2].text = suggestedQtys[2].toString();
              }
              isRemainingLocked = false;
            }
          } else {
            isRemainingLocked = remainingSum > 0;
          }

          isLoading = false;
        });
        _fadeCtrl.forward();
      } else {
        setState(() => isLoading = false);
        _fadeCtrl.forward();
      }
    } catch (e) {
      debugPrint('Error fetching product items: $e');
      setState(() => isLoading = false);
      _fadeCtrl.forward();
    }
  }

  List<Map<String, dynamic>> _coffeeDisplayItems(Map<String, dynamic> data) {
    final basePrice =
        double.tryParse(data['basePrice']?.toString() ?? '0') ?? 0.0;
    final sizes = (data['sizes'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((size) => Map<String, dynamic>.from(size))
        .toList();
    final addons = (data['addonOptions'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((addon) => Map<String, dynamic>.from(addon))
        .toList();

    return sizes.map((size) {
      final sizeName = size['name']?.toString().trim() ?? 'Regular';
      final delta = double.tryParse(size['priceDelta']?.toString() ?? '0') ?? 0;
      final addonLabel = addons.isEmpty
          ? ''
          : addons
                .map((addon) {
                  final name = addon['name']?.toString() ?? '';
                  final price =
                      double.tryParse(addon['priceDelta']?.toString() ?? '0') ??
                      0;
                  return price > 0
                      ? '$name +₱${price.toStringAsFixed(0)}'
                      : name;
                })
                .where((name) => name.trim().isNotEmpty)
                .join(', ');
      return {
        'name': sizeName,
        'price': (basePrice + delta).toStringAsFixed(0),
        'startingStock': 'Coffee',
        'addonLabel': addonLabel,
      };
    }).toList();
  }

  Future<void> _markCoffeeLowStock() async {
    if (!_isCoffee || _staffInventoryDocId.isEmpty) return;
    final flavor = widget.selectedItem ?? 'Coffee flavor';
    try {
      await FirebaseFirestore.instance
          .collection('staff_inventory')
          .doc(_staffInventoryDocId)
          .set({
            'isLowStock': true,
            'lowStockMarkedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await FirebaseFirestore.instance.collection('admin_notifications').add({
        'type': 'coffee_low_stock',
        'title': 'Coffee flavor is running low',
        'message': '$flavor is marked as running low.',
        'itemName': flavor,
        'staffInventoryDocId': _staffInventoryDocId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _showSnack('$flavor marked as running low');
    } catch (e) {
      if (mounted) _showSnack('Unable to mark coffee: $e');
    }
  }

  /// Calculate suggested remaining stock based on the staff-assigned inventory.
  Future<List<int>> _calculateSuggestedRemaining(
    String itemName,
    List<int> adminStartingStock,
    List<Map<String, dynamic>> variants,
  ) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return adminStartingStock;

      final snapshot = await FirebaseFirestore.instance
          .collection('staff_inventory')
          .where('staffId', isEqualTo: currentUserId)
          .get();

      if (snapshot.docs.isEmpty) {
        return adminStartingStock; // No sales yet, return starting stock
      }

      // Sort by timestamp descending in Dart to get the latest document
      final docs = snapshot.docs.where((doc) {
        final data = doc.data();
        final sourceId = data['sourceInventoryId']?.toString() ?? doc.id;
        final selectedId = widget.selectedInventoryId?.trim() ?? '';
        return data['isDeleted'] != true &&
            data['name']?.toString() == itemName &&
            (selectedId.isEmpty ||
                sourceId == selectedId ||
                doc.id == selectedId);
      }).toList();
      if (docs.isEmpty) return adminStartingStock;

      docs.sort((a, b) {
        final tsA =
            (a.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final tsB =
            (b.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return tsB.compareTo(tsA); // Descending order
      });

      final latestDoc = docs.first.data();
      final items = (latestDoc['items'] as List<dynamic>?) ?? [];

      // Calculate current stock from Firebase for each variant
      final suggestedQtys = <int>[0, 0, 0];
      for (int i = 0; i < variants.length && i < 3; i++) {
        final variantName = variants[i]['name']?.toString() ?? '';

        // Find this variant in the sales_inventory items
        for (final item in items) {
          final itemData = item as Map<String, dynamic>?;
          final savedVariant = itemData?['name']?.toString() ?? '';
          final savedVariantAlt = itemData?['variant']?.toString() ?? '';

          if (savedVariant == variantName || savedVariantAlt == variantName) {
            int currentStock = itemData?['stock'] is num
                ? (itemData?['stock'] as num).toInt()
                : int.tryParse(itemData?['stock']?.toString() ?? '') ?? 0;

            // If stock is 0 or missing, try fallback to startingStock
            if (currentStock <= 0) {
              currentStock = itemData?['startingStock'] is num
                  ? (itemData?['startingStock'] as num).toInt()
                  : int.tryParse(
                          itemData?['startingStock']?.toString() ?? '',
                        ) ??
                        0;
            }

            if (adminStartingStock.length > i && adminStartingStock[i] > 0) {
              currentStock = min(currentStock, adminStartingStock[i]);
            }

            suggestedQtys[i] = max(0, currentStock);
            break;
          }
        }
      }

      return suggestedQtys;
    } catch (e) {
      debugPrint('Error calculating suggested remaining: $e');
      return adminStartingStock;
    }
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────────

  void _showSystemMessageDialog(VoidCallback onGotIt) {
    _showStyledDialog(
      icon: Icons.check_circle_rounded,
      iconColor: _AppColors.success,
      title: 'Success',
      message:
          'Remaining stock successfully recorded for today. Review the summary below.',
      onGotIt: () {
        Navigator.pop(context);
        onGotIt();
      },
    );
  }

  void _showStyledDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required VoidCallback onGotIt,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: _AppColors.choco.withOpacity(0.5),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            color: _AppColors.cream,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: _AppColors.choco.withOpacity(0.2),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: iconColor.withOpacity(0.35),
                    width: 2,
                  ),
                ),
                child: Icon(icon, color: iconColor, size: 30),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _AppColors.choco,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: _AppColors.blush,
                  border: Border.all(color: _AppColors.dustyRose),
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: _AppColors.textMid,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _AppColors.choco,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: onGotIt,
                  child: Text(
                    'Got it',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _AppColors.white,
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

  // ── Dispose ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _fadeCtrl.dispose();
    for (var ctrl in itemControllers) ctrl.dispose();
    for (var focus in itemFocusNodes) focus.dispose();
    super.dispose();
  }

  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (productItems.isEmpty) {
      _showSnack('No items to save');
      return;
    }

    final selectedItem = widget.selectedItem ?? '';

    if (_isRemainingMode) {
      final existing = InventoryService().getEntryForItemToday(
        selectedItem,
        sourceInventoryId: widget.selectedInventoryId,
      );
      if (existing == null && !_forceRemainingMode) {
        _showSnack('No starting stock entry found for this item today.');
        return;
      }
      final wasEditingExisting =
          existing != null &&
          (existing.safeRemainingA +
                  existing.safeRemainingB +
                  existing.safeRemainingC) >
              0;
      final previousRemaining = [
        existing?.safeRemainingA ?? 0,
        existing?.safeRemainingB ?? 0,
        existing?.safeRemainingC ?? 0,
      ];

      final remainingQtys = itemControllers
          .map((ctrl) => int.tryParse(ctrl.text.trim()) ?? 0)
          .toList();
      if (remainingQtys.every((qty) => qty == 0)) {
        _showSnack(
          'Please enter remaining stock before calculating inventory.',
        );
        return;
      }

      final int qtyA = productItems.isNotEmpty
          ? int.tryParse(itemControllers[0].text.trim()) ?? 0
          : 0;
      final int qtyB = productItems.length > 1
          ? int.tryParse(itemControllers[1].text.trim()) ?? 0
          : 0;
      final int qtyC = productItems.length > 2
          ? int.tryParse(itemControllers[2].text.trim()) ?? 0
          : 0;

      // Prepare items data for calculation
      final itemsData = <Map<String, dynamic>>[];
      for (int i = 0; i < productItems.length; i++) {
        final itemName = productItems[i]['name'] ?? 'Item $i';
        final price = _isBundle
            ? _bundlePrice
            : productItems[i]['price']?.toString() ?? '0';
        itemsData.add({'name': itemName, 'price': price});
      }

      InventoryService().addRemainingStockForItem(
        itemName: selectedItem,
        quantityA: qtyA,
        quantityB: qtyB,
        quantityC: qtyC,
        startingA: _forceRemainingMode ? _adminStartingStock[0] : null,
        startingB: _forceRemainingMode ? _adminStartingStock[1] : null,
        startingC: _forceRemainingMode ? _adminStartingStock[2] : null,
        items: itemsData,
        sourceInventoryId: widget.selectedInventoryId,
      );

      final entry = InventoryService().getEntryForItemToday(
        selectedItem,
        sourceInventoryId: widget.selectedInventoryId,
      );
      if (entry != null) {
        final result = _calculateInventoryResult(entry);
        final currentUser = FirebaseAuth.instance.currentUser;
        String staffId = currentUser?.uid ?? 'Unknown';
        String staffName = currentUser?.displayName?.trim() ?? '';
        if (currentUser != null) {
          final doc = await FirebaseFirestore.instance
              .collection('staff_requests')
              .doc(currentUser.uid)
              .get();
          final data = doc.data();
          if (data != null) {
            staffId = (data['staffId'] as String?)?.trim().isNotEmpty == true
                ? (data['staffId'] as String).trim()
                : staffId;
            final firstName = (data['firstName'] as String?)?.trim() ?? '';
            final lastName = (data['lastName'] as String?)?.trim() ?? '';
            staffName = [
              firstName,
              lastName,
            ].where((v) => v.isNotEmpty).join(' ');
          }
        }
        if (staffName.isEmpty) {
          staffName = 'Staff Member';
        }
        if (wasEditingExisting &&
            (previousRemaining[0] != qtyA ||
                previousRemaining[1] != qtyB ||
                previousRemaining[2] != qtyC)) {
          await _notifyAdminRemainingEdited(
            itemName: selectedItem,
            staffId: staffId,
            staffName: staffName,
            previousRemaining: previousRemaining,
            newRemaining: [qtyA, qtyB, qtyC],
            items: itemsData,
          );
        }
        _showSystemMessageDialog(() {
          Navigator.of(context).push(
            _buildSummaryRoute(
              RemainingInventorySummaryPage(
                itemName: selectedItem,
                lineItems: result.lineItems,
                totalStartValue: result.totalStartValue,
                totalRemainingValue: result.totalRemainingValue,
                totalSoldCount: result.totalSoldCount,
                totalSoldValue: result.totalSoldValue,
                staffName: staffName,
                staffId: staffId,
                isBundle: _isBundle,
              ),
            ),
          );
        });
      } else {
        _showSnack('Remaining stock added');
      }
    } else {
      final itemsData = <Map<String, dynamic>>[];
      for (int i = 0; i < productItems.length; i++) {
        final itemName = productItems[i]['name'] ?? 'Item $i';
        final price = _isBundle
            ? _bundlePrice
            : productItems[i]['price']?.toString() ?? '0';
        final qty = int.tryParse(itemControllers[i].text.trim()) ?? 0;
        itemsData.add({'name': itemName, 'price': price, 'quantity': qty});
      }

      final inv = Inventory(
        item: selectedItem,
        ownerId: FirebaseAuth.instance.currentUser?.uid,
        sourceInventoryId: widget.selectedInventoryId,
        items: itemsData,
        startingA: itemsData.isNotEmpty ? itemsData[0]['quantity'] ?? 0 : 0,
        startingB: itemsData.length > 1 ? itemsData[1]['quantity'] ?? 0 : 0,
        startingC: itemsData.length > 2 ? itemsData[2]['quantity'] ?? 0 : 0,
      );
      InventoryService().addInventory(inv);
      _showSnack('Inventory saved successfully');
    }

    for (var ctrl in itemControllers) ctrl.clear();
    if (!_isRemainingMode) Navigator.of(context).pop();
  }

  Future<void> _notifyAdminRemainingEdited({
    required String itemName,
    required String staffId,
    required String staffName,
    required List<int> previousRemaining,
    required List<int> newRemaining,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final changes = <String>[];
      for (var i = 0; i < items.length && i < newRemaining.length; i++) {
        final name = items[i]['name']?.toString() ?? 'Item ${i + 1}';
        final oldValue = i < previousRemaining.length
            ? previousRemaining[i]
            : 0;
        final newValue = newRemaining[i];
        if (oldValue != newValue) {
          changes.add('$name: $oldValue to $newValue');
        }
      }
      if (changes.isEmpty) return;

      await FirebaseFirestore.instance.collection('admin_notifications').add({
        'type': 'remaining_edit',
        'title': 'Remaining stock edited',
        'message':
            '$staffName edited remaining stock for $itemName. ${changes.join(', ')}.',
        'staffId': staffId,
        'staffName': staffName,
        'itemName': itemName,
        'changes': changes,
        'previousRemaining': previousRemaining,
        'newRemaining': newRemaining,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      debugPrint('Failed to notify admin about remaining edit: $e');
    }
  }

  bool get _isRemainingMode => widget.isRemaining || _forceRemainingMode;

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.dmSans()),
        backgroundColor: _AppColors.choco,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Calculation ───────────────────────────────────────────────────────────────

  InventoryCalculationResult _calculateInventoryResult(Inventory entry) {
    final List<InventoryCalcLine> lines = [];
    final sourceItems = List<Map<String, dynamic>>.from(entry.items ?? []);

    double totalStartValue = 0;
    double totalRemainingValue = 0;
    int totalSoldCount = 0;
    double totalSoldValue = 0;

    final starts = [
      entry.safeStartingA,
      entry.safeStartingB,
      entry.safeStartingC,
    ];
    final rems = [
      entry.safeRemainingA,
      entry.safeRemainingB,
      entry.safeRemainingC,
    ];

    for (var i = 0; i < sourceItems.length; i++) {
      final item = sourceItems[i];
      final itemName = item['name']?.toString() ?? 'Item ${i + 1}';
      final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;

      final startQty = i < starts.length ? starts[i] : 0;
      final remainingQty = i < rems.length ? rems[i] : 0;
      final reducedQty =
          int.tryParse(item['reducedQuantity']?.toString() ?? '') ?? 0;
      final soldQty = (startQty - remainingQty - reducedQty)
          .clamp(0, startQty)
          .toInt();

      final startValue = startQty * price;
      final remainingValue = remainingQty * price;
      final soldValue = soldQty * price;

      totalStartValue += startValue;
      totalRemainingValue += remainingValue;
      totalSoldCount += soldQty;
      totalSoldValue += soldValue;

      lines.add(
        InventoryCalcLine(
          itemName: itemName,
          price: price,
          startQty: startQty,
          remainingQty: remainingQty,
          soldQty: soldQty,
          startValue: startValue,
          remainingValue: remainingValue,
          soldValue: soldValue,
        ),
      );
    }

    return InventoryCalculationResult(
      lineItems: lines,
      totalStartValue: totalStartValue,
      totalRemainingValue: totalRemainingValue,
      totalSoldCount: totalSoldCount,
      totalSoldValue: totalSoldValue,
    );
  }

  Route _buildSummaryRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final tween = Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOut));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 500),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.cream,
      body: isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_AppColors.chocoMid),
              ),
            )
          : FadeTransition(
              opacity: _fadeAnim,
              child: CustomScrollView(
                slivers: [
                  // ── Hero Header ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Stack(
                      children: [
                        Container(
                          height: 240,
                          decoration: BoxDecoration(
                            image: const DecorationImage(
                              image: AssetImage('Assets/Image/Bg.jpg'),
                              fit: BoxFit.cover,
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(32),
                              bottomRight: Radius.circular(32),
                            ),
                          ),
                        ),
                        Container(
                          height: 240,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _AppColors.choco.withOpacity(0.72),
                                _AppColors.chocoMid.withOpacity(0.45),
                                Colors.transparent,
                              ],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(32),
                              bottomRight: Radius.circular(32),
                            ),
                          ),
                        ),
                        // Back button
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 12,
                          left: 16,
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.4),
                                ),
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                        // Title content
                        Positioned(
                          bottom: 28,
                          left: 24,
                          right: 24,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _AppColors.gold.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _AppColors.goldLight.withOpacity(
                                      0.6,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _isCoffee
                                      ? 'Coffee'
                                      : _isRemainingMode
                                      ? 'Remaining Stock'
                                      : 'Starting Stock',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _AppColors.goldLight,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isCoffee
                                    ? 'Coffee Details'
                                    : 'Daily Inventory',
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isCoffee
                                    ? '${widget.selectedItem ?? 'Coffee'} Coffee'
                                    : widget.selectedItem ?? 'Item',
                                style: GoogleFonts.dmSans(
                                  color: Colors.white.withOpacity(0.75),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Body Content ─────────────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // Reminder banner
                        _ReminderBanner(
                          _isCoffee
                              ? 'Available coffee sizes and add-ons for this flavor.'
                              : "Please enter today's "
                                    "${_isRemainingMode ? 'remaining' : 'starting'} "
                                    "stock before closing.",
                        ),
                        const SizedBox(height: 22),

                        _SectionLabel(
                          _isCoffee
                              ? '${widget.selectedItem ?? 'Coffee'} Coffee'
                              : _isRemainingMode
                              ? 'Enter Remaining Stock'
                              : 'Enter Starting Stock',
                        ),
                        const SizedBox(height: 18),

                        // ── Items or locked state ──────────────────────────
                        if (productItems.isEmpty)
                          _EmptyState()
                        else
                          ...List.generate(productItems.length, (index) {
                            final item = productItems[index];
                            final originalStartingStock =
                                _isBundle && _bundleCount > 0
                                ? _bundleCount.toString()
                                : item['startingStock']?.toString() ?? '0';
                            final displayPrice = _isBundle
                                ? _bundlePrice
                                : item['price']?.toString() ?? '0';
                            var bottomLabel = _isRemainingMode
                                ? 'Enter Remaining Stock (End of Day)'
                                : 'Enter Starting Stock';
                            if (_isBundle && _bundleCount > 0) {
                              bottomLabel += ' · Bundle stock: $_bundleCount';
                            }
                            if (_isCoffee) {
                              bottomLabel =
                                  item['addonLabel']?.toString().trim() ?? '';
                            }
                            return _ItemCard(
                              itemName: item['name'] ?? 'Item ${index + 1}',
                              price: displayPrice,
                              index: index,
                              controller: itemControllers[index],
                              focusNode: itemFocusNodes[index],
                              startingStock: originalStartingStock,
                              bottomLabel: bottomLabel,
                            );
                          }),

                        const SizedBox(height: 12),

                        // ── Existing Remaining Data Notice ────────────────
                        if (widget.isRemaining && isRemainingLocked)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Remaining stock previously saved. Update values if needed.',
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                color: _AppColors.textLight,
                              ),
                            ),
                          ),

                        // ── Save / Calculate / Update Button ─────────────
                        if (_isCoffee)
                          _PrimaryButton(
                            label: 'Mark Coffee Flavor Low',
                            icon: Icons.warning_amber_rounded,
                            onTap: _markCoffeeLowStock,
                          )
                        else
                          _PrimaryButton(
                            label: _isRemainingMode
                                ? (isRemainingLocked
                                      ? 'Update Remaining'
                                      : 'Calculate Inventory')
                                : 'Save Inventory',
                            icon: _isRemainingMode
                                ? Icons.calculate_rounded
                                : Icons.check_rounded,
                            onTap: _save,
                          ),

                        const SizedBox(height: 12),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _AppColors.parchment,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AppColors.divider),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: _AppColors.textLight,
          ),
          const SizedBox(height: 12),
          Text(
            'No items found for this product',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              color: _AppColors.textLight,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Locked State ──────────────────────────────────────────────────────────────
class _LockedState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _AppColors.parchment,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _AppColors.dustyRose, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _AppColors.chocoLight.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: 20,
                  color: _AppColors.chocoLight,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Remaining stock already submitted',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _AppColors.choco,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'This item has its remaining stock recorded for today. You can update again tomorrow.',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: _AppColors.textMid,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          _PrimaryButton(
            label: 'Back to Dashboard',
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

// ── Primary Button ────────────────────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_AppColors.chocoMid, _AppColors.choco],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _AppColors.choco.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Container(
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: _AppColors.goldLight, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
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

// ─── Data Classes (unchanged) ─────────────────────────────────────────────────

class InventoryCalcLine {
  final String itemName;
  final double price;
  final int startQty;
  final int remainingQty;
  final int soldQty;
  final double startValue;
  final double remainingValue;
  final double soldValue;

  InventoryCalcLine({
    required this.itemName,
    required this.price,
    required this.startQty,
    required this.remainingQty,
    required this.soldQty,
    required this.startValue,
    required this.remainingValue,
    required this.soldValue,
  });
}

class InventoryCalculationResult {
  final List<InventoryCalcLine> lineItems;
  final double totalStartValue;
  final double totalRemainingValue;
  final int totalSoldCount;
  final double totalSoldValue;

  InventoryCalculationResult({
    required this.lineItems,
    required this.totalStartValue,
    required this.totalRemainingValue,
    required this.totalSoldCount,
    required this.totalSoldValue,
  });
}

// ─── Summary Page ─────────────────────────────────────────────────────────────

class RemainingInventorySummaryPage extends StatelessWidget {
  final String itemName;
  final bool isBundle;
  final List<InventoryCalcLine> lineItems;
  final double totalStartValue;
  final double totalRemainingValue;
  final int totalSoldCount;
  final double totalSoldValue;
  final String staffName;
  final String staffId;

  const RemainingInventorySummaryPage({
    super.key,
    required this.itemName,
    required this.isBundle,
    required this.lineItems,
    required this.totalStartValue,
    required this.totalRemainingValue,
    required this.totalSoldCount,
    required this.totalSoldValue,
    required this.staffName,
    required this.staffId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.cream,
      body: CustomScrollView(
        slivers: [
          // ── Custom AppBar ──────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: _AppColors.choco,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const BottomNav()),
                (route) => false,
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
              title: Text(
                'Inventory Result',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_AppColors.chocoMid, _AppColors.choco],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Hero Summary Card ──────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF48FB1), Color(0xFFD81B60)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: _AppColors.choco.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Staff avatar row
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              size: 28,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                staffName,
                                style: GoogleFonts.playfairDisplay(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '#$staffId',
                                style: GoogleFonts.dmSans(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                      _SummaryDivider(),
                      const SizedBox(height: 20),

                      // Item / Bundle label
                      _SummaryChip(
                        label: isBundle ? 'Bundle' : 'Item',
                        value: itemName,
                      ),
                      const SizedBox(height: 20),

                      // Stock rows
                      _SummaryStockTable(lineItems: lineItems),
                      const SizedBox(height: 24),
                      _SummaryDivider(),
                      const SizedBox(height: 20),

                      // Big numbers
                      Row(
                        children: [
                          Expanded(
                            child: _BigStat(
                              label: 'Total Sold',
                              value: '$totalSoldCount',
                              unit: 'pcs',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _BigStat(
                              label: "Today's Sales",
                              value: '₱${totalSoldValue.toStringAsFixed(2)}',
                              unit: '',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Breakdown Card ─────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: _AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _AppColors.divider),
                    boxShadow: [
                      BoxShadow(
                        color: _AppColors.choco.withOpacity(0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const _SectionLabel('Calculation Breakdown'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...lineItems.map((line) => _BreakdownRow(line: line)),
                      Container(
                        height: 1,
                        color: _AppColors.divider,
                        margin: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      _TotalRow(
                        'Total Starting Value',
                        '₱${totalStartValue.toStringAsFixed(2)}',
                      ),
                      const SizedBox(height: 6),
                      _TotalRow(
                        'Total Remaining Value',
                        '₱${totalRemainingValue.toStringAsFixed(2)}',
                      ),
                      const SizedBox(height: 6),
                      _TotalRow(
                        'Total Sold Value',
                        '₱${totalSoldValue.toStringAsFixed(2)}',
                        highlight: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Print Button ───────────────────────────────────────────
                _PrimaryButton(
                  label: 'Save report',
                  icon: Icons.save_rounded,
                  onTap: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const BottomNav()),
                      (route) => false,
                    );
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Summary sub-widgets ───────────────────────────────────────────────────────

class _SummaryDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(height: 1, color: Colors.white.withOpacity(0.15)),
        ),
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _AppColors.goldLight.withOpacity(0.6),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Container(height: 1, color: Colors.white.withOpacity(0.15)),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: GoogleFonts.dmSans(color: Colors.white54, fontSize: 13),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _AppColors.goldLight.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _AppColors.goldLight.withOpacity(0.4)),
          ),
          child: Text(
            value,
            style: GoogleFonts.dmSans(
              color: _AppColors.goldLight,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryStockTable extends StatelessWidget {
  final List<InventoryCalcLine> lineItems;
  const _SummaryStockTable({required this.lineItems});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                'Item',
                style: GoogleFonts.dmSans(
                  color: Colors.white54,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            _HeaderCell('Start'),
            _HeaderCell('Remain'),
            _HeaderCell('Sold'),
          ],
        ),
        const SizedBox(height: 8),
        ...lineItems.map(
          (l) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    l.itemName,
                    style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _DataCell('${l.startQty}'),
                _DataCell('${l.remainingQty}'),
                _DataCell('${l.soldQty}', color: _AppColors.goldLight),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.dmSans(
          color: Colors.white54,
          fontSize: 11,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final Color? color;
  const _DataCell(this.text, {this.color});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.dmSans(
          color: color ?? Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _BigStat({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              color: Colors.white54,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      unit,
                      style: GoogleFonts.dmSans(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final InventoryCalcLine line;
  const _BreakdownRow({required this.line});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _AppColors.blush,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _AppColors.dustyRose),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.itemName,
            style: GoogleFonts.playfairDisplay(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _AppColors.choco,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MiniStat('Start', '₱${line.startValue.toStringAsFixed(2)}'),
              const SizedBox(width: 12),
              _MiniStat('Remain', '₱${line.remainingValue.toStringAsFixed(2)}'),
              const SizedBox(width: 12),
              _MiniStat(
                'Sold',
                '₱${line.soldValue.toStringAsFixed(2)}',
                highlight: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _MiniStat(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 10,
            color: _AppColors.textLight,
            letterSpacing: 0.6,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: highlight ? _AppColors.chocoLight : _AppColors.textMid,
          ),
        ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _TotalRow(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            color: highlight ? _AppColors.choco : _AppColors.textMid,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: highlight ? _AppColors.chocoLight : _AppColors.textMid,
          ),
        ),
      ],
    );
  }
}
