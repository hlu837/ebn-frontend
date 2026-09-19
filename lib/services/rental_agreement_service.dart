import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/owner_bank_account.dart';
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
  /// Fayda ID number + supporting documents against a rent_now request
  /// they already sent.
  Future<RentalAgreement> submitDocuments({
    required String token,
    required String propertyRequestId,
    required String idDocumentUrl,
    required String faydaIdNumber,
    List<String> documentUrls = const [],
    String? note,
  }) async {
    final res = await _post('/api/rental-agreements', {
      'propertyRequestId': propertyRequestId,
      'idDocumentUrl': idDocumentUrl,
      'documentUrls': documentUrls,
      'faydaIdNumber': faydaIdNumber,
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
  /// agreement, starting the payment countdown. [termMonths] is optional
  /// — omit for a month-to-month arrangement with no fixed lease end.
  /// [advanceMonths] is how many months of rent the owner wants collected
  /// up front — the server computes the actual amount due from the
  /// listing's own monthly price, so no rent figure is sent from here.
  /// The agreement text itself is generated server-side from the
  /// standard lease template — there's no `terms` field to send.
  Future<RentalAgreement> sendAgreement({
    required String token,
    required String id,
    required int advanceMonths,
    double? depositAmount,
    int hours = 24,
    int? termMonths,
  }) async {
    final res = await _post('/api/rental-agreements/$id/send', {
      'advanceMonths': advanceMonths,
      if (depositAmount != null) 'depositAmount': depositAmount,
      'hours': hours,
      if (termMonths != null) 'termMonths': termMonths,
    }, token: token);
    return RentalAgreement.fromJson(res);
  }

  /// POST /api/rental-agreements/:id/accept — requester accepts the
  /// terms the owner sent. Required before payment can close the deal.
  Future<RentalAgreement> acceptAgreement({required String token, required String id}) async {
    final res = await _post('/api/rental-agreements/$id/accept', {}, token: token);
    return RentalAgreement.fromJson(res);
  }

  /// POST /api/rental-agreements/:id/submit-receipt — requester-side:
  /// after transferring rent via one of the owner's bank accounts, the
  /// tenant attaches their own proof of payment. [receiptUrl] is a data
  /// URI, same convention as idDocumentUrl. Moves the row to
  /// 'payment_submitted' and notifies the owner to review it.
  Future<RentalAgreement> submitReceipt({required String token, required String id, required String receiptUrl}) async {
    final res = await _post('/api/rental-agreements/$id/submit-receipt', {'receiptUrl': receiptUrl}, token: token);
    return RentalAgreement.fromJson(res);
  }

  /// POST /api/rental-agreements/:id/confirm-receipt — owner-side:
  /// the tenant-submitted receipt checks out, closes the deal.
  Future<RentalAgreement> confirmReceipt({required String token, required String id}) async {
    final res = await _post('/api/rental-agreements/$id/confirm-receipt', {}, token: token);
    return RentalAgreement.fromJson(res);
  }

  /// POST /api/rental-agreements/:id/reject-receipt — owner-side: the
  /// submitted receipt doesn't check out, sends it back for a
  /// re-upload rather than killing the deal outright. [reason] is
  /// shown to the tenant.
  Future<RentalAgreement> rejectReceipt({required String token, required String id, String? reason}) async {
    final res = await _post('/api/rental-agreements/$id/reject-receipt', {
      if (reason != null) 'reason': reason,
    }, token: token);
    return RentalAgreement.fromJson(res);
  }

  /// GET /api/rental-agreements/:id/document — the direct URL for the
  /// downloadable, signed lease agreement PDF (only available once
  /// status is 'paid'). Carries the token as `?token=` rather than a
  /// header since this is meant to be opened directly (e.g. via
  /// url_launcher) rather than fetched with an HTTP client — see
  /// backend routes/auth.js requireAuthQueryOk.
  Uri documentDownloadUri({required String token, required String id}) {
    return _uri('/api/rental-agreements/$id/document?token=${Uri.encodeQueryComponent(token)}');
  }

  /// POST /api/rental-agreements/:id/reject
  Future<RentalAgreement> reject({required String token, required String id, String? reason}) async {
    final res = await _post('/api/rental-agreements/$id/reject', {
      if (reason != null) 'reason': reason,
    }, token: token);
    return RentalAgreement.fromJson(res);
  }

  /// POST /api/rental-agreements/:id/mark-paid-manual — owner confirms a
  /// payment that happened outside Chapa (bank transfer, cash) and
  /// attaches proof. [receiptUrl] is a data URI, same convention as the
  /// requester's idDocumentUrl (see submit_rental_documents_screen.dart).
  Future<RentalAgreement> markPaidManually({required String token, required String id, required String receiptUrl}) async {
    final res = await _post('/api/rental-agreements/$id/mark-paid-manual', {'receiptUrl': receiptUrl}, token: token);
    return RentalAgreement.fromJson(res);
  }

  /// GET /api/rental-agreements/:id/bank-accounts — the owner's bank
  /// accounts to transfer rent into, shown on the payment screen once
  /// the tenant has accepted the agreement terms (409s before that).
  Future<List<OwnerBankAccount>> fetchBankAccounts({required String token, required String id}) async {
    final res = await _getList('/api/rental-agreements/$id/bank-accounts', token: token);
    return res.map((e) => OwnerBankAccount.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// POST /api/rental-agreements/:id/vacate — owner confirms the tenant
  /// moved out. The only thing that reopens the listing after a lease
  /// (see rentalAgreements.markVacated on the backend).
  Future<RentalAgreement> vacate({required String token, required String id}) async {
    final res = await _post('/api/rental-agreements/$id/vacate', {}, token: token);
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
