import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/admin_settings_models.dart';
import '../models/investor_membership_plan.dart';
import '../models/membership_pricing_models.dart';

/// Thrown for any admin-settings call the backend rejects. [message] is
/// safe to show directly in a SnackBar.
class AdminSettingsServiceException implements Exception {
  final String message;
  const AdminSettingsServiceException(this.message);

  @override
  String toString() => message;
}

/// Talks to the real backend's `/api/admin-settings/*` routes — mirrors
/// [AdminService]'s shape and conventions.
class AdminSettingsService {
  static const String baseUrl = ApiConfig.baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  // ── Categories ──────────────────────────────────────────────────────

  Future<List<AdminCategory>> fetchCategories({required String token}) async {
    final json = await _get('/api/admin-settings/categories', token: token);
    final rows =
        (json['categories'] as List<dynamic>).cast<Map<String, dynamic>>();
    return rows.map(AdminCategory.fromJson).toList();
  }

  Future<AdminCategory> createCategory({
    required String label,
    required int listingFeeCents,
    required String token,
  }) async {
    final json = await _post(
      '/api/admin-settings/categories',
      {'label': label, 'listingFeeCents': listingFeeCents},
      token: token,
    );
    return AdminCategory.fromJson(json);
  }

  Future<AdminCategory> updateCategory(
    String id, {
    String? label,
    int? listingFeeCents,
    bool? isActive,
    required String token,
  }) async {
    final json = await _patch(
      '/api/admin-settings/categories/$id',
      {
        if (label != null) 'label': label,
        if (listingFeeCents != null) 'listingFeeCents': listingFeeCents,
        if (isActive != null) 'isActive': isActive,
      },
      token: token,
    );
    return AdminCategory.fromJson(json);
  }

  Future<List<AdminCategory>> reorderCategories(List<String> orderedIds,
      {required String token}) async {
    final json = await _put(
        '/api/admin-settings/categories/reorder', {'orderedIds': orderedIds},
        token: token);
    final rows =
        (json['categories'] as List<dynamic>).cast<Map<String, dynamic>>();
    return rows.map(AdminCategory.fromJson).toList();
  }

  Future<void> archiveCategory(String id, {required String token}) async {
    await _delete('/api/admin-settings/categories/$id', token: token);
  }

  // ── Cities ──────────────────────────────────────────────────────────

  Future<List<AdminCity>> fetchCities({required String token}) async {
    final json = await _get('/api/admin-settings/cities', token: token);
    final rows = (json['cities'] as List<dynamic>).cast<Map<String, dynamic>>();
    return rows.map(AdminCity.fromJson).toList();
  }

  Future<AdminCity> createCity(
      {required String name, bool isLive = true, required String token}) async {
    final json = await _post(
        '/api/admin-settings/cities', {'name': name, 'isLive': isLive},
        token: token);
    return AdminCity.fromJson(json);
  }

  Future<AdminCity> updateCity(String id,
      {String? name, bool? isLive, required String token}) async {
    final json = await _patch(
      '/api/admin-settings/cities/$id',
      {if (name != null) 'name': name, if (isLive != null) 'isLive': isLive},
      token: token,
    );
    return AdminCity.fromJson(json);
  }

  Future<void> removeCity(String id, {required String token}) async {
    await _delete('/api/admin-settings/cities/$id', token: token);
  }

  // ── Service Providers (maintenance-request workflow Phase 3) ────────

  Future<List<AdminServiceProvider>> fetchServiceProviders({required String token}) async {
    final json = await _get('/api/admin-settings/service-providers', token: token);
    final rows = (json['serviceProviders'] as List<dynamic>).cast<Map<String, dynamic>>();
    return rows.map(AdminServiceProvider.fromJson).toList();
  }

  // No createServiceProvider anymore -- onboarding is self-service via the
  // Affiliater's own "Become an Expert" flow (POST
  // /api/affiliates/me/expert-profile). Admin only reviews (PATCH
  // isActive), edits, and removes -- see updateServiceProvider/
  // removeServiceProvider below.

  Future<AdminServiceProvider> updateServiceProvider(
    String id, {
    String? name,
    String? category,
    String? phone,
    String? city,
    double? latitude,
    double? longitude,
    int? rateCents,
    double? rating,
    String? photoUrl,
    bool? isActive,
    required String token,
  }) async {
    final json = await _patch(
      '/api/admin-settings/service-providers/$id',
      {
        if (name != null) 'name': name,
        if (category != null) 'category': category,
        if (phone != null) 'phone': phone,
        if (city != null) 'city': city,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (rateCents != null) 'rateCents': rateCents,
        if (rating != null) 'rating': rating,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (isActive != null) 'isActive': isActive,
      },
      token: token,
    );
    return AdminServiceProvider.fromJson(json);
  }

  Future<void> removeServiceProvider(String id, {required String token}) async {
    await _delete('/api/admin-settings/service-providers/$id', token: token);
  }

  // ── Maintenance job oversight & specialist payouts (Phases 6-7) ─────

