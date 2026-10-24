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
  'allowReturns': 'Submit returns',
  'allowChecklist': 'Use allocation checklist',
  'allowRefunds': 'Process refunds',
  'allowHoldOrders': 'Hold and resume orders',
  'allowDiscounts': 'Apply discounts',
};
const adminPermissions = {
  'adminAllowInventoryEdits': 'Edit inventory',
  'adminAllowStaffManagement': 'Create and manage staff',
  'adminAllowChecklist': 'Receive allocations from Super Admin',
  'adminAllowReturns': 'Submit returns to Super Admin',
};
const allBranchesSelection = '__all_branches__';
const _branchScopedKeys = [
  'discounts',
  'payments',
  'discountsEnabled',
  'taxEnabled',
  'taxClassification',
  'taxTin',
  'allowRefunds',
  'allowHoldOrders',
  'allowReceiptHistory',
  'allowDiscounts',
  'allowReturns',
  'allowChecklist',
  'adminAllowInventoryEdits',
  'adminAllowChecklist',
  'adminAllowReturns',
  'adminAllowStaffManagement',
  'adminAllowAllocations',
  'adminAllowReturnApproval',
  'adminAllowReconciliationApproval',
];
DocumentReference<Map<String, dynamic>> get transactionSettings =>
    FirebaseFirestore.instance.collection('admin_settings').doc('transactions');

Map<String, dynamic> settingsForBranch(
  Map<String, dynamic> settings,
  String branchId,
) {
  final branchSettings = settings['branchSettings'];
  if (branchId.isEmpty) return settings;
  final scopedSettings = branchSettings is Map
      ? branchSettings[branchId]
      : null;
  final scoped = scopedSettings is Map
      ? Map<String, dynamic>.from(scopedSettings)
      : <String, dynamic>{};
  final result = {...settings, ...scoped};
  for (final key in _branchScopedKeys) {
    if (scoped.containsKey(key)) continue;
    if (key == 'discounts') {
      result[key] = defaultDiscounts;
    } else if (key == 'payments') {
      result[key] = defaultPayments;
    } else if (key == 'taxEnabled') {
      result[key] = false;
    } else if (key == 'taxClassification') {
      result[key] = 'nonVat';
    } else if (key == 'taxTin') {
      result[key] = '';
    } else {
      result[key] = true;
    }
  }
  return result;
}

double transactionTaxRate(Map<String, dynamic> settings) {
  if (settings['taxEnabled'] != true ||
      settings['taxClassification'] != 'vat') {
    return 0;
  }
  return 0.12;
}

double roundTransactionMoney(double amount) => (amount * 100).round() / 100;

class TransactionTaxBreakdown {
  const TransactionTaxBreakdown({
    required this.total,
    required this.vatableSales,
    required this.vatAmount,
  });

  final double total;
  final double vatableSales;
  final double vatAmount;
}

TransactionTaxBreakdown transactionTaxBreakdown(
  Map<String, dynamic> settings, {
  required double grossAmount,
}) {
  final total = roundTransactionMoney(grossAmount);
  final rate = transactionTaxRate(settings);
  if (rate == 0 || total <= 0) {
    return TransactionTaxBreakdown(total: total, vatableSales: 0, vatAmount: 0);
  }

  final vatableSales = roundTransactionMoney(total / (1 + rate));
  final vatAmount = roundTransactionMoney(total - vatableSales);
  return TransactionTaxBreakdown(
    total: total,
    vatableSales: vatableSales,
    vatAmount: vatAmount,
  );
}

double transactionTaxAmount(
  Map<String, dynamic> settings, {
  required double grossAmount,
}) => transactionTaxBreakdown(settings, grossAmount: grossAmount).vatAmount;

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
      settings['allowDiscounts'] == false) {
    return 0;
  }
  return ((num.tryParse(
                '${selectedDiscount(settings, id)['percent']}',
              )?.toDouble() ??
              0) /
          100)
      .clamp(0, 1);
}
