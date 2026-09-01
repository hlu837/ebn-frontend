import 'package:flutter/material.dart';
import 'asset_detail_screen.dart';
import 'ebn_landing_page.dart';
import 'role_select_screen.dart';
import 'about_us_screen.dart';
import 'contact_us_screen.dart';
import 'faq_screen.dart';
import 'how_it_works_screen.dart';
import 'membership_screen.dart';
import 'platform_features_screen.dart';
import 'broker_map_screen.dart';
import '../data/faq_data.dart';
import '../data/landing_content.dart';
import '../l10n/app_localizations.dart';
import '../models/asset.dart';
import '../models/auth_response.dart';
import '../models/user_role.dart';
import '../services/asset_service.dart';
import '../theme/landing_colors.dart';
import '../widgets/asset_list_card.dart';
import '../widgets/landing_shared.dart';

// Guest user for viewing listings without authentication
const _kGuestUser = AppUser(
  id: 'guest',
  fullName: 'Guest User',
  email: 'guest@ebn.et',
  role: UserRole.user,
);

// -----------------------------------------------------------------------------
// Maps the marketing "services" categories (in the order they're declared in
// landing_content.dart) onto the Asset model's category enum, so category
// chips and search results can filter the live listings feed below.
// Order: Vehicles, Machinery, House, Warehouse, Land, Construction
// Materials, Broker List.
// The last entry (Broker List) isn't a real asset category — it's handled
// as a special case in the grid's onTap below, opening the broker
// directory instead of filtering listings, so its slug here is a
// placeholder that's never used for filtering.
// -----------------------------------------------------------------------------
const _serviceToAssetCategory = <AssetCategorySlug>[
  AssetCategorySlug.vehicles,
  AssetCategorySlug.machinery,
  AssetCategorySlug.house,
  AssetCategorySlug.warehouse,
  AssetCategorySlug.others,
  AssetCategorySlug.constructionMaterials,
  AssetCategorySlug.others,
];

// Index of the "Broker List" tile within `kServices` — kept as a constant
// so the special-cased tap handling below doesn't rely on a magic number.
const _brokerListServiceIndex = 6;

// -----------------------------------------------------------------------------
// Section anchors -- module-level so they survive rebuilds; used so the
// landing-page search can scroll straight to the section a result lives in.
// The properties key is a GlobalKey<State> so search can also reach into
// _PropertiesSection and apply a filter directly.
// -----------------------------------------------------------------------------
final _propertiesSectionKey = GlobalKey<_PropertiesSectionState>();

void _scrollToSection(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx != null) {
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }
}

void _scrollToProperties({AssetCategorySlug? category, String? query}) {
  _propertiesSectionKey.currentState?.applyExternalFilter(
    category: category,
    query: query,
  );
  _scrollToSection(_propertiesSectionKey);
}

/// Real `GET /api/assets` results, once loaded — kept here (rather than on
/// [_PropertiesSectionState] alone) so the top-nav search index, which is
/// built synchronously on tap outside of any fetch, can use the same real
/// data instead of only ever knowing about the bundled mock list. Falls
/// Empty until the first successful `GET /api/assets` fetch lands.
List<Asset> _cachedLandingAssets = [];

// -----------------------------------------------------------------------------
// Landing-page search -- now spans marketing pages *and* the live listings.
// -----------------------------------------------------------------------------
class _SearchResult {
  final String category;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onSelect;
  const _SearchResult({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onSelect,
  });
}

