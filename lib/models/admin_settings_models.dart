/// Models backing the Admin > Settings screens — `/api/admin-settings/*`.
library;

class AdminCategory {
  final String id;
  final String slug;
  final String label;
  final int listingFeeCents;
  final int sortOrder;
  final bool isActive;

  const AdminCategory({
    required this.id,
    required this.slug,
    required this.label,
    required this.listingFeeCents,
    required this.sortOrder,
    required this.isActive,
  });

  double get listingFeeBirr => listingFeeCents / 100;

  factory AdminCategory.fromJson(Map<String, dynamic> json) {
    return AdminCategory(
      id: json['id'] as String,
      slug: json['slug'] as String? ?? '',
      label: json['label'] as String? ?? '',
      listingFeeCents: (json['listingFeeCents'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

class AdminCity {
  final String id;
  final String name;
  final bool isLive;
  final int sortOrder;

  const AdminCity({required this.id, required this.name, required this.isLive, required this.sortOrder});

  factory AdminCity.fromJson(Map<String, dynamic> json) {
    return AdminCity(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      isLive: json['isLive'] as bool? ?? true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Admin > Settings > Service Providers — the directory backing Phase 3
/// of the maintenance-request workflow (`/api/admin-settings/service-providers`).
/// `category` stays a raw wire string here (not an enum) since this
/// model is shared only within the admin CRUD screen; the tenant-facing
/// browse screen uses the richer `ServiceProviderCategory` enum in
/// `models/service_provider.dart`.
class AdminServiceProvider {
  final String id;
  final String name;
  final String category;
  final String phone;
  final String city;
  final double? latitude;
  final double? longitude;
  final int rateCents;
  final double? rating;
  final String? photoUrl;
  final bool isActive;
  final String? userId;

  const AdminServiceProvider({
    required this.id,
    required this.name,
    required this.category,
    required this.phone,
    required this.city,
    this.latitude,
    this.longitude,
    required this.rateCents,
    this.rating,
    this.photoUrl,
    required this.isActive,
    this.userId,
  });

  double get rateBirr => rateCents / 100;

  factory AdminServiceProvider.fromJson(Map<String, dynamic> json) {
    return AdminServiceProvider(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? 'other',
      phone: json['phone'] as String? ?? '',
      city: json['city'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      rateCents: (json['rateCents'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble(),
      photoUrl: json['photoUrl'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      userId: json['userId'] as String?,
    );
  }
}

/// GET /api/admin-settings/service-providers/wallets row — an
/// AdminServiceProvider plus its current specialist_wallet_transactions
/// balance (Phase 6). Balance is derived server-side (SUM of the
/// ledger), not stored on the provider row itself.
class AdminServiceProviderBalance {
  final AdminServiceProvider provider;
  final int balanceCents;
  const AdminServiceProviderBalance({required this.provider, required this.balanceCents});

  double get balanceBirr => balanceCents / 100;

  factory AdminServiceProviderBalance.fromJson(Map<String, dynamic> json) {
    return AdminServiceProviderBalance(
      provider: AdminServiceProvider.fromJson(json),
      balanceCents: (json['balanceCents'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One row of a specialist's payout ledger — GET
/// /api/admin-settings/service-providers/:id/wallet. Mirrors
/// specialist_wallet_transactions (085_specialist_wallet_transactions.sql):
/// 'credit' rows are positive (escrow released to them), 'payout' rows
/// are negative (admin recorded an offline payment already made).
class AdminSpecialistWalletTransaction {
  final String id;
  final String type; // 'credit' | 'payout'
  final int amountCents;
  final String label;
  final DateTime createdAt;

  const AdminSpecialistWalletTransaction({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.label,
    required this.createdAt,
  });

  double get amountBirr => amountCents / 100;

  factory AdminSpecialistWalletTransaction.fromJson(Map<String, dynamic> json) {
    return AdminSpecialistWalletTransaction(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'credit',
      amountCents: (json['amountCents'] as num?)?.toInt() ?? 0,
      label: json['label'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// GET /api/admin-settings/maintenance-assignments row — Phase 7
/// oversight: every job a tenant has assigned, with its escrow state, so
/// an admin can spot stuck payments or step into a dispute.
class AdminMaintenanceAssignment {
  final String id;
  final String maintenanceRequestId;
  final String escrowStatus; // pending_payment | held | released | refunded
  final int quotedCostCents;
  final String currency;
  final String? providerName;
  final String? providerPhone;
  final String? assetTitle;
  final DateTime createdAt;
  final DateTime? heldAt;
  final DateTime? releasedAt;
  final DateTime? refundedAt;

  const AdminMaintenanceAssignment({
    required this.id,
    required this.maintenanceRequestId,
    required this.escrowStatus,
    required this.quotedCostCents,
    required this.currency,
    this.providerName,
    this.providerPhone,
    this.assetTitle,
    required this.createdAt,
    this.heldAt,
    this.releasedAt,
    this.refundedAt,
  });

  double get quotedCostBirr => quotedCostCents / 100;

  factory AdminMaintenanceAssignment.fromJson(Map<String, dynamic> json) {
    return AdminMaintenanceAssignment(
      id: json['id'] as String,
      maintenanceRequestId: json['maintenanceRequestId'] as String,
      escrowStatus: json['escrowStatus'] as String? ?? 'pending_payment',
      quotedCostCents: (json['quotedCostCents'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'ETB',
      providerName: (json['provider'] as Map<String, dynamic>?)?['name'] as String?,
      providerPhone: (json['provider'] as Map<String, dynamic>?)?['phone'] as String?,
      assetTitle: (json['asset'] as Map<String, dynamic>?)?['title'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      heldAt: json['heldAt'] != null ? DateTime.tryParse(json['heldAt'] as String) : null,
      releasedAt: json['releasedAt'] != null ? DateTime.tryParse(json['releasedAt'] as String) : null,
      refundedAt: json['refundedAt'] != null ? DateTime.tryParse(json['refundedAt'] as String) : null,
    );
  }
}

class AdminFaqEntry {
  final String id;
  final String question;
  final String answer;
  final int sortOrder;
  final bool isActive;

  const AdminFaqEntry({
    required this.id,
    required this.question,
    required this.answer,
    required this.sortOrder,
    required this.isActive,
  });

  factory AdminFaqEntry.fromJson(Map<String, dynamic> json) {
    return AdminFaqEntry(
      id: json['id'] as String,
      question: json['question'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

class AdminContentPage {
  final String pageKey;
  final String title;
  final String body;

  const AdminContentPage({required this.pageKey, required this.title, required this.body});

  factory AdminContentPage.fromJson(Map<String, dynamic> json) {
    return AdminContentPage(
      pageKey: json['pageKey'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
    );
  }
}

class AdminGeneralSettings {
  final String appName;
  final String? logoUrl;
  final String? supportEmail;
  final String? supportPhone;

  const AdminGeneralSettings({
    required this.appName,
    required this.logoUrl,
    required this.supportEmail,
    required this.supportPhone,
  });

  factory AdminGeneralSettings.fromJson(Map<String, dynamic> json) {
    return AdminGeneralSettings(
      appName: json['appName'] as String? ?? 'Onsite',
      logoUrl: json['logoUrl'] as String?,
      supportEmail: json['supportEmail'] as String?,
      supportPhone: json['supportPhone'] as String?,
    );
  }
}

class AdminAccountSummary {
  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final DateTime createdAt;

  const AdminAccountSummary({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.createdAt,
  });

  factory AdminAccountSummary.fromJson(Map<String, dynamic> json) {
    return AdminAccountSummary(
      id: json['id'] as String,
      fullName: json['fullName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
