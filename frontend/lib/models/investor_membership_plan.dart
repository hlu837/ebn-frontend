import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The Investor "Shareholder & Investor Membership" plan — price,
/// benefits, and copy shown on the signup/upgrade screen. Fetched from
/// `GET /api/config/investor-membership-plan` so an admin can change the
/// price or benefits (see `AdminInvestorMembershipPlanScreen`) without an
/// app redeploy. [kDefaultInvestorMembershipPlan] below is only used as
/// an offline-safe placeholder while the real value loads.
class InvestorMembershipPlan {
  final int stepNumber;
  final String title;
  final double priceEtb;
  final String description;
  final List<String> benefits;
  final String footerNote;
  final Color primaryColor;
  final Color headerBgColor;
  final String tierKey;

  const InvestorMembershipPlan({
    required this.stepNumber,
    required this.title,
    required this.priceEtb,
    required this.description,
    required this.benefits,
    required this.footerNote,
    required this.primaryColor,
    required this.headerBgColor,
    required this.tierKey,
  });

  String get formattedPrice {
    final s = priceEtb.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final posFromEnd = s.length - i;
      buffer.write(s[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) buffer.write(',');
    }
    return '${buffer.toString()} ETB';
  }

  factory InvestorMembershipPlan.fromJson(Map<String, dynamic> json) {
    return InvestorMembershipPlan(
      stepNumber: 4,
      title: json['title'] as String? ?? kDefaultInvestorMembershipPlan.title,
      priceEtb: (json['priceEtb'] as num?)?.toDouble() ??
          kDefaultInvestorMembershipPlan.priceEtb,
      description: json['description'] as String? ??
          kDefaultInvestorMembershipPlan.description,
      benefits: (json['benefits'] as List<dynamic>?)?.cast<String>() ??
          kDefaultInvestorMembershipPlan.benefits,
      footerNote: json['footerNote'] as String? ??
          kDefaultInvestorMembershipPlan.footerNote,
      primaryColor: AppColors.ink,
      headerBgColor: const Color(0xFFF3F1ED),
      tierKey: json['tierKey'] as String? ??
          kDefaultInvestorMembershipPlan.tierKey,
    );
  }
}

/// Offline-safe placeholder shown only until the real plan loads from the
/// server, or if the device has no connection — never displayed as if it
/// were confirmed, live pricing (see [InvestorMembershipPlanSelectScreen]).
const kDefaultInvestorMembershipPlan = InvestorMembershipPlan(
  stepNumber: 4,
  title: 'SHAREHOLDER & INVESTOR\nMEMBERSHIP',
  priceEtb: 1500000,
  description: 'Become part of the future vision of AEBNG.',
  benefits: [
    'Shareholder Opportunity',
    'Executive-Level Access',
    'Partnership Opportunities',
    'Major Investment Projects',
    'Priority Business Deals',
    'Long-Term Growth Benefits',
    'Leadership Participation',
    'National & International Expansion Opportunities',
  ],
  footerNote: 'Join the exclusive investor circle.',
  primaryColor: AppColors.ink,
  headerBgColor: Color(0xFFF3F1ED),
  tierKey: 'investor_shareholder',
);