List<_SearchResult> _buildSearchIndex(
  BuildContext context, {
  required VoidCallback goToAboutUs,
  required VoidCallback goToContactUs,
  required VoidCallback goToFaq,
  required VoidCallback goToSignUp,
  required VoidCallback goToHowItWorks,
  required VoidCallback goToMembership,
  required VoidCallback goToPlatform,
}) {
  final results = <_SearchResult>[];

  for (int i = 0; i < kServices.length; i++) {
    final s = kServices[i];
    final assetCategory = _serviceToAssetCategory[i];
    final isBrokerList = i == _brokerListServiceIndex;
    results.add(
      _SearchResult(
        category: 'Category',
        title: s.title,
        subtitle: s.desc,
        icon: s.icon,
        onSelect: isBrokerList
            ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BrokerMapScreen(
                      category: AssetCategorySlug.others,
                      categoryLabel: 'All',
                      showAllBrokers: true,
                    ),
                  ),
                )
            : () => _scrollToProperties(category: assetCategory),
      ),
    );
    if (isBrokerList) continue;
    for (final sub in s.subcategories) {
      results.add(
        _SearchResult(
          category: s.title,
          title: sub,
          subtitle: 'Subcategory under ${s.title}',
          icon: s.icon,
          onSelect: () =>
              _scrollToProperties(category: assetCategory, query: sub),
        ),
      );
    }
  }
  for (final asset in _cachedLandingAssets) {
    results.add(
      _SearchResult(
        category: asset.category.label,
        title: asset.title,
        subtitle: '${asset.formattedPrice} \u00b7 ${asset.city ?? ''}',
        icon: Icons.location_on_outlined,
        onSelect: () =>
            _scrollToProperties(category: asset.category, query: asset.title),
      ),
    );
  }
  for (final step in kSteps) {
    results.add(
      _SearchResult(
        category: 'How it works',
        title: step.title,
        subtitle: step.desc,
        icon: step.icon,
        onSelect: goToHowItWorks,
      ),
    );
  }
  for (final tier in kTiers) {
    results.add(
      _SearchResult(
        category: 'Membership',
        title: tier.name,
        subtitle: tier.priority,
        icon: tier.icon,
        onSelect: goToMembership,
      ),
    );
  }
  for (final feature in kFeatures) {
    results.add(
      _SearchResult(
        category: 'Platform',
        title: feature.title,
        subtitle: 'Key platform feature',
        icon: feature.icon,
        onSelect: goToPlatform,
      ),
    );
  }
  for (final faq in faqItems) {
    results.add(
      _SearchResult(
        category: 'FAQ',
        title: faq.question,
        subtitle: faq.answer,
        icon: Icons.help_outline,
        onSelect: goToFaq,
      ),
    );
  }
  results.add(
    _SearchResult(
      category: 'Page',
      title: 'About Us',
      subtitle: 'Learn more about EBN',
      icon: Icons.info_outline,
      onSelect: goToAboutUs,
    ),
  );
  results.add(
    _SearchResult(
      category: 'Page',
      title: 'Contact Us',
      subtitle: 'Get in touch with the team',
      icon: Icons.mail_outline,
      onSelect: goToContactUs,
    ),
  );
  results.add(
    _SearchResult(
      category: 'Action',
      title: 'Sign Up / Get Started',
      subtitle: 'Create an account',
      icon: Icons.arrow_forward,
      onSelect: goToSignUp,
    ),
  );
  return results;
}

class _LandingSearchDelegate extends SearchDelegate<void> {
  final List<_SearchResult> results;
  _LandingSearchDelegate(this.results)
      : super(searchFieldLabel: 'Search EBN\u2026');

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
              icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final q = query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? results
        : results.where((result) {
            return result.title.toLowerCase().contains(q) ||
                result.subtitle.toLowerCase().contains(q) ||
                result.category.toLowerCase().contains(q);
          }).toList();
    if (filtered.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No matches found.',
            style: TextStyle(color: LandingColors.muted),
          ),
        ),
      );
    }
    return Container(
      color: LandingColors.background,
      child: ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: LandingColors.border),
        itemBuilder: (context, index) {
          final result = filtered[index];
          return ListTile(
            leading: Icon(result.icon, color: LandingColors.gold),
            title: Text(result.title),
            subtitle: Text(result.subtitle),
            trailing: Text(result.category),
            onTap: () {
              close(context, null);
              result.onSelect();
            },
          );
        },
      ),
    );
  }
}