  Future<List<AdminServiceProviderBalance>> fetchServiceProviderWallets({required String token}) async {
    final json = await _getList('/api/admin-settings/service-providers/wallets', token: token);
    return json.map((e) => AdminServiceProviderBalance.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<({int balanceCents, List<AdminSpecialistWalletTransaction> transactions})> fetchServiceProviderWallet(
    String providerId, {
    required String token,
  }) async {
    final json = await _get('/api/admin-settings/service-providers/$providerId/wallet', token: token);
    final rows = (json['transactions'] as List<dynamic>).cast<Map<String, dynamic>>();
    return (
      balanceCents: (json['balanceCents'] as num?)?.toInt() ?? 0,
      transactions: rows.map(AdminSpecialistWalletTransaction.fromJson).toList(),
    );
  }

  Future<void> recordSpecialistPayout(
    String providerId, {
    required int amountCents,
    required String label,
    required String token,
  }) async {
    await _post(
      '/api/admin-settings/service-providers/$providerId/wallet/payout',
      {'amountCents': amountCents, 'label': label},
      token: token,
    );
  }

  Future<List<AdminMaintenanceAssignment>> fetchMaintenanceAssignments({required String token, String? escrowStatus}) async {
    final json = await _getList(
      '/api/admin-settings/maintenance-assignments${escrowStatus != null ? '?escrowStatus=$escrowStatus' : ''}',
      token: token,
    );
    return json.map((e) => AdminMaintenanceAssignment.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> refundMaintenanceAssignment(String id, {String? note, required String token}) async {
    await _patch('/api/admin-settings/maintenance-assignments/$id/refund', {if (note != null) 'note': note}, token: token);
  }

  // ── FAQ ─────────────────────────────────────────────────────────────

  Future<List<AdminFaqEntry>> fetchFaq({required String token}) async {
    final json = await _get('/api/admin-settings/faq', token: token);
    final rows = (json['faq'] as List<dynamic>).cast<Map<String, dynamic>>();
    return rows.map(AdminFaqEntry.fromJson).toList();
  }

  Future<AdminFaqEntry> createFaq(
      {required String question,
      required String answer,
      required String token}) async {
    final json = await _post(
        '/api/admin-settings/faq', {'question': question, 'answer': answer},
        token: token);
    return AdminFaqEntry.fromJson(json);
  }

  Future<AdminFaqEntry> updateFaq(
    String id, {
    String? question,
    String? answer,
    bool? isActive,
    required String token,
  }) async {
    final json = await _patch(
      '/api/admin-settings/faq/$id',
      {
        if (question != null) 'question': question,
        if (answer != null) 'answer': answer,
        if (isActive != null) 'isActive': isActive,
      },
      token: token,
    );
    return AdminFaqEntry.fromJson(json);
  }

  Future<void> removeFaq(String id, {required String token}) async {
    await _delete('/api/admin-settings/faq/$id', token: token);
  }

  // ── Content pages (About Us / Features) ────────────────────────────

  Future<List<AdminContentPage>> fetchContentPages(
      {required String token}) async {
    final json = await _get('/api/admin-settings/content-pages', token: token);
    final rows = (json['pages'] as List<dynamic>).cast<Map<String, dynamic>>();
    return rows.map(AdminContentPage.fromJson).toList();
  }

  Future<AdminContentPage> updateContentPage(
    String pageKey, {
    required String title,
    required String body,
    required String token,
  }) async {
    final json = await _put('/api/admin-settings/content-pages/$pageKey',
        {'title': title, 'body': body},
        token: token);
    return AdminContentPage.fromJson(json);
  }

  // ── Admin accounts ──────────────────────────────────────────────────

  Future<List<AdminAccountSummary>> fetchAdmins({required String token}) async {
    final json = await _get('/api/admin-settings/admins', token: token);
    final rows = (json['admins'] as List<dynamic>).cast<Map<String, dynamic>>();
    return rows.map(AdminAccountSummary.fromJson).toList();
  }

  Future<AdminAccountSummary> inviteAdmin({
    required String fullName,
    required String email,
    required String password,
    String? phone,
    required String token,
  }) async {
    final json = await _post(
      '/api/admin-settings/admins',
      {
        'fullName': fullName,
        'email': email,
        'password': password,
        if (phone != null) 'phone': phone
      },
      token: token,
    );
    return AdminAccountSummary.fromJson(json);
  }

  Future<void> revokeAdmin(String id, {required String token}) async {
    await _delete('/api/admin-settings/admins/$id', token: token);
  }

  // ── General settings ────────────────────────────────────────────────

  Future<AdminGeneralSettings> fetchGeneralSettings(
      {required String token}) async {
    final json = await _get('/api/admin-settings/general', token: token);
    return AdminGeneralSettings.fromJson(json);
  }

  /// GET /api/admin-settings/general with no auth header — the backend
  /// route is unauthenticated and returns only app name / logo / support
  /// email / support phone, which the guest landing page needs so it can
  /// show real platform contact details instead of a hardcoded number.
  Future<AdminGeneralSettings> fetchPublicGeneralSettings() async {
    final json = await _get('/api/admin-settings/general');
    return AdminGeneralSettings.fromJson(json);
  }

  Future<AdminGeneralSettings> updateGeneralSettings({
    String? appName,
    String? logoUrl,
    String? supportEmail,
    String? supportPhone,
    required String token,
  }) async {
    final json = await _patch(
      '/api/admin-settings/general',
      {
        if (appName != null) 'appName': appName,
        if (logoUrl != null) 'logoUrl': logoUrl,
        if (supportEmail != null) 'supportEmail': supportEmail,
        if (supportPhone != null) 'supportPhone': supportPhone,
      },
      token: token,
    );
    return AdminGeneralSettings.fromJson(json);
  }

  // ── Membership Pricing ────────────────────────────────────────────────

  /// GET /api/admin-settings/membership-pricing — fetches all tier prices
  Future<MembershipPricing> fetchMembershipPricing(
      {required String token}) async {
    final json =
        await _get('/api/admin-settings/membership-pricing', token: token);
    return MembershipPricing.fromJson(json);
  }

  /// PATCH /api/admin-settings/membership-pricing/:role/:tier
  Future<MembershipTierPrice> updateMembershipPrice({
    required String role,
    required String tier,
    required double monthlyFeeEtb,
    required String token,
  }) async {
    final json = await _patch(
      '/api/admin-settings/membership-pricing/$role/$tier',
      {'monthlyFeeEtb': monthlyFeeEtb},
      token: token,
    );
    return MembershipTierPrice.fromJson(json);
  }

  // ── Investor Membership Plan ────────────────────────────────────────────

  /// GET /api/admin-settings/investor-membership-plan
  Future<InvestorMembershipPlan> fetchInvestorMembershipPlan(
      {required String token}) async {
    final json = await _get('/api/admin-settings/investor-membership-plan',
        token: token);
    return InvestorMembershipPlan.fromJson(json);
  }

  /// PUT /api/admin-settings/investor-membership-plan
  Future<InvestorMembershipPlan> updateInvestorMembershipPlan({
    required String title,
    required String description,
    required double priceEtb,
    required List<String> benefits,
    required String footerNote,
    required String token,
  }) async {
    final json = await _put(
      '/api/admin-settings/investor-membership-plan',
      {
        'title': title,
        'description': description,
        'priceEtb': priceEtb,
        'benefits': benefits,
        'footerNote': footerNote,
      },
      token: token,
    );
    return InvestorMembershipPlan.fromJson(json);
  }

  // ── HTTP helpers — mirrors AdminService's _get/_patch/_decode ────────

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _get(String path, {String? token}) async {
    http.Response res;
    try {
      res = await http
          .get(_uri(path), headers: _headers(token))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const AdminSettingsServiceException(
          "Couldn't reach the server. Check your connection and try again.");
    }
    return _decode(res);
  }

  /// Same as [_get] but for endpoints that return a raw JSON array
  /// rather than an object — used by the maintenance-assignments/wallet
  /// endpoints (Phases 6-7), which don't follow the
  /// `{serviceProviders: [...]}` wrapping the older list endpoints use.
  Future<List<dynamic>> _getList(String path, {String? token}) async {
    http.Response res;
    try {
      res = await http
          .get(_uri(path), headers: _headers(token))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const AdminSettingsServiceException(
          "Couldn't reach the server. Check your connection and try again.");
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      Map<String, dynamic> json;
      try {
        final decoded = jsonDecode(res.body.isEmpty ? '{}' : res.body);
        json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } catch (_) {
        json = const {};
      }
      throw AdminSettingsServiceException(json['error'] as String? ?? 'Something went wrong (${res.statusCode}).');
    }
    try {
      return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {
      throw const AdminSettingsServiceException('Unexpected response from the server.');
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {String? token}) async {
    http.Response res;
    try {
      res = await http
          .post(_uri(path), headers: _headers(token), body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const AdminSettingsServiceException(
          "Couldn't reach the server. Check your connection and try again.");
    }
    return _decode(res);
  }

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body,
      {String? token}) async {
    http.Response res;
    try {
      res = await http
          .patch(_uri(path), headers: _headers(token), body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const AdminSettingsServiceException(
          "Couldn't reach the server. Check your connection and try again.");
    }
    return _decode(res);
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body,
      {String? token}) async {
    http.Response res;
    try {
      res = await http
          .put(_uri(path), headers: _headers(token), body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const AdminSettingsServiceException(
          "Couldn't reach the server. Check your connection and try again.");
    }
    return _decode(res);
  }

  Future<Map<String, dynamic>> _delete(String path, {String? token}) async {
    http.Response res;
    try {
      res = await http
          .delete(_uri(path), headers: _headers(token))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const AdminSettingsServiceException(
          "Couldn't reach the server. Check your connection and try again.");
    }
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      throw const AdminSettingsServiceException(
          'Unexpected response from the server.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AdminSettingsServiceException(json['error'] as String? ??
          'Something went wrong (${res.statusCode}).');
    }
    return json;
  }
}
