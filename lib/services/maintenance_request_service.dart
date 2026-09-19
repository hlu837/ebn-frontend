import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/maintenance_request.dart';
import 'auth_service.dart';

/// Thrown for any /api/maintenance-requests failure — safe to show
/// directly in a SnackBar.
class MaintenanceRequestException implements Exception {
  final String message;
  const MaintenanceRequestException(this.message);

  @override
  String toString() => message;
}

/// Talks to the real backend's `/api/maintenance-requests/*` routes —
/// Phase 1 of the maintenance-request workflow (tenant files -> owner
/// accepts/rejects).
class MaintenanceRequestService {
  static const String baseUrl = AuthService.baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// GET /api/maintenance-requests/eligible-assets — which of the
  /// caller's leases are currently active, i.e. which assets they're
  /// allowed to file a request against. Empty list means no button
  /// should show anywhere.
  Future<List<EligibleMaintenanceAsset>> fetchEligibleAssets({required String token}) async {
    final json = await _getList('/api/maintenance-requests/eligible-assets', token: token);
    return json.map((e) => EligibleMaintenanceAsset.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// POST /api/maintenance-requests — tenant files a new request.
  Future<MaintenanceRequest> submit({
    required String token,
    required String assetId,
    required MaintenanceCategory category,
    required String description,
    List<String> photoUrls = const [],
  }) async {
    final json = await _post(
      '/api/maintenance-requests',
      {
        'assetId': assetId,
        'category': category.wireValue,
        'description': description,
        'photoUrls': photoUrls,
      },
      token: token,
    );
    return MaintenanceRequest.fromJson(json);
  }

  /// GET /api/maintenance-requests/mine — the caller's own filed requests, as a tenant.
  Future<List<MaintenanceRequest>> fetchMine({required String token}) async {
    final json = await _getList('/api/maintenance-requests/mine', token: token);
    return json.map((e) => MaintenanceRequest.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /api/maintenance-requests/queue — the caller's incoming requests, as an owner.
  Future<List<MaintenanceRequest>> fetchQueue({required String token, String? status}) async {
    final path = status == null
        ? '/api/maintenance-requests/queue'
        : '/api/maintenance-requests/queue?status=$status';
    final json = await _getList(path, token: token);
    return json.map((e) => MaintenanceRequest.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// PATCH /api/maintenance-requests/:id/decide — owner accepts or rejects.
  Future<MaintenanceRequest> decide({
    required String token,
    required String id,
    required bool accept,
    String? note,
  }) async {
    final json = await _patch(
      '/api/maintenance-requests/$id/decide',
      {'accept': accept, if (note != null) 'note': note},
      token: token,
    );
    return MaintenanceRequest.fromJson(json);
  }

  // ── HTTP helpers — mirrors RentalAgreementService's shape ────────────

  Future<Map<String, dynamic>> _get(String path, {required String token}) async {
    http.Response res;
    try {
      res = await http
          .get(_uri(path), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const MaintenanceRequestException("Couldn't reach the server. Check your connection and try again.");
    }
    return _decodeObject(res);
  }

  Future<List<dynamic>> _getList(String path, {required String token}) async {
    http.Response res;
    try {
      res = await http
          .get(_uri(path), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const MaintenanceRequestException("Couldn't reach the server. Check your connection and try again.");
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MaintenanceRequestException(_errorFrom(res));
    }
    try {
      return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {
      throw const MaintenanceRequestException('Unexpected response from the server.');
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {required String token}) async {
    http.Response res;
    try {
      res = await http
          .post(
            _uri(path),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const MaintenanceRequestException("Couldn't reach the server. Check your connection and try again.");
    }
    return _decodeObject(res);
  }

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body, {required String token}) async {
    http.Response res;
    try {
      res = await http
          .patch(
            _uri(path),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const MaintenanceRequestException("Couldn't reach the server. Check your connection and try again.");
    }
    return _decodeObject(res);
  }

  Map<String, dynamic> _decodeObject(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MaintenanceRequestException(_errorFrom(res));
    }
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const MaintenanceRequestException('Unexpected response from the server.');
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
