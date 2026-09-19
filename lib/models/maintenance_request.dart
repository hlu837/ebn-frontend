/// Mirrors the JSON shape returned by `/api/maintenance-requests/*` on the
/// real backend (`backend/src/models/maintenanceRequests.js` → `toPublic`).
/// Phase 1 of the maintenance-request workflow: tenant files an issue
/// against a unit they actively rent -> owner accepts (handles it
/// themselves) or rejects (tenant assigns a specialist directly — later
/// phase, not modeled yet).
library;

enum MaintenanceCategory { electrical, plumbing, structural, appliance, other }

extension MaintenanceCategoryX on MaintenanceCategory {
  static MaintenanceCategory fromWire(String? value) {
    switch (value) {
      case 'electrical':
        return MaintenanceCategory.electrical;
      case 'plumbing':
        return MaintenanceCategory.plumbing;
      case 'structural':
        return MaintenanceCategory.structural;
      case 'appliance':
        return MaintenanceCategory.appliance;
      case 'other':
      default:
        return MaintenanceCategory.other;
    }
  }

  String get wireValue {
    switch (this) {
      case MaintenanceCategory.electrical:
        return 'electrical';
      case MaintenanceCategory.plumbing:
        return 'plumbing';
      case MaintenanceCategory.structural:
        return 'structural';
      case MaintenanceCategory.appliance:
        return 'appliance';
      case MaintenanceCategory.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case MaintenanceCategory.electrical:
        return 'Electrical';
      case MaintenanceCategory.plumbing:
        return 'Plumbing';
      case MaintenanceCategory.structural:
        return 'Structural';
      case MaintenanceCategory.appliance:
        return 'Appliance';
      case MaintenanceCategory.other:
        return 'Other';
    }
  }
}

/// 'assigned' and 'completed' are Phase 4/6 additions (see
/// 083_maintenance_requests_assignment_status.sql) — a request only
/// reaches them once the tenant has picked a specialist from the
/// directory (MaintenanceAssignment) and, later, confirmed the job done.
enum MaintenanceRequestStatus { submitted, accepted, rejected, assigned, completed }

extension MaintenanceRequestStatusX on MaintenanceRequestStatus {
  static MaintenanceRequestStatus fromWire(String? value) {
    switch (value) {
      case 'accepted':
        return MaintenanceRequestStatus.accepted;
      case 'rejected':
        return MaintenanceRequestStatus.rejected;
      case 'assigned':
        return MaintenanceRequestStatus.assigned;
      case 'completed':
        return MaintenanceRequestStatus.completed;
      case 'submitted':
      default:
        return MaintenanceRequestStatus.submitted;
    }
  }

  String get label {
    switch (this) {
      case MaintenanceRequestStatus.submitted:
        return 'Awaiting owner';
      case MaintenanceRequestStatus.accepted:
        return 'Owner handling it';
      case MaintenanceRequestStatus.rejected:
        return 'Declined — assign a specialist';
      case MaintenanceRequestStatus.assigned:
        return 'Specialist assigned';
      case MaintenanceRequestStatus.completed:
        return 'Completed';
    }
  }
}

/// One of the caller's currently-active leases — returned by
/// `GET /api/maintenance-requests/eligible-assets`. Drives whether the
/// "Report a maintenance issue" button shows on a given
/// `_AgreementCard`, and which asset a new request is filed against.
class EligibleMaintenanceAsset {
  final String rentalAgreementId;
  final String assetId;
  final String assetTitle;
  final String? assetImageUrl;

  const EligibleMaintenanceAsset({
    required this.rentalAgreementId,
    required this.assetId,
    required this.assetTitle,
    this.assetImageUrl,
  });

  factory EligibleMaintenanceAsset.fromJson(Map<String, dynamic> json) {
    return EligibleMaintenanceAsset(
      rentalAgreementId: json['rentalAgreementId'] as String,
      assetId: json['assetId'] as String,
      assetTitle: json['assetTitle'] as String? ?? '',
      assetImageUrl: json['assetImageUrl'] as String?,
    );
  }
}

class MaintenanceRequestAsset {
  final String id;
  final String title;
  final String? imageUrl;
  const MaintenanceRequestAsset({required this.id, required this.title, this.imageUrl});

  factory MaintenanceRequestAsset.fromJson(Map<String, dynamic> json) {
    return MaintenanceRequestAsset(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

class MaintenanceRequest {
  final String id;
  final String rentalAgreementId;
  final String assetId;
  final String ownerId;
  final String tenantId;
  final MaintenanceCategory category;
  final String description;
  final List<String> photoUrls;
  final MaintenanceRequestStatus status;
  final DateTime? decidedAt;
  final String? decisionNote;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final MaintenanceRequestAsset? asset;

  const MaintenanceRequest({
    required this.id,
    required this.rentalAgreementId,
    required this.assetId,
    required this.ownerId,
    required this.tenantId,
    required this.category,
    required this.description,
    this.photoUrls = const [],
    required this.status,
    this.decidedAt,
    this.decisionNote,
    required this.createdAt,
    this.updatedAt,
    this.asset,
  });

  factory MaintenanceRequest.fromJson(Map<String, dynamic> json) {
    return MaintenanceRequest(
      id: json['id'] as String,
      rentalAgreementId: json['rentalAgreementId'] as String,
      assetId: json['assetId'] as String,
      ownerId: json['ownerId'] as String,
      tenantId: json['tenantId'] as String,
      category: MaintenanceCategoryX.fromWire(json['category'] as String?),
      description: json['description'] as String? ?? '',
      photoUrls: (json['photoUrls'] as List<dynamic>? ?? const []).map((e) => e as String).toList(),
      status: MaintenanceRequestStatusX.fromWire(json['status'] as String?),
      decidedAt: json['decidedAt'] != null ? DateTime.tryParse(json['decidedAt'] as String) : null,
      decisionNote: json['decisionNote'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
      asset: json['asset'] != null ? MaintenanceRequestAsset.fromJson(json['asset'] as Map<String, dynamic>) : null,
    );
  }
}
