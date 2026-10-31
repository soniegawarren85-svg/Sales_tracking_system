List<String> staffDashboardImageUrls(Map<String, dynamic> data) {
  final images = <String>[];
  final seenImages = <String>{};
  final seenItems = <String>{};

  String? firstImage(dynamic value) {
    if (value is String) {
      final image = value.trim();
      return image.isEmpty ? null : image;
    }
    if (value is Iterable) {
      for (final entry in value) {
        final image = firstImage(entry);
        if (image != null) return image;
      }
    }
    return null;
  }

  String? imageFor(Map record) {
    for (final key in const ['imageUrl', 'imageUrls', 'images', 'photos']) {
      final image = firstImage(record[key]);
      if (image != null) return image;
    }
    return null;
  }

  final items = data['items'];
  if (items is List) {
    for (final item in items.whereType<Map>()) {
      final id = [
        item['variantId'],
        item['publicId'],
        item['itemPublicId'],
        item['id'],
        item['itemId'],
        item['sourceItemId'],
      ].map((value) => '${value ?? ''}'.trim()).firstWhere(
        (value) => value.isNotEmpty,
        orElse: () => '',
      );
      final name = '${item['name'] ?? ''}'.trim().toLowerCase();
      final variant = '${item['variant'] ?? ''}'.trim().toLowerCase();
      final itemKey = id.isNotEmpty ? '$id|$variant' : '$name|$variant';
      if (itemKey != '|' && !seenItems.add(itemKey.toLowerCase())) continue;

      final image = imageFor(item);
      if (image != null && seenImages.add(image)) images.add(image);
    }
  }

  if (images.isEmpty) {
    final image = imageFor(data);
    if (image != null && seenImages.add(image)) images.add(image);
    for (final key in const ['imageUrls', 'images', 'photos']) {
      final values = data[key];
      if (values is! Iterable) continue;
      for (final value in values) {
        final fallbackImage = firstImage(value);
        if (fallbackImage != null && seenImages.add(fallbackImage)) {
          images.add(fallbackImage);
        }
      }
    }
  }
  return images;
}
