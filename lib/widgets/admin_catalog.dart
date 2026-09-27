import 'package:sales_tracking/theme/app_colors.dart';
import '../services/short_id_service.dart';
import '../services/public_item_id.dart';
import 'admin_addons.dart';
import '../services/bundle_stock_service.dart';
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
  final availableBatches =
      bundleRows(bundle['bundleInstances'])
          .where(
            (instance) =>
                bundleInstanceAvailable(instance, bundle) &&
                bundleRows(
                  instance['items'],
                ).any((item) => '${item['expirationDate'] ?? ''}'.isNotEmpty),
          )
          .toList()
        ..sort(
          (a, b) => '${a['expirationDate'] ?? ''}'.compareTo(
            '${b['expirationDate'] ?? ''}',
          ),
        );
  final contents = availableBatches.isEmpty
      ? bundle['items']
      : availableBatches.first['items'];
  return (contents as List? ?? []).whereType<Map>().map((raw) {
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
        if (id != null && '$id'.isNotEmpty
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
      final resolved = {
        ...data,
        'items': catalogBundleContents(data, products),
      };
      final stock = availableBundleStock(resolved, now: day);
      result.add(
        AdminCatalogEntry(
          id: identifier([data['publicId'], data['bundleId'], data['id']]),
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
          id: identifier([data['publicId'], data['categoryId'], data['id']]),
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
              item['publicId'],
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
        id: identifier([data['publicId'], data['coffeeId'], data['id']]),
        name: data['name']?.toString() ?? 'Beverages',
        type: 'Beverages',
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
    this.pinnedControls = false,
    this.type = 'All',
    required this.onOpen,
    this.onCategorySelected,
    this.actions,
    this.onBeverageTabChanged,
    this.onVoid,
    this.onView,
    this.firestore,
  });
  final FirebaseFirestore? firestore;
  final ValueChanged<Map<String, dynamic>?>? onCategorySelected;
  final Widget? actions;
  final ValueChanged<bool>? onBeverageTabChanged;
  final ValueChanged<AdminCatalogEntry>? onVoid;
  final ValueChanged<AdminCatalogEntry>? onView;
  final bool gallery;
  final bool pinnedControls;
  final String type;
  final void Function(AdminCatalogEntry entry) onOpen;
  @override
  State<AdminCatalog> createState() => _AdminCatalogState();
}

class _AdminCatalogState extends State<AdminCatalog> {
  late final _products = (widget.firestore ?? FirebaseFirestore.instance)
      .collection('sales_inventory')
      .snapshots();
  late final _coffees = (widget.firestore ?? FirebaseFirestore.instance)
      .collection('coffee_products')
      .snapshots();
  @override
  void initState() {
    super.initState();
    if (widget.firestore == null)
      ShortIdService.refresh().catchError((Object _) {});
  }

  String _filter = 'All';
  String _query = '';
  String? _category;
  bool _showAddons = false;

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
            final sections = <Widget>[
              if (widget.gallery)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: ['All', 'Categories', 'Bundle', 'Beverages']
                      .map(
                        (type) => ChoiceChip(
                          label: Text(
                            type == 'Beverages' ? 'Beverages items' : type,
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          selectedColor: AppColors.primaryDark,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: catalogCategoryKey(doc) == _category
                                ? Colors.white
                                : AppColors.primaryDark,
                            fontWeight: FontWeight.w700,
                          ),
                          label: Text('${doc['name'] ?? 'Category'}'),
                          selected: catalogCategoryKey(doc) == _category,
                          onSelected: (_) {
                            setState(() => _category = catalogCategoryKey(doc));
                            widget.onCategorySelected?.call(doc);
                          },
                        ),
                      )
                      .toList(),
                ),
              if (widget.actions != null) widget.actions!,
              if (!widget.gallery && widget.type == 'Beverages') ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final addon in [false, true])
                      ChoiceChip(
                        label: Text(addon ? 'Add-ons' : 'Beverages'),
                        selected: _showAddons == addon,
                        selectedColor: AppColors.primaryDark,
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                          color: _showAddons == addon
                              ? Colors.white
                              : AppColors.primaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: (_) => setState(() {
                          _showAddons = addon;
                          widget.onBeverageTabChanged?.call(addon);
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(key: ValueKey('catalog-results'), height: 16),
              if (!widget.gallery && widget.type == 'Beverages' && !_showAddons)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Beverages',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              if (!widget.gallery && widget.type == 'Beverages' && _showAddons)
                AdminAddonsTable(query: _query, firestore: widget.firestore)
              else if (entries.isEmpty)
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
                _table(entries),
            ];
            if (!widget.pinnedControls)
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: sections,
              );
            final split =
                sections.indexWhere(
                  (section) => section.key == const ValueKey('catalog-results'),
                ) +
                1;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...sections.take(split),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('inventory-table-scroll'),
                    padding: const EdgeInsets.only(bottom: 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: sections.skip(split).toList(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
  );

  Widget _table(List<AdminCatalogEntry> entries) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 720;
      final beverages = widget.type == 'Beverages';
      Widget actions(AdminCatalogEntry entry) => Wrap(
        spacing: 2,
        children: [
          IconButton.filledTonal(
            tooltip: 'Edit ${entry.name}',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => widget.onOpen(entry),
          ),
          if (entry.type == 'Bundle' && widget.onView != null)
            IconButton(
              tooltip: 'View contents',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              onPressed: () => widget.onView!(entry),
            ),
          if (widget.onVoid != null)
            IconButton(
              tooltip: 'Void ${entry.name}',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.block,
                size: 18,
                color: AppColors.primaryDark,
              ),
              onPressed: () => widget.onVoid!(entry),
            ),
        ],
      );
      Widget identity(AdminCatalogEntry entry) => Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 42,
              height: 42,
              child: _CatalogPhotos(
                key: ValueKey('photo-${entry.id}'),
                images: entry.images,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (narrow) Text(
                  entry.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      Widget status(AdminCatalogEntry entry) => Text(
        entry.available ? 'Available' : 'Unavailable',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: entry.available ? Colors.green.shade700 : Colors.red.shade700,
        ),
      );
      Widget cell(Widget child, [int flex = 1]) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: child,
        ),
      );
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              color: AppColors.primaryDark,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                child: narrow
                    ? Row(
                        children: [
                          Text(beverages ? 'Beverages' : 'Inventory items'),
                          const Spacer(),
                          Text('${entries.length} items'),
                        ],
                      )
                    : Row(
                        children: [
                          cell(const Text('ID')),
                          cell(const Text('Item'), 3),
                          if (beverages)
                            ...[
                              'Small',
                              'Medium',
                              'Large',
                            ].map((size) => cell(Text(size)))
                          else ...[
                            cell(const Text('Price')),
                            cell(const Text('Expiry'), 2),
                            cell(const Text('Stock')),
                          ],
                          cell(const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('Availability'))),
                          cell(const Text('Actions'), 2),
                        ],
                      ),
              ),
            ),
            ...entries.asMap().entries.map((row) {
              final entry = row.value;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: row.key.isEven ? Colors.white : AppColors.surfaceTint,
                  border: const Border(
                    top: BorderSide(color: AppColors.border),
                  ),
                ),
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          identity(entry),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              if (beverages)
                                ...['Small', 'Medium', 'Large'].map(
                                  (size) =>
                                      Text('$size: ${_price(entry, size)}'),
                                )
                              else ...[
                                Text(_price(entry)),
                                Text('Stock: ${entry.stock ?? 0}'),
                                Text('Expires: ${catalogExpiryLabel(entry)}'),
                              ],
                            ],
                          ),
                          Row(
                            children: [
                              status(entry),
                              const Spacer(),
                              actions(entry),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          cell(Tooltip(message: entry.id, child: Text(entry.id, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)))),
                          cell(identity(entry), 3),
                          if (beverages)
                            ...['Small', 'Medium', 'Large'].map(
                              (size) => cell(
                                Text(
                                  _price(entry, size),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                          else ...[
                            cell(
                              Text(
                                _price(entry),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            cell(
                              Text(
                                catalogExpiryLabel(entry),
                                style: const TextStyle(fontSize: 12),
                              ),
                              2,
                            ),
                            cell(Text('${entry.stock ?? 0}')),
                          ],
                          cell(status(entry)),
                          cell(actions(entry), 2),
                        ],
                      ),
              );
            }),
          ],
        ),
      );
    },
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
    color: AppColors.blush,
    child: Center(
      child: Icon(Icons.image_outlined, size: 44, color: AppColors.primaryDark),
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
