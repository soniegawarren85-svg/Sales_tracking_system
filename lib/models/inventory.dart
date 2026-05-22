import 'package:cloud_firestore/cloud_firestore.dart';

class Inventory {
  /// Name of the product (e.g., "cakes", "asds")
  final String? item;
  final String? ownerId;
  final String? sourceInventoryId;

  /// List of individual items with their details and quantities
  final List<Map<String, dynamic>>? items;

  /// Total net sales revenue recorded for this inventory entry.
  final double? totalSalesRevenue;

  /// Legacy quantities (for backward compatibility)
  final int? startingA;
  final int? startingB;
  final int? startingC;

  /// Quantities entered when recording the remaining stock later.
  int? remainingA;
  int? remainingB;
  int? remainingC;

  final DateTime timestamp;

  Inventory({
    String? item,
    this.ownerId,
    this.sourceInventoryId,
    List<Map<String, dynamic>>? items,
    // legacy compatibility: callers used to pass itemA/itemB/itemC.
    int? itemA,
    int? itemB,
    int? itemC,
    int? startingA,
    int? startingB,
    int? startingC,
    int? remainingA,
    int? remainingB,
    int? remainingC,
    double? totalSalesRevenue,
    DateTime? timestamp,
  }) : item = item,
       items = items,
       totalSalesRevenue = totalSalesRevenue,
       startingA = startingA ?? itemA ?? 0,
       startingB = startingB ?? itemB ?? 0,
       startingC = startingC ?? itemC ?? 0,
       remainingA = remainingA ?? 0,
       remainingB = remainingB ?? 0,
       remainingC = remainingC ?? 0,
       timestamp = timestamp ?? DateTime.now();

  /// Total stock (start + remaining) for convenience.
  int get itemA => (startingA ?? 0) + (remainingA ?? 0);
  int get itemB => (startingB ?? 0) + (remainingB ?? 0);
  int get itemC => (startingC ?? 0) + (remainingC ?? 0);

  /// Safe accessors so callers don't have to worry about `null`.
  int get safeStartingA => startingA ?? 0;
  int get safeStartingB => startingB ?? 0;
  int get safeStartingC => startingC ?? 0;

  int get safeRemainingA => remainingA ?? 0;
  int get safeRemainingB => remainingB ?? 0;
  int get safeRemainingC => remainingC ?? 0;

  /// Non-null item accessor.
  String get safeItem => item ?? '';

  /// Get items list safely
  List<Map<String, dynamic>> get safeItems => items ?? [];

  /// Safe revenue accessor.
  double get safeTotalSalesRevenue => totalSalesRevenue ?? 0.0;

  /// JSON serialization for persistence
  Map<String, dynamic> toJson() => {
    'item': item,
    'ownerId': ownerId,
    'sourceInventoryId': sourceInventoryId,
    'items': items,
    'totalSalesRevenue': totalSalesRevenue,
    'startingA': startingA,
    'startingB': startingB,
    'startingC': startingC,
    'remainingA': remainingA,
    'remainingB': remainingB,
    'remainingC': remainingC,
    'timestamp': timestamp.toIso8601String(),
  };

  factory Inventory.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    List<Map<String, dynamic>>? parsedItems;
    if (itemsRaw is List) {
      parsedItems = itemsRaw
          .whereType<Map<String, dynamic>>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }

    // Support both 'item' and 'name' fields (for compatibility)
    final itemName = json['item'] as String? ?? json['name'] as String?;

    final totalSalesRevenue = json['totalSalesRevenue'] is num
        ? (json['totalSalesRevenue'] as num).toDouble()
        : double.tryParse(json['totalSalesRevenue']?.toString() ?? '') ?? 0.0;

    final value = Inventory(
      item: itemName,
      ownerId: json['ownerId'] as String?,
      sourceInventoryId: json['sourceInventoryId'] as String?,
      items: parsedItems,
      totalSalesRevenue: totalSalesRevenue,
      startingA: json['startingA'] is int
          ? json['startingA'] as int
          : int.tryParse(json['startingA']?.toString() ?? '0'),
      startingB: json['startingB'] is int
          ? json['startingB'] as int
          : int.tryParse(json['startingB']?.toString() ?? '0'),
      startingC: json['startingC'] is int
          ? json['startingC'] as int
          : int.tryParse(json['startingC']?.toString() ?? '0'),
      remainingA: json['remainingA'] is int
          ? json['remainingA'] as int
          : int.tryParse(json['remainingA']?.toString() ?? '0'),
      remainingB: json['remainingB'] is int
          ? json['remainingB'] as int
          : int.tryParse(json['remainingB']?.toString() ?? '0'),
      remainingC: json['remainingC'] is int
          ? json['remainingC'] as int
          : int.tryParse(json['remainingC']?.toString() ?? '0'),
      timestamp: _parseTimestamp(json['timestamp']),
    );

    return value;
  }

  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();
    
    // Handle Firestore Timestamp object
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }
    
    // Handle String ISO8601 timestamps
    if (timestamp is String) {
      try {
        return DateTime.parse(timestamp);
      } catch (e) {
        // Continue
      }
    }
    
    // Handle milliseconds since epoch as int
    if (timestamp is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      } catch (e) {
        // Continue
      }
    }
    
    // Fallback to now
    return DateTime.now();
  }
}

