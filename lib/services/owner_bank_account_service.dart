import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/owner_bank_account.dart';
import 'auth_service.dart';

/// Thrown for any /api/owner-bank-accounts failure — safe to show
/// directly in a SnackBar.
class OwnerBankAccountException implements Exception {
  final String message;
  const OwnerBankAccountException(this.message);

  @override
  String toString() => message;
}

/// Talks to `/api/owner-bank-accounts/*` — a property owner managing the
/// bank accounts a tenant sees on the payment screen once they accept a
/// rental agreement.
class OwnerBankAccountService {
  static const String baseUrl = AuthService.baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// GET /api/owner-bank-accounts/banks — banks currently accepted, for
  /// the "add account" dropdown.
  Future<List<PlatformBank>> fetchBanks({required String token}) async {
    final res = await _getList('/api/owner-bank-accounts/banks', token: token);
    final list = (res['banks'] as List<dynamic>? ?? const []);
    return list.map((e) => PlatformBank.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /api/owner-bank-accounts/me — the caller's own accounts, numbers
  /// masked.
  Future<List<OwnerBankAccount>> listMine({required String token}) async {
    final res = await _getRawList('/api/owner-bank-accounts/me', token: token);
    return res.map((e) => OwnerBankAccount.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// POST /api/owner-bank-accounts
  Future<OwnerBankAccount> create({
    required String token,
    required String bankId,
    required String accountName,
    required String accountNumber,
    bool? isDefault,
  }) async {
    final res = await _post('/api/owner-bank-accounts', {
      'bankId': bankId,
      'accountName': accountName,
      'accountNumber': accountNumber,
      if (isDefault != null) 'isDefault': isDefault,
    }, token: token);
    return OwnerBankAccount.fromJson(res);
  }

  /// PATCH /api/owner-bank-accounts/:id
  Future<OwnerBankAccount> update({
    required String token,
    required String id,
    String? bankId,
    String? accountName,
    String? accountNumber,
    bool? isDefault,
  }) async {
    final res = await _patch('/api/owner-bank-accounts/$id', {
      if (bankId != null) 'bankId': bankId,
      if (accountName != null) 'accountName': accountName,
      if (accountNumber != null) 'accountNumber': accountNumber,
      if (isDefault != null) 'isDefault': isDefault,
    }, token: token);
    return OwnerBankAccount.fromJson(res);
  }

  /// DELETE /api/owner-bank-accounts/:id
  Future<void> delete({required String token, required String id}) async {
    http.Response res;
    try {
      res = await http
          .delete(_uri('/api/owner-bank-accounts/$id'), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const OwnerBankAccountException("Couldn't reach the server. Check your connection and try again.");
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw OwnerBankAccountException(_errorFrom(res));
    }
  }

  // ── internals ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {required String token}) async {
    http.Response res;
    try {
      res = await http
          .post(_uri(path), headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const OwnerBankAccountException("Couldn't reach the server. Check your connection and try again.");
    }
    return _decodeObject(res);
  }

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body, {required String token}) async {
    http.Response res;
    try {
      res = await http
          .patch(_uri(path), headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const OwnerBankAccountException("Couldn't reach the server. Check your connection and try again.");
    }
    return _decodeObject(res);
  }

  Future<Map<String, dynamic>> _getList(String path, {required String token}) async {
    http.Response res;
    try {
      res = await http.get(_uri(path), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const OwnerBankAccountException("Couldn't reach the server. Check your connection and try again.");
    }
    return _decodeObject(res);
  }

  Future<List<dynamic>> _getRawList(String path, {required String token}) async {
    http.Response res;
    try {
      res = await http.get(_uri(path), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const OwnerBankAccountException("Couldn't reach the server. Check your connection and try again.");
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw OwnerBankAccountException(_errorFrom(res));
    }
    try {
      return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {
      throw const OwnerBankAccountException('Unexpected response from the server.');
    }
  }

  Map<String, dynamic> _decodeObject(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw OwnerBankAccountException(_errorFrom(res));
    }
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const OwnerBankAccountException('Unexpected response from the server.');
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
