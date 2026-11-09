List<Map<String, dynamic>> mergeStaffAddonOptions({
  required Iterable<Map> beverageOptions,
  required Iterable<Map> allocatedAddons,
}) {
  final byName = <String, Map<String, dynamic>>{};

  for (final raw in allocatedAddons) {
    final addon = Map<String, dynamic>.from(raw);
    final name = '${addon['name'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    addon['staffInventoryDocId'] ??= addon['sourceDocId'];
    byName[name.toLowerCase()] = addon;
  }

  for (final raw in beverageOptions) {
    final addon = Map<String, dynamic>.from(raw);
    final name = '${addon['name'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    byName.putIfAbsent(name.toLowerCase(), () => addon);
  }

  return byName.values.toList();
}
