import 'package:flutter/material.dart';

import '../services/number_format.dart';

class CoffeeAddonOptionCard extends StatelessWidget {
  const CoffeeAddonOptionCard({
    super.key,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final double price;
  final String imageUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? const Color(0xFF7A1F5C)
        : const Color(0xFFE9C9D9);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('addon-option-$name'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF7A1F5C).withValues(alpha: 0.08)
                : const Color(0xFFFFF8FA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: imageUrl.trim().isEmpty
                      ? const ColoredBox(
                          color: Color(0xFFF9EAF1),
                          child: Icon(
                            Icons.add_circle_outline,
                            color: Color(0xFF7A1F5C),
                          ),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0xFFF9EAF1),
                            child: Icon(
                              Icons.add_circle_outline,
                              color: Color(0xFF7A1F5C),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF7A1F5C)
                            : const Color(0xFF54203F),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      price > 0 ? '+${formatMoney(price)}' : 'Included',
                      style: const TextStyle(
                        color: Color(0xFF8A7080),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF7A1F5C),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
