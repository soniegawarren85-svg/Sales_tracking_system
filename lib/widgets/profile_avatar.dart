import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.data, this.radius = 22});
  final Map<String, dynamic> data;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final url = '${data['photoUrl'] ?? data['profileImageUrl'] ?? ''}';
    final name = '${data['firstName'] ?? data['staffName'] ?? 'Staff'}'.trim();
    final fallback = Center(
      child: Text(name.isEmpty ? 'S' : name.substring(0, 1).toUpperCase()),
    );
    Widget photo = fallback;
    try {
      if (url.startsWith('data:image/')) {
        photo = Image.memory(
          base64Decode(url.split(',').last),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        );
      } else if (url.isNotEmpty) {
        photo = Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        );
      }
    } catch (_) {}
    return ClipOval(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        color: AppColors.surface,
        child: photo,
      ),
    );
  }
}
