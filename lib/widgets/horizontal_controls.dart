import 'package:flutter/material.dart';

class HorizontalControls extends StatelessWidget {
  const HorizontalControls({
    super.key,
    required this.children,
    this.spacing = 8,
  });
  final List<Widget> children;
  final double spacing;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          children[i],
        ],
      ],
    ),
  );
}
