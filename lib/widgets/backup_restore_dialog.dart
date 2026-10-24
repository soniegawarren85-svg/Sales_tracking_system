import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_backup.dart';
import '../services/save_bytes.dart';
import '../theme/app_colors.dart';
import 'inventory_records_table.dart';

class BackupRestoreDialog extends StatefulWidget {
  const BackupRestoreDialog({super.key, this.firestore});

  final FirebaseFirestore? firestore;

  @override
  State<BackupRestoreDialog> createState() => _BackupRestoreDialogState();
}

class _BackupRestoreDialogState extends State<BackupRestoreDialog> {
  bool _busy = false;
  String _stage = '';
  String _message = '';
  String _role = '';
  String _userId = '';
  String? _currentHistoryId;
  Uint8List? _createdBytes;
  BackupManifest? _createdManifest;

  FirebaseFirestore get _database =>
      widget.firestore ?? FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _history =>
      _database.collection('backup_history');
  bool get _isSuperAdmin => _role == 'super_admin';
  bool get _canUseManualBackup => _role == 'admin' || _isSuperAdmin;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _role = preferences.getString('lastRole')?.trim().toLowerCase() ?? '';
      _userId = preferences.getString('lastUserId')?.trim() ?? '';
    });
  }

  Future<void> _createBackup() async {
    if (!_canUseManualBackup) {
      _showMessage('Sign in as an Admin or Super Admin to create a backup.');
      return;
    }
    final historyRef = _history.doc();
    final startedAt = DateTime.now().toUtc();
    setState(() {
      _busy = true;
      _stage = 'Reading Firestore records…';
      _message = '';
    });
    try {
      await historyRef.set({
        'backupId': historyRef.id,
        'backupType': 'manual',
        'status': 'in_progress',
        'createdAt': FieldValue.serverTimestamp(),
        'createdById': _userId,
        'createdByRole': _role,
      });
      final bytes = await DatabaseBackup.export(firestore: _database);
      final manifest = DatabaseBackup.inspect(bytes);
      if (bytes.length > DatabaseBackup.maxBackupBytes) {
        throw const FormatException(
          'Backup exceeds the 50 MB manual export limit.',
        );
      }
      await historyRef.update({
        'backupId': manifest.backupId,
        'status': 'successful',
        'createdAt': Timestamp.fromDate(startedAt),
        'completedAt': FieldValue.serverTimestamp(),
        'createdById': _userId,
        'createdByRole': _role,
        'fileName': 'sales-tracking-${manifest.backupId}.json',
        'fileSizeBytes': bytes.length,
        'documentCount': manifest.documentCount,
        'collectionCounts': manifest.collectionCounts,
        'storageLocation': 'session_memory',
      });
      if (!mounted) return;
      setState(() {
        _createdBytes = bytes;
        _createdManifest = manifest;
        _currentHistoryId = historyRef.id;
        _stage = '';
        _message =
            'Backup file created. Download it to save a copy on this device.';
      });
    } catch (error) {
      try {
        await historyRef.set({
          'backupId': historyRef.id,
          'backupType': 'manual',
          'status': 'failed',
          'createdAt': Timestamp.fromDate(startedAt),
          'createdById': _userId,
          'createdByRole': _role,
          'result':
              'Export failed. Check connection and Firestore permissions.',
        }, SetOptions(merge: true));
      } catch (historyError) {
        debugPrint('Backup failure history could not be saved: $historyError');
      }
      if (mounted) {
        setState(() {
          _stage = '';
          _message = 'Backup failed: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadBackup() async {
    final bytes = _createdBytes;
    final manifest = _createdManifest;
    if (bytes == null || manifest == null) {
      _showMessage('Create a backup before downloading it.');
      return;
    }
    final filename = 'sales-tracking-${manifest.backupId}.json';
    try {
      final path = kIsWeb
          ? filename
          : await FilePicker.platform.saveFile(
              fileName: filename,
              bytes: bytes,
              type: FileType.custom,
              allowedExtensions: const ['json'],
            );
      if (path == null && !kIsWeb) return;
      if (path != null) await saveBytes(path, bytes);
      final historyId = _currentHistoryId;
      if (historyId != null) {
        await _history.doc(historyId).update({
          'storageLocation': 'local_device',
          'downloadedAt': FieldValue.serverTimestamp(),
        });
      }
      if (!mounted) return;
      _showMessage('Backup downloaded. Store the file in a safe location.');
    } catch (error) {
      if (mounted) {
        _showMessage(
          'The file may have downloaded, but the download/history update failed: $error',
        );
      }
    }
  }

  Future<void> _selectBackupForPreview() async {
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt'],
        withData: true,
      );
      if (selected == null) return;
      final bytes = selected.files.single.bytes;
      if (bytes == null) {
        _showMessage('The selected file could not be read.');
        return;
      }
      final manifest = DatabaseBackup.inspect(bytes);
      DatabaseBackup.validate(bytes);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _RestorePreviewDialog(
          manifest: manifest,
          isSuperAdmin: _isSuperAdmin,
        ),
      );
    } catch (error) {
      if (mounted) _showMessage('Backup validation failed: $error');
    }
  }

  void _showMessage(String message) {
    if (mounted) setState(() => _message = message);
  }

  Query<Map<String, dynamic>> _historyQuery() {
    Query<Map<String, dynamic>> query = _history.limit(100);
    if (!_isSuperAdmin) {
      query = query.where('createdById', isEqualTo: _userId);
    }
    return query;
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.background,
    insetPadding: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 1120,
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: _role.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPlanNotice(),
                        const SizedBox(height: 18),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _historyQuery().snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return _errorCard(
                                'Backup history could not be loaded: ${snapshot.error}',
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final entries =
                                snapshot.data!.docs
                                    .map((doc) => doc.data())
                                    .toList()
                                  ..sort(
                                    (a, b) => _dateOf(
                                      b['createdAt'],
                                    ).compareTo(_dateOf(a['createdAt'])),
                                  );
                            final lastSuccessful = entries
                                .where(
                                  (entry) => entry['status'] == 'successful',
                                )
                                .firstOrNull;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildStatusCards(lastSuccessful),
                                const SizedBox(height: 22),
                                _buildSectionTitle(
                                  'Backup actions',
                                  'Manual exports are saved to your device; they are not archived in Firebase.',
                                ),
                                const SizedBox(height: 12),
                                _buildActions(),
                                if (_busy) ...[
                                  const SizedBox(height: 14),
                                  LinearProgressIndicator(
                                    minHeight: 5,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _stage,
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                                if (_message.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  _messageCard(_message),
                                ],
                                const SizedBox(height: 24),
                                _buildSectionTitle(
                                  'Automatic backup',
                                  'Schedules run on Firebase servers and do not require the app to stay open.',
                                ),
                                const SizedBox(height: 12),
                                _buildAutomaticSettings(),
                                const SizedBox(height: 24),
                                _buildSectionTitle(
                                  'Backup history',
                                  'Shows real manual export attempts recorded by this app. Files remain on the device that downloaded them.',
                                ),
                                const SizedBox(height: 12),
                                _buildHistory(entries),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
          ),
          _buildFooter(context),
        ],
      ),
    ),
  );

  Widget _buildHeader(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.primaryDark, AppColors.primary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.shield_outlined, color: Colors.white),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Backup Management',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Create, review, and protect your system data',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: _busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close, color: Colors.white),
        ),
      ],
    ),
  );

  Widget _buildPlanNotice() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E6),
      border: Border.all(color: const Color(0xFFF2D59A)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: Color(0xFF9A6700)),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Current project plan: Spark (confirmed). Automatic scheduling and secure server-side restore are not enabled. Those require an authorized Firebase backend; Cloud Scheduler/Cloud Functions deployment and Cloud Storage can require Blaze billing and incur charges. No paid service has been activated.',
            style: TextStyle(
              color: Color(0xFF664D03),
              height: 1.45,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildStatusCards(Map<String, dynamic>? lastSuccessful) {
    final lastAt = lastSuccessful == null
        ? 'No successful backup yet'
        : _formatDate(lastSuccessful['createdAt']);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final cards = [
          _statusCard(
            'Last successful backup',
            lastAt,
            Icons.check_circle_outline_rounded,
            lastSuccessful == null ? AppColors.textMuted : Colors.green,
          ),
          _statusCard(
            'Next scheduled backup',
            'Not configured',
            Icons.schedule_rounded,
            AppColors.textMuted,
          ),
          _statusCard(
            'Backup status',
            _busy ? 'In progress' : 'Manual only',
            _busy ? Icons.sync_rounded : Icons.info_outline_rounded,
            _busy ? AppColors.primary : AppColors.textMuted,
          ),
        ];
        return compact
            ? Column(
                children: [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: 10),
                  ],
                ],
              )
            : Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    Expanded(child: cards[i]),
                    if (i < cards.length - 1) const SizedBox(width: 12),
                  ],
                ],
              );
      },
    );
  }

  Widget _statusCard(String title, String value, IconData icon, Color color) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildActions() => LayoutBuilder(
    builder: (context, constraints) {
      final cards = [
        _actionCard(
          icon: Icons.add_to_drive_rounded,
          title: 'Create Backup',
          description:
              'Read the app collections and prepare a validated JSON export.',
          buttonLabel: 'Create backup',
          onPressed: _busy ? null : _createBackup,
          color: AppColors.primary,
        ),
        _actionCard(
          icon: Icons.download_rounded,
          title: 'Download Backup',
          description: _createdManifest == null
              ? 'Create a backup first, then save the generated file to this device.'
              : '${_createdManifest!.documentCount} documents · ${_formatBytes(_createdManifest!.byteLength)}',
          buttonLabel: 'Download file',
          onPressed: _busy || _createdBytes == null ? null : _downloadBackup,
          color: const Color(0xFF3949AB),
        ),
        _actionCard(
          icon: Icons.restore_rounded,
          title: 'Upload & Restore',
          description:
              'Upload a file to validate it and preview its date and record counts. Restore is locked until secure backend controls are available.',
          buttonLabel: 'Upload & preview',
          onPressed: _busy ? null : _selectBackupForPreview,
          color: const Color(0xFF00897B),
        ),
      ];
      if (constraints.maxWidth < 760) {
        return Column(
          children: [
            for (final card in cards) ...[card, const SizedBox(height: 12)],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i]),
            if (i < cards.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    },
  );

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String description,
    required String buttonLabel,
    required VoidCallback? onPressed,
    required Color color,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 58,
          child: Text(
            description,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(buttonLabel),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildAutomaticSettings() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Enable automatic backup',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('Unavailable on the current Spark setup'),
          value: false,
          onChanged: null,
        ),
        const Divider(),
        DropdownButtonFormField<String>(
          initialValue: 'daily',
          decoration: const InputDecoration(
            labelText: 'Backup frequency',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'daily', child: Text('Daily')),
            DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
            DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
          ],
          onChanged: null,
        ),
        const SizedBox(height: 10),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Not scheduled. Enabling this requires a deployed server-side scheduler, verified billing plan, backup storage bucket, retention policy, and budget alerts.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildHistory(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          children: [
            Icon(Icons.inventory_2_outlined, size: 36, color: AppColors.rose),
            SizedBox(height: 8),
            Text(
              'No backup attempts yet',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 4),
            Text(
              'Completed or failed manual export attempts will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 980,
          child: InventoryRecordsTable(
            headings: const [
              'Backup Date & Time',
              'Type',
              'File Size',
              'Status',
              'Download',
              'Restore',
            ],
            flex: const {0: 1.5, 1: .7, 2: .8, 3: .8, 4: 1, 5: 1},
            rows: entries.map((entry) {
              final status = '${entry['status'] ?? 'unknown'}';
              final bytes = entry['fileSizeBytes'];
              final downloadedToDevice =
                  entry['storageLocation'] == 'local_device';
              final isCurrentSession =
                  _createdBytes != null &&
                  _createdManifest?.backupId == entry['backupId'];
              return <Widget>[
                Text(_formatDate(entry['createdAt'])),
                Text('${entry['backupType'] ?? 'Manual'}'),
                Text(bytes is num ? _formatBytes(bytes.toInt()) : '—'),
                _statusPill(status),
                Tooltip(
                  message: isCurrentSession
                      ? 'Download the generated backup file.'
                      : downloadedToDevice
                      ? 'This file was downloaded on another session/device and is not archived in Firebase.'
                      : 'This export is no longer in memory and is not stored in Firebase.',
                  child: TextButton.icon(
                    onPressed: isCurrentSession ? _downloadBackup : null,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: Text(
                      isCurrentSession
                          ? 'Download'
                          : downloadedToDevice
                          ? 'On device'
                          : 'Not archived',
                    ),
                  ),
                ),
                Tooltip(
                  message: _isSuperAdmin
                      ? 'Restore requires the secure server-side workflow.'
                      : 'Only the Super Admin may restore a backup.',
                  child: TextButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.lock_outline_rounded, size: 16),
                    label: const Text('Locked'),
                  ),
                ),
              ];
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    final successful = status == 'successful';
    final failed = status == 'failed';
    final label = switch (status) {
      'successful' => 'Successful',
      'failed' => 'Failed',
      'in_progress' => 'In Progress',
      _ => status,
    };
    final color = successful
        ? Colors.green
        : failed
        ? Colors.red
        : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.shade700,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AppColors.primaryDeep,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          height: 1.4,
        ),
      ),
    ],
  );

  Widget _messageCard(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surfaceTint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: const TextStyle(color: AppColors.text)),
  );

  Widget _errorCard(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFEBEE),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: const TextStyle(color: Colors.red)),
  );

  Widget _buildFooter(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Text(
            'Manual exports exclude authentication credentials and reset tokens. Uploaded image files and Firebase Authentication accounts are not included; image references stored in Firestore remain in the export.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  DateTime _dateOf(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime(1970);
    return DateTime(1970);
  }

  String _formatDate(dynamic value) {
    final date = _dateOf(value).toLocal();
    if (date.year == 1970) return 'In progress';
    final local = MaterialLocalizations.of(context);
    return '${local.formatMediumDate(date)} '
        '${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _RestorePreviewDialog extends StatelessWidget {
  const _RestorePreviewDialog({
    required this.manifest,
    required this.isSuperAdmin,
  });

  final BackupManifest manifest;
  final bool isSuperAdmin;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Backup preview'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _previewLine(
              'Backup date',
              MaterialLocalizations.of(
                context,
              ).formatMediumDate(manifest.createdAt.toLocal()),
            ),
            _previewLine('Backup ID', manifest.backupId),
            _previewLine('Total records', '${manifest.documentCount}'),
            _previewLine('File size', '${manifest.byteLength} bytes'),
            const SizedBox(height: 10),
            const Text(
              'Records by collection',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final entry in manifest.collectionCounts.entries)
              _previewLine(entry.key, '${entry.value}'),
            const SizedBox(height: 12),
            Text(
              isSuperAdmin
                  ? 'Validation passed. Restore is still unavailable until a secure backend can reauthenticate you, create a safety backup, lock writes, and verify recovery.'
                  : 'Only the Super Admin may restore a backup. This account can validate and preview the file only.',
              style: const TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.lock_outline_rounded),
        label: const Text('Restore unavailable'),
      ),
    ],
  );

  Widget _previewLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 126,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
