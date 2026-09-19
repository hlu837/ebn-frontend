/// Mirrors the JSON shape returned by `/api/maintenance-assignments/*` on
/// the real backend (`backend/src/models/maintenanceAssignments.js` →
/// `toPublic`). Phases 4-6 of the maintenance-request workflow: tenant
/// picks a specialist for a request the owner rejected, pays the quoted
/// cost into escrow, and later taps a single "confirm job done" action
/// that releases the payment. No provider login yet, so there's no
/// separate provider-side "mark complete" step — see
/// 084_maintenance_assignments.sql.
library;

enum EscrowStatus { pendingPayment, held, released, refunded }

extension EscrowStatusX on EscrowStatus {
  static EscrowStatus fromWire(String? value) {
    switch (value) {
      case 'held':
        return EscrowStatus.held;
      case 'released':
        return EscrowStatus.released;
      case 'refunded':
        return EscrowStatus.refunded;
      case 'pending_payment':
      default:
        return EscrowStatus.pendingPayment;
    }
  }

  String get label {
    switch (this) {
      case EscrowStatus.pendingPayment:
        return 'Awaiting payment';
      case EscrowStatus.held:
        return 'Payment held in escrow';
      case EscrowStatus.released:
        return 'Paid out';
      case EscrowStatus.refunded:
        return 'Refunded';
    }
  }
}

class MaintenanceAssignmentProvider {
  final String id;
  final String name;
  final String category;
  final String phone;
  const MaintenanceAssignmentProvider({required this.id, required this.name, required this.category, required this.phone});

  factory MaintenanceAssignmentProvider.fromJson(Map<String, dynamic> json) {
    return MaintenanceAssignmentProvider(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? 'other',
      phone: json['phone'] as String? ?? '',
    );
  }
}

class MaintenanceAssignmentAsset {
  final String id;
  final String title;
  final String? imageUrl;
  const MaintenanceAssignmentAsset({required this.id, required this.title, this.imageUrl});

  factory MaintenanceAssignmentAsset.fromJson(Map<String, dynamic> json) {
    return MaintenanceAssignmentAsset(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

class MaintenanceAssignment {
  final String id;
  final String maintenanceRequestId;
  final String serviceProviderId;
  final String tenantId;
  final int quotedCostCents;
  final String currency;
  final EscrowStatus escrowStatus;
  final String? paymentTxRef;
  final DateTime? heldAt;
  final DateTime? releasedAt;
  final DateTime? refundedAt;
  final String? refundNote;
  final DateTime? completedAt;
  final DateTime createdAt;
  final MaintenanceAssignmentProvider? provider;
  final MaintenanceAssignmentAsset? asset;

  const MaintenanceAssignment({
    required this.id,
    required this.maintenanceRequestId,
    required this.serviceProviderId,
    required this.tenantId,
    required this.quotedCostCents,
    this.currency = 'ETB',
    required this.escrowStatus,
    this.paymentTxRef,
    this.heldAt,
    this.releasedAt,
    this.refundedAt,
    this.refundNote,
    this.completedAt,
    required this.createdAt,
    this.provider,
    this.asset,
  });

  double get quotedCostBirr => quotedCostCents / 100;

  factory MaintenanceAssignment.fromJson(Map<String, dynamic> json) {
    return MaintenanceAssignment(
      id: json['id'] as String,
      maintenanceRequestId: json['maintenanceRequestId'] as String,
      serviceProviderId: json['serviceProviderId'] as String,
      tenantId: json['tenantId'] as String,
      quotedCostCents: (json['quotedCostCents'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'ETB',
      escrowStatus: EscrowStatusX.fromWire(json['escrowStatus'] as String?),
      paymentTxRef: json['paymentTxRef'] as String?,
      heldAt: json['heldAt'] != null ? DateTime.tryParse(json['heldAt'] as String) : null,
      releasedAt: json['releasedAt'] != null ? DateTime.tryParse(json['releasedAt'] as String) : null,
      refundedAt: json['refundedAt'] != null ? DateTime.tryParse(json['refundedAt'] as String) : null,
      refundNote: json['refundNote'] as String?,
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'] as String) : null,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      provider: json['provider'] != null
          ? MaintenanceAssignmentProvider.fromJson(json['provider'] as Map<String, dynamic>)
          : null,
      asset: json['asset'] != null ? MaintenanceAssignmentAsset.fromJson(json['asset'] as Map<String, dynamic>) : null,
    );
  }
}
