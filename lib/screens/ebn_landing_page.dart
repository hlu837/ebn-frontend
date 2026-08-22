import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'role_select_screen.dart';
import 'login_screen.dart';
import 'category_listing_screen.dart';
import 'broker_map_screen.dart';
import 'order_request_form_screen.dart';
import 'sell_property_form_screen.dart';
import 'support_screen.dart';
import '../models/asset.dart';
import '../models/auth_response.dart';
import '../models/company_ad.dart';
import '../models/user_role.dart';
import '../services/asset_service.dart';
import '../services/company_ad_service.dart';
import '../utils/media_encoding.dart';
import '../widgets/company_ad_card.dart';
import '../widgets/order_category_sheet.dart';
import 'asset_detail_screen.dart';

const _kGuestUser = AppUser(
  id: 'guest',
  fullName: 'Guest User',
  email: 'guest@ebn.et',
  role: UserRole.user,
);

class EBNColors {
  static const red = Color(0xFFFF2636);
  static const darkCard = Color(0xFF1C1E22);
  static const green = Color(0xFF1E8E3E);
  static const grey = Color(0xFF8A8D93);
  static const lightGrey = Color(0xFFF0F0F2);
  static const border = Color(0xFFE7E7EA);
}

// ---------------------------------------------------------------------------
// DATA MODELS
// ---------------------------------------------------------------------------

class QuickAction {
  final IconData icon;
  final String label;
  final bool highlighted;
  const QuickAction(this.icon, this.label, {this.highlighted = false});
}

// ---------------------------------------------------------------------------
// PAGE
// ---------------------------------------------------------------------------

class EBNLandingPage extends StatefulWidget {
  final VoidCallback? onOpenSearch;

  const EBNLandingPage({super.key, this.onOpenSearch});

  @override
  State<EBNLandingPage> createState() => _EBNLandingPageState();
}

class _EBNLandingPageState extends State<EBNLandingPage> {
  int _selectedTab = 0;

  // Only used by the static fallback banner (`_buildInspectionBanner`),
  // shown when there are no admin-authored company ads yet.
  final int _bannerIndex = 0;

  final AssetService _assetService = AssetService();
  final CompanyAdService _companyAdService = CompanyAdService();

  // Empty until the real `GET /api/assets` response lands — the trending
  // section shows a loading/empty state rather than made-up listings in
  // the meantime.
  List<Asset> _assets = [];
  bool _assetsLoading = true;

