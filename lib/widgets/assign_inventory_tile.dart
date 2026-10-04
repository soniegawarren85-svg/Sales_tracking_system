import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

class AssignInventoryTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final TextEditingController controller;
  final bool enabled;

  const AssignInventoryTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.controller,
    required this.enabled,
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
