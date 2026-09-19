import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/service_provider.dart';

/// Thrown for any /api/service-providers failure — safe to show directly
/// in a SnackBar.
class ServiceProviderServiceException implements Exception {
  final String message;
  const ServiceProviderServiceException(this.message);

  @override
  String toString() => message;
}

/// Talks to the real backend's `/api/service-providers/*` routes — the
/// tenant-facing browse side of Phase 3 of the maintenance-request
/// workflow. Admin CRUD for the same table lives under
/// `/api/admin-settings/service-providers` — see [AdminSettingsService].
class ServiceProviderService {
  static const String baseUrl = ApiConfig.baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// GET /api/service-providers — the active directory, optionally
  /// filtered by category and/or city.
  Future<List<ServiceProvider>> fetchDirectory({
    required String token,
    ServiceProviderCategory? category,
    String? city,
  }) async {
    final params = <String, String>{
      if (category != null) 'category': category.wireValue,
      if (city != null && city.isNotEmpty) 'city': city,
    };
    final uri = _uri('/api/service-providers').replace(queryParameters: params.isEmpty ? null : params);
    final json = await _getListAt(uri, token: token);
    return json.map((e) => ServiceProvider.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /api/service-providers/:id
  Future<ServiceProvider> fetchById({required String token, required String id}) async {
    final json = await _get('/api/service-providers/$id', token: token);
    return ServiceProvider.fromJson(json);
  }

  // ── HTTP helpers — mirrors MaintenanceRequestService's shape ─────────

  Future<Map<String, dynamic>> _get(String path, {required String token}) async {
    http.Response res;
    try {
      res = await http
          .get(_uri(path), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const ServiceProviderServiceException("Couldn't reach the server. Check your connection and try again.");
    }
    return _decodeObject(res);
  }

  Future<List<dynamic>> _getListAt(Uri uri, {required String token}) async {
    http.Response res;
    try {
      res = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const ServiceProviderServiceException("Couldn't reach the server. Check your connection and try again.");
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ServiceProviderServiceException(_errorFrom(res));
    }
    try {
      return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {
      throw const ServiceProviderServiceException('Unexpected response from the server.');
    }
  }

  Map<String, dynamic> _decodeObject(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ServiceProviderServiceException(_errorFrom(res));
    }
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const ServiceProviderServiceException('Unexpected response from the server.');
    }
  }

  String _errorFrom(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return 'Something went wrong (${res.statusCode}).';
  }
}
