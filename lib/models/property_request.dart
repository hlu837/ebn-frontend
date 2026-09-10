/// Mirrors the JSON shape returned by `/api/property-requests/*` on the
/// real backend (`backend/src/models/propertyRequests.js` → `toPublic`).
library;

import 'chat_message.dart' as chat;

enum PropertyRequestType { info, tour, rentNow }

extension PropertyRequestTypeX on PropertyRequestType {
  static PropertyRequestType fromWire(String? value) {
    switch (value) {
      case 'tour':
        return PropertyRequestType.tour;
      case 'rent_now':
        return PropertyRequestType.rentNow;
      case 'info':
      default:
        return PropertyRequestType.info;
    }
  }

  String get wireValue {
    switch (this) {
      case PropertyRequestType.tour:
        return 'tour';
      case PropertyRequestType.rentNow:
        return 'rent_now';
      case PropertyRequestType.info:
        return 'info';
    }
  }

  /// Short label for a chip/badge in the Inbox list.
  String get label {
    switch (this) {
      case PropertyRequestType.tour:
        return 'Tour';
      case PropertyRequestType.rentNow:
        return 'Rent Now';
      case PropertyRequestType.info:
        return 'Info';
    }
  }
}

enum PropertyRequestStatus { pending, inProgress, closed }

extension PropertyRequestStatusX on PropertyRequestStatus {
  static PropertyRequestStatus fromWire(String? value) {
    switch (value) {
      case 'in_progress':
        return PropertyRequestStatus.inProgress;
      case 'closed':
        return PropertyRequestStatus.closed;
      case 'pending':
      default:
        return PropertyRequestStatus.pending;
    }
  }

  String get wireValue {
    switch (this) {
      case PropertyRequestStatus.inProgress:
        return 'in_progress';
      case PropertyRequestStatus.closed:
        return 'closed';
      case PropertyRequestStatus.pending:
        return 'pending';
    }
  }

  /// "Next step" hint shown on the Inbox list/detail — kept in sync with
  /// what the Review tab will eventually let the owner do next.
  String get nextStepLabel {
    switch (this) {
      case PropertyRequestStatus.pending:
        return 'Needs your reply';
      case PropertyRequestStatus.inProgress:
        return 'Conversation in progress';
      case PropertyRequestStatus.closed:
        return 'Closed';
    }
  }
}

class PropertyRequestAsset {
  final String id;
  final String title;
  final String? imageUrl;
  const PropertyRequestAsset({required this.id, required this.title, this.imageUrl});

  factory PropertyRequestAsset.fromJson(Map<String, dynamic> json) {
    return PropertyRequestAsset(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

class PropertyRequestRequester {
  final String id;
  final String fullName;
  const PropertyRequestRequester({required this.id, required this.fullName});

  factory PropertyRequestRequester.fromJson(Map<String, dynamic> json) {
    return PropertyRequestRequester(
      id: json['id'] as String,
      fullName: json['fullName'] as String? ?? '',
    );
  }
}

class PropertyRequest {
  final String id;
  final String assetId;
  final String ownerId;
  final String requesterId;
  final PropertyRequestType requestType;
  final PropertyRequestStatus status;
  final String? threadId;
  final String? message;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final PropertyRequestAsset? asset;
  final PropertyRequestRequester? requester;
  final String? lastMessageBody;
  final DateTime? lastMessageAt;
  final int unreadCount;

  const PropertyRequest({
    required this.id,
    required this.assetId,
    required this.ownerId,
    required this.requesterId,
    required this.requestType,
    required this.status,
    this.threadId,
    this.message,
    required this.createdAt,
    this.updatedAt,
    this.asset,
    this.requester,
    this.lastMessageBody,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory PropertyRequest.fromJson(Map<String, dynamic> json) {
    return PropertyRequest(
      id: json['id'] as String,
      assetId: json['assetId'] as String,
      ownerId: json['ownerId'] as String,
      requesterId: json['requesterId'] as String,
      requestType: PropertyRequestTypeX.fromWire(json['requestType'] as String?),
      status: PropertyRequestStatusX.fromWire(json['status'] as String?),
      threadId: json['threadId'] as String?,
      message: json['message'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
      asset: json['asset'] != null ? PropertyRequestAsset.fromJson(json['asset'] as Map<String, dynamic>) : null,
      requester: json['requester'] != null
          ? PropertyRequestRequester.fromJson(json['requester'] as Map<String, dynamic>)
          : null,
      lastMessageBody: json['lastMessageBody'] as String?,
      lastMessageAt: json['lastMessageAt'] != null ? DateTime.tryParse(json['lastMessageAt'] as String) : null,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Builds the [chat.ChatThread] this request's conversation lives in,
  /// straight from the fields already embedded on the list/detail
  /// response — lets the Inbox open the existing chat screen
  /// ([BrokerChatScreen.fromThread]) without a separate fetch.
  chat.ChatThread toChatThread() {
    return chat.ChatThread(
      id: threadId ?? '',
      customerId: requesterId,
      agentId: ownerId,
      assetId: assetId,
      lastMessageBody: lastMessageBody,
      lastMessageAt: lastMessageAt,
      unreadCount: unreadCount,
      asset: asset != null ? chat.ChatThreadAsset(id: asset!.id, title: asset!.title, imageUrl: asset!.imageUrl) : null,
      otherParty: requester != null
          ? chat.ChatThreadOtherParty(id: requester!.id, fullName: requester!.fullName)
          : null,
    );
  }
}
