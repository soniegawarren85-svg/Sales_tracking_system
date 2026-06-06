import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

// ─── Color Palette ──────────────────────────────────────────────────────────
const _primary = Color(0xFFE91E63);
const _primaryDeep = Color(0xFFC2105C);
const _primaryLight = Color(0xFFF48FB1);
const _bg = Color(0xFFFFF8F3);
const _border = Color(0xFFF8BBD0);
const _cardBg = Color(0xFFFFFFFF);

// ─── Entry Point ────────────────────────────────────────────────────────────
class CoffeeMenuPage extends StatefulWidget {
  const CoffeeMenuPage({super.key});

  @override
  State<CoffeeMenuPage> createState() => _CoffeeMenuPageState();
}

class _CoffeeMenuPageState extends State<CoffeeMenuPage>
    with TickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _descriptionController = TextEditingController();
  final _flavorNameController = TextEditingController();
  final _flavorPriceController = TextEditingController();
  final _addonNameController = TextEditingController();
  final _addonPriceController = TextEditingController();

  final _sizes = <_OptionDraft>[];
  final _imagePicker = ImagePicker();
  Uint8List? _coffeeImageBytes;
  bool _savingProduct = false;

  // Animation controllers
  late final AnimationController _formFadeCtrl;
  late final Animation<double> _formFade;
  late final Animation<Offset> _formSlide;

  @override
  void initState() {
    super.initState();
    _sizes.addAll([
      _OptionDraft(name: 'Small', priceDelta: '0'),
      _OptionDraft(name: 'Medium', priceDelta: '20'),
      _OptionDraft(name: 'Large', priceDelta: '40'),
    ]);

    _formFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _formFade = CurvedAnimation(parent: _formFadeCtrl, curve: Curves.easeOut);
    _formSlide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _formFadeCtrl, curve: Curves.easeOut));

    _formFadeCtrl.forward();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _flavorNameController.dispose();
    _flavorPriceController.dispose();
    _addonNameController.dispose();
    _addonPriceController.dispose();
    for (final s in _sizes) {
      s.dispose();
    }
    _formFadeCtrl.dispose();
    super.dispose();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  double _parsePrice(String value) =>
      double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: isError
            ? const Color(0xFFD32F2F)
            : const Color(0xFF2E7D32),
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
    prefixIcon: Icon(icon, color: _primary, size: 20),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.red, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.red, width: 2),
    ),
  );

  Widget _sectionHeader(String label, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_primary, _primaryDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 17),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: _primaryDeep,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
      ],
    ),
  );

  void _resetSizes() {
    for (final size in _sizes) {
      size.dispose();
    }
    _sizes
      ..clear()
      ..addAll([
        _OptionDraft(name: 'Small', priceDelta: '0'),
        _OptionDraft(name: 'Medium', priceDelta: '20'),
        _OptionDraft(name: 'Large', priceDelta: '40'),
      ]);
  }

  Future<void> _pickCoffeeImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 900,
      maxHeight: 900,
      imageQuality: 75,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _coffeeImageBytes = bytes);
  }

  Future<String?> _uploadCoffeeImage(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imageRef = FirebaseStorage.instance.ref().child(
        'coffee_images/$timestamp.jpg',
      );
      final upload = await imageRef
          .putData(bytes, SettableMetadata(contentType: 'image/jpeg'))
          .timeout(const Duration(seconds: 90));
      return upload.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Coffee image upload failed, using local data URL: $e');
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }
  }

  // ─── Save Global Option ────────────────────────────────────────────────────

  Future<void> _saveGlobalOption({
    required String collection,
    required TextEditingController nameController,
    required TextEditingController priceController,
  }) async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Enter option name', isError: true);
      return;
    }
    final price = _parsePrice(priceController.text);
    await _firestore.collection(collection).add({
      'name': name,
      'priceDelta': price,
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    nameController.clear();
    priceController.clear();
    _showSnack('Saved!');
  }

  // ─── Save Product ──────────────────────────────────────────────────────────

  Future<void> _saveProduct() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final sizes = _sizes
        .map(
          (s) => {
            'name': s.nameController.text.trim(),
            'priceDelta': _parsePrice(s.priceController.text),
          },
        )
        .where((s) => s['name']?.toString().isNotEmpty == true)
        .toList();

    if (sizes.isEmpty) {
      _showSnack('Add at least one size', isError: true);
      return;
    }

    setState(() => _savingProduct = true);
    try {
      final imageUrl = await _uploadCoffeeImage(_coffeeImageBytes).timeout(
        const Duration(seconds: 18),
        onTimeout: () => _coffeeImageBytes == null
            ? null
            : 'data:image/jpeg;base64,${base64Encode(_coffeeImageBytes!)}',
      );
      final coffeeId = await _firestore.runTransaction<String>((
        transaction,
      ) async {
        final counterRef = _firestore
            .collection('system_counters')
            .doc('coffee_products');
        final productRef = _firestore.collection('coffee_products').doc();
        final counterSnap = await transaction.get(counterRef);
        final current = (counterSnap.data()?['current'] as num?)?.toInt() ?? 0;
        final next = current + 1;
        final now = DateTime.now();
        final coffeeId =
            '${now.year}${now.month}${now.day}-${next.toString().padLeft(3, '0')}';

        transaction.set(counterRef, {
          'current': next,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(productRef, {
          'coffeeId': coffeeId,
          'coffeeIdNumber': next,
          'name': _flavorNameController.text.trim(),
          'basePrice': _parsePrice(_flavorPriceController.text),
          'description': _descriptionController.text.trim(),
          'imageUrl': imageUrl ?? '',
          'sizes': sizes,
          'flavorIds': <String>[],
          'addonIds': <String>[],
          'isCoffee': true,
          'isDeleted': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return coffeeId;
      });
      setState(() {
        _flavorNameController.clear();
        _flavorPriceController.clear();
        _descriptionController.clear();
        _coffeeImageBytes = null;
        _resetSizes();
      });
      _showSnack('Coffee product saved! ID: $coffeeId');
    } catch (e) {
      _showSnack('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingProduct = false);
    }
  }

  // ─── Widgets ──────────────────────────────────────────────────────────────

  Widget _buildProductForm() {
    return _Panel(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primary, _primaryDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: const [
                  Icon(Icons.coffee_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Create Coffee Flavor',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Section 1: Flavor Info ──────────────────────────────────────
            _sectionHeader('Flavor Info', Icons.spa_rounded),
            const SizedBox(height: 10),
            TextFormField(
              controller: _flavorNameController,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
              decoration: _inputDeco('Flavor Name', Icons.label_rounded),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _flavorPriceController,
              validator: (v) =>
                  _parsePrice(v ?? '') <= 0 ? 'Enter a valid price' : null,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _inputDeco(
                'Flavor Price (PHP)',
                Icons.payments_rounded,
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: _inputDeco('Description', Icons.notes_rounded),
            ),
            const SizedBox(height: 14),
            _CoffeeImagePicker(
              imageBytes: _coffeeImageBytes,
              imageUrl: '',
              onPick: _pickCoffeeImage,
              onRemove: () => setState(() => _coffeeImageBytes = null),
            ),
            const SizedBox(height: 22),

            // ── Section 2: Sizes ─────────────────────────────────────────────
            _sectionHeader('Sizes & Price', Icons.local_drink_rounded),
            const SizedBox(height: 4),
            Text(
              'Set a price delta (added on top of base price) for each size.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ..._sizes.asMap().entries.map((entry) {
              final index = entry.key;
              final size = entry.value;
              return _AnimatedSizeRow(
                key: ValueKey(size),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: size.nameController,
                          decoration: _inputDeco(
                            'Size Name',
                            Icons.straighten_rounded,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: size.priceController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: _inputDeco('+ PHP', Icons.add),
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedOpacity(
                        opacity: _sizes.length == 1 ? 0.3 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: IconButton(
                          onPressed: _sizes.length == 1
                              ? null
                              : () => setState(() {
                                  final removed = _sizes.removeAt(index);
                                  removed.dispose();
                                }),
                          icon: const Icon(
                            Icons.remove_circle_rounded,
                            color: _primaryDeep,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(() => _sizes.add(_OptionDraft())),
              icon: const Icon(Icons.add_circle_rounded, size: 18),
              label: const Text('Add Size'),
              style: TextButton.styleFrom(
                foregroundColor: _primary,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 26),

            // ── Save Button ───────────────────────────────────────────────────
            _AnimatedSaveButton(
              saving: _savingProduct,
              onPressed: _savingProduct ? null : _saveProduct,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalOptionManager({
    required String title,
    required String collection,
    required IconData icon,
    required TextEditingController nameController,
    required TextEditingController priceController,
    required String nameLabel,
    required String buttonLabel,
    required String emptyText,
  }) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(title, icon),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: nameController,
                  decoration: _inputDeco(nameLabel, Icons.label_rounded),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDeco('+ PHP', Icons.add_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _saveGlobalOption(
                collection: collection,
                nameController: nameController,
                priceController: priceController,
              ),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: Text(buttonLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryDeep,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestore
                .collection(collection)
                .where('isDeleted', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Text(
                  emptyText,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: docs.map((doc) {
                  final data = doc.data();
                  return _AnimatedChip(
                    label: data['name']?.toString() ?? '',
                    price: ((data['priceDelta'] ?? 0) as num).toStringAsFixed(
                      0,
                    ),
                    onDelete: () => doc.reference.update({
                      'isDeleted': true,
                      'updatedAt': FieldValue.serverTimestamp(),
                    }),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProductList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('coffee_products').snapshots(),
      builder: (context, snapshot) {
        final docs =
            (snapshot.data?.docs ?? [])
                .where((doc) => doc.data()['isDeleted'] != true)
                .toList()
              ..sort((a, b) {
                final aDate = a.data()['createdAt'];
                final bDate = b.data()['createdAt'];
                if (aDate is Timestamp && bDate is Timestamp) {
                  return bDate.compareTo(aDate);
                }
                return b.id.compareTo(a.id);
              });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _sectionHeader('Coffee Products', Icons.list_alt_rounded),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${docs.length}',
                    style: const TextStyle(
                      color: _primaryDeep,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (docs.isEmpty)
              _Panel(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'No coffee products yet.',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ),
                ),
              )
            else
              ...docs.asMap().entries.map((entry) {
                return _ProductCard(
                  key: ValueKey(entry.value.id),
                  doc: entry.value,
                  firestore: _firestore,
                  onEdit: () => _showEditProductDialog(entry.value),
                  onDelete: () => entry.value.reference.update({
                    'isDeleted': true,
                    'updatedAt': FieldValue.serverTimestamp(),
                  }),
                );
              }),
          ],
        );
      },
    );
  }

  Future<void> _showEditProductDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final nameController = TextEditingController(
      text: data['name']?.toString() ?? '',
    );
    final priceController = TextEditingController(
      text: ((data['basePrice'] ?? 0) as num).toStringAsFixed(0),
    );
    final descriptionController = TextEditingController(
      text: data['description']?.toString() ?? '',
    );
    var editImageBytes = <int>[];
    var removeExistingImage = false;
    final sizeDrafts = (data['sizes'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map(
          (size) => _OptionDraft(
            name: size['name']?.toString() ?? '',
            priceDelta: ((size['priceDelta'] ?? 0) as num).toStringAsFixed(0),
          ),
        )
        .toList();
    if (sizeDrafts.isEmpty) {
      sizeDrafts.add(_OptionDraft(name: 'Small', priceDelta: '0'));
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Coffee'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: _inputDeco(
                        'Flavor Name',
                        Icons.label_rounded,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _inputDeco(
                        'Flavor Price (PHP)',
                        Icons.payments_rounded,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _inputDeco(
                        'Description',
                        Icons.notes_rounded,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CoffeeImagePicker(
                      imageBytes: editImageBytes.isEmpty
                          ? null
                          : Uint8List.fromList(editImageBytes),
                      imageUrl: removeExistingImage
                          ? ''
                          : data['imageUrl']?.toString() ?? '',
                      onPick: () async {
                        final picked = await _imagePicker.pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 900,
                          maxHeight: 900,
                          imageQuality: 75,
                        );
                        if (picked == null) return;
                        final bytes = await picked.readAsBytes();
                        setDialogState(() {
                          editImageBytes = bytes;
                          removeExistingImage = false;
                        });
                      },
                      onRemove: () => setDialogState(() {
                        editImageBytes = [];
                        removeExistingImage = true;
                      }),
                    ),
                    const SizedBox(height: 14),
                    ...sizeDrafts.asMap().entries.map((entry) {
                      final index = entry.key;
                      final size = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: size.nameController,
                                decoration: _inputDeco(
                                  'Size',
                                  Icons.straighten_rounded,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: size.priceController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: _inputDeco('+ PHP', Icons.add),
                              ),
                            ),
                            IconButton(
                              onPressed: sizeDrafts.length == 1
                                  ? null
                                  : () => setDialogState(() {
                                      final removed = sizeDrafts.removeAt(
                                        index,
                                      );
                                      removed.dispose();
                                    }),
                              icon: const Icon(Icons.remove_circle_rounded),
                              color: _primaryDeep,
                            ),
                          ],
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(
                          () => sizeDrafts.add(_OptionDraft()),
                        ),
                        icon: const Icon(Icons.add_circle_rounded),
                        label: const Text('Add Size'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newImageUrl = editImageBytes.isEmpty
                        ? null
                        : await _uploadCoffeeImage(
                            Uint8List.fromList(editImageBytes),
                          );
                    final sizes = sizeDrafts
                        .map(
                          (size) => {
                            'name': size.nameController.text.trim(),
                            'priceDelta': _parsePrice(
                              size.priceController.text,
                            ),
                          },
                        )
                        .where(
                          (size) => size['name']?.toString().isNotEmpty == true,
                        )
                        .toList();
                    await doc.reference.update({
                      'name': nameController.text.trim(),
                      'basePrice': _parsePrice(priceController.text),
                      'description': descriptionController.text.trim(),
                      if (newImageUrl != null) 'imageUrl': newImageUrl,
                      if (removeExistingImage) 'imageUrl': '',
                      'sizes': sizes,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    _showSnack('Coffee updated!');
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    priceController.dispose();
    descriptionController.dispose();
    for (final size in sizeDrafts) {
      size.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          title: const Text(
            'Coffee Menu',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFFFFD6E5),
            labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            tabs: [
              Tab(icon: Icon(Icons.spa_rounded), text: 'Flavors'),
              Tab(
                icon: Icon(Icons.add_circle_outline_rounded),
                text: 'Add-ons',
              ),
              Tab(icon: Icon(Icons.list_alt_rounded), text: 'List'),
            ],
          ),
        ),
        body: FadeTransition(
          opacity: _formFade,
          child: SlideTransition(
            position: _formSlide,
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  children: [_buildProductForm()],
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  children: [
                    _buildGlobalOptionManager(
                      title: 'Create Add-on',
                      collection: 'coffee_addons',
                      icon: Icons.add_circle_outline_rounded,
                      nameController: _addonNameController,
                      priceController: _addonPriceController,
                      nameLabel: 'Add-on Name',
                      buttonLabel: 'Save Add-on',
                      emptyText: 'No add-ons saved yet.',
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  children: [_buildProductList()],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoffeeImagePicker extends StatelessWidget {
  final Uint8List? imageBytes;
  final String imageUrl;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _CoffeeImagePicker({
    required this.imageBytes,
    required this.imageUrl,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasNetworkImage = imageUrl.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 64,
              height: 64,
              color: _primaryLight.withOpacity(0.18),
              child: imageBytes != null
                  ? Image.memory(imageBytes!, fit: BoxFit.cover)
                  : hasNetworkImage
                  ? Image.network(imageUrl, fit: BoxFit.cover)
                  : const Icon(
                      Icons.local_cafe_rounded,
                      color: _primary,
                      size: 28,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              imageBytes != null || hasNetworkImage
                  ? 'Coffee image selected'
                  : 'Upload coffee image',
              style: const TextStyle(
                color: _primaryDeep,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            onPressed: onPick,
            icon: const Icon(Icons.photo_library_rounded),
            color: _primary,
          ),
          if (imageBytes != null || hasNetworkImage)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
              color: _primaryDeep,
            ),
        ],
      ),
    );
  }
}

// ─── Product Card with Expandable Details ───────────────────────────────────

class _ProductCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final FirebaseFirestore firestore;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCard({
    super.key,
    required this.doc,
    required this.firestore,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  String _formatCoffeeId(int number) {
    final now = DateTime.now();
    return '${now.year}${now.month}${now.day}-${number.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final rawSizes = data['sizes'] as List<dynamic>? ?? [];
    final flavorIds = List<String>.from(data['flavorIds'] as List? ?? []);
    final addonIds = List<String>.from(data['addonIds'] as List? ?? []);
    final basePrice = (data['basePrice'] ?? 0) as num;
    final description = data['description']?.toString() ?? '';
    final imageUrl = data['imageUrl']?.toString() ?? '';
    final coffeeId = data['coffeeId']?.toString();
    final coffeeIdNumber = (data['coffeeIdNumber'] as num?)?.toInt();
    final displayId =
        coffeeId ??
        (coffeeIdNumber == null
            ? 'No Coffee ID'
            : _formatCoffeeId(coffeeIdNumber));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card Header (always visible) ──────────────────────────────
            InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: imageUrl.isEmpty
                              ? const LinearGradient(
                                  colors: [_primary, _primaryDeep],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: imageUrl.isEmpty ? null : _primaryLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: imageUrl.isEmpty
                            ? const Icon(
                                Icons.coffee_rounded,
                                color: Colors.white,
                                size: 24,
                              )
                            : imageUrl.startsWith('data:image/')
                            ? Image.memory(
                                base64Decode(imageUrl.split(',').last),
                                fit: BoxFit.cover,
                              )
                            : Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.coffee_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['name']?.toString() ?? 'Coffee',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _primaryDeep,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _MiniTag(
                                label: displayId,
                                color: _primary.withOpacity(0.12),
                                textColor: _primaryDeep,
                              ),
                              _MiniTag(
                                label: 'PHP ${basePrice.toStringAsFixed(0)}',
                                color: const Color(0xFFE8F5E9),
                                textColor: const Color(0xFF2E7D32),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Expand/Collapse indicator
                    SizedBox(
                      width: 112,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 300),
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: _primaryDeep,
                              size: 24,
                            ),
                          ),
                          IconButton(
                            onPressed: widget.onEdit,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: _primaryDeep,
                              size: 20,
                            ),
                            visualDensity: VisualDensity.compact,
                            splashRadius: 18,
                          ),
                          IconButton(
                            onPressed: widget.onDelete,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: _primaryDeep,
                              size: 20,
                            ),
                            visualDensity: VisualDensity.compact,
                            splashRadius: 18,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Expandable Details ────────────────────────────────────────
            SizeTransition(
              sizeFactor: _expandAnim,
              axisAlignment: -1,
              child: FadeTransition(
                opacity: _expandAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    Divider(color: _border, height: 1),
                    const SizedBox(height: 14),

                    // Description
                    if (description.isNotEmpty) ...[
                      Text(
                        description,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Sizes
                    _DetailSection(
                      title: 'Sizes',
                      icon: Icons.local_drink_rounded,
                      child: Column(
                        children: rawSizes.map((s) {
                          final sizeMap = s as Map<String, dynamic>;
                          final sizeName = sizeMap['name']?.toString() ?? '';
                          final delta = (sizeMap['priceDelta'] ?? 0) as num;
                          final total = basePrice + delta;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                _SizeIndicator(name: sizeName),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    sizeName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (delta > 0)
                                  Text(
                                    '+PHP ${delta.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Colors.black38,
                                      fontSize: 11,
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [_primary, _primaryDeep],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'PHP ${total.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Flavors
                    if (flavorIds.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _FirestoreOptionList(
                        title: 'Flavors',
                        icon: Icons.spa_rounded,
                        ids: flavorIds,
                        collection: 'coffee_flavors',
                        firestore: widget.firestore,
                      ),
                    ],

                    // Add-ons
                    if (addonIds.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _FirestoreOptionList(
                        title: 'Add-ons',
                        icon: Icons.add_circle_outline_rounded,
                        ids: addonIds,
                        collection: 'coffee_addons',
                        firestore: widget.firestore,
                      ),
                    ],

                    if (flavorIds.isEmpty && addonIds.isEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'No flavors or add-ons assigned.',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],

                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Firestore Option List (for expanded details) ───────────────────────────

class _FirestoreOptionList extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> ids;
  final String collection;
  final FirebaseFirestore firestore;

  const _FirestoreOptionList({
    required this.title,
    required this.icon,
    required this.ids,
    required this.collection,
    required this.firestore,
  });

  @override
  Widget build(BuildContext context) {
    return _DetailSection(
      title: title,
      icon: icon,
      child: FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
        future: Future.wait(
          ids.map((id) => firestore.collection(collection).doc(id).get()),
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _primary,
                  ),
                ),
              ),
            );
          }
          final docs = snapshot.data!
              .where((d) => d.exists && d.data() != null)
              .toList();
          if (docs.isEmpty) {
            return Text(
              'Options removed or unavailable.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            );
          }
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: docs.map((d) {
              final data = d.data()!;
              final delta = (data['priceDelta'] ?? 0) as num;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _primary.withOpacity(0.25)),
                ),
                child: Text(
                  delta > 0
                      ? '${data['name']} +PHP ${delta.toStringAsFixed(0)}'
                      : '${data['name']}',
                  style: const TextStyle(
                    color: _primaryDeep,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ─── Detail Section Widget ───────────────────────────────────────────────────

class _DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _DetailSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border.withOpacity(0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _primary, size: 15),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: _primaryDeep,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ─── Size Indicator ──────────────────────────────────────────────────────────

class _SizeIndicator extends StatelessWidget {
  final String name;
  const _SizeIndicator({required this.name});

  @override
  Widget build(BuildContext context) {
    final lower = name.toLowerCase();
    double size;
    if (lower.contains('small') || lower == 's') {
      size = 16;
    } else if (lower.contains('large') || lower == 'l') {
      size = 26;
    } else {
      size = 20;
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _primary, width: 1.5),
        color: _primary.withOpacity(0.1),
      ),
    );
  }
}

// ─── Mini Tag ────────────────────────────────────────────────────────────────

class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _MiniTag({
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

// ─── Animated Chip ───────────────────────────────────────────────────────────

class _AnimatedChip extends StatefulWidget {
  final String label;
  final String price;
  final VoidCallback onDelete;

  const _AnimatedChip({
    required this.label,
    required this.price,
    required this.onDelete,
  });

  @override
  State<_AnimatedChip> createState() => _AnimatedChipState();
}

class _AnimatedChipState extends State<_AnimatedChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _anim,
      child: Chip(
        backgroundColor: _primaryLight.withOpacity(0.15),
        side: BorderSide(color: _primary.withOpacity(0.3)),
        label: Text(
          widget.price != '0'
              ? '${widget.label}  +PHP ${widget.price}'
              : widget.label,
          style: const TextStyle(
            color: _primaryDeep,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        deleteIcon: const Icon(
          Icons.close_rounded,
          size: 15,
          color: _primaryDeep,
        ),
        onDeleted: widget.onDelete,
      ),
    );
  }
}

// ─── Animated Save Button ────────────────────────────────────────────────────

class _AnimatedSaveButton extends StatefulWidget {
  final bool saving;
  final VoidCallback? onPressed;

  const _AnimatedSaveButton({required this.saving, required this.onPressed});

  @override
  State<_AnimatedSaveButton> createState() => _AnimatedSaveButtonState();
}

class _AnimatedSaveButtonState extends State<_AnimatedSaveButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.97,
      upperBound: 1.0,
    );
    _ctrl.value = 1.0;
    _scale = _ctrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _ctrl.reverse();
  void _onTapUp(_) => _ctrl.forward();
  void _onTapCancel() => _ctrl.forward();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scale,
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.saving ? Colors.grey.shade300 : _primary,
              foregroundColor: Colors.white,
              elevation: widget.saving ? 0 : 3,
              shadowColor: _primary.withOpacity(0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: widget.saving
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: _primaryDeep,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Row(
                      key: ValueKey('label'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Save Coffee Flavor',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 0.5,
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
}

// ─── Animated Size Row ───────────────────────────────────────────────────────

class _AnimatedSizeRow extends StatefulWidget {
  final Widget child;
  const _AnimatedSizeRow({super.key, required this.child});

  @override
  State<_AnimatedSizeRow> createState() => _AnimatedSizeRowState();
}

class _AnimatedSizeRowState extends State<_AnimatedSizeRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0.05, 0),
      end: Offset.zero,
    ).animate(_fade);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ─── Panel ───────────────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _primaryDeep.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─── Option Draft ─────────────────────────────────────────────────────────────

class _OptionDraft {
  final TextEditingController nameController;
  final TextEditingController priceController;

  _OptionDraft({String name = '', String priceDelta = ''})
    : nameController = TextEditingController(text: name),
      priceController = TextEditingController(text: priceDelta);

  void dispose() {
    nameController.dispose();
    priceController.dispose();
  }
}
