import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/database_backup.dart';
import '../services/save_bytes.dart';

class BackupRestoreDialog extends StatefulWidget {
  const BackupRestoreDialog({super.key});
  @override
  State<BackupRestoreDialog> createState() => _BackupRestoreDialogState();
}

class _BackupRestoreDialogState extends State<BackupRestoreDialog> {
  bool _busy = false;
  String _message = '';
  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => _message = 'Operation failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Backup and Restore'),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Download your application Firestore records as a restorable TXT file. Keep this file outside Firebase so it remains available if records are deleted. Firebase Authentication accounts and uploaded image files are separate and are not included.',
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Download backup'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                    final bytes = await DatabaseBackup.export();
                    final filename =
                        'sales-backup-${DateTime.now().millisecondsSinceEpoch}.txt';
                    final path = kIsWeb
                        ? filename
                        : await FilePicker.platform.saveFile(
                            fileName: filename,
                            bytes: bytes,
                            type: FileType.custom,
                            allowedExtensions: ['txt', 'json'],
                          );
                    if (path == null && !kIsWeb) return;
                    if (path != null) await saveBytes(path, bytes);
                    if (mounted)
                      setState(
                        () => _message =
                            'Backup export finished. Keep the downloaded file safely.',
                      );
                  }),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload backup and restore'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                    final selected = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['txt', 'json'],
                      withData: true,
                    );
                    if (selected == null) return;
                    final records = DatabaseBackup.validate(
                      selected.files.single.bytes!,
                    );
                    if (!context.mounted) return;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Restore database?'),
                        content: Text(
                          'Restore ${records.length} documents? Existing documents with matching IDs will be replaced. Other documents will be kept.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Restore'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    await DatabaseBackup.restore(records);
                    if (mounted)
                      setState(
                        () => _message =
                            'Restored ${records.length} documents successfully.',
                      );
                  }),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message.isNotEmpty) Text(_message),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
