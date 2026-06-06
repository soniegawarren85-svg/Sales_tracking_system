import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../services/expiry_notification_service.dart';
import 'pink_theme.dart';
import 'Expired.dart';

// ──────────────────────────────────────────────────────────────────────────────

// ─── REUSABLE ANIMATED LIST ITEM ──────────────────────────────────────────────
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
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.14),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 55 * widget.index), () {
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

class _AutoImageCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final Widget Function(String imageUrl) imageBuilder;
  final Widget fallback;

  const _AutoImageCarousel({
    required this.imageUrls,
    required this.imageBuilder,
    required this.fallback,
  });

  @override
  State<_AutoImageCarousel> createState() => _AutoImageCarouselState();
}

class _AutoImageCarouselState extends State<_AutoImageCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _AutoImageCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrls.length != widget.imageUrls.length) {
      _index = 0;
      _timer?.cancel();
      if (_controller.hasClients) _controller.jumpToPage(0);
      _startTimer();
    }
  }

  void _startTimer() {
    if (widget.imageUrls.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      _index = (_index + 1) % widget.imageUrls.length;
      _controller.animateToPage(
        _index,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) return widget.fallback;
    if (widget.imageUrls.length == 1) {
      return widget.imageBuilder(widget.imageUrls.first);
    }
    return PageView.builder(
      controller: _controller,
      physics: const BouncingScrollPhysics(),
      itemCount: widget.imageUrls.length,
      onPageChanged: (page) => _index = page,
      itemBuilder: (context, index) => widget.imageBuilder(
        widget.imageUrls[index],
      ),
    );
  }
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage>
    with SingleTickerProviderStateMixin {
  Uint8List? selectedImageBytes;
  final picker = ImagePicker();
  final _firestore = FirebaseFirestore.instance;
  late AnimationController _fabController;

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    ExpiryNotificationService().checkAndNotifyExpiringItems();
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  String _generateVariantId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomSuffix = Random().nextInt(999999).toString().padLeft(6, '0');
    return 'VAR-$timestamp-$randomSuffix';
  }

  int _getDaysUntilExpiry(String expirationDate) {
    try {
      final expiryDate = DateTime.parse(expirationDate);
      final today = DateTime.now();
      return expiryDate.difference(today).inDays;
    } catch (e) {
      return 999;
    }
  }

  bool _isExpiringSoon(String expirationDate) {
    final daysLeft = _getDaysUntilExpiry(expirationDate);
    return daysLeft > 0 && daysLeft <= 3; // Warn 1-3 days before expiry
  }

  bool _isExpired(String expirationDate) {
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

  Future<bool> _hasExistingExpirationNotification(
    List<String> variantIds,
    String notificationType,
  ) async {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final snapshot = await _firestore
        .collection('admin_notifications')
        .where('type', isEqualTo: notificationType)
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
        )
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final existingIds = ((data['itemIds'] as List<dynamic>?) ?? [])
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet();
      if (existingIds.length == variantIds.length &&
          existingIds.containsAll(variantIds)) {
        return true;
      }
    }
    return false;
  }

  // ─── NOTIFICATION METHODS ──────────────────────────────────────────────────

  Future<void> _checkAndNotifyExpiringItems() async {
    try {
      final snapshot = await _firestore.collection('sales_inventory').get();
      final expiringItems = <Map<String, dynamic>>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['isDeleted'] == true) continue;

        final categoryName = data['name']?.toString() ?? '';
        final items = (data['items'] as List<dynamic>?) ?? [];

        for (var item in items) {
          final itemData = item as Map<String, dynamic>;
          final expiryDate = itemData['expirationDate']?.toString() ?? '';
          final daysLeft = _getDaysUntilExpiry(expiryDate);

          if (daysLeft > 0 && daysLeft <= 3) {
            expiringItems.add({
              'categoryName': categoryName,
              'itemName': itemData['name']?.toString() ?? '',
              'variantId': itemData['id']?.toString() ?? '',
              'daysLeft': daysLeft,
              'expiryDate': expiryDate,
            });
          }
        }
      }

      if (expiringItems.isNotEmpty) {
        await _addExpirationNotification(
          expiringItems,
          'expiration_warning',
          '⚠️ Items Expiring Soon',
          'The following items are expiring within 3 days:\n\n',
        );
      }
    } catch (e) {
      debugPrint('Error checking expiring items: $e');
    }
  }

  Future<void> _addExpirationNotification(
    List<Map<String, dynamic>> items,
    String notificationType,
    String title,
    String messagePrefix,
  ) async {
    final variantIds = items
        .map((item) => item['variantId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (variantIds.isNotEmpty &&
        await _hasExistingExpirationNotification(
          variantIds,
          notificationType,
        )) {
      debugPrint('Expiration notification already exists for today.');
      return;
    }

    final itemNames = items
        .map(
          (item) =>
              '${item['itemName']} (${item['categoryName']}) - ${item['daysLeft']} days',
        )
        .join('\n');

    final itemCount = items.length;

    await _firestore.collection('admin_notifications').add({
      'type': notificationType,
      'title': title,
      'message': '$messagePrefix$itemNames',
      'createdAt': Timestamp.now(),
      'dateCreated': DateTime.now(),
      'isRead': false,
      'itemCount': itemCount,
      'itemIds': variantIds,
    });
  }

  // ─── DATA METHODS ──────────────────────────────────────────────────────────

  String _imageContentType(Uint8List bytes, String? pickedMimeType) {
    final mimeType = pickedMimeType?.trim().toLowerCase() ?? '';
    if (mimeType == 'image/jpg') return 'image/jpeg';
    if (mimeType == 'image/x-png') return 'image/png';
    if (mimeType.startsWith('image/')) return mimeType;
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'image/gif';
    }
    return 'image/jpeg';
  }

  String _extensionForContentType(String contentType) {
    switch (contentType) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return 'jpg';
    }
  }

  String? _imageDataUrl(Uint8List bytes, String contentType) {
    final dataUrl = 'data:$contentType;base64,${base64Encode(bytes)}';
    if (dataUrl.length > 700000) {
      debugPrint(
        'Image is too large for Firestore fallback: ${dataUrl.length} chars',
      );
      return null;
    }
    return dataUrl;
  }

  Uint8List? _bytesFromDataUrl(String dataUrl) {
    final commaIndex = dataUrl.indexOf(',');
    if (!dataUrl.startsWith('data:image/') || commaIndex == -1) return null;
    try {
      return base64Decode(dataUrl.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }

  List<String> _variantImageUrls(Map<String, dynamic> item) {
    final urls = <String>[];
    final seen = <String>{};
    final variants = item['items'] as List<dynamic>? ?? [];
    for (final rawVariant in variants) {
      if (rawVariant is! Map) continue;
      final url = rawVariant['imageUrl']?.toString().trim() ?? '';
      if (url.isNotEmpty && seen.add(url)) urls.add(url);
    }
    final categoryUrl = item['imageUrl']?.toString().trim() ?? '';
    if (categoryUrl.isNotEmpty && seen.add(categoryUrl)) urls.add(categoryUrl);
    return urls;
  }

  Future<String?> _uploadInventoryImage(
    Uint8List? bytes, {
    String folder = 'inventory_images',
    String? pickedMimeType,
  }) async {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomSuffix = Random().nextInt(999999).toString().padLeft(6, '0');
      final contentType = _imageContentType(bytes, pickedMimeType);
      final extension = _extensionForContentType(contentType);
      final imagePath = '$folder/${timestamp}_$randomSuffix.$extension';
      final imageRef = FirebaseStorage.instance.ref().child(imagePath);
      final metadata = SettableMetadata(contentType: contentType);
      final snapshotUpload = await imageRef
          .putData(bytes, metadata)
          .timeout(const Duration(seconds: 3));
      return snapshotUpload.ref
          .getDownloadURL()
          .timeout(const Duration(seconds: 3));
    } catch (uploadError) {
      final contentType = _imageContentType(bytes, pickedMimeType);
      final dataUrl = _imageDataUrl(bytes, contentType);
      if (dataUrl != null) {
        debugPrint(
          'Storage upload unavailable, saved image directly in Firestore: $uploadError',
        );
        return dataUrl;
      }
      debugPrint('Image upload failed and fallback image is too large: $uploadError');
      return null;
    }
  }

  Future<void> _saveInventory(Map<String, dynamic> item) async {
    try {
      List<Map<String, dynamic>> itemsList = [];
      if (item['items'] is List) {
        for (var i in item['items']) {
          if (i is Map) {
            final itemImageUrl = await _uploadInventoryImage(
              i['image'] is Uint8List ? i['image'] as Uint8List : null,
              folder: 'inventory_item_images',
              pickedMimeType: i['imageMimeType']?.toString(),
            );
            final savedImageUrl =
                itemImageUrl ?? i['imageUrl']?.toString() ?? '';
            itemsList.add({
              'id': i['id']?.toString() ?? _generateVariantId(),
              'name': i['name']?.toString() ?? '',
              'price': i['price']?.toString() ?? '',
              'startingStock': i['startingStock']?.toString() ?? '0',
              'stock':
                  i['stock']?.toString() ??
                  i['startingStock']?.toString() ??
                  '0',
              'expirationDate': i['expirationDate']?.toString() ?? '',
              'imageUrl': savedImageUrl,
            });
          }
        }
      }

      await _firestore.collection('sales_inventory').add({
        'name': item['name'] ?? '',
        'price': item['price'] ?? '0',
        'items': itemsList,
        'startingStock': item['startingStock'] ?? '0',
        'imageUrl': itemsList
            .map((variant) => variant['imageUrl']?.toString() ?? '')
            .firstWhere((url) => url.isNotEmpty, orElse: () => ''),
        'timestamp': Timestamp.now(),
        'isBundle': false,
      });
      await ExpiryNotificationService().checkAndNotifyExpiringItems();
      if (mounted) _showSuccessSnack('Item saved successfully!');
    } catch (e) {
      debugPrint('Error saving: $e');
      if (mounted) _showErrorSnack('Error saving: $e');
    }
  }

  Future<void> _markStaffInventoryDeleted(String sourceInventoryId) async {
    final snapshot = await _firestore
        .collection('staff_inventory')
        .where('sourceInventoryId', isEqualTo: sourceInventoryId)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'isDeleted': true,
        'deletedAt': Timestamp.now(),
      });
    }
    if (snapshot.docs.isNotEmpty) {
      await batch.commit();
    }
  }

  Future<void> _removeStaffInventoryVariant({
    required String sourceInventoryId,
    required Map<String, dynamic> removedVariant,
  }) async {
    final removedId = removedVariant['id']?.toString() ?? '';
    final removedName = removedVariant['name']?.toString() ?? '';
    final snapshot = await _firestore
        .collection('staff_inventory')
        .where('sourceInventoryId', isEqualTo: sourceInventoryId)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final items = (data['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();

      final nextItems = items.where((entry) {
        final id = entry['id']?.toString() ?? '';
        final name = entry['name']?.toString() ?? '';
        if (removedId.isNotEmpty && id == removedId) return false;
        if (removedName.isNotEmpty && name == removedName) return false;
        return true;
      }).toList();

      if (nextItems.length == items.length) continue;
      batch.update(doc.reference, {
        'items': nextItems,
        if (nextItems.isEmpty) 'isDeleted': true,
        if (nextItems.isEmpty) 'deletedAt': Timestamp.now(),
      });
    }
    if (snapshot.docs.isNotEmpty) {
      await batch.commit();
    }
  }

  void _removeInventoryAt(String itemId) async {
    try {
      await _firestore.collection('sales_inventory').doc(itemId).update({
        'isDeleted': true,
        'deletedAt': Timestamp.now(),
      });
      await _markStaffInventoryDeleted(itemId);
      if (mounted) _showSuccessSnack('Item removed.');
    } catch (e) {
      debugPrint('Error removing: $e');
      if (mounted) _showErrorSnack('Error removing: $e');
    }
  }

  Future<void> pickImage() async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 320,
      maxHeight: 320,
      imageQuality: 40,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      debugPrint('Picked image size: ${bytes.length} bytes (compressed)');
      setState(() => selectedImageBytes = bytes);
    }
  }

  // ─── SNACKBARS ─────────────────────────────────────────────────────────────

  Widget _imagePickerTile({
    required String title,
    required String subtitle,
    required Uint8List? imageBytes,
    required VoidCallback onTap,
    VoidCallback? onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PinkTheme.inputFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PinkTheme.inputBorder, width: 1.3),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 58,
              height: 58,
              color: PinkTheme.badgeBg,
              child: imageBytes == null
                  ? const Icon(
                      Icons.image_rounded,
                      color: PinkTheme.primary,
                      size: 26,
                    )
                  : Image.memory(imageBytes, fit: BoxFit.cover),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: PinkTheme.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: PinkTheme.textLight,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onTap,
            icon: const Icon(Icons.photo_library_rounded, size: 20),
            color: PinkTheme.primary,
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 19),
              color: PinkTheme.deleteRed,
            ),
        ],
      ),
    );
  }

  Widget _variantImageTile({
    Uint8List? imageBytes,
    String? imageUrl,
    double size = 44,
  }) {
    final url = imageUrl?.trim() ?? '';
    Widget child;

    if (imageBytes != null && imageBytes.isNotEmpty) {
      child = Image.memory(imageBytes, fit: BoxFit.cover);
    } else if (url.startsWith('data:image/')) {
      final bytes = _bytesFromDataUrl(url);
      child = bytes == null
          ? const Icon(
              Icons.image_rounded,
              color: PinkTheme.primary,
              size: 22,
            )
          : Image.memory(bytes, fit: BoxFit.cover);
    } else if (url.isNotEmpty) {
      if (url.startsWith('Assets/') || url.startsWith('assets/')) {
        child = Image.asset(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.image_rounded,
            color: PinkTheme.primary,
            size: 22,
          ),
        );
      } else {
        child = Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.image_rounded,
            color: PinkTheme.primary,
            size: 22,
          ),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
        );
      }
    } else {
      child = const Icon(
        Icons.image_rounded,
        color: PinkTheme.primary,
        size: 22,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: size,
        height: size,
        color: PinkTheme.badgeBg,
        child: child,
      ),
    );
  }

  void _showSuccessSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: PinkTheme.successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: PinkTheme.deleteRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ─── DELETE CONFIRM ────────────────────────────────────────────────────────

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: PinkTheme.deleteRed.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_rounded,
                  color: PinkTheme.deleteRed,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Remove Item?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: PinkTheme.textDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This will remove "${item['name']}" from inventory. You can restore it later from the removed items screen within 30 days.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: PinkTheme.textMid,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: PinkTheme.textMid,
                        side: const BorderSide(
                          color: PinkTheme.divider,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PinkTheme.deleteRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Remove',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) _removeInventoryAt(item['id']);
  }

  // ─── ADD INVENTORY BOTTOM SHEET ────────────────────────────────────────────

  void _showAddInventorySheet() {
    selectedImageBytes = null;
    final nameController = TextEditingController();
    final itemNameController = TextEditingController();
    final itemPriceController = TextEditingController();
    final itemStockController = TextEditingController();
    final itemExpirationController = TextEditingController();
    DateTime? selectedExpirationDate;
    Uint8List? itemImageBytes;
    String? itemImageMimeType;
    List<Map<String, dynamic>> items = [];
    bool isSaving = false;
    String? validationMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: PinkTheme.divider,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                PinkTheme.primaryLight,
                                PinkTheme.accent,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.add_box_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add New Item',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: PinkTheme.textDark,
                              ),
                            ),
                            Text(
                              'Fill in the details below',
                              style: TextStyle(
                                fontSize: 13,
                                color: PinkTheme.textLight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(height: 1, color: PinkTheme.divider),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: PinkTheme.deleteRed.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: PinkTheme.deleteRed.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: PinkTheme.deleteRed,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                validationMessage!,
                                style: const TextStyle(
                                  color: PinkTheme.deleteRed,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.only(
                        left: 24,
                        right: 24,
                        top: 24,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('Item Category Name'),
                          const SizedBox(height: 10),
                          _pinkTextField(
                            controller: nameController,
                            hint: 'e.g., Cupcakes, Cakes...',
                            icon: Icons.inventory_2_rounded,
                          ),
                          const SizedBox(height: 24),
                          _sectionLabel('Add items with Price'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: _pinkTextField(
                                  controller: itemNameController,
                                  hint: 'Item name',
                                  icon: Icons.label_rounded,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _pinkTextField(
                                  controller: itemPriceController,
                                  hint: 'Price',
                                  icon: Icons.payments_rounded,
                                  keyboardType: TextInputType.number,
                                  prefixText: '₱',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate:
                                    selectedExpirationDate ?? DateTime.now(),
                                firstDate: DateTime.now().subtract(
                                  const Duration(days: 0),
                                ),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 3650),
                                ),
                              );
                              if (pickedDate != null) {
                                setModalState(() {
                                  selectedExpirationDate = pickedDate;
                                  itemExpirationController.text =
                                      '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}';
                                });
                              }
                            },
                            child: AbsorbPointer(
                              child: _pinkTextField(
                                controller: itemExpirationController,
                                hint: 'Expiration date',
                                icon: Icons.calendar_today_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _pinkTextField(
                            controller: itemStockController,
                            hint: 'Overall stock',
                            icon: Icons.inventory_2_rounded,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 10),
                          _imagePickerTile(
                            title: 'Item Picture',
                            subtitle: itemImageBytes == null
                                ? 'Add picture for this item'
                                : 'Picture selected',
                            imageBytes: itemImageBytes,
                            onTap: () async {
                              final picked = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 320,
                                maxHeight: 320,
                                imageQuality: 40,
                              );
                              if (picked == null) return;
                              final bytes = await picked.readAsBytes();
                              setModalState(() {
                                itemImageBytes = bytes;
                                itemImageMimeType = picked.mimeType;
                              });
                            },
                            onRemove: itemImageBytes == null
                                ? null
                                : () => setModalState(() {
                                    itemImageBytes = null;
                                    itemImageMimeType = null;
                                  }),
                          ),
                          const SizedBox(height: 14),
                          Center(
                            child: GestureDetector(
                              onTap: () {
                                if (itemNameController.text.isEmpty ||
                                    itemPriceController.text.isEmpty ||
                                    itemStockController.text.isEmpty ||
                                    selectedExpirationDate == null) {
                                  setModalState(() {
                                    validationMessage =
                                        'Please enter item name, price, stock, and expiration date.';
                                  });
                                  return;
                                }
                                setModalState(() {
                                  validationMessage = null;
                                  items.add({
                                    'id': _generateVariantId(),
                                    'name': itemNameController.text.trim(),
                                    'price': itemPriceController.text.trim(),
                                    'startingStock': itemStockController.text
                                        .trim(),
                                    'stock': itemStockController.text.trim(),
                                    'expirationDate': itemExpirationController
                                        .text
                                        .trim(),
                                    if (itemImageBytes != null)
                                      'image': itemImageBytes,
                                    if (itemImageMimeType != null)
                                      'imageMimeType': itemImageMimeType,
                                  });
                                  itemNameController.clear();
                                  itemPriceController.clear();
                                  itemStockController.clear();
                                  itemExpirationController.clear();
                                  selectedExpirationDate = null;
                                  itemImageBytes = null;
                                  itemImageMimeType = null;
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                height: 52,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      PinkTheme.accent,
                                      PinkTheme.primaryDark,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: PinkTheme.primary.withOpacity(
                                        0.35,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    'Add items',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (items.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                _sectionLabel('Added Items'),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: PinkTheme.badgeBg,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${items.length}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: PinkTheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final nameCtrl = TextEditingController(
                                  text: items[index]['name'],
                                );
                                final priceCtrl = TextEditingController(
                                  text: items[index]['price'],
                                );
                                final imageBytes =
                                    items[index]['image'] is Uint8List
                                    ? items[index]['image'] as Uint8List
                                    : null;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: PinkTheme.scaffoldBg,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: PinkTheme.divider,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                color: PinkTheme.badgeBg,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  '${index + 1}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: PinkTheme.primary,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            _variantImageTile(
                                              imageBytes: imageBytes,
                                              imageUrl: items[index]['imageUrl']
                                                  ?.toString(),
                                              size: 34,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              flex: 2,
                                              child: TextField(
                                                controller: nameCtrl,
                                                onChanged: (v) =>
                                                    items[index]['name'] = v,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: PinkTheme.textDark,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                      hintText: 'Item name',
                                                      border: InputBorder.none,
                                                      isDense: true,
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                    ),
                                              ),
                                            ),
                                            Container(
                                              width: 1,
                                              height: 22,
                                              color: PinkTheme.divider,
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              '₱',
                                              style: TextStyle(
                                                color: PinkTheme.primary,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Expanded(
                                              child: TextField(
                                                controller: priceCtrl,
                                                keyboardType:
                                                    TextInputType.number,
                                                onChanged: (v) =>
                                                    items[index]['price'] = v,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: PinkTheme.primary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                      hintText: '0.00',
                                                      border: InputBorder.none,
                                                      isDense: true,
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                    ),
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () => setModalState(
                                                () => items.removeAt(index),
                                              ),
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                  left: 8,
                                                ),
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: PinkTheme.deleteRed
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  Icons.delete_rounded,
                                                  color: PinkTheme.deleteRed,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Text(
                                              'Overall',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: PinkTheme.textMid,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${items[index]['startingStock'] ?? items[index]['stock'] ?? '0'} pcs',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: PinkTheme.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Text(
                                              'Expires',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: PinkTheme.textMid,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                '${items[index]['expirationDate'] ?? '--'}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: PinkTheme.primary,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isSaving
                                    ? PinkTheme.primary.withOpacity(0.6)
                                    : PinkTheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                elevation: 6,
                                shadowColor: PinkTheme.primary.withOpacity(0.4),
                              ),
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (nameController.text.isNotEmpty &&
                                          items.isNotEmpty) {
                                        try {
                                          setModalState(() => isSaving = true);
                                        } catch (e) {
                                          debugPrint('setModalState error: $e');
                                        }
                                        try {
                                          final newItem = {
                                            'name': nameController.text,
                                            'items': items
                                                .map(
                                                  (i) => {
                                                    'id': i['id'],
                                                    'name': i['name'],
                                                    'price': i['price'],
                                                    'startingStock':
                                                        i['startingStock'] ??
                                                        '0',
                                                    'stock':
                                                        i['stock'] ??
                                                        i['startingStock'] ??
                                                        '0',
                                                    'expirationDate':
                                                        i['expirationDate'] ??
                                                        '',
                                                    'imageUrl':
                                                        i['imageUrl'] ?? '',
                                                    if (i['image'] != null)
                                                      'image': i['image'],
                                                    if (i['imageMimeType'] !=
                                                        null)
                                                      'imageMimeType':
                                                          i['imageMimeType'],
                                                  },
                                                )
                                                .toList(),
                                          };
                                          await _saveInventory(newItem);
                                          setState(
                                            () => selectedImageBytes = null,
                                          );
                                          if (mounted) Navigator.pop(context);
                                        } catch (e) {
                                          debugPrint('Save error in modal: $e');
                                          if (mounted)
                                            _showErrorSnack('Save failed: $e');
                                          try {
                                            setModalState(
                                              () => isSaving = false,
                                            );
                                          } catch (resetError) {
                                            debugPrint(
                                              'Could not reset saving state: $resetError',
                                            );
                                          }
                                        }
                                      } else {
                                        setModalState(() {
                                          validationMessage =
                                              'Please add a category name and at least one item.';
                                        });
                                      }
                                    },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  isSaving
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.save_rounded,
                                          size: 22,
                                        ),
                                  SizedBox(width: isSaving ? 12 : 8),
                                  Text(
                                    isSaving ? 'Saving...' : 'Save Item',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Get Current Stock From Sales Inventory ────────────────────────────────
  Future<int> _getCurrentStockForVariant(
    String categoryId,
    String variantId,
  ) async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('sales_inventory')
          .doc(categoryId)
          .get();

      if (!docSnapshot.exists) {
        return 0;
      }

      final data = docSnapshot.data();
      if (data == null) {
        return 0;
      }

      final items = (data['items'] as List<dynamic>?) ?? [];

      for (final item in items) {
        final itemData = item as Map<String, dynamic>?;
        if (itemData == null) continue;
        final idMatch = itemData['id']?.toString() == variantId;
        final nameMatch = !idMatch && itemData['name']?.toString() == variantId;
        if (idMatch || nameMatch) {
          final rawStock = itemData['stock'];
          int currentStock;
          if (rawStock is num) {
            currentStock = rawStock.toInt();
          } else {
            currentStock =
                int.tryParse(rawStock?.toString() ?? '') ??
                _parseQuantity(itemData['startingStock']);
          }

          if (currentStock < 0) {
            currentStock = 0;
          }

          return currentStock;
        }
      }

      return 0; // Variant not found in this document
    } catch (e) {
      debugPrint('Error getting current stock: $e');
      return 0;
    }
  }

  // ─── ITEMS DETAIL MODAL ────────────────────────────────────────────────────

  void _showItemsModal(Map<String, dynamic> item) {
    final categoryId = item['id']?.toString() ?? '';
    bool shouldSaveMissingIds = false;
    final List<Map<String, dynamic>> itemsList =
        ((item['items'] as List<dynamic>? ?? [])
                .where((e) {
                  final variant = e as Map<String, dynamic>?;
                  final expiryDate =
                      variant?['expirationDate']?.toString() ?? '';
                  return !_isExpired(expiryDate);
                })
                .map(
                  (e) => Map<String, dynamic>.from(e as Map<String, dynamic>),
                ))
            .map((variant) {
              if (variant['id'] == null || variant['id'].toString().isEmpty) {
                variant['id'] = _generateVariantId();
                shouldSaveMissingIds = true;
              }
              if (variant['stock'] == null) {
                variant['stock'] = variant['startingStock'] ?? '0';
              }
              return variant;
            })
            .toList();

    if (shouldSaveMissingIds && categoryId.isNotEmpty) {
      _firestore.collection('sales_inventory').doc(categoryId).update({
        'items': itemsList,
      });
    }

    Future<void> addVariant(
      void Function(void Function()) setModalState,
    ) async {
      final addNameController = TextEditingController();
      final addPriceController = TextEditingController();
      final addStockController = TextEditingController();
      final addExpirationController = TextEditingController();
      DateTime? addDate;
      Uint8List? addImageBytes;
      String? addImageMimeType;

      final saved = await showDialog<bool>(
        context: context,
        builder: (_) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Text('Add item variant'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: addNameController,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: addPriceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          prefixText: '₱',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: addStockController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Overall stock',
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: addDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 3650),
                            ),
                          );
                          if (picked != null) {
                            setState(() {
                              addDate = picked;
                              addExpirationController.text =
                                  '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                            });
                          }
                        },
                        child: AbsorbPointer(
                          child: TextField(
                            controller: addExpirationController,
                            decoration: const InputDecoration(
                              labelText: 'Expiration date',
                              prefixIcon: Icon(Icons.calendar_today_rounded),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _imagePickerTile(
                        title: 'Item Picture',
                        subtitle: addImageBytes == null
                            ? 'Add picture for this variant'
                            : 'Picture selected',
                        imageBytes: addImageBytes,
                        onTap: () async {
                          final picked = await picker.pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 320,
                            maxHeight: 320,
                            imageQuality: 40,
                          );
                          if (picked == null) return;
                          final bytes = await picked.readAsBytes();
                          setState(() {
                            addImageBytes = bytes;
                            addImageMimeType = picked.mimeType;
                          });
                        },
                        onRemove: addImageBytes == null
                            ? null
                            : () => setState(() {
                                addImageBytes = null;
                                addImageMimeType = null;
                              }),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (addNameController.text.isEmpty ||
                          addPriceController.text.isEmpty ||
                          addStockController.text.isEmpty ||
                          addExpirationController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please fill all variant fields before saving.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context, true);
                    },
                    child: const Text('Add'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (saved == true) {
        final newVariant = <String, dynamic>{
          'id': _generateVariantId(),
          'name': addNameController.text.trim(),
          'price': addPriceController.text.trim(),
          'startingStock': addStockController.text.trim(),
          'stock': addStockController.text.trim(),
          'expirationDate': addExpirationController.text.trim(),
        };
        try {
          final imageUrl = await _uploadInventoryImage(
            addImageBytes,
            folder: 'inventory_item_images',
            pickedMimeType: addImageMimeType,
          );
          if (imageUrl != null && imageUrl.isNotEmpty) {
            newVariant['imageUrl'] = imageUrl;
          }
          final allItems = (item['items'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          allItems.add(newVariant);
          final categoryImageUrl = item['imageUrl']?.toString() ?? '';
          await _firestore.collection('sales_inventory').doc(item['id']).update({
            'items': allItems,
            if (categoryImageUrl.isEmpty &&
                imageUrl != null &&
                imageUrl.isNotEmpty)
              'imageUrl': imageUrl,
          });
          setModalState(() {
            itemsList.add(newVariant);
            item['items'] = allItems;
            if (categoryImageUrl.isEmpty &&
                imageUrl != null &&
                imageUrl.isNotEmpty) {
              item['imageUrl'] = imageUrl;
            }
          });
          _showSuccessSnack('Variant added.');
        } catch (e) {
          debugPrint('Variant add error: $e');
          _showErrorSnack('Failed to add variant: $e');
        }
      }

      addNameController.dispose();
      addPriceController.dispose();
      addStockController.dispose();
      addExpirationController.dispose();
    }

    Future<void> editVariant(
      int index,
      void Function(void Function()) setModalState,
    ) async {
      final variant = Map<String, dynamic>.from(itemsList[index]);
      final editNameController = TextEditingController(
        text: variant['name']?.toString() ?? '',
      );
      final editPriceController = TextEditingController(
        text: variant['price']?.toString() ?? '',
      );
      final editStockController = TextEditingController(
        text: variant['startingStock']?.toString() ?? '',
      );
      final editExpirationController = TextEditingController(
        text: variant['expirationDate']?.toString() ?? '',
      );
      DateTime? editDate;
      if (variant['expirationDate'] != null &&
          variant['expirationDate'].toString().isNotEmpty) {
        editDate = DateTime.tryParse(variant['expirationDate'].toString());
      }

      final saved = await showDialog<bool>(
        context: context,
        builder: (_) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Text('Edit item variant'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: editNameController,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: editPriceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          prefixText: '₱',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: editStockController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Overall stock',
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: editDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 0),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 3650),
                            ),
                          );
                          if (picked != null) {
                            setState(() {
                              editDate = picked;
                              editExpirationController.text =
                                  '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                            });
                          }
                        },
                        child: AbsorbPointer(
                          child: TextField(
                            controller: editExpirationController,
                            decoration: const InputDecoration(
                              labelText: 'Expiration date',
                              prefixIcon: Icon(Icons.calendar_today_rounded),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (editNameController.text.isEmpty ||
                          editPriceController.text.isEmpty ||
                          editStockController.text.isEmpty ||
                          editExpirationController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please fill all variant fields before saving.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      itemsList[index] = {
                        'id': variant['id']?.toString() ?? _generateVariantId(),
                        'name': editNameController.text.trim(),
                        'price': editPriceController.text.trim(),
                        'startingStock': editStockController.text.trim(),
                        'stock': editStockController.text.trim(),
                        'expirationDate': editExpirationController.text.trim(),
                        'imageUrl': variant['imageUrl']?.toString() ?? '',
                      };
                      Navigator.pop(context, true);
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (saved == true) {
        try {
          await _firestore.collection('sales_inventory').doc(item['id']).update(
            {'items': itemsList},
          );
          setModalState(() {});
          _showSuccessSnack('Variant updated.');
        } catch (e) {
          debugPrint('Variant edit error: $e');
          _showErrorSnack('Failed to update variant: $e');
        }
      }
    }

    Future<void> removeVariant(
      int index,
      void Function(void Function()) setModalState,
    ) async {
      final removedVariant = Map<String, dynamic>.from(itemsList[index]);
      if (itemsList.length == 1) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: PinkTheme.deleteRed.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.delete_rounded,
                      color: PinkTheme.deleteRed,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Remove Category?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: PinkTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Removing the last variant will remove the entire category.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: PinkTheme.textMid,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: PinkTheme.textMid,
                            side: const BorderSide(
                              color: PinkTheme.divider,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: PinkTheme.deleteRed,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Remove',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        if (confirm == true) {
          _removeInventoryAt(item['id']);
          if (mounted) Navigator.pop(context);
        }
        return;
      }

      try {
        setModalState(() => itemsList.removeAt(index));
        await _firestore.collection('sales_inventory').doc(item['id']).update({
          'items': itemsList,
          'removedItems': FieldValue.arrayUnion([
            {
              'name': removedVariant['name'] ?? '',
              'price': removedVariant['price'] ?? '0',
              'startingStock': removedVariant['startingStock'] ?? '0',
              'expirationDate': removedVariant['expirationDate'] ?? '',
              'removedAt': Timestamp.now(),
            },
          ]),
        });
        await _removeStaffInventoryVariant(
          sourceInventoryId: item['id']?.toString() ?? '',
          removedVariant: removedVariant,
        );
        _showSuccessSnack('Variant removed.');
      } catch (e) {
        debugPrint('Variant remove error: $e');
        _showErrorSnack('Failed to remove variant: $e');
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.55,
              minChildSize: 0.4,
              maxChildSize: 0.85,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 14),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: PinkTheme.divider,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    item['name'],
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      color: PinkTheme.primary,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        PinkTheme.primaryLight,
                                        PinkTheme.accent,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${itemsList.length} variants',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () => addVariant(setModalState),
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Add item'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: PinkTheme.primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'All available variants and prices',
                              style: TextStyle(
                                fontSize: 13,
                                color: PinkTheme.textLight,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(height: 1, color: PinkTheme.divider),
                          ],
                        ),
                      ),
                      Expanded(
                        child: itemsList.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(22),
                                      decoration: const BoxDecoration(
                                        color: PinkTheme.badgeBg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.list_alt_rounded,
                                        size: 46,
                                        color: PinkTheme.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No items added',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: PinkTheme.textLight,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  16,
                                  24,
                                  32,
                                ),
                                itemCount: itemsList.length,
                                itemBuilder: (context, index) {
                                  final d = itemsList[index];
                                  final itemId = d['id']?.toString() ?? '';
                                  final itemName = d['name']?.toString() ?? '';
                                  final itemPrice =
                                      d['price']?.toString() ?? '';
                                  final itemStart =
                                      d['startingStock']?.toString() ?? '';
                                  final itemExpiration =
                                      d['expirationDate']?.toString() ?? '';
                                  final itemImageUrl =
                                      d['imageUrl']?.toString() ?? '';

                                  return _FadeSlideIn(
                                    index: index,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: index.isEven
                                              ? PinkTheme.scaffoldBg
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: PinkTheme.divider,
                                            width: 1.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: PinkTheme.primary
                                                  .withOpacity(0.05),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    _variantImageTile(
                                                      imageUrl: itemImageUrl,
                                                      size: 48,
                                                    ),
                                                    Positioned(
                                                      left: -4,
                                                      top: -4,
                                                      child: Container(
                                                        width: 20,
                                                        height: 20,
                                                        decoration:
                                                            BoxDecoration(
                                                          color:
                                                              PinkTheme.primary,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(7),
                                                        ),
                                                        child: Center(
                                                          child: Text(
                                                            '${index + 1}',
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        itemName,
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: PinkTheme
                                                              .textDark,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      if (itemPrice
                                                          .isNotEmpty) ...[
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          '₱ $itemPrice',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                color: PinkTheme
                                                                    .primary,
                                                              ),
                                                        ),
                                                      ],
                                                      const SizedBox(height: 6),
                                                      if (itemId
                                                          .isNotEmpty) ...[
                                                        Text(
                                                          'ID: $itemId',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: PinkTheme
                                                                    .textMid,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                      ],
                                                      Wrap(
                                                        spacing: 10,
                                                        runSpacing: 4,
                                                        children: [
                                                          FutureBuilder<int>(
                                                            future:
                                                                _getCurrentStockForVariant(
                                                                  categoryId,
                                                                  itemId,
                                                                ),
                                                            builder: (context, snapshot) {
                                                              final displayStock =
                                                                  snapshot
                                                                      .hasData
                                                                  ? snapshot
                                                                        .data!
                                                                  : _parseQuantity(
                                                                      itemStart,
                                                                    );
                                                              return Text(
                                                                'Start: $displayStock pcs',
                                                                style: const TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: PinkTheme
                                                                      .textMid,
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                          Text(
                                                            'Expires: $itemExpiration',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: PinkTheme
                                                                      .primary,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                GestureDetector(
                                                  onTap: () => editVariant(
                                                    index,
                                                    setModalState,
                                                  ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: PinkTheme
                                                          .primaryLight
                                                          .withOpacity(0.2),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: const Icon(
                                                      Icons.edit_rounded,
                                                      color: PinkTheme.primary,
                                                      size: 18,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                GestureDetector(
                                                  onTap: () => removeVariant(
                                                    index,
                                                    setModalState,
                                                  ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: PinkTheme.deleteRed
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Icon(
                                                      Icons.remove_rounded,
                                                      color:
                                                          PinkTheme.deleteRed,
                                                      size: 18,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ─── INVENTORY CARD ────────────────────────────────────────────────────────

  String _buildCategoryId(Map<String, dynamic> item) {
    final timestampValue = item['timestamp'];
    final DateTime dt = timestampValue is Timestamp
        ? timestampValue.toDate().toLocal()
        : DateTime.now();

    final datePart =
        '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';
    final timePart =
        '${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}';

    final candidateName = (item['name'] as String?)?.trim() ?? '';
    String codeSource = candidateName.isNotEmpty
        ? candidateName
        : (item['id']?.toString() ?? 'CAT');
    codeSource = codeSource.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final code = codeSource.length >= 4
        ? codeSource.substring(0, 4).toUpperCase()
        : codeSource.toUpperCase().padRight(4, 'X');

    return 'CAT-$datePart-$timePart-$code';
  }

  double _parseAmount(dynamic value) {
    if (value is num) return value.toDouble();
    final text = value?.toString() ?? '';
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  int _parseQuantity(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _calculateExpectedSales(Map<String, dynamic> item) {
    final variants = (item['items'] as List<dynamic>?) ?? [];
    var total = 0.0;
    for (final rawVariant in variants) {
      if (rawVariant is Map<String, dynamic>) {
        final price = _parseAmount(rawVariant['price']);
        var quantity = _parseQuantity(rawVariant['startingStock']);
        if (quantity <= 0) {
          quantity = _parseQuantity(rawVariant['stock']);
        }
        total += price * quantity;
      } else if (rawVariant is Map) {
        final variant = rawVariant.cast<String, dynamic>();
        final price = _parseAmount(variant['price']);
        var quantity = _parseQuantity(variant['startingStock']);
        if (quantity <= 0) {
          quantity = _parseQuantity(variant['stock']);
        }
        total += price * quantity;
      }
    }
    return total;
  }

  int _calculateTotalStock(Map<String, dynamic> item) {
    final variants = (item['items'] as List<dynamic>?) ?? [];
    var total = 0;
    for (final rawVariant in variants) {
      if (rawVariant is Map<String, dynamic>) {
        var quantity = _parseQuantity(rawVariant['stock']);
        if (quantity <= 0) {
          quantity = _parseQuantity(rawVariant['startingStock']);
        }
        total += quantity;
      } else if (rawVariant is Map) {
        final variant = rawVariant.cast<String, dynamic>();
        var quantity = _parseQuantity(variant['stock']);
        if (quantity <= 0) {
          quantity = _parseQuantity(variant['startingStock']);
        }
        total += quantity;
      }
    }
    return total;
  }

  Widget _inventoryCard(int index, Map<String, dynamic> item) {
    final int itemCount = (item['items'] as List?)?.length ?? 0;
    final items = (item['items'] as List<dynamic>?) ?? [];
    final int totalStock = _calculateTotalStock(item);

    // Check if any variant is expiring soon
    bool hasExpiringItems = false;
    for (var variant in items) {
      final variantMap = variant as Map<String, dynamic>?;
      final expiryDate = variantMap?['expirationDate']?.toString() ?? '';
      if (_isExpiringSoon(expiryDate)) {
        hasExpiringItems = true;
        break;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            blurRadius: 24,
            color: PinkTheme.primary.withOpacity(0.10),
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            blurRadius: 6,
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Container(
                  height: 190,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [PinkTheme.primaryLight, PinkTheme.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: _AutoImageCarousel(
                    imageUrls: _variantImageUrls(item),
                    imageBuilder: _buildItemImage,
                    fallback: _imagePlaceholder(),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.35),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              if (hasExpiringItems)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC107),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFC107).withOpacity(0.6),
                          blurRadius: 12,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.warning_rounded,
                      color: Colors.black87,
                      size: 22,
                    ),
                  ),
                ),
              Positioned(
                bottom: 14,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.grid_view_rounded,
                        size: 14,
                        color: PinkTheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$itemCount variant${itemCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: PinkTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () => _confirmDelete(item),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 8,
                          color: Colors.black.withOpacity(0.15),
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: PinkTheme.deleteRed,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item['name'],
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: PinkTheme.primary,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: PinkTheme.primary.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$totalStock pcs in stock',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: PinkTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Category ID: ${_buildCategoryId(item)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: PinkTheme.textLight,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => _showItemsModal(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [PinkTheme.primary, PinkTheme.accent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: PinkTheme.primary.withOpacity(0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: PinkTheme.primaryLight.withOpacity(0.3),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_rounded, size: 52, color: Colors.white60),
            SizedBox(height: 8),
            Text(
              'No Image',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemImage(String imageUrl) {
    if (imageUrl.startsWith('data:image/')) {
      final bytes = _bytesFromDataUrl(imageUrl);
      if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
      return _imagePlaceholder();
    }
    if (imageUrl.startsWith('Assets/') || imageUrl.startsWith('assets/')) {
      return Image.asset(imageUrl, fit: BoxFit.cover);
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _imagePlaceholder(),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            valueColor: const AlwaysStoppedAnimation(Colors.white),
            value: progress.expectedTotalBytes != null
                ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                : null,
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: PinkTheme.textMid,
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _pinkTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? prefixText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: PinkTheme.textDark,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: PinkTheme.textLight,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        prefixText: prefixText,
        prefixStyle: const TextStyle(
          color: PinkTheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        prefixIcon: Icon(icon, color: PinkTheme.primaryLight, size: 20),
        filled: true,
        fillColor: PinkTheme.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PinkTheme.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: PinkTheme.inputBorder,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PinkTheme.inputFocused, width: 2),
        ),
      ),
    );
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PinkTheme.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── ENHANCED HEADER ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [PinkTheme.primaryDark, PinkTheme.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 24,
                    color: PinkTheme.primary.withOpacity(0.32),
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Row 1: Back + Title ──────────────────────────────────────
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inventory',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            Text(
                              'Manage your products',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── Row 2: Bulk + Removed (grouped) | Expired (separate) ─────
                  Row(
                    children: [
                      // ── Grouped Pill: Bulk + Removed ─────────────────────────
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              // ── Bulk Button ──────────────────────────────────────
                              Expanded(
                                child: GestureDetector(
                                  onTap: () async {
                                    final inventory = await _getInventoryList();
                                    if (mounted) {
                                      final saved = await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => BulkInventoryPage(
                                            inventory: inventory,
                                          ),
                                        ),
                                      );
                                      if (saved == true && mounted)
                                        setState(() {});
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.20),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.25,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.inventory_2_rounded,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Flexible(
                                          child: Text(
                                            'Bulk',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // ── Divider ─────────────────────────────────────────
                              Container(
                                width: 1,
                                height: 28,
                                color: Colors.white.withOpacity(0.25),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                              ),

                              // ── Removed Button ────────────────────────────────────
                              Expanded(
                                child: GestureDetector(
                                  onTap: () async {
                                    final restored = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const RemovedInventoryPage(),
                                      ),
                                    );
                                    if (restored == true && mounted)
                                      setState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.20),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.25,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.restore_from_trash_rounded,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Flexible(
                                          child: Text(
                                            'Removed',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      // ── Expired Button (Standalone, Distinct) ──────────────────
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 124),
                        child: GestureDetector(
                          onTap: () async {
                            await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ExpiredPage(),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFFF6B35).withOpacity(0.92),
                                  const Color(0xFFFF3D57).withOpacity(0.88),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFFF3D57,
                                  ).withOpacity(0.45),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                              border: Border.all(
                                color: Colors.white.withOpacity(0.25),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.22),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Flexible(
                                  child: Text(
                                    'Expired',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── LIST ──────────────────────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('sales_inventory').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(
                              PinkTheme.primary,
                            ),
                            strokeWidth: 3,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Loading inventory...',
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
                          const Icon(
                            Icons.error_rounded,
                            color: PinkTheme.deleteRed,
                            size: 48,
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
                  final docs = snapshot.data?.docs ?? [];
                  final activeItems = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['isDeleted'] == true) return false;
                    if (data['isBundle'] == true) return false;
                    if (data.containsKey('bundleId') &&
                        data['bundleId'] != null &&
                        data['bundleId'].toString().isNotEmpty) {
                      return false;
                    }
                    final activeVariants =
                        ((data['items'] as List<dynamic>?) ?? []).where((e) {
                          final variant = e as Map<String, dynamic>?;
                          final expiryDate =
                              variant?['expirationDate']?.toString() ?? '';
                          return !_isExpired(expiryDate);
                        }).toList();
                    return activeVariants.isNotEmpty;
                  }).toList();
                  if (activeItems.isEmpty) return _emptyState();
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                    itemCount: activeItems.length,
                    itemBuilder: (context, index) {
                      final doc = activeItems[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final filteredItems =
                          ((data['items'] as List<dynamic>?) ?? [])
                              .where((e) {
                                final variant = e as Map<String, dynamic>?;
                                final expiryDate =
                                    variant?['expirationDate']?.toString() ??
                                    '';
                                return !_isExpired(expiryDate);
                              })
                              .map(
                                (e) => Map<String, dynamic>.from(
                                  e as Map<String, dynamic>,
                                ),
                              )
                              .toList();
                      final item = {
                        'id': doc.id,
                        'name': data['name'] ?? '',
                        'price': data['price'] ?? '0',
                        'items': filteredItems,
                        'imageUrl': data['imageUrl'],
                        'timestamp': data['timestamp'],
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _FadeSlideIn(
                          index: index,
                          child: _inventoryCard(index, item),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddInventorySheet,
        backgroundColor: PinkTheme.primary,
        foregroundColor: Colors.white,
        elevation: 10,
        extendedPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 0,
        ),
        icon: const Icon(Icons.add_rounded, size: 26),
        label: const Text(
          'Add Item',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getInventoryList() async {
    try {
      final snapshot = await _firestore.collection('sales_inventory').get();
      List<Map<String, dynamic>> inventory = [];
      for (var doc in snapshot.docs) {
        if (doc.data().containsKey('isDeleted') && doc['isDeleted'] == true)
          continue;
        if (doc.data().containsKey('isBundle') && doc['isBundle'] == true)
          continue;
        if (doc.data().containsKey('bundleId') &&
            doc['bundleId'] != null &&
            doc['bundleId'].toString().isNotEmpty)
          continue;
        final data = doc.data();
        final filteredItems = ((data['items'] as List<dynamic>?) ?? [])
            .where((e) {
              final variant = e as Map<String, dynamic>?;
              final expiryDate = variant?['expirationDate']?.toString() ?? '';
              return !_isExpired(expiryDate);
            })
            .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
            .toList();
        if (filteredItems.isEmpty) continue;
        inventory.add({
          'id': doc.id,
          'name': data['name'] ?? '',
          'price': data['price'] ?? '0',
          'items': filteredItems,
          'imageUrl': data['imageUrl'],
          'timestamp': data['timestamp'],
        });
      }
      return inventory;
    } catch (e) {
      debugPrint('Error getting inventory list: $e');
      return [];
    }
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [PinkTheme.badgeBg, Color(0xFFFDE0EC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              size: 60,
              color: PinkTheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Items Yet',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: PinkTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap "Add Item" below to create\nyour first inventory entry.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: PinkTheme.textLight,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BULK INVENTORY PAGE  ──  FULLY ENHANCED UI + ANIMATIONS
// ═══════════════════════════════════════════════════════════════════════════════

class BulkInventoryPage extends StatefulWidget {
  final List<Map<String, dynamic>> inventory;
  const BulkInventoryPage({super.key, required this.inventory});

  @override
  State<BulkInventoryPage> createState() => _BulkInventoryPageState();
}

class _BulkInventoryPageState extends State<BulkInventoryPage>
    with TickerProviderStateMixin {
  final TextEditingController bundleNameController = TextEditingController();
  final TextEditingController bundlePriceController = TextEditingController();
  final TextEditingController bundleQuantityController = TextEditingController(
    text: '1',
  );
  Uint8List? bundleImageBytes;
  final ImagePicker _bundlePicker = ImagePicker();
  final Map<String, Map<int, int>> selectedVariantQuantities = {};
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<Map<String, dynamic>> bundles = [];
  bool _isSaving = false;
  int _selectedTabIndex = 0;
  late List<Map<String, dynamic>> _inventory;

  // ── Animations
  late AnimationController _headerAnim;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late AnimationController _bodyAnim;
  late Animation<double> _bodyFade;

  @override
  void initState() {
    super.initState();
    _inventory = widget.inventory
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    _headerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _headerFade = CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _headerAnim, curve: Curves.easeOutCubic));

    _bodyAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _bodyFade = CurvedAnimation(parent: _bodyAnim, curve: Curves.easeIn);

    _headerAnim.forward();
    _bodyAnim.forward();
    _loadBundles();
    bundleQuantityController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    bundleNameController.dispose();
    bundlePriceController.dispose();
    bundleQuantityController.dispose();
    _headerAnim.dispose();
    _bodyAnim.dispose();
    super.dispose();
  }

  Future<void> _loadBundles() async {
    try {
      final snapshot = await _firestore
          .collection('sales_inventory')
          .where('isBundle', isEqualTo: true)
          .get();
      if (!mounted) return;
      setState(() {
        bundles.clear();
        for (final doc in snapshot.docs) {
          final data = Map<String, dynamic>.from(
            doc.data() as Map<String, dynamic>? ?? {},
          );
          if (data['isDeleted'] == true) continue;
          final items = data['items'] ?? [];
          bundles.add({
            'id': doc.id,
            'name': data['name'] ?? '',
            'price': data['price'] ?? '0',
            'bundleCount': data['bundleCount'] ?? 1,
            'bundleId': data['bundleId'] ?? '',
            'bundleInstances': data['bundleInstances'] ?? [],
            'imageUrl': data['imageUrl'],
            'items': items is List ? items.cast<dynamic>() : <dynamic>[],
            'timestamp': data['timestamp'],
          });
        }
      });
    } catch (e) {
      debugPrint('Error loading bundles: $e');
    }
  }

  Future<void> _markStaffInventoryDeleted(String sourceInventoryId) async {
    final snapshot = await _firestore
        .collection('staff_inventory')
        .where('sourceInventoryId', isEqualTo: sourceInventoryId)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'isDeleted': true,
        'deletedAt': Timestamp.now(),
      });
    }
    if (snapshot.docs.isNotEmpty) {
      await batch.commit();
    }
  }

  void _switchTab(int index) {
    _bodyAnim.reverse().then((_) {
      setState(() => _selectedTabIndex = index);
      _bodyAnim.forward();
    });
  }

  void _incrementVariant(String itemId, int variantIndex) {
    setState(() {
      final quantities = selectedVariantQuantities[itemId] ?? <int, int>{};
      final currentCount = quantities[variantIndex] ?? 0;
      quantities[variantIndex] = currentCount + 1;
      selectedVariantQuantities[itemId] = quantities;
    });
  }

  void _decrementVariant(String itemId, int variantIndex) {
    setState(() {
      final quantities = selectedVariantQuantities[itemId];
      if (quantities == null) return;
      final currentCount = quantities[variantIndex] ?? 0;
      if (currentCount <= 1) {
        quantities.remove(variantIndex);
      } else {
        quantities[variantIndex] = currentCount - 1;
      }
      if (quantities.isEmpty) {
        selectedVariantQuantities.remove(itemId);
      } else {
        selectedVariantQuantities[itemId] = quantities;
      }
    });
  }

  void _setVariantQuantity(String itemId, int variantIndex, int newQuantity) {
    setState(() {
      final quantities = selectedVariantQuantities[itemId] ?? <int, int>{};
      if (newQuantity <= 0) {
        quantities.remove(variantIndex);
      } else {
        quantities[variantIndex] = newQuantity;
      }
      if (quantities.isEmpty) {
        selectedVariantQuantities.remove(itemId);
      } else {
        selectedVariantQuantities[itemId] = quantities;
      }
    });
  }

  int _parseQuantity(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String? _bundleDataUrl(Uint8List bytes) {
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    return dataUrl.length <= 700000 ? dataUrl : null;
  }

  Future<String?> _uploadBundleImage() async {
    final bytes = bundleImageBytes;
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imageRef = FirebaseStorage.instance.ref().child(
        'bundle_images/$timestamp.jpg',
      );
      final snapshotUpload = await imageRef
          .putData(bytes, SettableMetadata(contentType: 'image/jpeg'))
          .timeout(const Duration(seconds: 3));
      return snapshotUpload.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Bundle image upload failed: $e');
      return _bundleDataUrl(bytes);
    }
  }

  Future<void> _pickBundleImage() async {
    final picked = await _bundlePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 70,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => bundleImageBytes = bytes);
  }

  String _bundleInstanceId(String bundleId, int index) {
    final suffix = (index + 1).toString().padLeft(3, '0');
    return bundleId.isEmpty ? 'Bundle-$suffix' : '$bundleId-$suffix';
  }

  List<Map<String, dynamic>> _bundleInstancesFromBundle(
    Map<String, dynamic> bundle,
  ) {
    final savedInstances = bundle['bundleInstances'];
    if (savedInstances is List && savedInstances.isNotEmpty) {
      return savedInstances
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }

    final bundleCount = bundle['bundleCount'] is int
        ? bundle['bundleCount'] as int
        : int.tryParse(bundle['bundleCount']?.toString() ?? '1') ?? 1;
    final bundleId = bundle['bundleId']?.toString() ?? '';
    final items = bundle['items'] as List<dynamic>? ?? [];

    return List.generate(bundleCount, (index) {
      return {
        'number': index + 1,
        'id': _bundleInstanceId(bundleId, index),
        'status': 'available',
        'items': items.map((item) {
          if (item is! Map<String, dynamic>) return <String, dynamic>{};
          final quantity = _parseQuantity(item['quantity']);
          return {
            'name': item['name']?.toString() ?? 'Item',
            'price': item['price']?.toString() ?? '0',
            'quantity': quantity,
            'remaining': quantity,
          };
        }).toList(),
      };
    });
  }

  Widget _bundleImagePreview(String? imageUrl) {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) return const SizedBox.shrink();
    Widget image;
    if (url.startsWith('data:image/')) {
      final commaIndex = url.indexOf(',');
      Uint8List? bytes;
      if (commaIndex != -1) {
        try {
          bytes = base64Decode(url.substring(commaIndex + 1));
        } catch (_) {}
      }
      image = bytes == null
          ? const SizedBox.shrink()
          : Image.memory(bytes, fit: BoxFit.cover);
    } else {
      image = Image.network(url, fit: BoxFit.cover);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(aspectRatio: 16 / 9, child: image),
      ),
    );
  }

  String _generateBundleId() {
    final now = DateTime.now();
    final first = (now.microsecondsSinceEpoch % 90000 + 10000)
        .toString()
        .padLeft(5, '0');
    final second = (Random().nextInt(900) + 100).toString().padLeft(3, '0');
    return '$first $second';
  }

  int get _selectedVariantCount => selectedVariantQuantities.values.fold(
    0,
    (sum, qtyMap) => sum + qtyMap.values.fold<int>(0, (p, q) => p + q),
  );

  String? _getBundleStockValidationMessage(int bundleQty) {
    if (_selectedVariantCount == 0 || bundleQty < 1) return null;

    int? maxBundles;
    for (final item in _inventory) {
      final itemId = item['id']?.toString() ?? '';
      final quantities = selectedVariantQuantities[itemId];
      if (quantities == null) continue;
      final variants = item['items'] as List<dynamic>? ?? [];
      for (final entry in quantities.entries) {
        final variantIndex = entry.key;
        final perBundleQty = entry.value;
        if (perBundleQty <= 0 ||
            variantIndex < 0 ||
            variantIndex >= variants.length) {
          continue;
        }
        final variant = variants[variantIndex] as Map<String, dynamic>? ?? {};
        final availableQty = _parseQuantity(
          variant['stock'] ?? variant['startingStock'],
        );
        final possibleBundles = perBundleQty > 0
            ? availableQty ~/ perBundleQty
            : 0;
        maxBundles = maxBundles == null
            ? possibleBundles
            : (possibleBundles < maxBundles ? possibleBundles : maxBundles);
      }
    }

    if (maxBundles == null) return null;
    if (maxBundles <= 0) {
      return 'Selected quantities exceed available stock.';
    }
    if (bundleQty > maxBundles) {
      return 'Maximum bundles allowed for current selection is $maxBundles.';
    }
    return null;
  }

  Future<void> _saveBulkBundle() async {
    final name = bundleNameController.text.trim();
    final price = bundlePriceController.text.trim();
    final bundleQtyStr = bundleQuantityController.text.trim();
    final bundleQty = int.tryParse(bundleQtyStr) ?? 1;

    if (name.isEmpty) {
      _showErrorSnack('Please enter a bundle name.');
      return;
    }
    if (_selectedVariantCount == 0) {
      _showErrorSnack('Select at least one variant from inventory.');
      return;
    }
    if (bundleQty < 1) {
      _showErrorSnack('Number of bundles must be at least 1.');
      return;
    }

    final validationMessage = _getBundleStockValidationMessage(bundleQty);
    if (validationMessage != null) {
      _showErrorSnack(validationMessage);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final selectedVariants = <Map<String, dynamic>>[];
      for (final item in _inventory) {
        final itemId = item['id']?.toString() ?? '';
        final quantities = selectedVariantQuantities[itemId];
        if (quantities == null) continue;
        final variants = item['items'] as List<dynamic>? ?? [];
        for (final entry in quantities.entries) {
          final variantIndex = entry.key;
          final quantity = entry.value;
          if (variantIndex < 0 || variantIndex >= variants.length) continue;
          final variant = variants[variantIndex] as Map<String, dynamic>? ?? {};
          final totalQtyNeeded = quantity * bundleQty;
          final availableQty = _parseQuantity(
            variant['stock'] ?? variant['startingStock'],
          );
          if (totalQtyNeeded > availableQty) {
            _showErrorSnack(
              'Not enough \"${variant['name']}\" in inventory.\nNeed: $totalQtyNeeded, Available: $availableQty',
            );
            if (mounted) setState(() => _isSaving = false);
            return;
          }
          selectedVariants.add({
            'itemId': itemId,
            'variantIndex': variantIndex,
            'quantity': quantity,
          });
        }
      }

      final bundleId = _generateBundleId();
      final bundleImageUrl = await _uploadBundleImage();

      final updatedItemsByDoc = await _firestore
          .runTransaction<Map<String, List<dynamic>>>((transaction) async {
            final selectedItems = <Map<String, String>>[];
            final docsToUpdate = <String, List<dynamic>>{};
            final docRefs = <String, DocumentReference<Map<String, dynamic>>>{};
            final docNames = <String, String>{};

            for (final selected in selectedVariants) {
              final itemId = selected['itemId']?.toString() ?? '';
              final variantIndex = selected['variantIndex'] as int? ?? -1;
              final quantity = selected['quantity'] as int? ?? 0;
              final totalQtyNeeded = quantity * bundleQty;
              final docRef = _firestore
                  .collection('sales_inventory')
                  .doc(itemId);
              docRefs[itemId] = docRef;

              if (!docsToUpdate.containsKey(itemId)) {
                final docSnapshot = await transaction.get(docRef);
                final data = docSnapshot.data();

                if (data == null) {
                  throw Exception('Inventory item no longer exists.');
                }

                docsToUpdate[itemId] = List<dynamic>.from(
                  data['items'] as List? ?? [],
                );
                docNames[itemId] = data['name']?.toString() ?? '';
              }

              final items = docsToUpdate[itemId]!;
              if (variantIndex < 0 || variantIndex >= items.length) {
                throw Exception('Selected variant no longer exists.');
              }

              final variant = Map<String, dynamic>.from(
                items[variantIndex] as Map? ?? {},
              );
              final availableQty = _parseQuantity(
                variant['stock'] ?? variant['startingStock'],
              );

              if (totalQtyNeeded > availableQty) {
                throw Exception(
                  'Not enough "${variant['name'] ?? 'variant'}" in inventory. Need: $totalQtyNeeded, Available: $availableQty',
                );
              }

              final updatedStock = availableQty - totalQtyNeeded;
              variant['stock'] = updatedStock.toString();
              items[variantIndex] = variant;
              docsToUpdate[itemId] = items;

              selectedItems.add({
                'parentName': docNames[itemId] ?? '',
                'name': variant['name']?.toString() ?? '',
                'price': variant['price']?.toString() ?? '0',
                'quantity': quantity.toString(),
              });
            }

            final bundleInstances = List.generate(bundleQty, (index) {
              return {
                'number': index + 1,
                'id': _bundleInstanceId(bundleId, index),
                'status': 'available',
                'items': selectedItems.map((item) {
                  final quantity = _parseQuantity(item['quantity']);
                  return {
                    'name': item['name'] ?? 'Item',
                    'price': item['price'] ?? '0',
                    'quantity': quantity,
                    'remaining': quantity,
                  };
                }).toList(),
              };
            });

            for (final entry in docsToUpdate.entries) {
              final docRef = docRefs[entry.key];
              if (docRef != null) {
                transaction.update(docRef, {'items': entry.value});
              }
            }

            final bundleRef = _firestore.collection('sales_inventory').doc();
            transaction.set(bundleRef, {
              'name': name,
              'price': price.isEmpty ? '0' : price,
              'items': selectedItems,
              'bundleCount': bundleQty,
              'bundleId': bundleId,
              'bundleInstances': bundleInstances,
              'imageUrl': bundleImageUrl,
              'timestamp': Timestamp.now(),
              'isBundle': true,
            });

            return docsToUpdate;
          });

      if (!mounted) return;
      await _loadBundles();
      if (!mounted) return;
      setState(() {
        for (final entry in updatedItemsByDoc.entries) {
          final itemIndex = _inventory.indexWhere(
            (item) => item['id']?.toString() == entry.key,
          );
          if (itemIndex >= 0) {
            _inventory[itemIndex] = {
              ..._inventory[itemIndex],
              'items': entry.value,
            };
          }
        }
        selectedVariantQuantities.clear();
        bundleImageBytes = null;
      });
      bundleNameController.clear();
      bundlePriceController.clear();
      bundleQuantityController.text = '1';
      _switchTab(0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  bundleQty == 1
                      ? 'Bundle created successfully!'
                      : '$bundleQty bundles created successfully!',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
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
    } catch (e) {
      debugPrint('Bulk save error: $e');
      _showErrorSnack('Failed to create bundle: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showErrorSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: PinkTheme.deleteRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccessSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: PinkTheme.successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _confirmDeleteBundle(Map<String, dynamic> bundle) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: PinkTheme.deleteRed.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_rounded,
                  color: PinkTheme.deleteRed,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Remove Bundle?',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: PinkTheme.textDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This will remove "${bundle['name'] ?? 'bundle'}" from Bundles.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: PinkTheme.textMid,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: PinkTheme.textMid,
                        side: const BorderSide(
                          color: PinkTheme.divider,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PinkTheme.deleteRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Remove',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true && bundle['id'] != null) {
      try {
        await _firestore.collection('sales_inventory').doc(bundle['id']).update(
          {'isDeleted': true, 'deletedAt': Timestamp.now()},
        );
        await _markStaffInventoryDeleted(bundle['id'].toString());
        await _loadBundles();
        _showSuccessSnack('Bundle removed.');
      } catch (e) {
        debugPrint('Bundle delete error: $e');
        _showErrorSnack('Failed to remove bundle: $e');
      }
    }
  }

  void _showBundleInstancesDialog(Map<String, dynamic> bundle) {
    final bundleCount = bundle['bundleCount'] is int
        ? bundle['bundleCount'] as int
        : int.tryParse(bundle['bundleCount']?.toString() ?? '1') ?? 1;
    final bundleInstances = _bundleInstancesFromBundle(bundle);
    final bundleName = bundle['name']?.toString() ?? 'Bundle';
    final bundlePrice = bundle['price']?.toString() ?? '0';

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 620),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: PinkTheme.primary.withOpacity(0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        PinkTheme.primaryDark.withOpacity(0.94),
                        PinkTheme.accent.withOpacity(0.9),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.inventory_2_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bundleName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$bundleCount bundle${bundleCount == 1 ? '' : 's'} available',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: bundleInstances.isEmpty
                      ? const Center(
                          child: Text(
                            'No bundle stock available.',
                            style: TextStyle(
                              color: PinkTheme.textLight,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: bundleInstances.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final instance = bundleInstances[index];
                            final instanceItems =
                                instance['items'] as List<dynamic>? ?? [];
                            final status =
                                instance['status']?.toString() ?? 'available';
                            final statusLabel = status == 'inCategory'
                                ? 'In category'
                                : status == 'sold'
                                ? 'Sold'
                                : 'Available';
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: PinkTheme.badgeBg,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: PinkTheme.divider,
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Bundle #${instance['number'] ?? index + 1}',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w900,
                                                color: PinkTheme.textDark,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'Bundle ID: ${instance['id'] ?? _bundleInstanceId(bundle['bundleId']?.toString() ?? '', index)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: PinkTheme.textLight,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: PinkTheme.primary,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Text(
                                          '₱$bundlePrice',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Text(
                                          statusLabel,
                                          style: const TextStyle(
                                            color: PinkTheme.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (instanceItems.isEmpty)
                                    const Text(
                                      'No items in this bundle.',
                                      style: TextStyle(
                                        color: PinkTheme.textLight,
                                        fontSize: 12,
                                      ),
                                    )
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: instanceItems.map((item) {
                                        final itemMap =
                                            item is Map<String, dynamic>
                                            ? item
                                            : <String, dynamic>{};
                                        final itemName =
                                            itemMap['name']?.toString() ??
                                            'Item';
                                        final itemQty = _parseQuantity(
                                          itemMap['remaining'] ??
                                              itemMap['quantity'],
                                        );
                                        final originalQty = _parseQuantity(
                                          itemMap['quantity'],
                                        );
                                        final refundedQty = _parseQuantity(
                                          itemMap['refunded'],
                                        );
                                        final safeQty = _parseQuantity(
                                          itemMap['safeQuantity'] ??
                                              (originalQty - refundedQty),
                                        );
                                        final itemPrice =
                                            itemMap['price']?.toString() ?? '0';
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: PinkTheme.divider,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                itemName,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: PinkTheme.textDark,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                refundedQty > 0
                                                    ? 'safe $safeQty · refund $refundedQty'
                                                    : '$itemQty/$originalQty',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                  color: PinkTheme.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '₱$itemPrice',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: PinkTheme.textLight,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedVariantCount;
    return Scaffold(
      backgroundColor: PinkTheme.scaffoldBg,
      body: Column(
        children: [
          // ── ANIMATED GRADIENT HEADER ─────────────────────────────────────────
          SlideTransition(
            position: _headerSlide,
            child: FadeTransition(
              opacity: _headerFade,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [PinkTheme.primaryDark, PinkTheme.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 22,
                      color: Color(0x40E75480),
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 20, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bulk Bundle',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  Text(
                                    'Group inventory items into bundles',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selectedCount > 0) ...[
                              AnimatedScale(
                                scale: 1.0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.elasticOut,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.22),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.layers_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$selectedCount selected',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Material(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap: () async {
                                  final restored = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const RemovedInventoryPage(),
                                    ),
                                  );
                                  if (restored == true && mounted) {
                                    await _loadBundles();
                                  }
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_selectedTabIndex == 1)
                          const SizedBox(height: 18),
                        // ── TAB SWITCHER ─────────────────────────────────────
                        if (_selectedTabIndex == 1)
                          Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            children: [
                              _buildHeaderTab(
                                label: 'Bundles',
                                icon: Icons.inventory_2_rounded,
                                index: 0,
                              ),
                              _buildHeaderTab(
                                label: 'Build Bundle',
                                icon: Icons.add_box_rounded,
                                index: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── ANIMATED BODY ────────────────────────────────────────────────────
          Expanded(
            child: FadeTransition(
              opacity: _bodyFade,
              child: _selectedTabIndex == 0
                  ? Stack(
                      children: [
                        _buildBundlesTab(),
                        Positioned(
                          right: 20,
                          bottom: 24,
                          child: FloatingActionButton(
                            heroTag: 'bulk_bundle_add',
                            backgroundColor: PinkTheme.primary,
                            foregroundColor: Colors.white,
                            onPressed: () => _switchTab(1),
                            child: const Icon(Icons.add_rounded, size: 32),
                          ),
                        ),
                      ],
                    )
                  : _buildBuildTab(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderTab({
    required String label,
    required IconData icon,
    required int index,
  }) {
    final isActive = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchTab(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      blurRadius: 12,
                      color: PinkTheme.primary.withOpacity(0.18),
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? PinkTheme.primary : Colors.white70,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isActive ? PinkTheme.primary : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── BUNDLES TAB ────────────────────────────────────────────────────────────
  Widget _buildBundlesTab() {
    if (bundles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [PinkTheme.badgeBg, Color(0xFFFDE0EC)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                size: 52,
                color: PinkTheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Bundles Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: PinkTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Switch to Build Bundle\nto create your first bundle.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: PinkTheme.textLight,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () => _switchTab(1),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [PinkTheme.primary, PinkTheme.accent],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: PinkTheme.primary.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Text(
                  'Create Bundle',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      itemCount: bundles.length,
      itemBuilder: (context, index) {
        final bundle = bundles[index];
        final bundleItems = bundle['items'] as List<dynamic>? ?? [];
        final itemCount = bundleItems.length;
        final bundleCount = bundle['bundleCount'] is int
            ? bundle['bundleCount'] as int
            : int.tryParse(bundle['bundleCount']?.toString() ?? '1') ?? 1;
        final bundleId =
            bundle['bundleId']?.toString() ?? bundle['id']?.toString() ?? '';
        return _FadeSlideIn(
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: PinkTheme.primary.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Banner header
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          PinkTheme.primaryDark.withOpacity(0.92),
                          PinkTheme.accent.withOpacity(0.88),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.inventory_2_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bundle['name']?.toString() ?? '',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$itemCount item${itemCount == 1 ? '' : 's'} in bundle',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                              if (bundleId.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Bundle ID: $bundleId',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (bundleCount > 1) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  'x$bundleCount',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '₱${bundle['price']?.toString() ?? '0'}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () => _confirmDeleteBundle(bundle),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _bundleImagePreview(bundle['imageUrl']?.toString()),
                  // Items chips
                  if (itemCount > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: bundleItems.map((e) {
                          final name = e['name']?.toString() ?? '';
                          final qty = e['quantity']?.toString() ?? '1';
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: PinkTheme.badgeBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: PinkTheme.divider),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: PinkTheme.textDark,
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: PinkTheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'x$qty',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No items in this bundle.',
                        style: TextStyle(
                          color: PinkTheme.textLight,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _showBundleInstancesDialog(bundle),
                        icon: const Icon(Icons.visibility_rounded, size: 17),
                        label: const Text('View all item'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PinkTheme.primary,
                          side: const BorderSide(
                            color: PinkTheme.divider,
                            width: 1.4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── BUILD BUNDLE TAB ───────────────────────────────────────────────────────
  Widget _buildBuildTab() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info hint card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        PinkTheme.primaryLight.withOpacity(0.28),
                        PinkTheme.badgeBg,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: PinkTheme.divider),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: PinkTheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.lightbulb_rounded,
                          color: PinkTheme.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Pick variants from your inventory below, set quantities, then tap Create Bundle.',
                          style: TextStyle(
                            fontSize: 12,
                            color: PinkTheme.textMid,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Bundle name
                _styledFieldLabel('Bundle Name'),
                const SizedBox(height: 8),
                _enhancedField(
                  controller: bundleNameController,
                  hint: 'e.g., Cupcakes set, Cakes set...',
                  icon: Icons.inventory_2_rounded,
                ),
                const SizedBox(height: 14),

                _styledFieldLabel('Bundle Picture'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PinkTheme.inputFill,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: PinkTheme.inputBorder),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 58,
                          height: 58,
                          color: PinkTheme.badgeBg,
                          child: bundleImageBytes == null
                              ? const Icon(
                                  Icons.image_rounded,
                                  color: PinkTheme.primary,
                                  size: 26,
                                )
                              : Image.memory(
                                  bundleImageBytes!,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          bundleImageBytes == null
                              ? 'Add picture for this bundle'
                              : 'Picture selected',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: PinkTheme.textMid,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _pickBundleImage,
                        icon: const Icon(Icons.photo_library_rounded),
                        color: PinkTheme.primary,
                      ),
                      if (bundleImageBytes != null)
                        IconButton(
                          onPressed: () =>
                              setState(() => bundleImageBytes = null),
                          icon: const Icon(Icons.close_rounded),
                          color: PinkTheme.deleteRed,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Bundle price
                _styledFieldLabel('Bundle Price'),
                const SizedBox(height: 8),
                _enhancedField(
                  controller: bundlePriceController,
                  hint: '0.00',
                  icon: Icons.payments_rounded,
                  keyboardType: TextInputType.number,
                  prefixText: '₱',
                ),
                const SizedBox(height: 14),

                // Number of bundles to create
                _styledFieldLabel('Number of Bundles'),
                const SizedBox(height: 8),
                _enhancedField(
                  controller: bundleQuantityController,
                  hint: '1',
                  icon: Icons.copy_rounded,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final bundleQty =
                        int.tryParse(bundleQuantityController.text.trim()) ?? 1;
                    final validationMessage = _getBundleStockValidationMessage(
                      bundleQty,
                    );
                    return validationMessage != null
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Text(
                              validationMessage,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.red,
                              ),
                            ),
                          )
                        : const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: 14),

                // Divider with label
                Row(
                  children: [
                    const Expanded(
                      child: Divider(color: PinkTheme.divider, thickness: 1.5),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: PinkTheme.badgeBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Select Variants',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: PinkTheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Divider(color: PinkTheme.divider, thickness: 1.5),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_inventory.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: PinkTheme.divider),
                    ),
                    child: const Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_rounded,
                            size: 40,
                            color: PinkTheme.textLight,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No inventory items available.',
                            style: TextStyle(
                              color: PinkTheme.textMid,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._inventory.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    final itemId = item['id']?.toString() ?? '';
                    final itemName = item['name']?.toString() ?? '';
                    final itemPrice = item['price']?.toString() ?? '0';
                    final variants = item['items'] as List<dynamic>? ?? [];
                    final selectedQuantities =
                        selectedVariantQuantities[itemId] ?? <int, int>{};
                    final totalSel = selectedQuantities.values.fold(
                      0,
                      (sum, q) => sum + q,
                    );
                    final bundleQty =
                        int.tryParse(bundleQuantityController.text.trim()) ?? 1;
                    final totalSelectedCount = totalSel * bundleQty;

                    return _FadeSlideIn(
                      index: idx,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: PinkTheme.primary.withOpacity(0.07),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Item header
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  10,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            PinkTheme.primaryLight,
                                            PinkTheme.accent,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.category_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            itemName,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: PinkTheme.textDark,
                                            ),
                                          ),
                                          Text(
                                            itemPrice != '0' &&
                                                    itemPrice.isNotEmpty
                                                ? '₱$itemPrice  •  ${variants.length} variant${variants.length == 1 ? '' : 's'}'
                                                : '${variants.length} variant${variants.length == 1 ? '' : 's'}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: PinkTheme.textLight,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 240,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: totalSelectedCount > 0
                                            ? PinkTheme.primary
                                            : PinkTheme.badgeBg,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Text(
                                        totalSelectedCount > 0
                                            ? '$totalSelectedCount selected'
                                            : 'None',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: totalSelectedCount > 0
                                              ? Colors.white
                                              : PinkTheme.textLight,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                height: 1,
                                color: PinkTheme.divider,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  16,
                                  14,
                                ),
                                child: Column(
                                  children: variants.asMap().entries.map((
                                    vEntry,
                                  ) {
                                    final variantIndex = vEntry.key;
                                    final variant =
                                        vEntry.value as Map<String, dynamic>? ??
                                        {};
                                    final variantName =
                                        variant['name']?.toString() ?? '';
                                    final variantPrice =
                                        variant['price']?.toString() ?? '0';
                                    final quantity =
                                        selectedQuantities[variantIndex] ?? 0;
                                    final bundleQty =
                                        int.tryParse(
                                          bundleQuantityController.text.trim(),
                                        ) ??
                                        1;
                                    final variantStock = _parseQuantity(
                                      variant['stock'] ??
                                          variant['startingStock'],
                                    );
                                    final totalNeeded = quantity * bundleQty;
                                    var remainingStock =
                                        variantStock - totalNeeded;
                                    if (remainingStock < 0) remainingStock = 0;
                                    final isSelected = quantity > 0;

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? PinkTheme.primaryLight
                                                    .withOpacity(0.14)
                                              : PinkTheme.inputFill,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? PinkTheme.primary
                                                : PinkTheme.inputBorder,
                                            width: isSelected ? 1.5 : 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    variantName,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: PinkTheme.textDark,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Item ID: ${variant['id']?.toString().isNotEmpty == true ? variant['id']?.toString() : 'N/A'}',
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color:
                                                          PinkTheme.textLight,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '₱$variantPrice',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: PinkTheme.primary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Stock: $variantStock pcs',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: PinkTheme.textMid,
                                                    ),
                                                  ),
                                                  if (quantity > 0) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      'Remaining: $remainingStock pcs',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            remainingStock > 0
                                                            ? PinkTheme.textDark
                                                            : PinkTheme
                                                                  .deleteRed,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            // Quantity controls
                                            Row(
                                              children: [
                                                InkWell(
                                                  onTap: quantity > 0
                                                      ? () => _decrementVariant(
                                                          itemId,
                                                          variantIndex,
                                                        )
                                                      : null,
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  child: Container(
                                                    width: 34,
                                                    height: 34,
                                                    decoration: BoxDecoration(
                                                      color: quantity > 0
                                                          ? PinkTheme.primary
                                                                .withOpacity(
                                                                  0.12,
                                                                )
                                                          : PinkTheme
                                                                .inputBorder,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Icon(
                                                      Icons.remove_rounded,
                                                      color: quantity > 0
                                                          ? PinkTheme.primary
                                                          : PinkTheme.textLight,
                                                      size: 18,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                SizedBox(
                                                  width: 76,
                                                  child: TextFormField(
                                                    key: ValueKey(
                                                      '$itemId-$variantIndex-$quantity',
                                                    ),
                                                    initialValue: quantity
                                                        .toString(),
                                                    keyboardType:
                                                        TextInputType.number,
                                                    textAlign: TextAlign.center,
                                                    decoration: InputDecoration(
                                                      contentPadding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 10,
                                                            horizontal: 8,
                                                          ),
                                                      border: OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                        borderSide: BorderSide(
                                                          color:
                                                              PinkTheme.divider,
                                                        ),
                                                      ),
                                                      enabledBorder:
                                                          OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                            borderSide:
                                                                BorderSide(
                                                                  color: PinkTheme
                                                                      .divider,
                                                                  width: 1.2,
                                                                ),
                                                          ),
                                                    ),
                                                    onChanged: (value) {
                                                      final newQty =
                                                          int.tryParse(value) ??
                                                          0;
                                                      _setVariantQuantity(
                                                        itemId,
                                                        variantIndex,
                                                        newQty,
                                                      );
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                InkWell(
                                                  onTap: () =>
                                                      _incrementVariant(
                                                        itemId,
                                                        variantIndex,
                                                      ),
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  child: Container(
                                                    width: 34,
                                                    height: 34,
                                                    decoration: BoxDecoration(
                                                      color: PinkTheme.primary
                                                          .withOpacity(0.18),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: const Icon(
                                                      Icons.add_rounded,
                                                      color: PinkTheme.primary,
                                                      size: 18,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // ── BOTTOM SAVE PANEL ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: [
              BoxShadow(
                color: PinkTheme.primary.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                child: _selectedVariantCount > 0
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: PinkTheme.badgeBg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.layers_rounded,
                                size: 16,
                                color: PinkTheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$_selectedVariantCount variant${_selectedVariantCount == 1 ? '' : 's'} selected',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: PinkTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveBulkBundle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PinkTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 6,
                    shadowColor: PinkTheme.primary.withOpacity(0.4),
                  ),
                  child: _isSaving
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.4,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Creating...',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_shopping_cart_rounded, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Create Bundle',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _styledFieldLabel(String label) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: PinkTheme.primary,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: PinkTheme.textDark,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _enhancedField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? prefixText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: PinkTheme.textDark,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: PinkTheme.textLight, fontSize: 13),
        prefixText: prefixText,
        prefixStyle: const TextStyle(
          color: PinkTheme.primary,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(icon, color: PinkTheme.primaryLight, size: 20),
        filled: true,
        fillColor: PinkTheme.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PinkTheme.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: PinkTheme.inputBorder,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PinkTheme.inputFocused, width: 2),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  REMOVED INVENTORY PAGE  ──  FULLY ENHANCED UI + ANIMATIONS
// ═══════════════════════════════════════════════════════════════════════════════

class RemovedInventoryPage extends StatefulWidget {
  const RemovedInventoryPage({super.key});

  @override
  State<RemovedInventoryPage> createState() => _RemovedInventoryPageState();
}

class _RemovedInventoryPageState extends State<RemovedInventoryPage>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  bool _hasRestored = false;
  final List<Map<String, dynamic>> _removedCategories = [];
  final List<Map<String, dynamic>> _removedVariants = [];
  final List<Map<String, dynamic>> _removedBundles = [];
  int _activeSection = 0; // 0 = categories, 1 = items, 2 = bundles

  late AnimationController _headerAnim;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late AnimationController _sectionAnim;
  late Animation<double> _sectionFade;

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _headerFade = CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _headerAnim, curve: Curves.easeOutCubic));

    _sectionAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _sectionFade = CurvedAnimation(parent: _sectionAnim, curve: Curves.easeIn);

    _headerAnim.forward();
    _sectionAnim.forward();
    _loadRemovedInventory();
  }

  @override
  void dispose() {
    _headerAnim.dispose();
    _sectionAnim.dispose();
    super.dispose();
  }

  void _switchSection(int index) {
    _sectionAnim.reverse().then((_) {
      setState(() => _activeSection = index);
      _sectionAnim.forward();
    });
  }

  Future<void> _loadRemovedInventory() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(days: 30));
      final snapshot = await _firestore.collection('sales_inventory').get();
      _removedCategories.clear();
      _removedVariants.clear();
      _removedBundles.clear();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final isDeleted = data['isDeleted'] == true;
        final deletedAt = data['deletedAt'] as Timestamp?;
        final currentItems =
            (data['items'] as List<dynamic>?)?.cast<dynamic>() ?? [];
        final removedItems =
            (data['removedItems'] as List<dynamic>?)?.cast<dynamic>() ?? [];

        final freshRemovedItems = <Map<String, dynamic>>[];
        for (final rawItem in removedItems) {
          if (rawItem is! Map) continue;
          final entry = Map<String, dynamic>.from(rawItem);
          final removedAt = entry['removedAt'] as Timestamp?;
          if (removedAt != null && removedAt.toDate().isBefore(cutoff))
            continue;
          freshRemovedItems.add(entry);
          if (!isDeleted) {
            _removedVariants.add({
              'parentId': doc.id,
              'parentName': data['name'] ?? '',
              'raw': entry,
              'name': entry['name'] ?? '',
              'price': entry['price'] ?? '0',
              'startingStock': entry['startingStock'] ?? '0',
              'expirationDate': entry['expirationDate'] ?? '',
              'removedAt': entry['removedAt'] as Timestamp?,
            });
          }
        }
        if (freshRemovedItems.length != removedItems.length) {
          await doc.reference.update({'removedItems': freshRemovedItems});
        }
        if (isDeleted) {
          if (deletedAt != null && deletedAt.toDate().isBefore(cutoff)) {
            await doc.reference.delete();
            continue;
          }
          if (data['isBundle'] == true) {
            _removedBundles.add({
              'id': doc.id,
              'name': data['name'] ?? '',
              'bundleId': data['bundleId'] ?? '',
              'bundleCount': data['bundleCount'] ?? 1,
              'deletedAt': deletedAt,
              'items': currentItems,
            });
          } else {
            _removedCategories.add({
              'id': doc.id,
              'name': data['name'] ?? '',
              'deletedAt': deletedAt,
              'items': currentItems,
              'removedItems': freshRemovedItems,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading removed inventory: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load removed inventory: $e'),
            backgroundColor: PinkTheme.deleteRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreCategory(Map<String, dynamic> category) async {
    try {
      final docRef = _firestore
          .collection('sales_inventory')
          .doc(category['id']);
      final doc = await docRef.get();
      if (!doc.exists) {
        _showSnack('Category no longer exists.', error: true);
        return;
      }
      final data = doc.data() ?? {};
      final currentItems =
          (data['items'] as List<dynamic>?)?.cast<dynamic>() ?? [];
      final removedItems =
          (data['removedItems'] as List<dynamic>?)?.cast<dynamic>() ?? [];
      final updateData = <String, dynamic>{
        'isDeleted': false,
        'deletedAt': FieldValue.delete(),
      };
      if (currentItems.isEmpty && removedItems.isNotEmpty) {
        updateData['items'] = removedItems
            .map(
              (item) => {
                'name': item['name'] ?? '',
                'price': item['price'] ?? '0',
                'startingStock': item['startingStock'] ?? '0',
                'expirationDate': item['expirationDate'] ?? '',
              },
            )
            .toList();
        updateData['removedItems'] = [];
      }
      await docRef.update(updateData);
      _showSnack('Category restored successfully.');
      setState(() => _hasRestored = true);
      await _loadRemovedInventory();
    } catch (e) {
      debugPrint('Restore category error: $e');
      _showSnack('Failed to restore category: $e', error: true);
    }
  }

  Future<void> _restoreBundle(Map<String, dynamic> bundle) async {
    try {
      final docRef = _firestore.collection('sales_inventory').doc(bundle['id']);
      final doc = await docRef.get();
      if (!doc.exists) {
        _showSnack('Bundle no longer exists.', error: true);
        return;
      }
      await docRef.update({
        'isDeleted': false,
        'deletedAt': FieldValue.delete(),
      });
      _showSnack('Bundle restored successfully.');
      setState(() => _hasRestored = true);
      await _loadRemovedInventory();
    } catch (e) {
      debugPrint('Restore bundle error: $e');
      _showSnack('Failed to restore bundle: $e', error: true);
    }
  }

  Future<void> _restoreVariant(Map<String, dynamic> variant) async {
    try {
      final docRef = _firestore
          .collection('sales_inventory')
          .doc(variant['parentId']);
      final doc = await docRef.get();
      if (!doc.exists) {
        _showSnack('Inventory category not found.', error: true);
        return;
      }
      final raw = variant['raw'] as Map<String, dynamic>;
      await docRef.update({
        'items': FieldValue.arrayUnion([
          {
            'name': raw['name'] ?? '',
            'price': raw['price'] ?? '0',
            'startingStock': raw['startingStock'] ?? '0',
            'expirationDate': raw['expirationDate'] ?? '',
          },
        ]),
        'removedItems': FieldValue.arrayRemove([raw]),
      });
      _showSnack('Item restored successfully.');
      setState(() => _hasRestored = true);
      await _loadRemovedInventory();
    } catch (e) {
      debugPrint('Restore variant error: $e');
      _showSnack('Failed to restore item: $e', error: true);
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_rounded : Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: error ? PinkTheme.deleteRed : PinkTheme.successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '--';
    final date = timestamp.toDate();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final totalRemoved =
        _removedCategories.length +
        _removedVariants.length +
        _removedBundles.length;
    return Scaffold(
      backgroundColor: PinkTheme.scaffoldBg,
      body: Column(
        children: [
          // ── ANIMATED HEADER ──────────────────────────────────────────────────
          SlideTransition(
            position: _headerSlide,
            child: FadeTransition(
              opacity: _headerFade,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [PinkTheme.primaryDark, PinkTheme.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 22,
                      color: Color(0x40E75480),
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 20, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Material(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap: () =>
                                    Navigator.pop(context, _hasRestored),
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
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Removed Inventory',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  Text(
                                    'Items removed within 30 days',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.delete_sweep_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$totalRemoved removed',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        // ── Section Pill Tabs ─────────────────────────────────
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            children: [
                              _sectionPill(
                                label: 'Categories',
                                count: _removedCategories.length,
                                index: 0,
                              ),
                              _sectionPill(
                                label: 'Items',
                                count: _removedVariants.length,
                                index: 1,
                              ),
                              _sectionPill(
                                label: 'Bundles',
                                count: _removedBundles.length,
                                index: 2,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── BODY ─────────────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(PinkTheme.primary),
                          strokeWidth: 3,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Loading removed items...',
                          style: TextStyle(
                            color: PinkTheme.textMid,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadRemovedInventory,
                    color: PinkTheme.primary,
                    child: FadeTransition(
                      opacity: _sectionFade,
                      child: _activeSection == 0
                          ? _buildCategoriesSection()
                          : _activeSection == 1
                          ? _buildVariantsSection()
                          : _buildBundlesSection(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionPill({
    required String label,
    required int count,
    required int index,
  }) {
    final isActive = _activeSection == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchSection(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      blurRadius: 12,
                      color: PinkTheme.primary.withOpacity(0.18),
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isActive ? PinkTheme.primary : Colors.white70,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? PinkTheme.primary
                      : Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isActive ? Colors.white : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── CATEGORIES SECTION ─────────────────────────────────────────────────────
  Widget _buildCategoriesSection() {
    if (_removedCategories.isEmpty) {
      return _emptySection(
        icon: Icons.folder_off_rounded,
        subtitle: 'Deleted product categories will appear here for 30 days.',
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      itemCount: _removedCategories.length,
      itemBuilder: (context, index) {
        final category = _removedCategories[index];
        final deletedAt = category['deletedAt'] as Timestamp?;
        final daysLabel = _daysLeftLabel(deletedAt);
        final urgent = _isUrgent(daysLabel);

        return _FadeSlideIn(
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: PinkTheme.primary.withOpacity(0.07),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                    decoration: BoxDecoration(
                      color: PinkTheme.deleteRed.withOpacity(0.06),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22),
                      ),
                      border: const Border(
                        bottom: BorderSide(color: PinkTheme.divider, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color:
                                (category['type'] == 'bundle'
                                        ? PinkTheme.primary
                                        : PinkTheme.deleteRed)
                                    .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            category['type'] == 'bundle'
                                ? Icons.inventory_2_rounded
                                : Icons.folder_rounded,
                            color: category['type'] == 'bundle'
                                ? PinkTheme.primary
                                : PinkTheme.deleteRed,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category['name'] ?? '',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: PinkTheme.textDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Removed on ${_formatTimestamp(deletedAt)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: PinkTheme.textLight,
                                ),
                              ),
                              if (category['type'] == 'bundle') ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Removed bulk bundle. Restore to recover it.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: PinkTheme.textLight,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (daysLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: urgent
                                  ? PinkTheme.deleteRed.withOpacity(0.12)
                                  : PinkTheme.badgeBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              daysLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: urgent
                                    ? PinkTheme.deleteRed
                                    : PinkTheme.textMid,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: PinkTheme.textLight,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Restoring this category will also restore all its items.',
                            style: TextStyle(
                              fontSize: 12,
                              color: PinkTheme.textLight,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => _restoreCategory(category),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [PinkTheme.primary, PinkTheme.accent],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: PinkTheme.primary.withOpacity(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.restore_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Restore',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBundlesSection() {
    if (_removedBundles.isEmpty) {
      return _emptySection(
        icon: Icons.inventory_2_rounded,
        subtitle: 'Removed bulk bundles will appear here for 30 days.',
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      itemCount: _removedBundles.length,
      itemBuilder: (context, index) {
        final bundle = _removedBundles[index];
        final bundleCount = bundle['bundleCount'] is int
            ? bundle['bundleCount'] as int
            : int.tryParse(bundle['bundleCount']?.toString() ?? '1') ?? 1;
        final bundleId = bundle['bundleId']?.toString() ?? '';
        final items = bundle['items'] as List<dynamic>? ?? [];
        final deletedAt = bundle['deletedAt'] as Timestamp?;
        final daysLabel = _daysLeftLabel(deletedAt);
        final urgent = _isUrgent(daysLabel);

        return _FadeSlideIn(
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: PinkTheme.primary.withOpacity(0.07),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                    decoration: BoxDecoration(
                      color: PinkTheme.primary.withOpacity(0.08),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22),
                      ),
                      border: const Border(
                        bottom: BorderSide(color: PinkTheme.divider, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: PinkTheme.primary.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.inventory_2_rounded,
                            color: PinkTheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bundle['name'] ?? '',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: PinkTheme.textDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                bundleId.isNotEmpty
                                    ? 'Bundle ID: $bundleId'
                                    : 'Removed bulk bundle',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: PinkTheme.textLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (bundleCount > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: PinkTheme.primary.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              'x$bundleCount',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: PinkTheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          size: 14,
                          color: PinkTheme.textLight,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Removed on ${_formatTimestamp(deletedAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: PinkTheme.textLight,
                            ),
                          ),
                        ),
                        if (daysLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: urgent
                                  ? PinkTheme.deleteRed.withOpacity(0.12)
                                  : PinkTheme.badgeBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              daysLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: urgent
                                    ? PinkTheme.deleteRed
                                    : PinkTheme.textMid,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: items.map((item) {
                          final name = item['name']?.toString() ?? '';
                          final qty = item['quantity']?.toString() ?? '1';
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: PinkTheme.badgeBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: PinkTheme.divider),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: PinkTheme.textDark,
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: PinkTheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'x$qty',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 0, 18, 16),
                      child: Text(
                        'This bundle has no associated items.',
                        style: TextStyle(
                          color: PinkTheme.textLight,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                    child: Row(
                      children: [
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _restoreBundle(bundle),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [PinkTheme.primary, PinkTheme.accent],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: PinkTheme.primary.withOpacity(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.restore_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Restore',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVariantsSection() {
    if (_removedVariants.isEmpty) {
      return _emptySection(
        icon: Icons.remove_shopping_cart_rounded,
        subtitle: 'Individually removed product variants will appear here.',
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      itemCount: _removedVariants.length,
      itemBuilder: (context, index) {
        final variant = _removedVariants[index];
        final removedAt = variant['removedAt'] as Timestamp?;
        final daysLabel = _daysLeftLabel(removedAt);
        final urgent = _isUrgent(daysLabel);

        return _FadeSlideIn(
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: PinkTheme.primary.withOpacity(0.07),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                    decoration: BoxDecoration(
                      color: PinkTheme.badgeBg.withOpacity(0.5),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22),
                      ),
                      border: const Border(
                        bottom: BorderSide(color: PinkTheme.divider, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                PinkTheme.primaryLight,
                                PinkTheme.primary,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.label_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                variant['name'] ?? '',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: PinkTheme.textDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.folder_open_rounded,
                                    size: 12,
                                    color: PinkTheme.textLight,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    variant['parentName'] ?? '--',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: PinkTheme.textLight,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (daysLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: urgent
                                  ? PinkTheme.deleteRed.withOpacity(0.12)
                                  : PinkTheme.badgeBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              daysLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: urgent
                                    ? PinkTheme.deleteRed
                                    : PinkTheme.textMid,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                    child: Row(
                      children: [
                        _infoChip(
                          icon: Icons.payments_rounded,
                          label: '₱${variant['price'] ?? '0'}',
                        ),
                        const SizedBox(width: 8),
                        _infoChip(
                          icon: Icons.inventory_2_rounded,
                          label: '${variant['startingStock'] ?? '0'} pcs',
                        ),
                        const SizedBox(width: 8),
                        _infoChip(
                          icon: Icons.calendar_today_rounded,
                          label: variant['expirationDate']?.isNotEmpty == true
                              ? variant['expirationDate']
                              : '--',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          size: 14,
                          color: PinkTheme.textLight,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Removed on ${_formatTimestamp(removedAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: PinkTheme.textLight,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _restoreVariant(variant),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [PinkTheme.primary, PinkTheme.accent],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: PinkTheme.primary.withOpacity(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.restore_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Restore',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: PinkTheme.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PinkTheme.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: PinkTheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: PinkTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptySection({required IconData icon, required String subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [PinkTheme.badgeBg, Color(0xFFFDE0EC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 60, color: PinkTheme.primary),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Items Yet',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: PinkTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: PinkTheme.textLight,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  String _daysLeftLabel(Timestamp? ts) {
    if (ts == null) return '';
    final expiry = ts.toDate().add(const Duration(days: 30));
    final diff = expiry.difference(DateTime.now()).inDays;
    if (diff <= 0) return 'Expires today';
    return '$diff day${diff == 1 ? '' : 's'} left';
  }

  bool _isUrgent(String label) =>
      label.contains('today') ||
      label.startsWith('1 ') ||
      label.startsWith('2 ') ||
      label.startsWith('3 ');
}
