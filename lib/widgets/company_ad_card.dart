import 'package:flutter/material.dart';

import '../models/company_ad.dart';
import '../utils/media_encoding.dart';

/// The single source of truth for what a company ad card looks like.
///
/// Used in two places:
/// 1. The landing page's promo carousel (the real, live rendering).
/// 2. The admin "New/Edit Ad" compose sheet, as a live preview — so admins
///    see exactly how their title/description/image will be cropped and
///    laid out *before* they post it, instead of guessing.
///
/// Because both places import this same widget, the preview can never
/// drift out of sync with what actually gets published.
///
/// Layout: title + description + a "Learn More"/"View" pill on the left
/// (6/11 of the width), image filling the right (5/11 of the width) at a
/// fixed 202px height. The image is cropped with [BoxFit.cover] to fill
/// that box — the right side works out to roughly a 4:5 (portrait)
/// rectangle on a typical phone width, so a wide landscape photo will get
/// its left/right edges trimmed, and very tall photos will get their
/// top/bottom trimmed. Center the subject of the photo and avoid text or
/// logos near the edges for best results.
class CompanyAdCard extends StatelessWidget {
  const CompanyAdCard({
    super.key,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.hasLink,
    this.imageProvider,
    this.onTap,
    this.backgroundColor = const Color(0xFF1C1E22),
    this.accentColor = const Color(0xFFFF2636),
  });

  /// Build directly from a loaded [CompanyAd] (landing page usage).
  factory CompanyAdCard.fromAd(
    CompanyAd ad, {
    Key? key,
    VoidCallback? onTap,
  }) {
    return CompanyAdCard(
      key: key,
      title: ad.title,
      description: ad.description,
      imageUrl: ad.imageUrl,
      hasLink: ad.linkUrl != null,
      onTap: onTap,
    );
  }

  final String title;
  final String description;
  final String imageUrl;
  final bool hasLink;
  final ImageProvider<Object>? imageProvider;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final image = imageProvider ??
        (imageUrl.isEmpty ? null : dataUrlOrNetworkImage(imageUrl));
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 8, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title.isEmpty ? 'Ad title' : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    if (description.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasLink
                                ? Icons.open_in_new_rounded
                                : Icons.zoom_in_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            hasLink ? 'Learn More' : 'View',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: SizedBox(
                height: 202,
                child: image != null
                    ? Image(image: image, fit: BoxFit.cover)
                    : Container(
                        color: Colors.grey[850],
                        child: const Icon(
                          Icons.image_outlined,
                          color: Colors.white54,
                          size: 40,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
