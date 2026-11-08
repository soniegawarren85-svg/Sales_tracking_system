import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_backup.dart';
import '../services/encrypted_backup.dart';
import '../services/save_bytes.dart';
import '../services/super_admin.dart';
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
  String _historySearch = '';
  String _statusFilter = 'All';
  bool _newestFirst = true;
  DateTimeRange? _historyDateRange;
  String _role = '';
  String _userId = '';
  String? _currentHistoryId;
  Uint8List? _createdBytes;
  BackupManifest? _createdManifest;
  Uint8List? _importedClearBytes;
  Uint8List? _importedEncryptedBytes;
  BackupManifest? _importedManifest;
  String? _importedHistoryId;
  bool _restoreRunning = false;

  FirebaseFirestore get _database =>
      widget.firestore ?? FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _history =>
      _database.collection('backup_history');
  bool get _isSuperAdmin => _role == 'super_admin';
  bool get _canUseManualBackup => _isSuperAdmin;

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
      _showMessage('Only the Super Admin can create a system backup.');
      return;
    }
    final details = await _requestBackupDetails();
    if (details == null || !mounted) return;
    final backupName = details.$1;
    final password = details.$2;
    bool verified;
    try {
      verified = await SuperAdmin.reauthenticateForBackup(
        password,
        database: _database,
      );
    } catch (error) {
      _showMessage('Firebase password verification failed: $error');
      return;
    }
    if (!verified) {
      _showMessage('Firebase Authentication could not verify that password.');
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
      final clearBytes = await DatabaseBackup.export(
        firestore: _database,
        backupName: backupName,
        backupId: historyRef.id,
        onProgress: (completed, total, collection) {
          if (mounted) {
            setState(
              () => _stage =
                  'Reading $collection ($completed of $total collections)',
            );
          }
        },
      );
      final manifest = DatabaseBackup.inspect(clearBytes);
      if (clearBytes.length > DatabaseBackup.maxBackupBytes) {
        throw const FormatException(
          'Backup exceeds the 50 MB manual export limit.',
        );
      }
      if (mounted) setState(() => _stage = 'Encrypting and validating file');
      final bytes = await EncryptedBackup.encrypt(clearBytes, password);
      final verifiedManifest = DatabaseBackup.inspect(
        await EncryptedBackup.decrypt(bytes, password),
      );
      if (verifiedManifest.documentCount != manifest.documentCount ||
          verifiedManifest.backupId != manifest.backupId) {
        throw const FormatException('Encrypted backup validation failed.');
      }
      await historyRef.update({
        'backupId': historyRef.id,
        'backupName': manifest.backupName,
        'status': 'successful',
        'createdAt': Timestamp.fromDate(startedAt),
        'completedAt': FieldValue.serverTimestamp(),
        'createdById': _userId,
        'createdByRole': _role,
        'fileName': 'sales-tracking-${historyRef.id}.stbackup',
        'fileSizeBytes': bytes.length,
        'backupVersion': 1,
        'applicationVersion': manifest.applicationVersion,
        'encryption': 'PBKDF2-HMAC-SHA256 + AES-256-GCM',
        'documentCount': manifest.documentCount,
        'collectionCounts': manifest.collectionCounts,
        'storageLocation': 'local-only',
        'fileAvailable': false,
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
      await _writeAudit('backup_created', historyRef.id, {
        'documentCount': manifest.documentCount,
        'fileSizeBytes': bytes.length,
      });
    } catch (error) {
      await _writeAudit('backup_create_failed', historyRef.id, {
        'errorType': error.runtimeType.toString(),
      });
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
    if (!_isSuperAdmin) {
      _showMessage('Only the Super Admin may download system backups.');
      return;
    }
    final bytes = _createdBytes;
    final manifest = _createdManifest;
    if (bytes == null || manifest == null) {
      _showMessage('Create a backup before downloading it.');
      return;
    }
    final filename =
        'sales-tracking-${_currentHistoryId ?? manifest.backupId}.stbackup';
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
          'fileDownloaded': true,
          'downloadedAt': FieldValue.serverTimestamp(),
        });
      }
      await _writeAudit('backup_downloaded', historyId ?? manifest.backupId);
      if (!mounted) return;
      _showMessage(
        'Encrypted backup downloaded. Keep the password separately.',
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          'The file may have downloaded, but the download/history update failed: $error',
        );
      }
    }
  }

  Future<void> _selectBackupForPreview() async {
    if (!_isSuperAdmin) {
      _showMessage('Only the Super Admin may import system backups.');
      return;
    }
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['stbackup'],
        withData: true,
      );
      if (selected == null) return;
      final bytes = selected.files.single.bytes;
      if (bytes == null) {
        _showMessage('The selected file could not be read.');
        return;
      }
      final password = await _requestBackupPassword();
      if (password == null || !mounted) return;
      final clearBytes = await EncryptedBackup.decrypt(bytes, password);
      final manifest = DatabaseBackup.inspect(clearBytes);
      final documents = DatabaseBackup.validate(
        clearBytes,
        firestore: _database,
      );
      final importedId = _history.doc().id;
      await _history.doc(importedId).set({
        'backupId': importedId,
        'sourceBackupId': manifest.backupId,
        'backupName': manifest.backupName,
        'backupType': 'imported',
        'status': 'imported',
        'createdAt': Timestamp.fromDate(manifest.createdAt),
        'importedAt': FieldValue.serverTimestamp(),
        'importedById': _userId,
        'importedByRole': _role,
        'backupVersion': 1,
        'applicationVersion': manifest.applicationVersion,
        'documentCount': manifest.documentCount,
        'fileSizeBytes': bytes.length,
        'fileAvailable': false,
      });
      await _writeAudit('backup_imported', importedId, {
        'documentCount': manifest.documentCount,
      });
      _importedClearBytes = clearBytes;
      _importedEncryptedBytes = bytes;
      _importedManifest = manifest;
      _importedHistoryId = importedId;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _RestorePreviewDialog(
          manifest: manifest,
          fileIntegrityValid: documents.length == manifest.documentCount,
          onRestore: _restoreImportedBackup,
        ),
      );
    } catch (error) {
      await _writeAudit('backup_import_failed', 'unavailable', {
        'errorType': error.runtimeType.toString(),
      });
      if (mounted) _showMessage('Backup validation failed: $error');
    }
  }

  Future<(String, String)?> _requestBackupDetails() async {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create encrypted backup'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Backup name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Super Admin password',
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Firebase Authentication verifies this password. It encrypts the file and is never saved.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final password = passwordController.text;
              if (name.isEmpty || password.isEmpty) return;
              Navigator.pop(context, (name, password));
            },
            child: const Text('Verify and create'),
          ),
        ],
      ),
    );
    nameController.dispose();
    passwordController.dispose();
    return result;
  }

  Future<String?> _requestBackupPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlock backup'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Original backup encryption password',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => controller.text.isEmpty
                ? null
                : Navigator.pop(context, controller.text),
            child: const Text('Decrypt and validate'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _writeAudit(
    String action,
    String backupId, [
    Map<String, Object?> extra = const {},
  ]) async {
    try {
      await _database.collection('backup_audit_logs').add({
        'action': action,
        'backupId': backupId,
        'actorId': _userId,
        'actorRole': _role,
        'createdAt': FieldValue.serverTimestamp(),
        ...extra,
      });
    } catch (error) {
      debugPrint(
        'Backup activity log could not be saved: ${error.runtimeType}',
      );
    }
  }

  Future<void> _restoreImportedBackup() async {
    final manifest = _importedManifest;
    final clearBytes = _importedClearBytes;
    if (!_isSuperAdmin || manifest == null || clearBytes == null) {
      _showMessage(
        'Only a validated backup can be restored by the Super Admin.',
      );
      return;
    }
    if (_restoreRunning || _busy) return;
    final password = await _requestCurrentPassword();
    if (password == null || !mounted) return;
    if (!await SuperAdmin.reauthenticateForBackup(
      password,
      database: _database,
    )) {
      _showMessage(
        'Firebase Authentication could not verify the current password.',
      );
      return;
    }

    final lockRef = _database.collection('backup_restore_locks').doc('system');
    final owner = '${SuperAdmin.id}-${DateTime.now().microsecondsSinceEpoch}';
    var acquired = false;
    setState(() {
      _busy = true;
      _restoreRunning = true;
      _stage = 'Creating a current-system safety backup';
      _message = '';
    });
    try {
      await _database.runTransaction((transaction) async {
        final lock = await transaction.get(lockRef);
        final expiry = lock.data()?['expiresAt'];
        final lockedUntil = expiry is Timestamp
            ? expiry.toDate()
            : DateTime(1970);
        if (lock.exists && lockedUntil.isAfter(DateTime.now())) {
          throw StateError('Another restore is already in progress.');
        }
        transaction.set(lockRef, {
          'owner': owner,
          'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(hours: 2)),
          ),
          'startedAt': FieldValue.serverTimestamp(),
        });
      });
      acquired = true;

      final safetyClear = await DatabaseBackup.export(
        firestore: _database,
        backupName: 'Before restore ${DateTime.now().toIso8601String()}',
      );
      final safetyManifest = DatabaseBackup.inspect(safetyClear);
      final safetyFile = await EncryptedBackup.encrypt(safetyClear, password);
      final check = DatabaseBackup.inspect(
        await EncryptedBackup.decrypt(safetyFile, password),
      );
      if (check.documentCount != safetyManifest.documentCount) {
        throw const FormatException(
          'Safety backup validation failed. Restore was stopped.',
        );
      }
      final safetyName =
          'sales-tracking-pre-restore-${DateTime.now().millisecondsSinceEpoch}.stbackup';
      final savedPath = kIsWeb
          ? safetyName
          : await FilePicker.platform.saveFile(
              fileName: safetyName,
              bytes: safetyFile,
              type: FileType.custom,
              allowedExtensions: const ['stbackup'],
            );
      if (savedPath == null && !kIsWeb) {
        throw StateError('Save the safety backup to continue with restore.');
      }
      if (savedPath != null) await saveBytes(savedPath, safetyFile);
      final safetyRef = _history.doc();
      await safetyRef.set({
        'backupId': safetyRef.id,
        'backupName': safetyManifest.backupName,
        'backupType': 'pre_restore_safety',
        'status': 'successful',
        'createdAt': Timestamp.fromDate(safetyManifest.createdAt),
        'createdById': _userId,
        'createdByRole': _role,
        'fileName': safetyName,
        'fileSizeBytes': safetyFile.length,
        'backupVersion': 1,
        'fileDownloaded': true,
        'fileAvailable': false,
        'documentCount': safetyManifest.documentCount,
        'collectionCounts': safetyManifest.collectionCounts,
      });
      await _writeAudit('pre_restore_backup_created', safetyRef.id, {
        'documentCount': safetyManifest.documentCount,
      });

      final documents = DatabaseBackup.validate(
        clearBytes,
        firestore: _database,
      );
      final total = documents.length;
      await DatabaseBackup.restoreMerge(
        documents,
        firestore: _database,
        onProgress: (completed, total) {
          if (mounted) {
            setState(() => _stage = 'Merging documents ($completed of $total)');
          }
        },
      );
      await _writeAudit('backup_restored', manifest.backupId, {
        'documentCount': total,
        'restoreMode': 'merge',
      });
      if (_importedHistoryId != null) {
        await _history.doc(_importedHistoryId).update({
          'status': 'restored',
          'restoredAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) {
        setState(
          () => _message =
              'Restore completed. Existing document IDs were merged; no documents were deleted.',
        );
      }
    } catch (error) {
      await _writeAudit('backup_restore_failed', manifest.backupId, {
        'errorType': error.runtimeType.toString(),
      });
      if (mounted) setState(() => _message = 'Restore stopped: $error');
    } finally {
      if (acquired) {
        try {
          await _database.runTransaction((transaction) async {
            final lock = await transaction.get(lockRef);
            if (lock.data()?['owner'] == owner) transaction.delete(lockRef);
          });
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _restoreRunning = false;
          _stage = '';
        });
      }
    }
  }

  Future<String?> _requestCurrentPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify Super Admin'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Current Firebase password',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => controller.text.isEmpty
                ? null
                : Navigator.pop(context, controller.text),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
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
                : !_isSuperAdmin
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Backup management is available to the Super Admin only.',
                      ),
                    ),
                  )
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
                                _buildStatusCards(entries, lastSuccessful),
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
                                  'Backup history',
                                  'History metadata is stored in Firestore. Backup files stay on the device where you saved them.',
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
            'Manual backups only. Files are encrypted and downloaded to your device; Firestore stores history metadata only. Restore merges records by document ID and never deletes documents. Uploaded image files and Firebase Authentication accounts are not included.',
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

  Widget _buildStatusCards(
    List<Map<String, dynamic>> entries,
    Map<String, dynamic>? lastSuccessful,
  ) {
    final lastAt = lastSuccessful == null
        ? 'No successful backup yet'
        : _formatDate(lastSuccessful['createdAt']);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final totalSize = entries.fold<int>(0, (total, row) {
          final size = row['fileSizeBytes'];
          return total + (size is num ? size.toInt() : 0);
        });
        final cards = [
          _statusCard(
            'Total backups',
            '${entries.where((e) => e['status'] == 'successful').length}',
            Icons.backup_outlined,
            AppColors.primary,
          ),
          _statusCard(
            'Latest backup',
            entries.isEmpty
                ? 'None yet'
                : _formatDate(entries.first['createdAt']),
            Icons.history_rounded,
            AppColors.primary,
          ),
          _statusCard(
            'Recorded file size',
            _formatBytes(totalSize),
            Icons.storage_rounded,
            AppColors.primary,
          ),
          _statusCard(
            'Last successful backup',
            lastAt,
            Icons.check_circle_outline_rounded,
            lastSuccessful == null ? AppColors.textMuted : Colors.green,
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
            : Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final card in cards)
                    SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: card,
                    ),
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
              'Verify your password, export supported Firestore data, and encrypt a new backup file.',
          buttonLabel: 'Create backup',
          onPressed: _busy ? null : _createBackup,
          color: AppColors.primary,
        ),
        _actionCard(
          icon: Icons.download_rounded,
          title: 'Download Backup',
          description: _createdManifest == null
              ? 'Create a backup first, then save its encrypted file to this device.'
              : '${_createdManifest!.documentCount} documents · ${_formatBytes(_createdManifest!.byteLength)}',
          buttonLabel: 'Download file',
          onPressed: _busy || _createdBytes == null ? null : _downloadBackup,
          color: const Color(0xFF3949AB),
        ),
        _actionCard(
          icon: Icons.restore_rounded,
          title: 'Import Backup',
          description:
              'Select an encrypted backup, enter its original password, validate it, then preview a merge restore.',
          buttonLabel: 'Import and preview',
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

  Widget _buildHistory(List<Map<String, dynamic>> entries) {
    final filtered =
        entries.where((entry) {
          final query = _historySearch.trim().toLowerCase();
          final date = _dateOf(entry['createdAt']);
          return (query.isEmpty ||
                  '${entry['backupName'] ?? ''} ${entry['backupId'] ?? ''}'
                      .toLowerCase()
                      .contains(query)) &&
              (_statusFilter == 'All' || entry['status'] == _statusFilter) &&
              (_historyDateRange == null ||
                  (!date.isBefore(_historyDateRange!.start) &&
                      !date.isAfter(
                        _historyDateRange!.end.add(const Duration(days: 1)),
                      )));
        }).toList()..sort((a, b) {
          final order = _dateOf(
            a['createdAt'],
          ).compareTo(_dateOf(b['createdAt']));
          return _newestFirst ? -order : order;
        });
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
    if (filtered.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: Text('No backups match these filters.')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search backup name or ID',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _historySearch = value),
              ),
            ),
            DropdownButton<String>(
              value: _statusFilter,
              items:
                  const ['All', 'successful', 'failed', 'imported', 'restored']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value == 'All' ? 'All statuses' : value),
                        ),
                      )
                      .toList(),
              onChanged: (value) =>
                  setState(() => _statusFilter = value ?? 'All'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateUtils.dateOnly(DateTime.now());
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: now,
                  initialDateRange: _historyDateRange,
                );
                if (range != null && mounted) {
                  setState(() => _historyDateRange = range);
                }
              },
              icon: const Icon(Icons.date_range),
              label: Text(
                _historyDateRange == null ? 'Date range' : 'Filtered',
              ),
            ),
            IconButton(
              tooltip: _newestFirst ? 'Newest first' : 'Oldest first',
              onPressed: () => setState(() => _newestFirst = !_newestFirst),
              icon: Icon(
                _newestFirst ? Icons.south_rounded : Icons.north_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1420,
              child: InventoryRecordsTable(
                headings: const [
                  'Backup Name',
                  'Backup ID',
                  'Date Created',
                  'Time Created',
                  'Created By',
                  'File Size',
                  'Version',
                  'Status',
                  'Actions',
                ],
                flex: const {
                  0: 1.2,
                  1: 1.2,
                  2: .8,
                  3: .7,
                  4: 1,
                  5: .7,
                  6: .5,
                  7: .7,
                  8: 1.3,
                },
                rows: filtered.map((entry) {
                  final status = '${entry['status'] ?? 'unknown'}';
                  final bytes = entry['fileSizeBytes'];
                  final isCurrentCreated =
                      _createdBytes != null &&
                      _currentHistoryId == entry['backupId'];
                  final isCurrentImported =
                      _importedEncryptedBytes != null &&
                      _importedHistoryId == entry['backupId'];
                  final fileBytes = isCurrentCreated
                      ? _createdBytes
                      : isCurrentImported
                      ? _importedEncryptedBytes
                      : null;
                  final date = _dateOf(entry['createdAt']).toLocal();
                  final hasDate = date.year != 1970;
                  return <Widget>[
                    Text(
                      '${entry['backupName'] ?? entry['backupType'] ?? 'Manual backup'}',
                    ),
                    SelectableText('${entry['backupId'] ?? '—'}'),
                    Text(
                      hasDate
                          ? MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(date)
                          : '—',
                    ),
                    Text(
                      hasDate
                          ? MaterialLocalizations.of(
                              context,
                            ).formatTimeOfDay(TimeOfDay.fromDateTime(date))
                          : '—',
                    ),
                    Text(
                      '${entry['createdByRole'] ?? entry['importedByRole'] ?? ''} · ${entry['createdById'] ?? entry['importedById'] ?? '—'}',
                    ),
                    Text(bytes is num ? _formatBytes(bytes.toInt()) : '—'),
                    Text('${entry['backupVersion'] ?? '1'}'),
                    _statusPill(status),
                    Row(
                      children: [
                        IconButton(
                          tooltip: fileBytes == null
                              ? 'File is not available in this session; import it from device'
                              : 'Download',
                          onPressed: fileBytes == null
                              ? null
                              : () => _downloadHistoryFile(entry, fileBytes),
                          icon: const Icon(Icons.download_outlined),
                        ),
                        IconButton(
                          tooltip: 'View details',
                          onPressed: () => _showBackupDetails(entry),
                          icon: const Icon(Icons.info_outline),
                        ),
                        IconButton(
                          tooltip: 'Activity details',
                          onPressed: () => _showBackupActivityDetails(
                            '${entry['backupId'] ?? ''}',
                          ),
                          icon: const Icon(Icons.history_rounded),
                        ),
                        IconButton(
                          tooltip: 'Import this file to enable restore',
                          onPressed:
                              isCurrentImported &&
                                  status == 'imported' &&
                                  !_busy
                              ? _confirmRestoreFromHistory
                              : null,
                          icon: const Icon(Icons.restore_rounded),
                        ),
                      ],
                    ),
                  ];
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _downloadHistoryFile(
    Map<String, dynamic> entry,
    Uint8List bytes,
  ) async {
    if (!_isSuperAdmin) return;
    final filename =
        '${entry['fileName'] ?? 'sales-tracking-${entry['backupId']}.stbackup'}';
    try {
      final path = kIsWeb
          ? filename
          : await FilePicker.platform.saveFile(
              fileName: filename,
              bytes: bytes,
              type: FileType.custom,
              allowedExtensions: const ['stbackup'],
            );
      if (path == null && !kIsWeb) return;
      if (path != null) await saveBytes(path, bytes);
      await _writeAudit('backup_downloaded', '${entry['backupId'] ?? ''}');
      if (mounted) _showMessage('Encrypted backup file downloaded.');
    } catch (error) {
      if (mounted) _showMessage('Download failed: $error');
    }
  }

  Future<void> _confirmRestoreFromHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm merge restore'),
        content: const Text(
          'Matching fields can be replaced by backup values. Documents absent from the backup remain, and nothing is deleted. A fresh encrypted safety backup will be saved first. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _restoreImportedBackup();
  }

  Future<void> _showBackupDetails(Map<String, dynamic> entry) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${entry['backupName'] ?? 'Backup details'}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in <String, String>{
                'Backup ID': '${entry['backupId'] ?? '—'}',
                'Created': _formatDate(entry['createdAt']),
                'Created by':
                    '${entry['createdByRole'] ?? entry['importedByRole'] ?? '—'} · ${entry['createdById'] ?? entry['importedById'] ?? '—'}',
                'Size': entry['fileSizeBytes'] is num
                    ? _formatBytes((entry['fileSizeBytes'] as num).toInt())
                    : '—',
                'Documents': '${entry['documentCount'] ?? '—'}',
                'Version': '${entry['backupVersion'] ?? '1'}',
                'Status': '${entry['status'] ?? 'unknown'}',
                'File availability':
                    _currentHistoryId == entry['backupId'] ||
                        _importedHistoryId == entry['backupId']
                    ? 'Available in this session'
                    : 'Not archived in Firebase; check original device',
              }.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('${row.key}: ${row.value}'),
                ),
              const SizedBox(height: 8),
              const Text(
                'Uploaded images and Firebase Authentication accounts are excluded; Firestore image references remain in the file.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBackupActivityDetails(String backupId) async {
    try {
      final snapshot = await _database
          .collection('backup_audit_logs')
          .where('backupId', isEqualTo: backupId)
          .get(const GetOptions(source: Source.server));
      final rows = snapshot.docs.map((doc) => doc.data()).toList()
        ..sort(
          (a, b) => _dateOf(b['createdAt']).compareTo(_dateOf(a['createdAt'])),
        );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Backup activity details'),
          content: SizedBox(
            width: 520,
            child: rows.isEmpty
                ? const Text(
                    'No activity records are available for this backup.',
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return ListTile(
                        leading: const Icon(Icons.history_rounded),
                        title: Text('${row['action'] ?? 'Activity'}'),
                        subtitle: Text(
                          '${row['actorRole'] ?? 'Super Admin'} · ${row['actorId'] ?? '—'} · ${_formatDate(row['createdAt'])}',
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
        ),
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Backup activity logs could not be loaded: $error');
      }
    }
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
    required this.fileIntegrityValid,
    required this.onRestore,
  });

  final BackupManifest manifest;
  final bool fileIntegrityValid;
  final Future<void> Function() onRestore;

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
            _previewLine('Backup name', manifest.backupName),
            _previewLine('Backup version', '1'),
            _previewLine('App version', manifest.applicationVersion),
            _previewLine('Total records', '${manifest.documentCount}'),
            _previewLine('File size', '${manifest.byteLength} bytes'),
            _previewLine('Collections', '${manifest.collectionCounts.length}'),
            _previewLine(
              'File integrity',
              fileIntegrityValid ? 'Valid (AES-GCM authenticated)' : 'Invalid',
            ),
            const SizedBox(height: 10),
            const Text(
              'Records by collection',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final entry in manifest.collectionCounts.entries)
              _previewLine(entry.key, '${entry.value}'),
            const SizedBox(height: 12),
            const Text(
              'Restore mode: merge by document ID. Fields present in the backup replace matching fields; fields absent from it remain. No production documents are deleted. A fresh encrypted safety backup must be saved before restore.',
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
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
        onPressed: !fileIntegrityValid
            ? null
            : () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Confirm merge restore'),
                    content: const Text(
                      'This will merge backup data into the live database. Matching fields can be replaced. Documents will not be deleted. A safety backup will be saved first. Continue?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Continue'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  Navigator.pop(context);
                  await onRestore();
                }
              },
        icon: const Icon(Icons.restore_rounded),
        label: const Text('Restore with merge'),
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
