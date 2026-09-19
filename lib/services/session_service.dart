import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_response.dart';
import '../models/user_role.dart';

/// Persists the signed-in user's session (id/token/profile) to on-device
/// storage so it survives an app restart, and clears it cleanly on logout.
///
/// This is the single place that "catches" the session at both ends of
/// the auth lifecycle:
///  - [saveSession] is called right after a successful login/signup —
///    the moment a real token exists.
///  - [clearSession] is called right before a logout navigates away —
///    so a stale token is never left behind on the device.
///  - [restoreSession] is read once at app start (see `main.dart`) to
///    decide whether to skip straight to the user's dashboard or fall
///    back to the landing page.
class SessionService {
  SessionService._();

  static const _kSessionKey = 'ebn_session_user_v1';

  /// Saves [user] (including its `token`) as the active session. No-ops
  /// if the user has no token yet (e.g. an account still pending
  /// payment/approval) — there's nothing safe to restore later.
  static Future<void> saveSession(AppUser user) async {
    if (user.token == null || user.token!.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessionKey, jsonEncode(_toJson(user)));
  }

  /// Reads back whatever was last saved by [saveSession], or `null` if
  /// there's no saved session (never logged in, or already logged out).
  /// Does not talk to the network — callers that need to confirm the
  /// token is still valid should follow up with `AuthService.me(token)`.
  static Future<AppUser?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final token = json['token'] as String?;
      if (token == null || token.isEmpty) return null;
      return AppUser.fromJson(json, token: token);
    } catch (_) {
      // Corrupt/old-shape entry — treat as no session rather than crash.
      await clearSession();
      return null;
    }
  }

  /// Wipes the saved session. Safe to call even if nothing was saved.
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionKey);
  }

  static Map<String, dynamic> _toJson(AppUser user) => {
        'id': user.id,
        'fullName': user.fullName,
        'email': user.email,
        'role': user.role.apiValue,
        'phone': user.phone,
        'agencyOrLicense': user.agencyOrLicense,
        'interestedInFractionalInvesting':
            user.interestedInFractionalInvesting,
        'referralCode': user.referralCode,
        'agentLatitude': user.agentLatitude,
        'agentLongitude': user.agentLongitude,
        'accountStatus': user.accountStatus,
        'pendingRole': user.pendingRole,
        'token': user.token,
      };
}
