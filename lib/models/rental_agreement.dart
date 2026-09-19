/// Mirrors the JSON shape returned by `/api/rental-agreements/*` on the
/// real backend (`backend/src/models/rentalAgreements.js` → `toPublic`).
/// This is the Review tab's full pipeline: requester submits ID +
/// documents -> owner reviews -> owner sends the rental agreement (24h
/// payment countdown) or rejects -> requester pays or the window lapses.
library;

import 'chat_message.dart' as chat;

enum RentalAgreementStatus { documentsSubmitted, agreementSent, accepted, paymentSubmitted, paid, rejected, expired }

extension RentalAgreementStatusX on RentalAgreementStatus {
  static RentalAgreementStatus fromWire(String? value) {
    switch (value) {
      case 'agreement_sent':
        return RentalAgreementStatus.agreementSent;
      case 'accepted':
        return RentalAgreementStatus.accepted;
      case 'payment_submitted':
        return RentalAgreementStatus.paymentSubmitted;
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
      case RentalAgreementStatus.accepted:
        return 'accepted';
      case RentalAgreementStatus.paymentSubmitted:
        return 'payment_submitted';
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
        return 'Review terms';
      case RentalAgreementStatus.accepted:
        return 'Awaiting payment';
      case RentalAgreementStatus.paymentSubmitted:
        return 'Receipt submitted';
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
  /// The listing's own advertised monthly rent — the figure
  /// [RentalAgreement.advanceMonths] gets multiplied against to produce
  /// [RentalAgreement.rentAmount]. Null only for very old rows joined
  /// against a listing whose price somehow isn't set.
  final double? priceAmount;
  final String? priceCurrency;
  const RentalAgreementAsset({
    required this.id,
    required this.title,
    this.imageUrl,
    this.priceAmount,
    this.priceCurrency,
  });

  factory RentalAgreementAsset.fromJson(Map<String, dynamic> json) {
    return RentalAgreementAsset(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      priceAmount: (json['priceAmount'] as num?)?.toDouble(),
      priceCurrency: json['priceCurrency'] as String?,
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
  final String? faydaIdNumber;
  final String? requesterNote;
  final String? agreementTerms;
  /// How many months of rent the owner asked for as advance payment —
  /// the input; [rentAmount] (months x the listing's monthly price) is
  /// the computed result. Null until the owner sends the agreement.
  final int? advanceMonths;
  final double? rentAmount;
  final double? depositAmount;
  final String currency;
  final DateTime? sentAt;
  final DateTime? expiresAt;
  final DateTime? acceptedAt;
  final String? rejectedReason;
  final String? paymentTxRef;
  final String paymentMethod;
  final String? receiptUrl;
  /// When the tenant themselves submitted [receiptUrl] via submitReceipt
  /// — null if this receipt was attached directly by the owner instead
  /// (markPaidManually), or if none was submitted yet.
  final DateTime? receiptSubmittedAt;
  /// Set when the owner sends a submitted receipt back for a re-upload
  /// (rejectReceipt) — cleared again once a fresh receipt comes in.
  final String? receiptRejectedReason;
  final DateTime? paidAt;
  final int? leaseTermMonths;
  final DateTime? leaseEndAt;
  final DateTime? vacatedAt;
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
    this.faydaIdNumber,
    this.requesterNote,
    this.agreementTerms,
    this.advanceMonths,
    this.rentAmount,
    this.depositAmount,
    this.currency = 'ETB',
    this.sentAt,
    this.expiresAt,
    this.acceptedAt,
    this.rejectedReason,
    this.paymentTxRef,
    this.paymentMethod = 'chapa',
    this.receiptUrl,
    this.receiptSubmittedAt,
    this.receiptRejectedReason,
    this.paidAt,
    this.leaseTermMonths,
    this.leaseEndAt,
    this.vacatedAt,
    required this.createdAt,
    this.updatedAt,
    this.asset,
    this.owner,
    this.requester,
    this.threadId,
  });

  /// Total the requester needs to pay to confirm — rent + deposit (if any).
  double get totalDue => (rentAmount ?? 0) + (depositAmount ?? 0);

  /// Null once paid/rejected/expired, or if no countdown was ever
  /// started. Stays live through 'accepted' too — accepting the terms
  /// doesn't pause the payment window, it's still the same countdown.
  Duration? get timeLeft {
    if ((status != RentalAgreementStatus.agreementSent && status != RentalAgreementStatus.accepted) ||
        expiresAt == null) {
      return null;
    }
    final left = expiresAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Builds a [chat.ChatThread] from this agreement's own joined asset/
  /// requester summary — no extra `/api/chat/*` call needed. Mirrors
  /// `PropertyRequest.toChatThread()`; used by the owner's Closed Deals
  /// list to jump straight into the tenant conversation.
  chat.ChatThread toChatThread() {
    return chat.ChatThread(
      id: threadId ?? '',
      customerId: requesterId,
      agentId: ownerId,
      assetId: assetId,
      lastMessageBody: null,
      lastMessageAt: null,
      unreadCount: 0,
      asset: asset != null ? chat.ChatThreadAsset(id: asset!.id, title: asset!.title, imageUrl: asset!.imageUrl) : null,
      otherParty: requester != null ? chat.ChatThreadOtherParty(id: requester!.id, fullName: requester!.fullName) : null,
    );
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
      faydaIdNumber: json['faydaIdNumber'] as String?,
      requesterNote: json['requesterNote'] as String?,
      agreementTerms: json['agreementTerms'] as String?,
      advanceMonths: (json['advanceMonths'] as num?)?.toInt(),
      rentAmount: (json['rentAmount'] as num?)?.toDouble(),
      depositAmount: (json['depositAmount'] as num?)?.toDouble(),
      currency: json['currency'] as String? ?? 'ETB',
      sentAt: json['sentAt'] != null ? DateTime.tryParse(json['sentAt'] as String) : null,
      expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'] as String) : null,
      acceptedAt: json['acceptedAt'] != null ? DateTime.tryParse(json['acceptedAt'] as String) : null,
      rejectedReason: json['rejectedReason'] as String?,
      paymentTxRef: json['paymentTxRef'] as String?,
      paymentMethod: json['paymentMethod'] as String? ?? 'chapa',
      receiptUrl: json['receiptUrl'] as String?,
      receiptSubmittedAt: json['receiptSubmittedAt'] != null ? DateTime.tryParse(json['receiptSubmittedAt'] as String) : null,
      receiptRejectedReason: json['receiptRejectedReason'] as String?,
      paidAt: json['paidAt'] != null ? DateTime.tryParse(json['paidAt'] as String) : null,
      leaseTermMonths: (json['leaseTermMonths'] as num?)?.toInt(),
      leaseEndAt: json['leaseEndAt'] != null ? DateTime.tryParse(json['leaseEndAt'] as String) : null,
      vacatedAt: json['vacatedAt'] != null ? DateTime.tryParse(json['vacatedAt'] as String) : null,
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
