import 'package:flutter/material.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Stats page content',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}
