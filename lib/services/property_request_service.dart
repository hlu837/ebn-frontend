import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart' as chat;
import '../models/property_request.dart';
import 'auth_service.dart';

/// Thrown for any /api/property-requests failure — bad request, a
/// listing with no owner set up for messaging, network error, etc.
/// [message] is safe to show directly in a SnackBar.
class PropertyRequestException implements Exception {
  final String message;
  const PropertyRequestException(this.message);

  @override
  String toString() => message;
}

/// Talks to the real backend's `/api/property-requests/*` routes — the
/// Property Owner Inbox. Actual messaging reuses `/api/chat/*`
/// (see `chat_service.dart`) via the thread each request is linked to.
class PropertyRequestService {
  static const String baseUrl = AuthService.baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// POST /api/property-requests — renter-side entry point. Returns both
  /// the created request and the chat thread it opened, so the caller
  /// can jump straight into the conversation.
  Future<(PropertyRequest, chat.ChatThread)> create({
    required String token,
    required String assetId,
    required PropertyRequestType requestType,
    required String message,
  }) async {
    final res = await _post('/api/property-requests', {
      'assetId': assetId,
      'requestType': requestType.wireValue,
      'message': message,
    }, token: token);
    return (
      PropertyRequest.fromJson(res['request'] as Map<String, dynamic>),
      chat.ChatThread.fromJson(res['thread'] as Map<String, dynamic>),
    );
  }

  /// GET /api/property-requests — the caller's Inbox as a Property
  /// Owner. Pass [status] as 'pending' | 'in_progress' | 'closed'.
  Future<List<PropertyRequest>> listInbox({
    required String token,
    String? status,
    String? assetId,
    PropertyRequestType? requestType,
  }) async {
    final params = <String, String>{
      if (status != null) 'status': status,
      if (assetId != null) 'assetId': assetId,
      if (requestType != null) 'requestType': requestType.wireValue,
    };
    final path = Uri(path: '/api/property-requests', queryParameters: params.isEmpty ? null : params).toString();
    final res = await _getList(path, token: token);
    return res.map((e) => PropertyRequest.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// PATCH /api/property-requests/:id/status
  Future<PropertyRequest> setStatus({
    required String token,
    required String id,
    required PropertyRequestStatus status,
  }) async {
    final res = await _patch('/api/property-requests/$id/status', {'status': status.wireValue}, token: token);
    return PropertyRequest.fromJson(res);
  }

  // ── internals ────────────────────────────────────────────────────────

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
      throw const PropertyRequestException("Couldn't reach the server. Check your connection and try again.");
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
      throw const PropertyRequestException("Couldn't reach the server. Check your connection and try again.");
    }
    return _decodeObject(res);
  }

  Future<List<dynamic>> _getList(String path, {required String token}) async {
    http.Response res;
    try {
      res = await http.get(_uri(path), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const PropertyRequestException("Couldn't reach the server. Check your connection and try again.");
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw PropertyRequestException(_errorFrom(res));
    }
    try {
      return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {
      throw const PropertyRequestException('Unexpected response from the server.');
    }
  }

  Map<String, dynamic> _decodeObject(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw PropertyRequestException(_errorFrom(res));
    }
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const PropertyRequestException('Unexpected response from the server.');
    }
  }

  String _errorFrom(http.Response res) {
    try {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return json['error'] as String? ?? 'Something went wrong (${res.statusCode}).';
    } catch (_) {
      return 'Something went wrong (${res.statusCode}).';
    }
  }
}
