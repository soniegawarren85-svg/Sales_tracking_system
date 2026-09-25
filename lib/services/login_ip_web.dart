// Browsers cannot expose the device's network interface address.
import 'dart:convert';
import 'dart:html' as html;

Future<String?> loginIp() async {
  final response = await html.HttpRequest.getString(
    'https://api.ipify.org?format=json',
  ).timeout(const Duration(seconds: 3));
  return (jsonDecode(response) as Map)['ip']?.toString();
}
