/// Mirrors the JSON shape returned by `/api/rental-agreements/*` on the
/// real backend (`backend/src/models/rentalAgreements.js` → `toPublic`).
/// This is the Review tab's full pipeline: requester submits ID +
/// documents -> owner reviews -> owner sends the rental agreement (24h
/// payment countdown) or rejects -> requester pays or the window lapses.
library;

enum RentalAgreementStatus { documentsSubmitted, agreementSent, paid, rejected, expired }

extension RentalAgreementStatusX on RentalAgreementStatus {
  static RentalAgreementStatus fromWire(String? value) {
    switch (value) {
      case 'agreement_sent':
        return RentalAgreementStatus.agreementSent;
      case 'paid':
        return RentalAgreementStatus.paid;
      case 'rejected':
        return RentalAgreementStatus.rejected;
      case 'expired':
        return RentalAgreementStatus.expired;
      case 'documents_submitted':
      default:
        return RentalAgreementStatus.documentsSubmitted;
    }
  }

  String get wireValue {
    switch (this) {
      case RentalAgreementStatus.agreementSent:
        return 'agreement_sent';
      case RentalAgreementStatus.paid:
        return 'paid';
      case RentalAgreementStatus.rejected:
        return 'rejected';
      case RentalAgreementStatus.expired:
        return 'expired';
      case RentalAgreementStatus.documentsSubmitted:
        return 'documents_submitted';
    }
  }

  /// Short label for a chip/badge.
  String get label {
    switch (this) {
      case RentalAgreementStatus.documentsSubmitted:
        return 'Needs review';
      case RentalAgreementStatus.agreementSent:
        return 'Awaiting payment';
      case RentalAgreementStatus.paid:
        return 'Closed';
      case RentalAgreementStatus.rejected:
        return 'Declined';
      case RentalAgreementStatus.expired:
        return 'Expired';
    }
  }
}

class RentalAgreementAsset {
  final String id;
  final String title;
  final String? imageUrl;
  const RentalAgreementAsset({required this.id, required this.title, this.imageUrl});

  factory RentalAgreementAsset.fromJson(Map<String, dynamic> json) {
    return RentalAgreementAsset(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

class RentalAgreementParty {
  final String id;
  final String fullName;
  const RentalAgreementParty({required this.id, required this.fullName});

  factory RentalAgreementParty.fromJson(Map<String, dynamic> json) {
    return RentalAgreementParty(id: json['id'] as String, fullName: json['fullName'] as String? ?? '');
  }
}

class RentalAgreement {
  final String id;
  final String propertyRequestId;
  final String assetId;
  final String ownerId;
  final String requesterId;
  final RentalAgreementStatus status;
  final String idDocumentUrl;
  final List<String> documentUrls;
  final String? requesterNote;
  final String? agreementTerms;
  final double? rentAmount;
  final double? depositAmount;
  final String currency;
  final DateTime? sentAt;
  final DateTime? expiresAt;
  final String? rejectedReason;
  final String? paymentTxRef;
  final DateTime? paidAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final RentalAgreementAsset? asset;
  final RentalAgreementParty? owner;
  final RentalAgreementParty? requester;
  final String? threadId;

  const RentalAgreement({
    required this.id,
    required this.propertyRequestId,
    required this.assetId,
    required this.ownerId,
    required this.requesterId,
    required this.status,
    required this.idDocumentUrl,
    this.documentUrls = const [],
    this.requesterNote,
    this.agreementTerms,
    this.rentAmount,
    this.depositAmount,
    this.currency = 'ETB',
    this.sentAt,
    this.expiresAt,
    this.rejectedReason,
    this.paymentTxRef,
    this.paidAt,
    required this.createdAt,
    this.updatedAt,
    this.asset,
    this.owner,
    this.requester,
    this.threadId,
  });

  /// Total the requester needs to pay to confirm — rent + deposit (if any).
  double get totalDue => (rentAmount ?? 0) + (depositAmount ?? 0);

  /// Null once paid/rejected/expired, or if no countdown was ever started.
  Duration? get timeLeft {
    if (status != RentalAgreementStatus.agreementSent || expiresAt == null) return null;
    final left = expiresAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  factory RentalAgreement.fromJson(Map<String, dynamic> json) {
    return RentalAgreement(
      id: json['id'] as String,
      propertyRequestId: json['propertyRequestId'] as String,
      assetId: json['assetId'] as String,
      ownerId: json['ownerId'] as String,
      requesterId: json['requesterId'] as String,
      status: RentalAgreementStatusX.fromWire(json['status'] as String?),
      idDocumentUrl: json['idDocumentUrl'] as String? ?? '',
      documentUrls: (json['documentUrls'] as List<dynamic>? ?? const []).map((e) => e as String).toList(),
      requesterNote: json['requesterNote'] as String?,
      agreementTerms: json['agreementTerms'] as String?,
      rentAmount: (json['rentAmount'] as num?)?.toDouble(),
      depositAmount: (json['depositAmount'] as num?)?.toDouble(),
      currency: json['currency'] as String? ?? 'ETB',
      sentAt: json['sentAt'] != null ? DateTime.tryParse(json['sentAt'] as String) : null,
      expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'] as String) : null,
      rejectedReason: json['rejectedReason'] as String?,
      paymentTxRef: json['paymentTxRef'] as String?,
      paidAt: json['paidAt'] != null ? DateTime.tryParse(json['paidAt'] as String) : null,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
      asset: json['asset'] != null ? RentalAgreementAsset.fromJson(json['asset'] as Map<String, dynamic>) : null,
      owner: json['owner'] != null ? RentalAgreementParty.fromJson(json['owner'] as Map<String, dynamic>) : null,
      requester:
          json['requester'] != null ? RentalAgreementParty.fromJson(json['requester'] as Map<String, dynamic>) : null,
      threadId: json['threadId'] as String?,
    );
  }
}
