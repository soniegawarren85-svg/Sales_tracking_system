import 'activity_log.dart';
import 'dart:io';
import 'dart:typed_data';

Future<void> saveBytes(String path, Uint8List bytes) async {
  // Mobile file pickers write the supplied bytes through the system provider.
  if (!(Platform.isAndroid || Platform.isIOS)) {
  await File(path).writeAsBytes(bytes, flush: true);
  }
  await ActivityLog.record('file_exported', 'Saved / downloaded report file', details: {'filename': path});
}
