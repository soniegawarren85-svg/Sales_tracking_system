import 'dart:async';
import 'dart:convert';
import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../services/transaction_settings.dart';
import '../services/catalog_image_service.dart';
import '../services/activity_log.dart';
import '../services/branch_status.dart';
import '../services/qr_image_decoder.dart';

String? discountPercentValidationMessage(String rawValue) {
  final value = double.tryParse(rawValue.trim());
  if (value == null || !value.isFinite || value < 1 || value > 20) {
    return 'Discount must be from 1% to 20%.';
  }
  return null;
}

bool validPaymentMethodName(String value) =>
    RegExp(r'^[A-Za-z ]+$').hasMatch(value.trim());

String _formatDiscountPercent(dynamic value) {
  final percent = num.tryParse('$value');
  if (percent == null) return '$value';
  return percent
      .toString()
      .replaceFirst(RegExp(r'\.0+$'), '')
      .replaceFirst(RegExp(r'(\.\d*?)0+$'), r'$1');
}

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

class _SettingEditorDialog extends StatefulWidget {
  const _SettingEditorDialog({
    required this.kind,
    required this.row,
    required this.existing,
  });

  final String kind;
  final Map<String, dynamic>? row;
  final List<Map<String, dynamic>> existing;

  @override
  State<_SettingEditorDialog> createState() => _SettingEditorDialogState();
}

class _SettingEditorDialogState extends State<_SettingEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _percent;
  late String _qr;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.row?['name'] ?? '');
    _percent = TextEditingController(text: '${widget.row?['percent'] ?? ''}');
    _qr = '${widget.row?['qrUrl'] ?? ''}';
  }

  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    super.dispose();
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
      '${widget.row == null ? 'Add' : 'Edit'} ${widget.kind == 'discounts' ? 'discount' : 'payment method'}',
    ),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              inputFormatters: widget.kind == 'discounts'
                  ? null
                  : [FilteringTextInputFormatter.allow(RegExp('[A-Za-z ]'))],
              decoration: InputDecoration(
                labelText: 'Name',
                helperText: widget.kind == 'discounts'
                    ? null
                    : 'Letters and spaces only.',
              ),
            ),
            if (widget.kind == 'discounts')
              TextField(
                controller: _percent,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: 'Discount percent',
                  suffixText: '%',
                  helperText: 'Maximum allowed discount is 20%.',
                  errorText: _percent.text.isEmpty
                      ? null
                      : discountPercentValidationMessage(_percent.text),
                ),
              )
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.qr_code),
                label: Text(
                  _uploading
                      ? 'Uploading…'
                      : _qr.isEmpty
                      ? 'Upload QR code'
                      : 'Replace QR code',
                ),
                onPressed: _uploading
                    ? null
                    : () async {
                        final picked = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                        );
                        if (picked == null || !mounted) return;
                        setState(() => _uploading = true);
                        try {
                          final bytes = await picked.readAsBytes();
                          final qrPayload = decodeQrImage(bytes);
                          if (qrPayload.trim().isEmpty) {
                            throw const FormatException(
                              'The selected QR code is empty.',
                            );
                          }
                          final url = await uploadCatalogImage(
                            bytes,
                            folder: 'payment_qr',
                          );
                          if (url == null) {
                            throw StateError('Upload failed');
                          }
                          _qr = url;
                          _error = null;
                        } catch (e) {
                          _error = e is FormatException
                              ? e.message
                              : 'Hindi ma-validate ang QR code. Subukang mag-upload ng malinaw na QR image.';
                        } finally {
                          if (mounted) setState(() => _uploading = false);
                        }
                      },
              ),
            if (widget.kind != 'discounts' && _qr.isNotEmpty) ...[
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
                child: _qr.startsWith('data:image/')
                    ? Image.memory(
                        base64Decode(_qr.split(',').last),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Text('Unable to load QR code'),
                      )
                    : Image.network(
                        _qr,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Text('Unable to load QR code'),
                      ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This QR code appears in the staff payment screen after saving.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ],
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFC7C7)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFB3261E)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _uploading ? null : () => Navigator.pop(context),
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
        onPressed: _uploading
            ? null
            : () {
                final value = double.tryParse(_percent.text);
                final discountValidation = discountPercentValidationMessage(
                  _percent.text,
                );
                if (widget.existing.any(
                  (entry) =>
                      entry['id'] != widget.row?['id'] &&
                      '${entry['name']}'.toLowerCase() ==
                          _name.text.trim().toLowerCase(),
                )) {
                  setState(
                    () => _error =
                        'This name is already used, including voided records.',
                  );
                  return;
                }
                if (_name.text.trim().isEmpty ||
                    (widget.kind != 'discounts' &&
                        (!validPaymentMethodName(_name.text) ||
                            _name.text.trim().toLowerCase() == 'cash')) ||
                    (widget.kind == 'discounts' &&
                        discountValidation != null) ||
                    (widget.kind != 'discounts' &&
                        widget.row == null &&
                        _qr.isEmpty)) {
                  setState(
                    () => _error = widget.kind == 'discounts'
                        ? discountValidation
                        : !validPaymentMethodName(_name.text)
                        ? 'Payment method names may contain letters and spaces only.'
                        : 'Enter a name and upload a readable QR code.',
                  );
                  return;
                }
                Navigator.pop(context, {
                  ...?widget.row,
                  'id':
                      widget.row?['id'] ??
                      DateTime.now().microsecondsSinceEpoch.toString(),
                  'name': _name.text.trim(),
                  if (widget.kind == 'discounts')
                    'percent': value
                  else
                    'qrUrl': _qr,
                });
              },
        child: const Text('Save'),
      ),
    ],
  );
}

