import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/admin_profile_identity.dart';

class AdminProfileLabel extends StatelessWidget {
  const AdminProfileLabel({super.key, this.greeting = false});
  final bool greeting;
  Future<String> identity() async {
    final prefs = await SharedPreferences.getInstance();
    return resolveAdminProfileIdentity(
      FirebaseFirestore.instance,
      prefs,
      authUserId: FirebaseAuth.instance.currentUser?.uid,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: identity(),
    builder: (context, id) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: id.hasData && id.data!.isNotEmpty
          ? FirebaseFirestore.instance
                .collection('staff_requests')
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
        final label = name.isEmpty ? 'Admin' : name;
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
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    ),
  );
}
