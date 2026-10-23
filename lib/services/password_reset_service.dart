import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const passwordResetWindow = Duration(minutes: 3);
const passwordResetScreenLifetime = Duration(minutes: 10);
// Enable after the reset functions and email sender have been deployed.
const passwordResetApiUrl = String.fromEnvironment('PASSWORD_RESET_API_URL');

class PasswordResetSession {
  const PasswordResetSession({
    required this.email,
    required this.resendAvailableAt,
    this.requestId,
    this.statusToken,
    this.completed = false,
  });

  final String email;
  final DateTime resendAvailableAt;
  final String? requestId;
  final String? statusToken;
  final bool completed;

  DateTime get requestedAt => resendAvailableAt.subtract(passwordResetWindow);
  bool shouldResumeAt(DateTime now) =>
      completed || now.difference(requestedAt) < passwordResetScreenLifetime;

  static String newRequestId() {
    final random = Random.secure();
    return base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
  }

  static Future<PasswordResetSession?> restore() async {
    final preferences = await SharedPreferences.getInstance();
    final email = preferences.getString('passwordResetEmail');
    final millis = preferences.getInt('passwordResetResendAvailableAt');
    if (email == null || millis == null) return null;
    return PasswordResetSession(
      email: email,
      resendAvailableAt: DateTime.fromMillisecondsSinceEpoch(millis),
      requestId: preferences.getString('passwordResetRequestId'),
      statusToken: preferences.getString('passwordResetStatusToken'),
      completed: preferences.getBool('passwordResetCompleted') ?? false,
    );
  }

  Future<void> persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('passwordResetEmail', email);
    await preferences.setInt(
      'passwordResetResendAvailableAt',
      resendAvailableAt.millisecondsSinceEpoch,
    );
    for (final entry in {
      'passwordResetRequestId': requestId,
      'passwordResetStatusToken': statusToken,
    }.entries) {
      if (entry.value == null) {
        await preferences.remove(entry.key);
      } else {
        await preferences.setString(entry.key, entry.value!);
      }
    }
    await preferences.setBool('passwordResetCompleted', completed);
    await preferences.remove('passwordResetExpiresAt');
  }

  static Future<bool> markCompleted(String requestId) async {
    final session = await restore();
    if (session == null || session.requestId != requestId || requestId.isEmpty)
      return false;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('passwordResetCompleted', true);
    return true;
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in [
      'passwordResetEmail',
      'passwordResetResendAvailableAt',
      'passwordResetExpiresAt',
      'passwordResetRequestId',
      'passwordResetStatusToken',
      'passwordResetCompleted',
    ]) {
      await preferences.remove(key);
    }
  }
}

Future<Map<String, dynamic>> passwordResetRequest(
  String path,
  Map<String, dynamic> body,
) async {
  final response = await http
      .post(
        Uri.parse('$passwordResetApiUrl/$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
      .timeout(const Duration(seconds: 20));
  final result = jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError(
      result['message']?.toString() ??
          'Unable to complete the request. Please try again.',
    );
  }
  return result;
}