class TransactionSettingsDialog extends StatefulWidget {
  const TransactionSettingsDialog({
    super.key,
    required this.kind,
    this.firestore,
    this.separateRoles = false,
    this.branchId,
  });
  final FirebaseFirestore? firestore;
  final String kind;
  final bool separateRoles;
  final String? branchId;
  @override
  State<TransactionSettingsDialog> createState() =>
      _TransactionSettingsDialogState();
}

class _TransactionSettingsDialogState extends State<TransactionSettingsDialog> {
  bool voided = false, busy = false;
  String? _taxTinDraft;
  Map<String, dynamic>? _latestSettings;
  late String? selectedBranchId;
  late final _firestore = widget.firestore ?? FirebaseFirestore.instance;
  late final reference = _firestore
      .collection('admin_settings')
      .doc('transactions');
  late final _branchesStream = _firestore
      .collection('branches')
      .orderBy('name')
      .snapshots();
  late final _settingsStream = reference.snapshots();

  @override
  void initState() {
    super.initState();
    selectedBranchId = widget.branchId ?? allBranchesSelection;
  }

  bool get _isBranchScoped =>
      widget.branchId != null &&
      ['discounts', 'payments', 'permissions', 'tax'].contains(widget.kind);

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
      final preservePaymentQr =
          widget.kind == 'payments' &&
          patch['payments'] is List &&
          branchIds.length > 1;
      final currentSettings = preservePaymentQr
          ? _latestSettings ?? (await reference.get()).data() ?? {}
          : <String, dynamic>{};
      Map<String, dynamic> patchForBranch(String branchId) {
        if (!preservePaymentQr) {
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

      final write = reference.set({
        'branchSettings': {
          for (final branchId in branchIds) branchId: patchForBranch(branchId),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      unawaited(_observeSettingsWrite(write));
      unawaited(
        ActivityLog.record(
          'settings_updated',
          message,
          database: reference.firestore,
          branchId: branchIds.length == 1 ? branchIds.first : null,
          branchIds: branchIds.toSet(),
          details: {
            'kind': widget.kind,
            'fields': patch.keys.toList(),
            'scope': branchIds.length > 1 ? 'All branches' : branchIds.first,
          },
        ),
      );
      if (mounted) notify('$message Saved locally; syncing to branch.');
    } catch (e) {
      if (mounted) notify('Unable to save: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _observeSettingsWrite(Future<void> write) async {
    try {
      await write;
    } catch (error) {
      debugPrint('Transaction settings sync failed: $error');
      if (mounted) {
        notify('Settings are saved on this device but could not sync: $error');
      }
    }
  }

  Future<Map<String, dynamic>?> edit(
    Map<String, dynamic>? row, {
    required String branchId,
  }) async {
    final latestSettings = _latestSettings;
    if (!mounted || latestSettings == null) return null;
    final existing = settingRows(
      settingsForBranch(latestSettings, branchId),
      widget.kind,
    );
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          _SettingEditorDialog(kind: widget.kind, row: row, existing: existing),
    );
  }

  Widget _branchDropdown(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> branches,
    String branchId, {
    bool includeAll = false,
  }) => DropdownButtonFormField<String>(
    initialValue: branchId,
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
              _taxTinDraft = null;
              voided = false;
            });
          },
  );

  bool get _hasAllBranches =>
      !_isBranchScoped &&
      (widget.kind == 'permissions' ||
          widget.kind == 'tax' ||
          widget.kind == 'discounts' ||
          widget.kind == 'payments');

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    constraints: const BoxConstraints(maxWidth: 700),
    backgroundColor: AppColors.surface,
    titleTextStyle: const TextStyle(
      color: AppColors.primaryDeep,
      fontSize: 24,
      fontWeight: FontWeight.bold,
    ),
    title: Row(
      children: [
        Expanded(
          child: Text(
            widget.kind == 'discounts'
                ? 'Discount Control'
                : widget.kind == 'tax'
                ? 'Tax Configuration'
                : widget.kind == 'permissions'
                ? 'Security and Approval'
                : 'Payment Settings',
          ),
        ),
        if (busy) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
          const Text('Saving…', style: TextStyle(fontSize: 12)),
        ],
      ],
    ),
    content: SizedBox(
      width: 620,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _branchesStream,
        builder: (context, branchSnapshot) {
          if (branchSnapshot.hasError) {
            return Text('Unable to load branches: ${branchSnapshot.error}');
          }
          if (!branchSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final branches = branchSnapshot.data!.docs.where((branch) {
            final data = branch.data();
            return isVisibleInBranchPerformance(data);
          }).toList();
          if (branches.isEmpty) {
            return const Text('No active branches are available.');
          }
          if (_isBranchScoped &&
              !branches.any((branch) => branch.id == widget.branchId)) {
            return const Text('The assigned branch is unavailable.');
          }
          final isAllBranches =
              _hasAllBranches && selectedBranchId == allBranchesSelection;
          final branchId = _isBranchScoped
              ? widget.branchId!
              : isAllBranches
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
            stream: _settingsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Unable to load settings: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rawSettings = snapshot.data!.data() ?? {};
              _latestSettings = rawSettings;
              final settingsByBranch = {
                for (final branch in branches)
                  branch.id: settingsForBranch(rawSettings, branch.id),
              };
              final data = settingsByBranch[branchId]!;
              if (widget.kind == 'tax') {
                final branchTaxSettings = settingsByBranch.values.toList();
                final taxEnabled = isAllBranches
                    ? branchTaxSettings.every(
                        (settings) => settings['taxEnabled'] == true,
                      )
                    : data['taxEnabled'] == true;
                final classifications = branchTaxSettings
                    .map(
                      (settings) =>
                          settings['taxClassification']?.toString() ?? 'nonVat',
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
                      if (!_isBranchScoped)
                        _branchDropdown(
                          branches,
                          isAllBranches ? allBranchesSelection : branchId,
                          includeAll: true,
                        ),
                      const SizedBox(height: 8),
                      if (busy) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text(
                          'Saving settings…',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                      SwitchListTile(
                        title: const Text('Enable tax'),
                        value: taxEnabled,
                        onChanged: busy
                            ? null
                            : (value) => saveBranches(targetBranches, {
                                'taxEnabled': value,
                              }, 'Tax setting updated for $branchName.'),
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
                      if (taxEnabled) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: TextFormField(
                            key: ValueKey('tax-tin-$selectedBranchId'),
                            initialValue:
                                isAllBranches &&
                                    branchTaxSettings
                                            .map(
                                              (settings) =>
                                                  '${settings['taxTin'] ?? ''}',
                                            )
                                            .toSet()
                                            .length >
                                        1
                                ? ''
                                : '${data['taxTin'] ?? ''}',
                            keyboardType: TextInputType.text,
                            textCapitalization: TextCapitalization.characters,
                            onChanged: (value) => _taxTinDraft = value,
                            onFieldSubmitted: (value) => saveBranches(
                              targetBranches,
                              {'taxTin': value.trim()},
                              'BIR TIN updated for $branchName.',
                            ),
                            decoration: InputDecoration(
                              labelText: 'BIR TIN (optional)',
                              suffixIcon: IconButton(
                                tooltip: 'Save TIN',
                                onPressed: busy
                                    ? null
                                    : () => saveBranches(
                                        targetBranches,
                                        {
                                          'taxTin':
                                              (_taxTinDraft ??
                                                      '${data['taxTin'] ?? ''}')
                                                  .trim(),
                                        },
                                        'BIR TIN updated for $branchName.',
                                      ),
                                icon: const Icon(Icons.save_outlined),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }
              if (widget.kind == 'permissions') {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_isBranchScoped)
                        _branchDropdown(
                          branches,
                          isAllBranches ? allBranchesSelection : branchId,
                          includeAll: true,
                        ),
                      const SizedBox(height: 8),
                      if (widget.separateRoles)
                        Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ExpansionTile(
                            title: const Text('Admin permissions'),
                            children: adminPermissions.entries
                                .map(
                                  (entry) => SwitchListTile(
                                    title: Text(entry.value),
                                    value: isAllBranches
                                        ? branches.every(
                                            (branch) =>
                                                settingsByBranch[branch
                                                    .id]![entry.key] !=
                                                false,
                                          )
                                        : data[entry.key] != false,
                                    onChanged: busy
                                        ? null
                                        : (value) => saveBranches(
                                            isAllBranches
                                                ? branches
                                                      .map((b) => b.id)
                                                      .toList()
                                                : [branchId],
                                            {entry.key: value},
                                            'Admin permission updated.',
                                          ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ExpansionTile(
                          initiallyExpanded: !widget.separateRoles,
                          title: const Text('Staff permissions'),
                          children: staffPermissions.entries
                              .map(
                                (entry) => SwitchListTile(
                                  title: Text(entry.value),
                                  value: isAllBranches
                                      ? branches.every(
                                          (branch) =>
                                              settingsByBranch[branch.id]![entry
                                                  .key] !=
                                              false,
                                        )
                                      : data[entry.key] != false,
                                  onChanged: busy
                                      ? null
                                      : (value) => isAllBranches
                                            ? saveBranches(
                                                branches
                                                    .map((branch) => branch.id)
                                                    .toList(),
                                                {entry.key: value},
                                                'Permission updated for all branches.',
                                              )
                                            : save(
                                                branchId,
                                                {entry.key: value},
                                                '$branchName permission updated successfully.',
                                              ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                );
              }
              final rows = settingRows(data, widget.kind);
              final targetBranches = isAllBranches
                  ? branches.map((branch) => branch.id).toList()
                  : [branchId];
              final discountsEnabled = isAllBranches
                  ? branches.every(
                      (branch) =>
                          settingsByBranch[branch.id]!['discountsEnabled'] ==
                          true,
                    )
                  : data['discountsEnabled'] == true;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isBranchScoped)
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
                                    )) {
                                  return;
                                }
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
                                ? Text(
                                    '${_formatDiscountPercent(row['percent'])}%',
                                  )
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
                                                )) {
                                                  return;
                                                }
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
