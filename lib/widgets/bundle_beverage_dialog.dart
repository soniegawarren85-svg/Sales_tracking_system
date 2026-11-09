import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

List<Map<String, dynamic>> bundleDrinkServings(Map<String, dynamic> bundle) {
  final result = <Map<String, dynamic>>[];
  for (final part in (bundle['bundleItems'] as List? ?? []).whereType<Map>()) {
    if (part['isCoffee'] != true &&
        part['sourceCollection'] != 'coffee_products') {
      continue;
    }
    final count = int.tryParse('${part['quantity'] ?? 1}') ?? 1;
    for (var i = 0; i < count; i++) {
      result.add({
        for (final key in [
          'name',
          'sourceInventoryId',
          'coffeeSize',
          'variantId',
        ])
          key: part[key],
        'serving': i + 1,
        'sugarLevel': '0%',
        'addons': <Map<String, dynamic>>[],
      });
    }
  }
  return result;
}

bool bundleIncludesAddon(Map<String, dynamic> bundle, Map addon) {
  final addonId = '${addon['id'] ?? addon['sourceInventoryId'] ?? ''}'.trim();
  if (addonId.isEmpty) return false;
  return (bundle['bundleItems'] as List? ?? const [])
      .whereType<Map>()
      .any((part) {
        if (part['sourceCollection'] != 'coffee_addons') return false;
        return [
          part['sourceInventoryId'],
          part['variantId'],
          part['itemId'],
          part['id'],
        ].any((value) => '${value ?? ''}'.trim() == addonId);
      });
}

Map<String, dynamic> customizeBundle(
  Map<String, dynamic> bundle,
  List<Map<String, dynamic>> drinks,
) {
  final extra = drinks.fold<double>(
    0,
    (sum, drink) =>
        sum +
        (drink['addons'] as List).whereType<Map>().fold<double>(
          0,
          (sum, addon) =>
              sum +
              (addon['includedInBundle'] == true
                  ? 0
                  : num.tryParse('${addon['priceDelta']}')?.toDouble() ?? 0),
        ),
  );
  final description = drinks
      .map((drink) {
        final addons = (drink['addons'] as List)
            .whereType<Map>()
            .map((addon) => addon['name'])
            .join(', ');
        return '${drink['name']} #${drink['serving']}: Sugar ${drink['sugarLevel']}${addons.isEmpty ? '' : ' + $addons'}';
      })
      .join('; ');
  final identity = jsonEncode(
    drinks
        .map(
          (drink) => [
            drink['sourceInventoryId'],
            drink['coffeeSize'],
            drink['serving'],
            drink['sugarLevel'],
            (drink['addons'] as List).map((addon) => addon['id']).toList(),
          ],
        )
        .toList(),
  );
  return {
    ...bundle,
    'id': 'bundle-options:$identity',
    'itemId': 'bundle-options:$identity',
    'variant': description,
    'bundleBeverages': drinks,
    'bundleBasePrice': bundle['price'],
    'bundleAddonTotal': extra,
    'price': (num.tryParse('${bundle['price']}')?.toDouble() ?? 0) + extra,
  };
}

class BundleBeverageDialog extends StatefulWidget {
  const BundleBeverageDialog({
    super.key,
    required this.bundle,
    this.addons = const [],
    this.addonsFuture,
  });
  final Map<String, dynamic> bundle;
  final List<Map<String, dynamic>> addons;
  final Future<List<Map<String, dynamic>>>? addonsFuture;
  @override
  State<BundleBeverageDialog> createState() => _BundleBeverageDialogState();
}

class _BundleBeverageDialogState extends State<BundleBeverageDialog> {
  late final drinks = bundleDrinkServings(widget.bundle);
  late List<Map<String, dynamic>> _availableAddons = widget.addons;
  final Set<int> _done = {};
  int _active = 0;

  @override
  void initState() {
    super.initState();
    widget.addonsFuture
        ?.then<void>((addons) {
          if (mounted) setState(() => _availableAddons = addons);
        })
        .catchError((Object _) {});
  }

  String sizeOf(int index) =>
      '${drinks[index]['coffeeSize'] ?? drinks[index]['variantId']}';
  @override
  Widget build(BuildContext context) => Dialog(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: SizedBox(
      width: 620,
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          Container(
            color: AppColors.primaryDark,
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.bundle['name']} · Beverage options',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Included in this bundle. Prepare each drink, then tap Done. The bundle is added after all drinks are ready.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final size in {
                      for (var i = 0; i < drinks.length; i++)
                        if (!_done.contains(i)) sizeOf(i),
                    })
                      ChoiceChip(
                        label: Text(
                          '$size (x${List.generate(drinks.length, (i) => i).where((i) => !_done.contains(i) && sizeOf(i) == size).length})',
                        ),
                        selected: sizeOf(_active) == size,
                        onSelected: (_) => setState(
                          () => _active = List.generate(drinks.length, (i) => i)
                              .firstWhere(
                                (i) => !_done.contains(i) && sizeOf(i) == size,
                              ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final index in [_active])
                  if (drinks.isNotEmpty && !_done.contains(index)) ...[
                    Text(
                      '${drinks[index]['name']} · Drink ${index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      'Size: ${drinks[index]['coffeeSize'] ?? drinks[index]['variantId']} · Included in bundle',
                    ),
                    const SizedBox(height: 14),
                    const Text('Sugar level'),
                    Wrap(
                      spacing: 8,
                      children: ['0%', '25%', '50%', '75%', '100%']
                          .map(
                            (sugar) => ChoiceChip(
                              label: Text(sugar),
                              selected: drinks[index]['sugarLevel'] == sugar,
                              selectedColor: AppColors.blush,
                              onSelected: (_) => setState(
                                () => drinks[index]['sugarLevel'] = sugar,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    if (_availableAddons.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Optional add-ons'),
                      Wrap(
                        spacing: 8,
                        children: _availableAddons.map((addon) {
                          final included = bundleIncludesAddon(
                            widget.bundle,
                            addon,
                          );
                          final selected = (drinks[index]['addons'] as List)
                              .cast<Map<String, dynamic>>();
                          final chosen = selected.any(
                            (entry) => entry['id'] == addon['id'],
                          );
                          return FilterChip(
                            label: Text(
                              included
                                  ? '${addon['name']} (Included in bundle)'
                                  : '${addon['name']} (+₱${addon['priceDelta']})',
                            ),
                            selected: included || chosen,
                            selectedColor: AppColors.blush,
                            onSelected: included
                                ? null
                                : (value) => setState(() {
                              if (value) {
                                selected.add({...addon});
                              } else {
                                selected.removeWhere(
                                  (entry) => entry['id'] == addon['id'],
                                );
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ],
                    const Divider(height: 32),
                  ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                ),
                onPressed: () {
                  _done.add(_active);
                  if (_done.length >= drinks.length) {
                    Navigator.pop(
                      context,
                      customizeBundle(widget.bundle, drinks),
                    );
                  } else {
                    setState(
                      () => _active = List.generate(
                        drinks.length,
                        (i) => i,
                      ).firstWhere((i) => !_done.contains(i)),
                    );
                  }
                },
                child: const Text('Done'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
