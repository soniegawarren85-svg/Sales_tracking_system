import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class EmailPendingBadge extends StatelessWidget {
  const EmailPendingBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: const Color(0xFFFFF0F5), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.rose)),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.schedule_rounded, size: 13, color: AppColors.primaryDark),
      SizedBox(width: 4),
      Text('Pending', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
    ]),
  );
}
