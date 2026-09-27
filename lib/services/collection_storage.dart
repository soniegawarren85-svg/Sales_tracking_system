import 'package:shared_preferences/shared_preferences.dart';

abstract class CollectionStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PreferencesCollectionStorage implements CollectionStorage {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(key, value)) {
      throw StateError('Unable to persist offline records');
    }
  }
}