class RoleGateScreen extends StatelessWidget {
  const RoleGateScreen({super.key});

  void _goToRoleSelect(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
    );
  }

  void _goToAboutUs(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AboutUsScreen()),
    );
  }

  void _goToContactUs(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ContactUsScreen()),
    );
  }

  void _goToFaq(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const FaqScreen()));
  }

  void _goToHowItWorks(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HowItWorksScreen()),
    );
  }

  void _goToMembership(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MembershipScreen()),
    );
  }

  void _goToPlatform(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlatformFeaturesScreen()),
    );
  }

  void _openSearch(BuildContext context) {
    final index = _buildSearchIndex(
      context,
      goToAboutUs: () => _goToAboutUs(context),
      goToContactUs: () => _goToContactUs(context),
      goToFaq: () => _goToFaq(context),
      goToSignUp: () => _goToRoleSelect(context),
      goToHowItWorks: () => _goToHowItWorks(context),
      goToMembership: () => _goToMembership(context),
      goToPlatform: () => _goToPlatform(context),
    );
    showSearch(context: context, delegate: _LandingSearchDelegate(index));
  }

  @override
  Widget build(BuildContext context) {
    return EBNLandingPage(onOpenSearch: () => _openSearch(context));
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color background;
  final Color iconColor;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.background,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: LandingColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: LandingColors.foreground,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: LandingColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// FULL CATEGORY GRID -- the big icon grid Jiji shows below its "Recommended"
// strip (Post ad / Trending / Vehicles / Property / ...), four tiles per row.
// "Post ad" always leads, highlighted in gold, mirroring Jiji's orange tile.
// -----------------------------------------------------------------------------
class _FullCategoryGrid extends StatelessWidget {
  final VoidCallback onPostAd;
  final void Function(int serviceIndex) onCategory;
  const _FullCategoryGrid({required this.onPostAd, required this.onCategory});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.text('categoryLabel'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: LandingColors.foreground,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 4,
            childAspectRatio: 0.76,
            children: [
              _GridCategoryTile(
                label: t.text('postAd'),
                icon: Icons.add_circle_rounded,
                highlighted: true,
                onTap: onPostAd,
              ),
              for (int i = 0; i < kServices.length; i++)
                _GridCategoryTile(
                  label: kServices[i].title,
                  icon: kServices[i].icon,
                  imageUrl: kServices[i].imageUrl,
                  onTap: () => onCategory(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GridCategoryTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? imageUrl;
  final bool highlighted;
  final VoidCallback onTap;
  const _GridCategoryTile({
    required this.label,
    required this.icon,
    this.imageUrl,
    this.highlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: highlighted
                  ? LandingColors.gold
                  : LandingColors.gold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: (imageUrl == null || highlighted)
                ? Icon(
                    icon,
                    size: 25,
                    color:
                        highlighted ? LandingColors.goldFg : LandingColors.gold,
                  )
                : Padding(
                    padding: const EdgeInsets.all(9),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(icon, size: 25, color: LandingColors.gold),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: LandingColors.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PROPERTIES -- the heart of the landing page now: category chips, a search
// box scoped to whichever category/subcategory is active, and the live
// listings feed. Search here only ever touches this section; the nav-bar
// search up top is the site-wide one and can also drop straight into this
// section with a category/query already applied (see _scrollToProperties).
// -----------------------------------------------------------------------------
class _PropertiesSection extends StatefulWidget {
  final VoidCallback onGetStarted;
  const _PropertiesSection({required this.onGetStarted});

  @override
  State<_PropertiesSection> createState() => _PropertiesSectionState();
}

class _PropertiesSectionState extends State<_PropertiesSection> {
  final TextEditingController _searchController = TextEditingController();
  AssetCategorySlug? _categoryFilter;

  final AssetService _assetService = AssetService();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    try {
      final assets = await _assetService.fetchAssets(limit: 200);
      if (!mounted) return;
      setState(() => _cachedLandingAssets = assets);
    } on AssetException catch (_) {
      // Backend down / unreachable — there's no bundled mock fallback, so
      // this just leaves `_cachedLandingAssets` as whatever it already was
      // (empty on first load, which renders the "No listings match your
      // search yet." empty state below).
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Called from the top-nav search so a result can both scroll here *and*
  /// pre-filter the section, e.g. tapping "Villas" under Property.
  void applyExternalFilter({AssetCategorySlug? category, String? query}) {
    setState(() {
      _categoryFilter = category;
      if (query != null) {
        _searchController.value = TextEditingValue(
          text: query,
          selection: TextSelection.collapsed(offset: query.length),
        );
      }
    });
  }

  List<Asset> get _visibleAssets {
    final query = _searchController.text.trim().toLowerCase();
    return _cachedLandingAssets.where((asset) {
      if (_categoryFilter != null && asset.category != _categoryFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        asset.title,
        asset.city ?? '',
        asset.addressLine ?? '',
        asset.category.label,
        asset.specLine,
        asset.attributes.values.join(' '),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  ServiceItem? get _activeService {
    if (_categoryFilter == null) return null;
    final i = _serviceToAssetCategory.indexOf(_categoryFilter!);
    return i == -1 ? null : kServices[i];
  }

  @override
  Widget build(BuildContext context) {
    final assets = _visibleAssets;
    final displayedAssets = assets.take(6).toList();
    final activeService = _activeService;
    final wide = !LandingBreakpoints.isMobile(context);
    final t = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 56),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: LandingColors.border)),
        color: Color(0xFFFFFFFF),
      ),
      child: MaxWidth(
        padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (activeService != null) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: activeService.subcategories.map((sub) {
                  final selected =
                      _searchController.text.trim().toLowerCase() ==
                          sub.toLowerCase();
                  return _SubcategoryChip(
                    label: sub,
                    selected: selected,
                    onTap: () => setState(
                      () => selected
                          ? _searchController.clear()
                          : _searchController.text = sub,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              activeService != null
                  ? '${activeService.title} listings'
                  : t.text('trendingAds'),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: LandingColors.foreground,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              t.text(
                'listingsAvailable',
                {
                  'count': assets.length.toString(),
                  'plural': assets.length == 1 ? '' : 's'
                },
              ),
              style: const TextStyle(
                fontSize: 12.5,
                color: LandingColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            if (displayedAssets.isEmpty)
              Container(
                decoration: BoxDecoration(
                  color: LandingColors.card,
                  border: Border.all(color: LandingColors.border),
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(vertical: 48),
                alignment: Alignment.center,
                child: Text(
                  t.text('noListingsMatchYourSearch'),
                  style: const TextStyle(color: LandingColors.muted),
                ),
              )
            else
              Padding(
                padding: EdgeInsets.all(wide ? 20 : 10),
                child: ResponsiveGrid(
                  itemCount: displayedAssets.length,
                  gap: 12,
                  breakpoints: const {0: 2, 640: 3, 1024: 4},
                  itemBuilder: (i) => AssetListCard(
                    asset: displayedAssets[i],
                    compact: true,
                    actionLabel: t.text('getStartedToRequest'),
                    onActionPressed: widget.onGetStarted,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AssetDetailScreen(
                            asset: displayedAssets[i],
                            user: _kGuestUser,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 40),
            _BrowseCta(onGetStarted: widget.onGetStarted),
          ],
        ),
      ),
    );
  }
}

class _SubcategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SubcategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? LandingColors.gold : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? LandingColors.gold : LandingColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: selected ? LandingColors.goldFg : LandingColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _BrowseCta extends StatelessWidget {
  final VoidCallback onGetStarted;
  const _BrowseCta({required this.onGetStarted});
  @override
  Widget build(BuildContext context) {
    final wide = LandingBreakpoints.isDesktop(context);
    final t = AppLocalizations.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.text('browseCtaTitle'),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: LandingColors.foreground,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          t.text('browseCtaSubtitle'),
          style: const TextStyle(fontSize: 14, color: LandingColors.muted),
        ),
      ],
    );
    final btn = GoldButton(
      label: t.text('getStartedSignUp'),
      trailing: Icons.arrow_forward,
      fontSize: 14,
      onTap: onGetStarted,
    );
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: LandingColors.card,
        border: Border.all(color: LandingColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: wide
          ? Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 24),
                btn,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 16), btn],
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// FOOTER
// -----------------------------------------------------------------------------
// Builds a language option for the popup menu, styled to match the landing
// page's warm cream / gold vibe (soft gold glyph chip + ink text) instead
// of the default Material list-tile look.
PopupMenuItem<String> _languageMenuItem(String value) {
  return PopupMenuItem<String>(
    value: value,
    height: 44,
    child: Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: LandingColors.gold.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.language,
            size: 14,
            color: LandingColors.gold,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: LandingColors.foreground,
          ),
        ),
      ],
    ),
  );
}

class _NavLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _NavLink(this.label);
  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: const TextStyle(color: Colors.white70, fontSize: 14),
    );
    if (onTap == null) return text;
    return InkWell(onTap: onTap, child: text);
  }
}

// -----------------------------------------------------------------------------
// MOBILE MENU SHEET -- hamburger destination, used on every breakpoint now
// that the nav bar itself only shows search / language / menu icons. Carries
// the secondary marketing links plus Log In and Get started.
// -----------------------------------------------------------------------------
class _MobileMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _MobileMenuItem(this.icon, this.label, this.onTap);
}

class _MobileMenuSheet extends StatelessWidget {
  final VoidCallback onHowItWorks;
  final VoidCallback onMembership;
  final VoidCallback onPlatform;
  final VoidCallback onAboutUs;
  final VoidCallback onContactUs;
  final VoidCallback onFaq;
  final VoidCallback onGetStarted;
  final VoidCallback onLogIn;
  const _MobileMenuSheet({
    required this.onHowItWorks,
    required this.onMembership,
    required this.onPlatform,
    required this.onAboutUs,
    required this.onContactUs,
    required this.onFaq,
    required this.onGetStarted,
    required this.onLogIn,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final items = [
      _MobileMenuItem(
          Icons.route_outlined, t.text('mobileHowItWorks'), onHowItWorks),
      _MobileMenuItem(
        Icons.workspace_premium_outlined,
        t.text('mobileMembership'),
        onMembership,
      ),
      _MobileMenuItem(
        Icons.dashboard_customize_outlined,
        t.text('mobilePlatform'),
        onPlatform,
      ),
      _MobileMenuItem(Icons.info_outline, t.text('mobileAboutUs'), onAboutUs),
      _MobileMenuItem(
          Icons.mail_outline, t.text('mobileContactUs'), onContactUs),
      _MobileMenuItem(Icons.help_outline, t.text('mobileFaq'), onFaq),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: LandingColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            for (final item in items)
              ListTile(
                leading: Icon(item.icon, color: LandingColors.gold),
                title: Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LandingColors.foreground,
                  ),
                ),
                onTap: item.onTap,
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: LandingColors.border),
            ),
            ListTile(
              leading: const Icon(Icons.login, color: LandingColors.gold),
              title: Text(
                t.text('mobileLogIn'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: LandingColors.foreground,
                ),
              ),
              onTap: onLogIn,
            ),
            ListTile(
              leading: const Icon(Icons.north_east, color: LandingColors.gold),
              title: Text(
                t.text('mobileGetStarted'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: LandingColors.foreground,
                ),
              ),
              onTap: onGetStarted,
            ),
          ],
        ),
      ),
    );
  }
}
