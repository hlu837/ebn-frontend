import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/investor_membership_plan.dart';

class InvestorMembershipPlanException implements Exception {
  final String message;
  const InvestorMembershipPlanException(this.message);

  @override
  String toString() => message;
}

/// Talks to the public `GET /api/config/investor-membership-plan` route.
/// No auth required — this is shown before signup completes. Mirrors
/// [MapConfigService]'s shape.
class InvestorMembershipPlanService {
  static const String baseUrl = ApiConfig.baseUrl;

  Future<InvestorMembershipPlan> fetchPlan() async {
    http.Response res;
    try {
      res = await http
          .get(Uri.parse('$baseUrl/api/config/investor-membership-plan'))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const InvestorMembershipPlanException(
          "Couldn't reach the server for the membership plan.");
    }

    dynamic json;
    try {
      json = jsonDecode(res.body);
    } catch (_) {
      throw const InvestorMembershipPlanException(
          'Unexpected response from the server.');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final error =
          json is Map<String, dynamic> ? json['error'] as String? : null;
      throw InvestorMembershipPlanException(
          error ?? 'Membership plan isn\'t configured on the server yet.');
    }

    return InvestorMembershipPlan.fromJson(json as Map<String, dynamic>);
  }
}
