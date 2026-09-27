import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

Uint8List _thumbnail(Uint8List bytes) {
  final original = img.decodeImage(bytes);
  if (original == null) throw const FormatException('Unsupported image');
  final decoded = img.bakeOrientation(original);
  final resized = img.copyResize(
    decoded,
    width: decoded.width >= decoded.height ? 640 : null,
    height: decoded.height > decoded.width ? 640 : null,
  );
  return Uint8List.fromList(img.encodeJpg(resized, quality: 72));
}

/// Resize once before uploading. A bounded fallback keeps small catalog photos
/// usable when Storage is unavailable, without storing the original full image.
Future<String?> uploadCatalogImage(
  Uint8List? bytes, {
  String folder = 'catalog_images',
}) async {
  if (bytes == null || bytes.isEmpty) return null;
  final compressed = await compute(_thumbnail, bytes);
  final ref = FirebaseStorage.instance.ref(
    '$folder/${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  final task = ref.putData(
    compressed,
    SettableMetadata(contentType: 'image/jpeg'),
  );
  try {
    return await (() async {
      await task;
      return ref.getDownloadURL();
    })().timeout(const Duration(seconds: 8));
  } catch (_) {
    // Restrict fallback size: multiple variants can share one Firestore document.
    if (compressed.length > 120000) return null;
    return 'data:image/jpeg;base64,${base64Encode(compressed)}';
  }
}
