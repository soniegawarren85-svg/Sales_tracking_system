import 'inventory_records_table.dart';
import 'void_reason_dialog.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/catalog_image_service.dart';
import '../services/short_id_service.dart';
import '../theme/app_colors.dart';

Future<void> showAdminAddonEditor(
  BuildContext context, {
  DocumentSnapshot<Map<String, dynamic>>? record,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _AddonEditor(record: record),
);

Widget _photo(String url) {
  if (url.isEmpty)
    return const Icon(Icons.extension_outlined, color: AppColors.primaryDark);
  if (url.startsWith('data:image/')) {
    try {
      return Image.memory(base64Decode(url.split(',').last), fit: BoxFit.cover);
    } catch (_) {
      return const Icon(Icons.image_not_supported);
    }
  }
  return Image.network(
    url,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported),
  );
}

class AdminAddonsTable extends StatefulWidget {
  const AdminAddonsTable({super.key, this.query = '', this.firestore});
  final FirebaseFirestore? firestore;
  final String query;

  @override
  State<AdminAddonsTable> createState() => _AdminAddonsTableState();
}

class _AdminAddonsTableState extends State<AdminAddonsTable> {
  @override
  void initState() {
    super.initState();
    if (widget.firestore == null) {
      ShortIdService.ensureAddonPublicIds().catchError((Object error) {
        debugPrint('Add-on public ID update failed: $error');
      });
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: (widget.firestore ?? FirebaseFirestore.instance)
        .collection('coffee_addons')
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Unable to load add-ons.');
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final rows = snapshot.data!.docs
          .where(
            (doc) =>
                doc.data()['isDeleted'] != true &&
                '${doc.data()['name']}'.toLowerCase().contains(
                  widget.query.toLowerCase(),
                ),
          )
          .toList();
      return LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InventoryRecordsTable(
                headings: const [
                  'ID',
                  'Add-on',
                  'Price',
                  'Expiry date',
                  'Actions',
                ],
                flex: const {0: 1.3, 1: 2.5, 2: 1.2, 3: 1.7, 4: 1.3},
                rows: rows.map((doc) {
                  final data = doc.data();
                  final publicId =
                      data['publicId']?.toString().trim().isNotEmpty == true
                      ? data['publicId'].toString().trim()
                      : 'Assigning ID…';
                  final expiry = DateTime.tryParse('${data['expirationDate']}');
                  final expired =
                      expiry != null &&
                      expiry.isBefore(DateUtils.dateOnly(DateTime.now()));
                  return <Widget>[
                    Text(
                      publicId,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Row(
                      children: [
                        if (constraints.maxWidth > 600) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: _photo('${data['imageUrl'] ?? ''}'),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            '${data['name'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '₱${(num.tryParse('${data['priceDelta']}') ?? 0).toStringAsFixed(2)}',
                    ),
                    Text(
                      '${data['expirationDate'] ?? 'Not recorded'}${expired ? '\nExpired' : ''}',
                    ),
                    Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Edit add-on',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () =>
                              showAdminAddonEditor(context, record: doc),
                        ),
                        IconButton(
                          tooltip: 'Void add-on',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.block,
                            size: 20,
                            color: AppColors.primaryDark,
                          ),
                          onPressed: () async {
                            final reason = await showVoidReasonDialog(
                              context,
                              '${data['name']}',
                            );
                            if (reason == null) return;
                            try {
                              await doc.reference.update({
                                'isDeleted': true,
                                'deletedAt': Timestamp.now(),
                                'voidReason': reason,
                              });
                            } catch (_) {
                              if (context.mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Unable to void add-on. Please retry.',
                                    ),
                                  ),
                                );
                            }
                          },
                        ),
                      ],
                    ),
                  ];
                }).toList(),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No add-ons found.'),
                ),
            ],
          );
        },
      );
    },
  );
}

class _AddonEditor extends StatefulWidget {
  const _AddonEditor({this.record});
  final DocumentSnapshot<Map<String, dynamic>>? record;
  @override
  State<_AddonEditor> createState() => _AddonEditorState();
}

class _AddonEditorState extends State<_AddonEditor> {
  final form = GlobalKey<FormState>();
  late final data = widget.record?.data() ?? <String, dynamic>{};
  late final name = TextEditingController(text: '${data['name'] ?? ''}');
  late final price = TextEditingController(text: '${data['priceDelta'] ?? ''}');
  late final expiry = TextEditingController(
    text: '${data['expirationDate'] ?? ''}',
  );
  Uint8List? photo;
  Future<String?>? upload;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    price.dispose();
    expiry.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final url = await upload;
      if (photo != null && url == null)
        throw StateError(
          'Image upload failed. Please select the picture again.',
        );
      final ref =
          widget.record?.reference ??
          FirebaseFirestore.instance.collection('coffee_addons').doc();
      await ref.set({
        if ((data['publicId']?.toString().trim() ?? '').isEmpty)
          'publicId': await ShortIdService.next('AD'),
        'name': name.text.trim(),
        'priceDelta': num.parse(price.text),
        'expirationDate': expiry.text,
        'isDeleted': false,
        if (url != null) 'imageUrl': url,
        'updatedAt': Timestamp.now(),
        if (widget.record == null) 'createdAt': Timestamp.now(),
      }, SetOptions(merge: true));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Unable to save. Check the picture and connection, then retry.',
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.record == null ? 'Add add-on' : 'Edit add-on'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                enabled: !saving,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: price,
                enabled: !saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Price (₱)'),
                validator: (v) {
                  final n = num.tryParse(v ?? '');
                  return n == null || !n.isFinite || n < 0
                      ? 'Enter a valid price'
                      : null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: expiry,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Expiration date',
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                validator: (v) =>
                    DateTime.tryParse(v ?? '') == null ? 'Choose a date' : null,
                onTap: saving
                    ? null
                    : () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate:
                              DateTime.tryParse(expiry.text) ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (date != null)
                          expiry.text = date.toIso8601String().split('T').first;
                      },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Picture'),
                leading: SizedBox(
                  width: 48,
                  height: 48,
                  child: photo == null
                      ? _photo('${data['imageUrl'] ?? ''}')
                      : Image.memory(photo!, fit: BoxFit.cover),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.photo_library_outlined),
                  onPressed: saving
                      ? null
                      : () async {
                          try {
                            final file = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 800,
                              maxHeight: 800,
                              imageQuality: 70,
                            );
                            if (file == null) return;
                            final bytes = await file.readAsBytes();
                            if (!mounted) return;
                            setState(() {
                              photo = bytes;
                              upload = uploadCatalogImage(
                                bytes,
                              ).catchError((_) => null);
                            });
                          } catch (_) {
                            if (mounted)
                              setState(
                                () => error = 'Unable to select picture.',
                              );
                          }
                        },
                ),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Saving…' : 'Save'),
      ),
    ],
  );
}
