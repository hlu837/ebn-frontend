import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/rental_agreement.dart';
import 'auth_service.dart';

/// Thrown for any /api/rental-agreements failure — safe to show directly
/// in a SnackBar.
class RentalAgreementException implements Exception {
  final String message;
  const RentalAgreementException(this.message);

  @override
  String toString() => message;
}

/// Talks to the real backend's `/api/rental-agreements/*` routes — the
/// Review tab's document review / agreement / payment pipeline.
class RentalAgreementService {
  static const String baseUrl = AuthService.baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// POST /api/rental-agreements — requester submits their digital ID +
  /// supporting documents against a rent_now request they already sent.
  Future<RentalAgreement> submitDocuments({
    required String token,
    required String propertyRequestId,
    required String idDocumentUrl,
    List<String> documentUrls = const [],
    String? note,
  }) async {
    final res = await _post('/api/rental-agreements', {
      'propertyRequestId': propertyRequestId,
      'idDocumentUrl': idDocumentUrl,
      'documentUrls': documentUrls,
      if (note != null) 'note': note,
    }, token: token);
    return RentalAgreement.fromJson(res);
  }

  /// GET /api/rental-agreements/queue — the owner's Review tab.
  /// [status] one of 'active' (default) | 'documents_submitted' |
  /// 'agreement_sent' | 'paid' | 'rejected' | 'expired'.
  Future<List<RentalAgreement>> listQueue({required String token, String status = 'active'}) async {
    final res = await _getList('/api/rental-agreements/queue?status=$status', token: token);
    return res.map((e) => RentalAgreement.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /api/rental-agreements/mine — the requester's own pipeline rows.
  Future<List<RentalAgreement>> listMine({required String token}) async {
    final res = await _getList('/api/rental-agreements/mine', token: token);
    return res.map((e) => RentalAgreement.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /api/rental-agreements/:id
  Future<RentalAgreement> getById({required String token, required String id}) async {
    final res = await _get('/api/rental-agreements/$id', token: token);
    return RentalAgreement.fromJson(res);
  }

  /// POST /api/rental-agreements/:id/send — owner approves and sends the
  /// agreement, starting the payment countdown.
  Future<RentalAgreement> sendAgreement({
    required String token,
    required String id,
    required String terms,
    required double rentAmount,
    double? depositAmount,
    String currency = 'ETB',
    int hours = 24,
  }) async {
    final res = await _post('/api/rental-agreements/$id/send', {
      'terms': terms,
      'rentAmount': rentAmount,
      if (depositAmount != null) 'depositAmount': depositAmount,
      'currency': currency,
      'hours': hours,
    }, token: token);
    return RentalAgreement.fromJson(res);
  }

  /// POST /api/rental-agreements/:id/reject
  Future<RentalAgreement> reject({required String token, required String id, String? reason}) async {
    final res = await _post('/api/rental-agreements/$id/reject', {
      if (reason != null) 'reason': reason,
    }, token: token);
    return RentalAgreement.fromJson(res);
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
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const RentalAgreementException("Couldn't reach the server. Check your connection and try again.");
    }
    return _decodeObject(res);
  }

  Future<Map<String, dynamic>> _get(String path, {required String token}) async {
    http.Response res;
    try {
      res = await http.get(_uri(path), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const RentalAgreementException("Couldn't reach the server. Check your connection and try again.");
    }
    return _decodeObject(res);
  }

  Future<List<dynamic>> _getList(String path, {required String token}) async {
    http.Response res;
    try {
      res = await http.get(_uri(path), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const RentalAgreementException("Couldn't reach the server. Check your connection and try again.");
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw RentalAgreementException(_errorFrom(res));
    }
    try {
      return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {
      throw const RentalAgreementException('Unexpected response from the server.');
    }
  }

  Map<String, dynamic> _decodeObject(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw RentalAgreementException(_errorFrom(res));
    }
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const RentalAgreementException('Unexpected response from the server.');
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
