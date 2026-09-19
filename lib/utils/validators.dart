class Validators {
  Validators._();

  static final RegExp _emailRegex = RegExp(r'^[\w\.\-+]+@([\w\-]+\.)+[\w\-]{2,}$');

  // Accepts optional leading + and 7-15 digits (E.164-ish, lenient for demo).
  static final RegExp _phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');

  // Ethiopian mobile numbers only, used on the SignUp form specifically:
  // local 10-digit (09XXXXXXXX / 07XXXXXXXX) or international with the
  // country code (+2519XXXXXXXX / +2517XXXXXXXX) — the latter is exactly
  // 13 characters, which is also the form's hard length cap.
  static final RegExp _signupPhoneRegex =
      RegExp(r'^(?:\+2519\d{8}|\+2517\d{8}|09\d{8}|07\d{8})$');

  // Digits anywhere in a name are rejected — "don't allow to use number"
  // per the SignUp form validation request.
  static final RegExp _digitRegex = RegExp(r'[0-9]');

  static String? fullName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Full name is required';
    if (v.length < 2) return 'Enter your full name';
    if (_digitRegex.hasMatch(v)) return 'Full name cannot contain numbers';
    return null;
  }

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  static String? phone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Phone number is required';
    if (!_phoneRegex.hasMatch(v)) return 'Enter a valid phone number';
    return null;
  }

  // Stricter phone check used only on the SignUp form (see the field's own
  // 13-char input limit + '0935779407' placeholder) — kept separate from
  // [phone] above so the more lenient general validator, still used on the
  // Sell/Rent property forms, doesn't change.
  static String? signupPhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Phone number is required';
    if (v.length > 13) return 'Phone number must be at most 13 characters';
    if (!_signupPhoneRegex.hasMatch(v)) {
      return 'Enter a valid phone number, e.g. 0935779407';
    }
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Use at least 6 characters';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    final v = value ?? '';
    if (v.isEmpty) return 'Please confirm your password';
    if (v != original) return 'Passwords do not match';
    return null;
  }

  static String? notEmpty(String? value, {String label = 'This field'}) {
    if ((value ?? '').trim().isEmpty) return '$label is required';
    return null;
  }
}
