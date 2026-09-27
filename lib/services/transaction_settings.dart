import 'package:cloud_firestore/cloud_firestore.dart';

const defaultDiscounts = [
  {'id': 'senior', 'name': 'Senior', 'percent': 20},
  {'id': 'pwd', 'name': 'PWD', 'percent': 20},
];
const defaultPayments = [
  {'id': 'cash', 'name': 'Cash'},
  {'id': 'gcash', 'name': 'GCash'},
];
const staffPermissions = {
  'allowRefunds': 'Process refunds',
  'allowHoldOrders': 'Hold and resume orders',
  'allowReceiptHistory': 'View receipt history',
  'allowDiscounts': 'Apply discounts',
};
DocumentReference<Map<String, dynamic>> get transactionSettings =>
    FirebaseFirestore.instance.collection('admin_settings').doc('transactions');
List<Map<String, dynamic>> settingRows(Map<String, dynamic> data, String key) =>
    (data[key] as List? ??
            (key == 'discounts' ? defaultDiscounts : defaultPayments))
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

Map<String, dynamic> selectedDiscount(
  Map<String, dynamic> settings,
  String? id,
) =>
    settingRows(
      settings,
      'discounts',
    ).where((row) => row['id'] == id && row['isVoided'] != true).firstOrNull ??
    {};
double discountFraction(Map<String, dynamic> settings, String? id) {
  if (settings['discountsEnabled'] == false ||
      settings['allowDiscounts'] == false)
    return 0;
  return ((num.tryParse(
                '${selectedDiscount(settings, id)['percent']}',
              )?.toDouble() ??
              0) /
          100)
      .clamp(0, 1);
}
