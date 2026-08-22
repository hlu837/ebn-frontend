/// A single admin-authored ad card shown in the landing page's promo
/// carousel (replaces the old static "Order Verified Inspection" banner).
///
/// If [linkUrl] is set, tapping the card should open that URL. If it's
/// null, tapping the card should just zoom the image instead — see
/// `_CompanyAdsCarousel` in `ebn_landing_page.dart`.
class CompanyAd {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final String? linkUrl;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CompanyAd({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.linkUrl,
    required this.sortOrder,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CompanyAd.fromJson(Map<String, dynamic> json) {
    return CompanyAd(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      linkUrl: (json['linkUrl'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['linkUrl'] as String,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
