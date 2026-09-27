// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveBytes(String path, Uint8List bytes) async {
  final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes]));
  final anchor = html.AnchorElement(href: url)
    ..download = path
    ..style.display = 'none';
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  await Future<void>.delayed(const Duration(seconds: 1));
  html.Url.revokeObjectUrl(url);
}
