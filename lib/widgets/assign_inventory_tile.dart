import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

String? assignmentQuantityValidationMessage({
  required Map<String, TextEditingController> controllers,
  required Map<String, String> kinds,
  required Map<String, int> limits,
  required Set<String> activeKinds,
}) {
  for (final entry in controllers.entries) {
    final kind = kinds[entry.key];
    if (!activeKinds.contains(kind)) continue;
    final requested = int.tryParse(entry.value.text) ?? 0;
    if (requested <= 0) continue;

    final isBundle = kind == 'bundle';
    final minimum = isBundle ? 10 : 20;
    final maximum = isBundle ? 50 : 150;
    if (requested < minimum || requested > maximum) {
      return isBundle
          ? 'Bundle quantity must be at least 10 and no more than 50.'
          : 'Category quantity must be at least 20 and no more than 150 units per item.';
    }

    final available = limits[entry.key];
    if (available != null && requested > available) {
      return 'Only $available ${isBundle ? 'bundles' : 'units'} are available for this item.';
    }
  }
  return null;
}

class AssignmentValidationNotice extends StatelessWidget {
  const AssignmentValidationNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4E8),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFFFC58A)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          color: Color(0xFFC65300),
          size: 20,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9A3D00),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class AssignInventoryTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final TextEditingController controller;
  final bool enabled;
  final int? maxQuantity;
  final ValueChanged<String>? onChanged;

  const AssignInventoryTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.controller,
    required this.enabled,
    this.maxQuantity,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: enabled ? AppColors.background : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.blush.withOpacity(0.7)),
      ),
      child: Flex(
        direction: MediaQuery.sizeOf(context).width < 600
            ? Axis.vertical
            : Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (MediaQuery.sizeOf(context).width >= 600)
            Icon(
              icon,
              color: enabled ? AppColors.primaryDark : Colors.grey,
              size: 20,
            ),
          const SizedBox(width: 10, height: 8),
          Flexible(
            flex: MediaQuery.sizeOf(context).width < 600 ? 0 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: null,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? AppColors.primaryDeep : Colors.grey,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: enabled ? Colors.grey.shade600 : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10, height: 8),
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 600
                ? double.infinity
                : 116,
            child: TextField(
              controller: controller,
              enabled: enabled,
              onChanged: onChanged,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                color: AppColors.primaryDeep,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                hintText: 'Qty',
                errorText:
                    maxQuantity != null &&
                        (int.tryParse(controller.text) ?? 0) > maxQuantity!
                    ? 'Only $maxQuantity available'
                    : null,
                filled: true,
                fillColor: Colors.white,
                prefixIcon: IconButton(
                  icon: const Icon(Icons.remove_rounded, size: 16),
                  color: enabled ? AppColors.primaryDark : Colors.grey,
                  onPressed: !enabled
                      ? null
                      : () {
                          final value = int.tryParse(controller.text) ?? 0;
                          controller.text = value <= 1
                              ? ''
                              : (value - 1).toString();
                          onChanged?.call(controller.text);
                        },
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 36,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  color: enabled ? AppColors.primaryDark : Colors.grey,
                  onPressed: !enabled
                      ? null
                      : () {
                          final value = int.tryParse(controller.text) ?? 0;
                          controller.text = (value + 1).toString();
                          onChanged?.call(controller.text);
                        },
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 36,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.blush.withOpacity(0.8),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
