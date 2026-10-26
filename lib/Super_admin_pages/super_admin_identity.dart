import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SuperAdminIdentity extends StatelessWidget {
  const SuperAdminIdentity({super.key, this.greeting = false, this.firestore});
  final bool greeting;
  final FirebaseFirestore? firestore;
  Future<String> identity() async {
    return 'Spr-001';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: identity(),
    builder: (context, id) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: id.hasData
          ? (firestore ?? FirebaseFirestore.instance)
                .collection('super_admin_profiles')
                .doc(id.data)
                .snapshots()
          : null,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? {};
        final name = [
          data['firstName'],
          data['middleName'],
          data['lastName'],
        ].where((s) => s != null && '$s'.trim().isNotEmpty).join(' ');
        final label = name.isEmpty ? 'Super admin' : name;
        final firstName = '${data['firstName'] ?? ''}'.trim();
        final photo = '${data['photoUrl'] ?? data['profileImageUrl'] ?? ''}';
        ImageProvider? image;
        try {
          if (photo.startsWith('data:image/')) {
            image = MemoryImage(base64Decode(photo.split(',').last));
          } else if (photo.isNotEmpty) {
            image = NetworkImage(photo);
          }
        } catch (_) {}
        if (greeting) {
          final hour = DateTime.now().hour;
          final salutation = hour < 12
              ? 'Good morning'
              : hour < 17
              ? 'Good afternoon'
              : 'Good evening';
          return Text(
            '$salutation, ${firstName.isEmpty ? label.split(' ').first : firstName}!',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          );
        }
        return Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: image,
              child: image == null ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Text(
                    'Spr-001',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
