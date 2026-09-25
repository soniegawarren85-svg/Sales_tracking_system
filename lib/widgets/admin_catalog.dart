import '../services/public_item_id.dart';
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

String catalogCategoryKey(Map data) =>
    '${data['name'] ?? ''}'.trim().toLowerCase();

bool catalogItemActive(Map item, DateTime now) {
  final raw = item['expirationDate'];
  final expiry = raw is Timestamp ? raw.toDate() : DateTime.tryParse('$raw');
  return item['isDeleted'] != true &&
      item['isVoided'] != true &&
      (expiry == null || !expiry.isBefore(DateUtils.dateOnly(now)));
}

List<Map<String, dynamic>> currentCatalogCategories(
  List<Map<String, dynamic>> products, {
  DateTime? now,
}) {
  final categories = <String, Map<String, dynamic>>{};
  for (final product in products) {
    if (product['isDeleted'] == true ||
        product['isVoided'] == true ||
        product['isBundle'] == true)
      continue;
    if (!(product['items'] as List? ?? []).whereType<Map>().any(
      (item) => catalogItemActive(item, now ?? DateTime.now()),
    ))
      continue;
    categories.putIfAbsent(catalogCategoryKey(product), () => product);
  }
  return categories.values.toList();
}

List<Map<String, dynamic>> catalogBundleContents(
  Map bundle, [
  List<Map<String, dynamic>> products = const [],
]) {
  return (bundle['items'] as List? ?? []).whereType<Map>().map((raw) {
    final item = Map<String, dynamic>.from(raw);
    if ('${item['expirationDate'] ?? ''}'.isNotEmpty) return item;
    final matches = <Map>[];
    for (final product in products.where(
      (product) => product['isBundle'] != true,
    )) {
      if (item['sourceInventoryId'] != null &&
          item['sourceInventoryId'] != product['id'])
        continue;
      if (item['parentName'] != null &&
          catalogCategoryKey(product) !=
              '${item['parentName']}'.trim().toLowerCase())
        continue;
      for (final variant
          in (product['items'] as List? ?? []).whereType<Map>()) {
        final id = item['variantId'] ?? item['itemId'];
        if (id != null
            ? (variant['id'] ?? variant['variantId']) == id
            : variant['name'] == item['name'])
          matches.add(variant);
      }
    }
    if (matches.length == 1) {
      item['expirationDate'] = matches.single['expirationDate'];
      item['imageUrl'] ??= matches.single['imageUrl'];
    }
    return item;
  }).toList();
}

String catalogExpiryLabel(AdminCatalogEntry entry) {
  final values = entry.type == 'Bundle'
      ? catalogBundleContents(entry.source)
      : [entry.details];
  final dates =
      values
          .map((item) => '${item['expirationDate'] ?? ''}'.split('T').first)
          .where((date) => date.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  if (dates.isEmpty)
    return '${entry.source['expirationDate'] ?? ''}'.isEmpty
        ? 'Not recorded'
        : '${entry.source['expirationDate']}'.split('T').first;
  return dates.join('\n');
}

class AdminCatalogEntry {
  const AdminCatalogEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.source,
    required this.images,
    this.stock,
    this.details = const {},
    this.available = true,
  });
  final String id, name, type;
  final Map<String, dynamic> source;
  final Map<String, dynamic> details;
  final List<String> images;
  final int? stock;
  final bool available;
}

