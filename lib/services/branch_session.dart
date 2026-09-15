import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The branch currently being viewed by the admin. A null id means Main Branch.
class BranchSession extends ChangeNotifier {
  BranchSession._();
  static final BranchSession instance = BranchSession._();

  static const _idKey = 'active_admin_branch_id';
  static const _nameKey = 'active_admin_branch_name';
  String? _branchId;
  String? _branchName;
  bool _loaded = false;

  String? get branchId => _branchId;
  bool get isMainBranch => _branchId == null;
  String get displayName => _branchName ?? 'Main Branch';

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _branchId = prefs.getString(_idKey);
    _branchName = prefs.getString(_nameKey);
    _loaded = true;
    notifyListeners();
  }

  Future<void> switchTo({String? branchId, String? branchName}) async {
    final prefs = await SharedPreferences.getInstance();
    _branchId = branchId;
    _branchName = branchId == null ? null : branchName;
    if (branchId == null) {
      await prefs.remove(_idKey);
      await prefs.remove(_nameKey);
    } else {
      await prefs.setString(_idKey, branchId);
      await prefs.setString(_nameKey, branchName ?? 'Branch');
    }
    _loaded = true;
    notifyListeners();
  }
}
