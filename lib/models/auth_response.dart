import 'user_role.dart';

/// The signed-in user for this session, returned by the real auth backend
/// (`/api/auth/signup` and `/api/auth/signin`) via [AuthService].
class AppUser {
  final String id;
  final String fullName;
  final String email;
  final UserRole role;
  final String? phone;

  /// Agent / Broker only — agency name or license/ID number, captured at
  /// signup to signal a professional verification process.
  final String? agencyOrLicense;

  /// Investor only — opted in to fractional property investment updates.
  final bool interestedInFractionalInvesting;

  /// Optional — who gets affiliate credit for this signup.
  final String? referralCode;

  /// Agent only — where they currently are, set via
  /// `AuthService.updateAgentLocation`. Null until they've set it once.
  final double? agentLatitude;
  final double? agentLongitude;

  /// Account status: 'active', 'pending_payment', or 'pending_approval'
  final String? accountStatus;

  /// Role requested during signup waiting for payment/approval
  final String? pendingRole;

  /// The JWT issued by the backend for this session. Send it as
  /// `Authorization: Bearer <token>` on any authenticated request
  /// (e.g. `GET /api/auth/me`, or future `/api/tour-requests` calls).
  final String? token;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.phone,
    this.agencyOrLicense,
    this.interestedInFractionalInvesting = false,
    this.referralCode,
    this.agentLatitude,
    this.agentLongitude,
    this.accountStatus,
    this.pendingRole,
    this.token,
  });

  /// Builds an [AppUser] from the `user` object the backend returns, plus
  /// the sibling `token` field (present on signup/signin, absent on `/me`).
  factory AppUser.fromJson(Map<String, dynamic> json, {String? token}) {
    return AppUser(
      id: json['id'] as String,
      fullName: json['fullName'] as String,
      email: json['email'] as String,
      role: UserRole.values.firstWhere(
        (r) => r.apiValue == json['role'],
        orElse: () => UserRole.user,
      ),
      phone: json['phone'] as String?,
      agencyOrLicense: json['agencyOrLicense'] as String?,
      interestedInFractionalInvesting:
          json['interestedInFractionalInvesting'] as bool? ?? false,
      referralCode: json['referralCode'] as String?,
      agentLatitude: (json['agentLatitude'] as num?)?.toDouble(),
      agentLongitude: (json['agentLongitude'] as num?)?.toDouble(),
      accountStatus: json['accountStatus'] as String?,
      pendingRole: json['pendingRole'] as String?,
      token: token,
    );
  }

  /// Same user, with a few selective fields updated.
  AppUser copyWith({
    String? id,
    String? fullName,
    String? email,
    UserRole? role,
    String? phone,
    String? agencyOrLicense,
    bool? interestedInFractionalInvesting,
    String? referralCode,
    double? agentLatitude,
    double? agentLongitude,
    String? token,
    String? accountStatus,
    String? pendingRole,
  }) =>
      AppUser(
        id: id ?? this.id,
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        role: role ?? this.role,
        phone: phone ?? this.phone,
        agencyOrLicense: agencyOrLicense ?? this.agencyOrLicense,
        interestedInFractionalInvesting: interestedInFractionalInvesting ??
            this.interestedInFractionalInvesting,
        referralCode: referralCode ?? this.referralCode,
        agentLatitude: agentLatitude ?? this.agentLatitude,
        agentLongitude: agentLongitude ?? this.agentLongitude,
        token: token ?? this.token,
        accountStatus: accountStatus ?? this.accountStatus,
        pendingRole: pendingRole ?? this.pendingRole,
      );

  /// Same user, with a (possibly different) token attached.
  AppUser copyWithToken(String? newToken) => copyWith(token: newToken);
}
