import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/maintenance_assignment.dart';
import 'auth_service.dart';

/// Thrown for any /api/maintenance-assignments failure — safe to show
/// directly in a SnackBar.
class MaintenanceAssignmentException implements Exception {
  final String message;
  const MaintenanceAssignmentException(this.message);

  @override
  String toString() => message;
}

/// Talks to the real backend's `/api/maintenance-assignments/*` routes —
/// Phase 4 (tenant assigns a specialist) and Phase 6 (tenant confirms the
/// job done and releases escrow) of the maintenance-request workflow.
/// Escrow payment itself (Phase 5) goes through the generic
/// PaymentService, same two-step pattern rental_agreement payments use —
/// see assign_specialist_screen.dart.
class MaintenanceAssignmentService {
  static const String baseUrl = AuthService.baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// POST /api/maintenance-assignments — tenant picks a specialist for a
  /// rejected request.
  Future<MaintenanceAssignment> assign({
    required String token,
    required String maintenanceRequestId,
    required String serviceProviderId,
    required int quotedCostCents,
  }) async {
    final json = await _post(
      '/api/maintenance-assignments',
      {
        'maintenanceRequestId': maintenanceRequestId,
        'serviceProviderId': serviceProviderId,
        'quotedCostCents': quotedCostCents,
      },
      token: token,
    );
    return MaintenanceAssignment.fromJson(json);
  }

  /// GET /api/maintenance-assignments/mine — the caller's own assignments, as a tenant.
  Future<List<MaintenanceAssignment>> fetchMine({required String token}) async {
    final json = await _getList('/api/maintenance-assignments/mine', token: token);
    return json.map((e) => MaintenanceAssignment.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /api/maintenance-assignments/:id
  Future<MaintenanceAssignment> fetchById({required String token, required String id}) async {
    final json = await _get('/api/maintenance-assignments/$id', token: token);
    return MaintenanceAssignment.fromJson(json);
  }

  /// PATCH /api/maintenance-assignments/:id/confirm-complete — tenant's
  /// single "job's done, release the payment" action.
  Future<MaintenanceAssignment> confirmComplete({required String token, required String id}) async {
    final json = await _patch('/api/maintenance-assignments/$id/confirm-complete', const {}, token: token);
    return MaintenanceAssignment.fromJson(json);
  }

  // ── HTTP helpers — mirrors MaintenanceRequestService's shape ────────

  Future<Map<String, dynamic>> _get(String path, {required String token}) async {
    http.Response res;
    try {
      res = await http
          .get(_uri(path), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const MaintenanceAssignmentException("Couldn't reach the server. Check your connection and try again.");
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
      throw const MaintenanceAssignmentException("Couldn't reach the server. Check your connection and try again.");
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MaintenanceAssignmentException(_errorFrom(res));
    }
    try {
      return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {
      throw const MaintenanceAssignmentException('Unexpected response from the server.');
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
      throw const MaintenanceAssignmentException("Couldn't reach the server. Check your connection and try again.");
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
      throw const MaintenanceAssignmentException("Couldn't reach the server. Check your connection and try again.");
    }
    return _decodeObject(res);
  }

  Map<String, dynamic> _decodeObject(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MaintenanceAssignmentException(_errorFrom(res));
    }
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const MaintenanceAssignmentException('Unexpected response from the server.');
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
