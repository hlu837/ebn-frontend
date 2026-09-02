import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/company_ad.dart';

/// Thrown for any company-ads call the backend rejects or that fails to
/// reach the server. [message] is safe to show directly in a SnackBar.
class CompanyAdException implements Exception {
  final String message;
  const CompanyAdException(this.message);

  @override
  String toString() => message;
}

/// Talks to `/api/company-ads` — the admin-authored ad cards shown in the
/// landing page's promo carousel. GET is public (no token needed) and
/// returns active ads only unless [includeInactive] is set, which the
/// admin management screen uses to see everything. POST/PUT/DELETE
/// require an admin token, matching the backend's `requireAuth` + admin
/// role check.
class CompanyAdService {
  static const String baseUrl = ApiConfig.baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<List<CompanyAd>> list({bool includeInactive = false}) async {
    final res = await _get(includeInactive ? '/api/company-ads?all=1' : '/api/company-ads');
    return (jsonDecode(res) as List)
        .map((e) => CompanyAd.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CompanyAd> create({
    required String token,
    required String title,
    required String description,
    required String imageUrl,
    String? linkUrl,
    bool isActive = true,
  }) async {
    final res = await _send(
      'POST',
      '/api/company-ads',
      body: {
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'linkUrl': linkUrl,
        'isActive': isActive,
      },
      token: token,
    );
    return CompanyAd.fromJson(jsonDecode(res) as Map<String, dynamic>);
  }

  Future<CompanyAd> update({
    required String token,
    required String id,
    String? title,
    String? description,
    String? imageUrl,
    String? linkUrl,
    bool clearLink = false,
    int? sortOrder,
    bool? isActive,
  }) async {
    final res = await _send(
      'PUT',
      '/api/company-ads/$id',
      body: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (linkUrl != null || clearLink) 'linkUrl': clearLink ? '' : linkUrl,
        if (sortOrder != null) 'sortOrder': sortOrder,
        if (isActive != null) 'isActive': isActive,
      },
      token: token,
    );
    return CompanyAd.fromJson(jsonDecode(res) as Map<String, dynamic>);
  }

  Future<void> delete({required String token, required String id}) async {
    await _send('DELETE', '/api/company-ads/$id', token: token);
  }

  // ── internals ────────────────────────────────────────────────────────

  Future<String> _get(String path) async {
    http.Response res;
    try {
      res = await http.get(_uri(path)).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const CompanyAdException(
          "Couldn't reach the server. Check your connection and try again.");
    }
    return _decode(res);
  }

  Future<String> _send(String method, String path,
      {Map<String, dynamic>? body, required String token}) async {
    http.Response res;
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    try {
      switch (method) {
        case 'POST':
          res = await http
              .post(_uri(path), headers: headers, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 20));
          break;
        case 'PUT':
          res = await http
              .put(_uri(path), headers: headers, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 20));
          break;
        case 'DELETE':
          res = await http.delete(_uri(path), headers: headers).timeout(const Duration(seconds: 15));
          break;
        default:
          throw ArgumentError('Unsupported method: $method');
      }
    } catch (_) {
      throw const CompanyAdException(
          "Couldn't reach the server. Check your connection and try again.");
    }
    return _decode(res);
  }

  String _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String message = 'Something went wrong (${res.statusCode}).';
      try {
        final json = jsonDecode(res.body);
        if (json is Map<String, dynamic> && json['error'] is String) {
          message = json['error'] as String;
        }
      } catch (_) {}
      throw CompanyAdException(message);
    }
    return res.body;
  }
}
