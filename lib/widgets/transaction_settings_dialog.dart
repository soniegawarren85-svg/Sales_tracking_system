import 'dart:convert';
import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../services/transaction_settings.dart';
import '../services/catalog_image_service.dart';

Future<bool> confirmSetting(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm change'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryDeep,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;

class TransactionSettingsDialog extends StatefulWidget {
  const TransactionSettingsDialog({
    super.key,
    required this.kind,
    this.firestore,
  });
  final FirebaseFirestore? firestore;
  final String kind;
  @override
  State<TransactionSettingsDialog> createState() =>
      _TransactionSettingsDialogState();
}

class _TransactionSettingsDialogState extends State<TransactionSettingsDialog> {
  final _controllers = <TextEditingController>[];
  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool voided = false, busy = false;
  late final reference = (widget.firestore ?? FirebaseFirestore.instance)
      .collection('admin_settings')
      .doc('transactions');
  void notify(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> save(Map<String, dynamic> patch, String message) async {
    setState(() => busy = true);
    try {
      await reference.set({
        ...patch,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) notify(message);
    } catch (e) {
      if (mounted) notify('Unable to save: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Map<String, dynamic>?> edit(Map<String, dynamic>? row) async {
    final existing = settingRows(
      (await reference.get()).data() ?? {},
      widget.kind,
    );
    if (!mounted) return null;
    final name = TextEditingController(text: row?['name'] ?? '');
    final percent = TextEditingController(text: '${row?['percent'] ?? ''}');
    _controllers.addAll([name, percent]);
    var qr = '${row?['qrUrl'] ?? ''}';
    var uploading = false;
    String? error;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          backgroundColor: AppColors.surface,
          titleTextStyle: const TextStyle(
            color: AppColors.primaryDeep,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          title: Text(
            '${row == null ? 'Add' : 'Edit'} ${widget.kind == 'discounts' ? 'discount' : 'payment method'}',
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  if (widget.kind == 'discounts')
                    TextField(
                      controller: percent,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Discount percent',
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      icon: const Icon(Icons.qr_code),
                      label: Text(
                        uploading
                            ? 'Uploading…'
                            : qr.isEmpty
                            ? 'Upload QR code'
                            : 'Replace QR code',
                      ),
                      onPressed: uploading
                          ? null
                          : () async {
                              final picked = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                              );
                              if (picked == null) return;
                              update(() => uploading = true);
                              try {
                                final url = await uploadCatalogImage(
                                  await picked.readAsBytes(),
                                  folder: 'payment_qr',
                                );
                                if (url == null)
                                  throw StateError('Upload failed');
                                qr = url;
                              } catch (e) {
                                error = '$e';
                              }
                              if (context.mounted)
                                update(() => uploading = false);
                            },
                    ),
                  if (widget.kind != 'discounts' && qr.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      height: 300,
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: qr.startsWith('data:image/')
                          ? Image.memory(
                              base64Decode(qr.split(',').last),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Text('Unable to load QR code'),
                            )
                          : Image.network(
                              qr,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Text('Unable to load QR code'),
                            ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This QR code appears in the staff payment screen after saving.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: uploading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDeep,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: uploading
                  ? null
                  : () {
                      final value = double.tryParse(percent.text);
                      if (existing.any(
                        (entry) =>
                            entry['id'] != row?['id'] &&
                            '${entry['name']}'.toLowerCase() ==
                                name.text.trim().toLowerCase(),
                      )) {
                        update(
                          () => error =
                              'This name is already used, including voided records.',
                        );
                        return;
                      }
                      if (name.text.trim().isEmpty ||
                          (widget.kind != 'discounts' &&
                              name.text.trim().toLowerCase() == 'cash') ||
                          (widget.kind == 'discounts' &&
                              (value == null ||
                                  !value.isFinite ||
                                  value <= 0 ||
                                  value > 100)) ||
                          (widget.kind != 'discounts' &&
                              row == null &&
                              qr.isEmpty)) {
                        update(
                          () => error =
                              'Enter a name and ${widget.kind == 'discounts' ? 'a percentage from 1 to 100' : 'upload a QR code'}.',
                        );
                        return;
                      }
                      Navigator.pop(context, {
                        ...?row,
                        'id':
                            row?['id'] ??
                            DateTime.now().microsecondsSinceEpoch.toString(),
                        'name': name.text.trim(),
                        if (widget.kind == 'discounts')
                          'percent': value
                        else
                          'qrUrl': qr,
                      });
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    return result;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.surface,
    titleTextStyle: const TextStyle(
      color: AppColors.primaryDeep,
      fontSize: 24,
      fontWeight: FontWeight.bold,
    ),
    title: Text(
      widget.kind == 'discounts'
          ? 'Discount Control'
          : widget.kind == 'permissions'
          ? 'Staff Permissions'
          : 'Payment Settings',
    ),
    content: SizedBox(
      width: 620,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: reference.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Text('Unable to load settings: ${snapshot.error}');
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!.data() ?? {};
          if (widget.kind == 'permissions')
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: staffPermissions.entries
                  .map(
                    (entry) => SwitchListTile(
                      title: Text(entry.value),
                      value: data[entry.key] != false,
                      onChanged: busy
                          ? null
                          : (value) => save({
                              entry.key: value,
                            }, 'Permission updated successfully.'),
                    ),
                  )
                  .toList(),
            );
          final rows = settingRows(data, widget.kind);
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.kind == 'discounts')
                  SwitchListTile(
                    title: const Text('Enable discounts'),
                    value: data['discountsEnabled'] != false,
                    onChanged: busy
                        ? null
                        : (value) async {
                            if (!value &&
                                !await confirmSetting(
                                  context,
                                  'Turn off all discounts in the staff cashier?',
                                ))
                              return;
                            await save({
                              'discountsEnabled': value,
                            }, 'Discount control updated successfully.');
                          },
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Text(voided ? 'Voided records' : 'Active records'),
                    ),
                    IconButton(
                      tooltip: voided ? 'Active records' : 'Voided records',
                      icon: Icon(
                        voided ? Icons.arrow_back : Icons.inventory_2_outlined,
                      ),
                      onPressed: () => setState(() => voided = !voided),
                    ),
                  ],
                ),
                ...rows
                    .asMap()
                    .entries
                    .where(
                      (entry) => (entry.value['isVoided'] == true) == voided,
                    )
                    .map((entry) {
                      final row = entry.value;
                      final cash =
                          widget.kind != 'discounts' &&
                          (row['id'] == 'cash' || row['name'] == 'Cash');
                      return ListTile(
                        title: Text('${row['name']}'),
                        subtitle: widget.kind == 'discounts'
                            ? Text('${row['percent']}%')
                            : null,
                        trailing: cash
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!voided)
                                    IconButton(
                                      tooltip: 'Edit',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: busy
                                          ? null
                                          : () async {
                                              final updated = await edit(row);
                                              if (updated != null) {
                                                rows[entry.key] = updated;
                                                await save({
                                                  widget.kind: rows,
                                                }, 'Saved successfully.');
                                              }
                                            },
                                    ),
                                  IconButton(
                                    tooltip: voided ? 'Restore' : 'Void',
                                    icon: Icon(
                                      voided ? Icons.restore : Icons.block,
                                    ),
                                    onPressed: busy
                                        ? null
                                        : () async {
                                            if (!await confirmSetting(
                                              context,
                                              '${voided ? 'Restore' : 'Void'} ${row['name']}?',
                                            ))
                                              return;
                                            rows[entry.key] = {
                                              ...row,
                                              'isVoided': !voided,
                                            };
                                            await save(
                                              {widget.kind: rows},
                                              voided
                                                  ? 'Restored successfully.'
                                                  : 'Voided successfully.',
                                            );
                                          },
                                  ),
                                ],
                              ),
                      );
                    }),
                if (!voided)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                    onPressed: busy
                        ? null
                        : () async {
                            final row = await edit(null);
                            if (row != null) {
                              rows.add(row);
                              await save({
                                widget.kind: rows,
                              }, 'Added successfully.');
                            }
                          },
                  ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