List<AdminCatalogEntry> adminCatalogEntries(
  List<Map<String, dynamic>> products,
  List<Map<String, dynamic>> coffees, {
  bool gallery = false,
  DateTime? now,
}) {
  final day = now ?? DateTime.now();
  int number(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
  String identifier(List<dynamic> values) => values
      .map((value) => publicItemId(value?.toString().trim() ?? ''))
      .firstWhere((value) => value.isNotEmpty, orElse: () => 'Not recorded');
  bool active(Map item) => catalogItemActive(item, day);

  List<String> images(Map data, List<Map> items) =>
      [data['imageUrl'], ...items.map((item) => item['imageUrl'])]
          .map((url) => url?.toString() ?? '')
          .where((url) => url.isNotEmpty)
          .toSet()
          .toList();
  final result = <AdminCatalogEntry>[];
  for (final data in products.where(
    (data) => data['isDeleted'] != true && data['isVoided'] != true,
  )) {
    final items = (data['items'] as List? ?? [])
        .whereType<Map>()
        .where(active)
        .toList();
    final bundle =
        data['isBundle'] == true ||
        (data['bundleId']?.toString().isNotEmpty ?? false);
    if (bundle) {
      final instances = (data['bundleInstances'] as List? ?? [])
          .whereType<Map>()
          .toList();
      final stock = instances.isEmpty
          ? number(data['bundleCount'])
          : instances
                .where(
                  (item) =>
                      active(item) &&
                      ['', 'available'].contains(
                        item['status']?.toString().toLowerCase() ?? '',
                      ),
                )
                .length;
      result.add(
        AdminCatalogEntry(
          id: identifier([data['bundleId'], data['id']]),
          name: data['name']?.toString() ?? 'Bundle',
          type: 'Bundle',
          source: {...data, 'items': catalogBundleContents(data, products)},
          details: data,
          images: images(data, items),
          stock: stock,
          available: stock > 0,
        ),
      );
    } else if (gallery && items.isNotEmpty) {
      final stock = items.fold<int>(
        0,
        (sum, item) => sum + number(item['stock'] ?? item['startingStock']),
      );
      result.add(
        AdminCatalogEntry(
          id: identifier([data['categoryId'], data['id']]),
          name: data['name']?.toString() ?? 'Category',
          type: 'Categories',
          source: {...data, 'items': items},
          images: images(data, items),
          stock: stock,
          available: stock > 0,
        ),
      );
    } else if (!gallery) {
      for (final item in items) {
        final stock = number(item['stock'] ?? item['startingStock']);
        result.add(
          AdminCatalogEntry(
            id: identifier([
              item['id'],
              item['itemId'],
              item['variantId'],
              data['id'],
            ]),
            name: (item['name'] ?? item['variant'] ?? data['name'] ?? 'Item')
                .toString(),
            type: 'Categories',
            source: data,
            details: Map<String, dynamic>.from(item),
            images: images(item, []),
            stock: stock,
            available: stock > 0,
          ),
        );
      }
    }
  }
  for (final data in coffees.where((data) => data['isDeleted'] != true)) {
    final stockValue = data['stock'] ?? data['startingStock'];
    final stock = stockValue == null ? null : number(stockValue);
    result.add(
      AdminCatalogEntry(
        id: identifier([data['coffeeId'], data['id']]),
        name: data['name']?.toString() ?? 'Coffee',
        type: 'Coffee',
        source: data,
        details: data,
        images: images(data, []),
        stock: stock,
        available: data['isAvailable'] != false && (stock == null || stock > 0),
      ),
    );
  }
  return result;
}

class AdminCatalog extends StatefulWidget {
  const AdminCatalog({
    super.key,
    this.gallery = false,
    this.type = 'All',
    required this.onOpen,
    this.onCategorySelected,
    this.actions,
    this.onVoid,
    this.onView,
  });
  final ValueChanged<Map<String, dynamic>?>? onCategorySelected;
  final Widget? actions;
  final ValueChanged<AdminCatalogEntry>? onVoid;
  final ValueChanged<AdminCatalogEntry>? onView;
  final bool gallery;
  final String type;
  final void Function(AdminCatalogEntry entry) onOpen;
  @override
  State<AdminCatalog> createState() => _AdminCatalogState();
}

class _AdminCatalogState extends State<AdminCatalog> {
  late final _products = FirebaseFirestore.instance
      .collection('sales_inventory')
      .snapshots();
  late final _coffees = FirebaseFirestore.instance
      .collection('coffee_products')
      .snapshots();
  String _filter = 'All';
  String _query = '';
  String? _category;

  String _price(AdminCatalogEntry entry, [String? size]) {
    final base = num.tryParse(
      '${entry.details['basePrice'] ?? entry.details['price'] ?? entry.source['price']}',
    );
    if (size == null) return base == null ? '—' : '₱${base.toStringAsFixed(2)}';
    final options = (entry.details['sizes'] as List? ?? [])
        .whereType<Map>()
        .where(
          (option) => [
            size.toLowerCase(),
            size[0].toLowerCase(),
          ].contains('${option['name']}'.toLowerCase()),
        );
    if (options.isEmpty || base == null) return '—';
    final delta = num.tryParse('${options.first['priceDelta']}') ?? 0;
    return '₱${(base + delta).toStringAsFixed(2)}';
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _products,
    builder: (context, products) =>
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _coffees,
          builder: (context, coffees) {
            if (products.hasError || coffees.hasError)
              return const Center(child: Text('Unable to load items.'));
            if (!products.hasData || !coffees.hasData)
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              );
            final all = adminCatalogEntries(
              products.data!.docs
                  .map((doc) => {...doc.data(), 'id': doc.id})
                  .toList(),
              coffees.data!.docs
                  .map((doc) => {...doc.data(), 'id': doc.id})
                  .toList(),
              gallery: widget.gallery,
            );
            final filter = widget.gallery && widget.type == 'All'
                ? _filter
                : widget.type;
            final categories = currentCatalogCategories(
              products.data!.docs
                  .map((doc) => {...doc.data(), 'id': doc.id})
                  .toList(),
            );
            final selected =
                categories
                    .where(
                      (category) => catalogCategoryKey(category) == _category,
                    )
                    .firstOrNull ??
                categories.firstOrNull;
            if (widget.type == 'Categories') {
              _category = selected == null
                  ? null
                  : catalogCategoryKey(selected);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) widget.onCategorySelected?.call(selected);
              });
            }
            final entries = all
                .where(
                  (entry) =>
                      (filter == 'All' || entry.type == filter) &&
                      (widget.type != 'Categories' ||
                          catalogCategoryKey(entry.source) == _category) &&
                      '${entry.id} ${entry.name}'.toLowerCase().contains(
                        _query,
                      ),
                )
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.gallery)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: ['All', 'Categories', 'Bundle', 'Coffee']
                        .map(
                          (type) => ChoiceChip(
                            label: Text(
                              type == 'Coffee' ? 'Coffee items' : type,
                            ),
                            selected: _filter == type,
                            onSelected: (_) => setState(() => _filter = type),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Search items',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.type == 'Categories')
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories
                        .map(
                          (doc) => ChoiceChip(
                            label: Text('${doc['name'] ?? 'Category'}'),
                            selected: catalogCategoryKey(doc) == _category,
                            onSelected: (_) {
                              setState(
                                () => _category = catalogCategoryKey(doc),
                              );
                              widget.onCategorySelected?.call(doc);
                            },
                          ),
                        )
                        .toList(),
                  ),
                if (widget.actions != null) widget.actions!,
                const SizedBox(height: 16),
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No items found.'),
                  )
                else if (widget.gallery)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 900
                          ? 3
                          : constraints.maxWidth >= 600
                          ? 2
                          : 1;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: entries.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 300,
                        ),
                        itemBuilder: (context, index) =>
                            _galleryCard(entries[index]),
                      );
                    },
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: DataTable(
                          columnSpacing: 24,
                          headingRowColor: const WidgetStatePropertyAll(
                            Color(0xFFFCE4EC),
                          ),
                          dataRowMinHeight: 64,
                          dataRowMaxHeight: widget.type == 'Bundle' ? 110 : 72,
                          columns: [
                            DataColumn(label: Text('ID')),
                            DataColumn(label: Text('Item name')),
                            const DataColumn(label: Text('Price')),
                            if (widget.type == 'Coffee')
                              ...['Small', 'Medium', 'Large'].map(
                                (size) => DataColumn(
                                  label: Tooltip(
                                    message: size,
                                    child: Text(size[0]),
                                  ),
                                ),
                              )
                            else
                              const DataColumn(label: Text('Expiry date')),
                            if (widget.type != 'Coffee')
                              const DataColumn(label: Text('Stock')),
                            DataColumn(label: Text('Availability')),
                            DataColumn(label: Text('Action')),
                          ],
                          rows: entries
                              .map(
                                (entry) => DataRow(
                                  cells: [
                                    DataCell(
                                      Tooltip(
                                        message: entry.id,
                                        child: SizedBox(
                                          width: 105,
                                          child: Text(
                                            entry.id,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: SizedBox(
                                              width: 46,
                                              height: 46,
                                              child: _CatalogPhotos(
                                                key: ValueKey(
                                                  'photo-${entry.id}',
                                                ),
                                                images: entry.images,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(entry.name),
                                        ],
                                      ),
                                    ),
                                    DataCell(Text(_price(entry))),
                                    if (widget.type == 'Coffee')
                                      ...['Small', 'Medium', 'Large'].map(
                                        (size) =>
                                            DataCell(Text(_price(entry, size))),
                                      )
                                    else
                                      DataCell(
                                        Tooltip(
                                          message: catalogExpiryLabel(entry),
                                          child: Text(
                                            catalogExpiryLabel(entry),
                                            maxLines: 4,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    if (widget.type != 'Coffee')
                                      DataCell(
                                        Text(entry.stock?.toString() ?? '-'),
                                      ),
                                    DataCell(
                                      Text(
                                        entry.available
                                            ? 'Available'
                                            : 'Unavailable',
                                        style: TextStyle(
                                          color: entry.available
                                              ? Colors.green.shade700
                                              : Colors.red.shade700,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Edit ${entry.name}',
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                            onPressed: () =>
                                                widget.onOpen(entry),
                                          ),
                                          if (entry.type == 'Bundle' &&
                                              widget.onView != null)
                                            IconButton(
                                              tooltip: 'View bundle contents',
                                              icon: const Icon(
                                                Icons.visibility_outlined,
                                              ),
                                              onPressed: () =>
                                                  widget.onView!(entry),
                                            ),
                                          if (widget.onVoid != null)
                                            IconButton(
                                              tooltip: 'Void ${entry.name}',
                                              icon: const Icon(
                                                Icons.block,
                                                color: Color(0xFFE91E63),
                                              ),
                                              onPressed: () =>
                                                  widget.onVoid!(entry),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
  );

  Widget _galleryCard(AdminCatalogEntry entry) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => widget.onOpen(entry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 165,
            child: _CatalogPhotos(
              key: ValueKey('${entry.type}-${entry.id}'),
              images: entry.images,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${entry.type} · ${entry.stock == null ? (entry.available ? 'Available' : 'Unavailable') : '${entry.stock} in stock'}',
                ),
                const SizedBox(height: 8),
                Text(
                  entry.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CatalogPhotos extends StatefulWidget {
  const _CatalogPhotos({super.key, required this.images});
  final List<String> images;
  @override
  State<_CatalogPhotos> createState() => _CatalogPhotosState();
}

class _CatalogPhotosState extends State<_CatalogPhotos> {
  final _controller = PageController();
  late final Timer _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_controller.hasClients && widget.images.length > 1) {
        final next =
            ((_controller.page ?? 0).round() + 1) % widget.images.length;
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant _CatalogPhotos oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.images.length != widget.images.length &&
        _controller.hasClients) {
      _controller.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _placeholder() => const ColoredBox(
    color: Color(0xFFFCE4EC),
    child: Center(
      child: Icon(Icons.image_outlined, size: 44, color: Color(0xFFC2105C)),
    ),
  );
  Widget _image(String url) {
    try {
      if (url.startsWith('data:'))
        return Image.memory(
          base64Decode(url.split(',').last),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } catch (_) {
      return _placeholder();
    }
  }

  @override
  Widget build(BuildContext context) => widget.images.isEmpty
      ? _placeholder()
      : PageView.builder(
          controller: _controller,
          itemCount: widget.images.length,
          itemBuilder: (_, index) => _image(widget.images[index]),
        );
}
