import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminCatalogEntry {
  const AdminCatalogEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.source,
    required this.images,
    this.stock,
    this.available = true,
  });
  final String id, name, type;
  final Map<String, dynamic> source;
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
      .map((value) => value?.toString().trim() ?? '')
      .firstWhere((value) => value.isNotEmpty, orElse: () => 'Not recorded');
  bool active(Map item) {
    final expiry = DateTime.tryParse(item['expirationDate']?.toString() ?? '');
    return item['isDeleted'] != true &&
        (expiry == null ||
            !expiry.isBefore(DateTime(day.year, day.month, day.day)));
  }

  List<String> images(Map data, List<Map> items) =>
      [data['imageUrl'], ...items.map((item) => item['imageUrl'])]
          .map((url) => url?.toString() ?? '')
          .where((url) => url.isNotEmpty)
          .toSet()
          .toList();
  final result = <AdminCatalogEntry>[];
  for (final data in products.where((data) => data['isDeleted'] != true)) {
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
          source: data,
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
            source: {...data, 'items': items},
            images: images(data, [item]),
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
  });
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
            final filter = widget.gallery ? _filter : widget.type;
            final entries = all
                .where(
                  (entry) =>
                      (filter == 'All' || entry.type == filter) &&
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
                          columns: const [
                            DataColumn(label: Text('ID')),
                            DataColumn(label: Text('Item name')),
                            DataColumn(label: Text('Stock')),
                            DataColumn(label: Text('Availability')),
                            DataColumn(label: Text('Action')),
                          ],
                          rows: entries
                              .map(
                                (entry) => DataRow(
                                  cells: [
                                    DataCell(SelectableText(entry.id)),
                                    DataCell(Text(entry.name)),
                                    DataCell(
                                      Text(entry.stock?.toString() ?? '—'),
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
                                      IconButton(
                                        tooltip: 'View / manage ${entry.name}',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => widget.onOpen(entry),
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