  // Admin-authored ad cards for the promo carousel (was a single static
  // "Order Verified Inspection" card — see `_buildInspectionBanner`,
  // now `_CompanyAdsCarousel`). Empty list until the real
  // `GET /api/company-ads` response lands.
  List<CompanyAd> _companyAds = [];
  bool _companyAdsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAssets();
    _loadCompanyAds();
  }

  Future<void> _loadCompanyAds() async {
    try {
      final ads = await _companyAdService.list();
      if (!mounted) return;
      setState(() {
        _companyAds = ads;
        _companyAdsLoading = false;
      });
    } on CompanyAdException catch (_) {
      // Backend down / unreachable — stop the spinner and fall back to
      // the static inspection banner rather than showing nothing.
      if (!mounted) return;
      setState(() => _companyAdsLoading = false);
    }
  }

  Future<void> _loadAssets() async {
    try {
      final assets = await _assetService.fetchAssets(limit: 200);
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _assetsLoading = false;
      });
    } on AssetException catch (_) {
      // Backend down / unreachable — stop the spinner and show the
      // "no listings" empty state rather than fabricated data.
      if (!mounted) return;
      setState(() => _assetsLoading = false);
    }
  }

  final List<String> _tabs = const [
    'For You',
    'Vehicles',
    'Real Estate',
    'Machinery',
  ];

  final List<QuickAction> _actions = const [
    QuickAction(Icons.add, 'Post Ad', highlighted: true),
    QuickAction(Icons.directions_car_outlined, 'Vehicles'),
    QuickAction(Icons.terrain_outlined, 'Machinery'),
    QuickAction(Icons.home_outlined, 'House'),
    QuickAction(Icons.warehouse_outlined, 'Warehouse'),
    QuickAction(Icons.landscape_outlined, 'Land'),
    QuickAction(Icons.swap_horiz, 'Materials'),
    QuickAction(Icons.groups_outlined, 'Brokers'),
  ];

  void _goToCategory(AssetCategorySlug slug, String label, IconData icon) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryListingScreen(
          category: slug,
          categoryLabel: label,
          categoryIcon: icon,
          onGetStarted: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const RoleSelectScreen()));
          },
        ),
      ),
    );
  }

  void _openOrderFlow() async {
    final category = await showOrderCategorySheet(context);
    if (category != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              OrderRequestFormScreen(user: _kGuestUser, category: category),
        ),
      );
    }
  }

  void _openSellFlow() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SellPropertyFormScreen(user: _kGuestUser),
      ),
    );
  }

  void _handleQuickAction(int index) {
    switch (index) {
      case 0: // Post Ad
        _openSellFlow();
        break;
      case 1: // Vehicles
        _goToCategory(
          AssetCategorySlug.vehicles,
          'Vehicles',
          Icons.directions_car_outlined,
        );
        break;
      case 2: // Machinery
        _goToCategory(
          AssetCategorySlug.machinery,
          'Machinery',
          Icons.terrain_outlined,
        );
        break;
      case 3: // House
        _goToCategory(AssetCategorySlug.house, 'House', Icons.home_outlined);
        break;
      case 4: // Warehouse
        _goToCategory(
          AssetCategorySlug.warehouse,
          'Warehouse',
          Icons.warehouse_outlined,
        );
        break;
      case 5: // Land
        _goToCategory(
          AssetCategorySlug.others,
          'Land',
          Icons.landscape_outlined,
        );
        break;
      case 6: // Materials
        _goToCategory(
          AssetCategorySlug.constructionMaterials,
          'Construction Materials',
          Icons.swap_horiz,
        );
        break;
      case 7: // Brokers
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const BrokerMapScreen(
              category: AssetCategorySlug.others,
              categoryLabel: 'All',
              showAllBrokers: true,
            ),
          ),
        );
        break;
    }
  }

  void _handleTabSelect(int index) {
    setState(() => _selectedTab = index);
    if (index == 1) {
      // Vehicles
      _goToCategory(
        AssetCategorySlug.vehicles,
        'Vehicles',
        Icons.directions_car_outlined,
      );
    } else if (index == 2) {
      // Real Estate
      _goToCategory(
        AssetCategorySlug.house,
        'Real Estate',
        Icons.home_outlined,
      );
    } else if (index == 3) {
      // Machinery
      _goToCategory(
        AssetCategorySlug.machinery,
        'Machinery',
        Icons.terrain_outlined,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(),
            _buildSearchBar(),
            _buildTabs(),
            _buildSafetyBanner(),
            if (_companyAdsLoading)
              const SizedBox.shrink()
            else if (_companyAds.isNotEmpty)
              _CompanyAdsCarousel(ads: _companyAds)
            else
              _buildInspectionBanner(),
            const SizedBox(height: 24),
            _buildQuickActions(),
            const SizedBox(height: 8),
            _buildOrderSellRow(),
            const SizedBox(height: 24),
            _buildTrendingHeader(),
            _buildTrendingGrid(),
            const SizedBox(height: 32),
            _buildCTASection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // --- Bottom Navigation Bar -------------------------------------------------

  Widget _buildBottomNavBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: EBNColors.border, width: 1)),
      ),
      child: BottomAppBar(
        elevation: 0,
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildBottomNavItem(
              icon: Icons.home_outlined,
              label: 'Main',
              onTap: () {
                // Home / Main - stay on landing page
                setState(() => _selectedTab = 0);
              },
            ),
            _buildBottomNavItem(
              icon: Icons.add_circle_outline,
              label: 'Post ad',
              onTap: () => _handleQuickAction(0),
            ),
            _buildBottomNavItem(
              icon: Icons.people_outlined,
              label: 'Brokers',
              onTap: () => _handleQuickAction(7),
            ),
            _buildBottomNavItem(
              icon: Icons.shopping_bag_outlined,
              label: 'Order',
              onTap: _openOrderFlow,
            ),
            _buildBottomNavItem(
              icon: Icons.help_outline,
              label: 'Support',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SupportScreen(user: _kGuestUser),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: EBNColors.grey, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: EBNColors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // --- Header --------------------------------------------------------------

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'EBN',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          Row(
            children: [
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: EBNColors.red,
                  side: const BorderSide(color: EBNColors.red, width: 1.4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Log In',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.search, size: 24),
                onPressed: widget.onOpenSearch,
              ),
              IconButton(
                icon: const Icon(Icons.language, size: 22),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Language selector: English (default)'),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Search bar ------------------------------------------------------------

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: GestureDetector(
        onTap: widget.onOpenSearch,
        child: const Row(
          children: [
            Icon(Icons.search, color: EBNColors.grey, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Search',
                style: TextStyle(color: EBNColors.grey, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Category tabs ---------------------------------------------------------

  Widget _buildTabs() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final selected = index == _selectedTab;
          return GestureDetector(
            onTap: () => _handleTabSelect(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? EBNColors.red : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: selected
                    ? null
                    : Border.all(color: EBNColors.border, width: 1),
              ),
              child: Text(
                _tabs[index],
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- Safety strip ------------------------------------------------------------

  Widget _buildSafetyBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFFDEDEB),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: EBNColors.red,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.black87,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: 'Stay safe with verified listings. ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: EBNColors.red,
                    ),
                  ),
                  TextSpan(
                    text:
                        'Request an on-site inspection before making transactions.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Dark promo / inspection carousel card ------------------------------------

  Widget _buildInspectionBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: EBNColors.darkCard,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 8, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order Verified\nInspection',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Get peace of mind with expert reporting.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton(
                        onPressed: _openOrderFlow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: EBNColors.red,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                        child: const Text(
                          'Request Now',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: SizedBox(
                  height: 190,
                  child: Container(
                    color: Colors.grey[850],
                    child: const Icon(
                      Icons.verified,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 12,
            left: 20,
            child: Row(
              children: List.generate(3, (i) {
                final active = i == _bannerIndex;
                return Container(
                  margin: const EdgeInsets.only(right: 5),
                  width: active ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: active ? 1 : 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // --- Quick action grid -------------------------------------------------------

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _actions.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 18,
          crossAxisSpacing: 8,
          childAspectRatio: 0.78,
        ),
        itemBuilder: (context, index) {
          final action = _actions[index];
          return GestureDetector(
            onTap: () => _handleQuickAction(index),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0F0EE),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    action.icon,
                    color: const Color(0xFF4A4A45),
                    size: 24,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  action.label,
                  style: const TextStyle(fontSize: 11.5, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Order us / Sell with us cards --------------------------------------------

  Widget _buildOrderSellRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _openOrderFlow,
              child: _infoCard(
                icon: Icons.verified_outlined,
                title: 'Order us',
                subtitle: 'get what you want',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _openSellFlow,
              child: _infoCard(
                icon: Icons.attach_money,
                title: 'Sell With Us',
                subtitle: 'Meet a broker',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EBNColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFF0F0EE),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF4A4A45)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: EBNColors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Trending ads --------------------------------------------------------------

  Widget _buildTrendingHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Trending Ads',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          GestureDetector(
            onTap: () {
              _goToCategory(
                AssetCategorySlug.house,
                'All Trending Ads',
                Icons.trending_up,
              );
            },
            child: const Row(
              children: [
                Text(
                  'See all',
                  style: TextStyle(
                    color: EBNColors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Icon(Icons.chevron_right, color: EBNColors.green, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Cards size themselves to their content instead of being forced into a
  // fixed-aspect-ratio grid cell (that approach requires hand-tuning a
  // magic ratio number every time the card's content changes, and drifts
  // out of sync — leaving either dead space or a bottom overflow).
  static const double _kTrendingGridSpacing = 16;

  Widget _buildTrendingGrid() {
    if (_assetsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_assets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Text(
          'No listings yet — check back soon.',
          textAlign: TextAlign.center,
          style: TextStyle(color: EBNColors.grey, fontSize: 13),
        ),
      );
    }
    final trending = _assets.take(4).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = (constraints.maxWidth - _kTrendingGridSpacing) / 2;
          return Wrap(
            spacing: _kTrendingGridSpacing,
            runSpacing: 20,
            children: [
              for (final asset in trending)
                SizedBox(
                  width: cardWidth,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AssetDetailScreen(asset: asset, user: _kGuestUser),
                        ),
                      );
                    },
                    child: _AdCard(asset: asset),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // --- CTA + footer -----------------------------------------------------------

  Widget _buildCTASection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      color: Colors.white,
      child: Column(
        children: [
          const Text(
            'Ready to verify with\nconfidence?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Join thousands of users securing their future today.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: EBNColors.grey),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: EBNColors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Get Started / Sign Up',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// COMPANY ADS CAROUSEL
// ---------------------------------------------------------------------------

/// Horizontally-scrollable carousel of admin-authored company ad cards,
/// replacing the old static "Order Verified Inspection" promo. Each ad
/// carries a title, description, image, and an optional link (set up
/// from the admin side — see `AdminCompanyAdsScreen`).
///
/// Tapping a card: if it has a link, open it (external browser); if it
/// doesn't, zoom the image full-screen instead.
class _CompanyAdsCarousel extends StatefulWidget {
  const _CompanyAdsCarousel({required this.ads});

  final List<CompanyAd> ads;

  @override
  State<_CompanyAdsCarousel> createState() => _CompanyAdsCarouselState();
}

class _CompanyAdsCarouselState extends State<_CompanyAdsCarousel> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap(CompanyAd ad) async {
    final link = ad.linkUrl;
    if (link != null && link.trim().isNotEmpty) {
      final uri = Uri.tryParse(link.trim());
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open that link.")),
        );
      }
      return;
    }
    // No link attached — zoom the image instead.
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _AdImageZoomDialog(imageUrl: ad.imageUrl),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
      children: [
        SizedBox(
          height: 190,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.ads.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final ad = widget.ads[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: CompanyAdCard.fromAd(ad, onTap: () => _handleTap(ad)),
              );
            },
          ),
        ),
        if (widget.ads.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.ads.length, (i) {
              final active = i == _index;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active
                      ? EBNColors.red
                      : EBNColors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ],
      ),
    );
  }
}


/// Full-screen, pinch-to-zoom image viewer shown when a company ad has no
/// link attached — tapping the card zooms the image instead of navigating.
class _AdImageZoomDialog extends StatelessWidget {
  const _AdImageZoomDialog({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final image = dataUrlOrNetworkImage(imageUrl);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: image != null
                  ? Image(image: image, fit: BoxFit.contain)
                  : const Icon(Icons.broken_image_outlined,
                      color: Colors.white54, size: 64),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AD CARD WIDGET
// ---------------------------------------------------------------------------

class _AdCard extends StatelessWidget {
  final Asset asset;
  const _AdCard({required this.asset});

  bool get _isNew => (asset.postedLabel ?? '').toLowerCase().contains('new');

  @override
  Widget build(BuildContext context) {
    final imageUrl = asset.imageUrl;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EBNColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 1.2,
                child: dataUrlOrNetworkImage(imageUrl) == null
                    ? Container(
                        color: Colors.grey[200],
                        child: const Icon(
                          Icons.image,
                          color: Colors.grey,
                          size: 36,
                        ),
                      )
                    : Image(
                        image: dataUrlOrNetworkImage(imageUrl)!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[200],
                            child: const Icon(
                              Icons.image,
                              color: Colors.grey,
                              size: 36,
                            ),
                          );
                        },
                      ),
              ),
              if (_isNew)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: EBNColors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'NEW',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite_border,
                    size: 14,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.formattedPrice,
                  style: const TextStyle(
                    color: EBNColors.green,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  asset.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 12,
                      color: EBNColors.grey,
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        asset.city ?? asset.addressLine ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: EBNColors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
                if (asset.specLine.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    asset.specLine,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
