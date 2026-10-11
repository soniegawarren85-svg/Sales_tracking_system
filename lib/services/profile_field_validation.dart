class ProfileFieldValidation {
  static String? name(String? value, {bool required = true}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return required ? 'This field is required.' : null;
    }
    if (!RegExp(r'^[\p{L}\s]+$', unicode: true).hasMatch(text)) {
      return 'Use letters and spaces only.';
    }
    return wordLimit(text);
  }

  static String? gmail(String? value, {bool required = true}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return required ? 'Enter your Gmail address.' : null;
    }
    if (!RegExp(
      r'^[A-Z0-9._%+-]+@gmail\.com$',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'Enter a valid Gmail address.';
    }
    return null;
  }

  static String? age(String? value, {bool required = true}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return required ? 'Enter your age.' : null;
    }
    final age = int.tryParse(text);
    if (age == null || age < 21 || age > 50) {
      return 'Age must be between 21 and 50.';
    }
    return null;
  }

  static String? phone(String? value, {bool required = true}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return required ? 'Enter your phone number.' : null;
    }
    if (!RegExp(r'^\d{11}$').hasMatch(text)) {
      return 'Phone number must be exactly 11 digits.';
    }
    return null;
  }

  static String? wordLimit(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (text.split(RegExp(r'\s+')).length > 20) {
      return 'Use no more than 20 words.';
    }
    return null;
  }
}
