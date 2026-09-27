import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

List<Map<String, dynamic>> bundleDrinkServings(Map<String, dynamic> bundle) {
  final result = <Map<String, dynamic>>[];
  for (final part in (bundle['bundleItems'] as List? ?? []).whereType<Map>()) {
    if (part['isCoffee'] != true &&
        part['sourceCollection'] != 'coffee_products')
      continue;
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
        'sugarLevel': '50%',
        'addons': <Map<String, dynamic>>[],
      });
    }
  }
  return result;
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
              sum + (num.tryParse('${addon['priceDelta']}')?.toDouble() ?? 0),
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
    'id': 'bundle-options:${identity}',
    'itemId': 'bundle-options:${identity}',
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
    required this.addons,
  });
  final Map<String, dynamic> bundle;
  final List<Map<String, dynamic>> addons;
  @override
  State<BundleBeverageDialog> createState() => _BundleBeverageDialogState();
}

class _BundleBeverageDialogState extends State<BundleBeverageDialog> {
  late final drinks = bundleDrinkServings(widget.bundle);
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
                for (var index = 0; index < drinks.length; index++) ...[
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
                  if (widget.addons.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Optional add-ons'),
                    Wrap(
                      spacing: 8,
                      children: widget.addons.map((addon) {
                        final selected = (drinks[index]['addons'] as List)
                            .cast<Map<String, dynamic>>();
                        final chosen = selected.any(
                          (entry) => entry['id'] == addon['id'],
                        );
                        return FilterChip(
                          label: Text(
                            '${addon['name']} (+₱${addon['priceDelta']})',
                          ),
                          selected: chosen,
                          selectedColor: AppColors.blush,
                          onSelected: (value) => setState(() {
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
                onPressed: () => Navigator.pop(
                  context,
                  customizeBundle(widget.bundle, drinks),
                ),
                child: const Text('Add bundle to order'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
