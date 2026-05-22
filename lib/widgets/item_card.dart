import 'dart:convert';

import 'package:flutter/material.dart';

enum ImageShape { circle, diamond }

class ItemCard extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;
  final String? imageAsset;
  final ImageShape shape;

  const ItemCard({
    super.key,
    this.title = 'Items Name',
    this.onTap,
    this.imageAsset,
    this.shape = ImageShape.circle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.08),
              spreadRadius: 1,
              blurRadius: 6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              height: 80,
              child: Stack(
                children: [
                  // pink background box with image filling the space
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 70,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF48FB1),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      // image is placed directly inside the pink container,
                      // no fixed size or shape, it simply covers the area
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: imageAsset != null
                            ? (imageAsset!.startsWith('data:image/')
                                ? Image.memory(
                                    base64Decode(
                                      imageAsset!.substring(
                                        imageAsset!.indexOf(',') + 1,
                                      ),
                                    ),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (c, e, s) => Center(
                                      child: Text(
                                        'Pic',
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                  )
                                : imageAsset!.startsWith('http')
                                ? Image.network(
                                    imageAsset!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (c, e, s) => Center(
                                      child: Text(
                                        'Pic',
                                        style: TextStyle(color: Colors.grey[700]),
                                      ),
                                    ),
                                  )
                                : Image.asset(
                                    imageAsset!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (c, e, s) => Center(
                                      child: Text(
                                        'Pic',
                                        style: TextStyle(color: Colors.grey[700]),
                                      ),
                                    ),
                                  ))
                            : Center(
                                child: Text(
                                  'Pic',
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: Color(0xFFF48FB1),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // image badge logic removed; image is now rendered directly inside
  // the pink container in build(). The shape and fixed size handling are
  // no longer needed so this method can be deleted.
}
