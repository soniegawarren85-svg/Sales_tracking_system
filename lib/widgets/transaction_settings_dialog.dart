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
  String? selectedBranchId;
  late final reference = (widget.firestore ?? FirebaseFirestore.instance)
      .collection('admin_settings')
      .doc('transactions');
  void notify(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> save(
    String branchId,
    Map<String, dynamic> patch,
    String message,
  ) => saveBranches([branchId], patch, message);

  Future<void> saveBranches(
    List<String> branchIds,
    Map<String, dynamic> patch,
    String message,
  ) async {
    setState(() => busy = true);
    try {
      final currentSettings = (await reference.get()).data() ?? {};
      Map<String, dynamic> patchForBranch(String branchId) {
        if (widget.kind != 'payments' ||
            patch['payments'] is! List ||
            branchIds.length < 2) {
          return patch;
        }
        final sourceRows = settingRows(
          settingsForBranch(currentSettings, branchIds.first),
          'payments',
        );
        final targetRows = settingRows(
          settingsForBranch(currentSettings, branchId),
          'payments',
        );
        final payments = (patch['payments'] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .map((row) {
              final source = sourceRows
                  .where((existing) => existing['id'] == row['id'])
                  .firstOrNull;
              final target = targetRows
                  .where((existing) => existing['id'] == row['id'])
                  .firstOrNull;
              if (source != null &&
                  target != null &&
                  row['qrUrl'] == source['qrUrl']) {
                row['qrUrl'] = target['qrUrl'];
              }
              return row;
            })
            .toList();
        return {...patch, 'payments': payments};
      }

      await reference.set({
        'branchSettings': {
          for (final branchId in branchIds)
            branchId: patchForBranch(branchId),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) notify(message);
    } catch (e) {
      if (mounted) notify('Unable to save: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Map<String, dynamic>?> edit(
    Map<String, dynamic>? row, {
    required String branchId,
  }) async {
    final existing = settingRows(
      settingsForBranch((await reference.get()).data() ?? {}, branchId),
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

  Widget _branchDropdown(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> branches,
    String branchId,
    {bool includeAll = false}
  ) => DropdownButtonFormField<String>(
    value: branchId,
    decoration: const InputDecoration(
      labelText: 'Branch',
      border: OutlineInputBorder(),
    ),
    items: [
      if (includeAll)
        const DropdownMenuItem(
          value: allBranchesSelection,
          child: Text('All branches'),
        ),
      ...branches.map(
        (branch) => DropdownMenuItem(
          value: branch.id,
          child: Text(branch.data()['name']?.toString() ?? branch.id),
        ),
      ),
    ],
    onChanged: busy
        ? null
        : (value) {
            if (value == null) return;
            setState(() {
              selectedBranchId = value;
              voided = false;
            });
          },
  );

  bool get _hasAllBranches =>
      widget.kind == 'permissions' ||
      widget.kind == 'tax' ||
      widget.kind == 'discounts' ||
      widget.kind == 'payments';

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
          : widget.kind == 'tax'
          ? 'Tax Configuration'
          : widget.kind == 'permissions'
          ? 'Security and Approval'
          : 'Payment Settings',
    ),
    content: SizedBox(
      width: 620,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: (widget.firestore ?? FirebaseFirestore.instance)
            .collection('branches')
            .orderBy('name')
            .snapshots(),
        builder: (context, branchSnapshot) {
          if (branchSnapshot.hasError) {
            return Text('Unable to load branches: ${branchSnapshot.error}');
          }
          if (!branchSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final branches = branchSnapshot.data!.docs;
          if (branches.isEmpty) {
            return const Text('Create a branch before configuring settings.');
          }
          final isAllBranches =
              _hasAllBranches &&
              selectedBranchId == allBranchesSelection;
          final branchId = isAllBranches
              ? branches.first.id
              : branches.any((branch) => branch.id == selectedBranchId)
              ? selectedBranchId!
              : branches.first.id;
          final branchName = isAllBranches
              ? 'All branches'
              : branches
                        .firstWhere((branch) => branch.id == branchId)
                        .data()['name']
                        ?.toString() ??
                    branchId;
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: reference.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Text('Unable to load settings: ${snapshot.error}');
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final rawSettings = snapshot.data!.data() ?? {};
              final data = settingsForBranch(rawSettings, branchId);
              if (widget.kind == 'tax') {
                final branchTaxSettings = branches
                    .map(
                      (branch) =>
                          settingsForBranch(rawSettings, branch.id),
                    )
                    .toList();
                final taxEnabled = isAllBranches
                    ? branchTaxSettings.every(
                        (settings) => settings['taxEnabled'] == true,
                      )
                    : data['taxEnabled'] == true;
                final classifications = branchTaxSettings
                    .map(
                      (settings) =>
                          settings['taxClassification']?.toString() ??
                          'nonVat',
                    )
                    .toSet();
                final taxClassification = isAllBranches
                    ? classifications.length == 1
                          ? classifications.single
                          : null
                    : data['taxClassification']?.toString() ?? 'nonVat';
                final targetBranches = isAllBranches
                    ? branches.map((branch) => branch.id).toList()
                    : [branchId];
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _branchDropdown(
                        branches,
                        isAllBranches ? allBranchesSelection : branchId,
                        includeAll: true,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Enable tax'),
                        value: taxEnabled,
                        onChanged: busy
                            ? null
                            : (value) => saveBranches(
                                targetBranches,
                                {'taxEnabled': value},
                                'Tax setting updated for $branchName.',
                              ),
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text(
                            'Tax classification',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      RadioListTile<String>(
                        title: const Text('Non-VAT registered'),
                        value: 'nonVat',
                        groupValue: taxClassification,
                        onChanged: busy || !taxEnabled
                            ? null
                            : (value) {
                                if (value == null) return;
                                saveBranches(
                                  targetBranches,
                                  {'taxClassification': value},
                                  'Tax classification updated for $branchName.',
                                );
                              },
                      ),
                      RadioListTile<String>(
                        title: const Text('VAT registered (12%)'),
                        value: 'vat',
                        groupValue: taxClassification,
                        onChanged: busy || !taxEnabled
                            ? null
                            : (value) {
                                if (value == null) return;
                                saveBranches(
                                  targetBranches,
                                  {'taxClassification': value},
                                  'Tax classification updated for $branchName.',
                                );
                              },
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'VAT is added to the discounted order amount in the staff cashier when tax is enabled.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (widget.kind == 'permissions')
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _branchDropdown(
                      branches,
                      isAllBranches ? allBranchesSelection : branchId,
                      includeAll: true,
                    ),
                    const SizedBox(height: 8),
                    ...staffPermissions.entries.map(
                      (entry) => SwitchListTile(
                        title: Text(entry.value),
                        value: isAllBranches
                            ? branches.every(
                                (branch) =>
                                    settingsForBranch(
                                      rawSettings,
                                      branch.id,
                                    )[entry.key] !=
                                    false,
                              )
                            : data[entry.key] != false,
                        onChanged: busy
                            ? null
                            : (value) => isAllBranches
                            ? saveBranches(
                                branches.map((branch) => branch.id).toList(),
                                {entry.key: value},
                                'Permission updated for all branches.',
                              )
                            : save(
                                branchId,
                                {entry.key: value},
                                '$branchName permission updated successfully.',
                              ),
                      ),
                    ),
                  ],
                );
              final rows = settingRows(data, widget.kind);
              final targetBranches = isAllBranches
                  ? branches.map((branch) => branch.id).toList()
                  : [branchId];
              final discountsEnabled = isAllBranches
                  ? branches.every(
                      (branch) =>
                          settingsForBranch(rawSettings, branch.id)['discountsEnabled'] !=
                          false,
                    )
                  : data['discountsEnabled'] != false;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _branchDropdown(
                      branches,
                      isAllBranches ? allBranchesSelection : branchId,
                      includeAll: true,
                    ),
                    const SizedBox(height: 8),
                    if (widget.kind == 'discounts')
                      SwitchListTile(
                        title: const Text('Enable discounts'),
                        value: discountsEnabled,
                        onChanged: busy
                            ? null
                            : (value) async {
                                if (!value &&
                                    !await confirmSetting(
                                      context,
                                      'Turn off all discounts in the $branchName staff cashier?',
                                    ))
                                  return;
                                await saveBranches(
                                  targetBranches,
                                  {'discountsEnabled': value},
                                  '$branchName discount control updated successfully.',
                                );
                              },
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            voided ? 'Voided records' : 'Active records',
                          ),
                        ),
                        IconButton(
                          tooltip: voided ? 'Active records' : 'Voided records',
                          icon: Icon(
                            voided
                                ? Icons.arrow_back
                                : Icons.inventory_2_outlined,
                          ),
                          onPressed: () => setState(() => voided = !voided),
                        ),
                      ],
                    ),
                    ...rows
                        .asMap()
                        .entries
                        .where(
                          (entry) =>
                              (entry.value['isVoided'] == true) == voided,
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
                                                  final updated = await edit(
                                                    row,
                                                    branchId: branchId,
                                                  );
                                                  if (updated != null) {
                                                    rows[entry.key] = updated;
                                                    await saveBranches(
                                                      targetBranches,
                                                      {widget.kind: rows},
                                                      'Saved for $branchName.',
                                                    );
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
                                                await saveBranches(
                                                  targetBranches,
                                                  {widget.kind: rows},
                                                  voided
                                                      ? 'Restored for $branchName.'
                                                      : 'Voided for $branchName.',
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
                                final row = await edit(
                                  null,
                                  branchId: branchId,
                                );
                                if (row != null) {
                                  rows.add(row);
                                  await saveBranches(targetBranches, {
                                    widget.kind: rows,
                                  }, 'Added for $branchName.');
                                }
                              },
                      ),
                  ],
                ),
              );
            },
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
