import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'role_select_screen.dart';
import 'login_screen.dart';
import 'category_listing_screen.dart';
import 'broker_map_screen.dart';
import 'order_request_form_screen.dart';
import 'sell_property_form_screen.dart';
import 'support_screen.dart';
import '../l10n/app_localizations.dart';
import '../models/asset.dart';
import '../models/admin_settings_models.dart';
import '../models/auth_response.dart';
import '../models/company_ad.dart';
import '../models/order_request.dart';
import '../models/user_role.dart';
import '../providers/locale_controller.dart';
import '../services/admin_settings_service.dart';
import '../services/asset_service.dart';
import '../services/company_ad_service.dart';
import '../services/order_request_service.dart';
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

// ---------------------------------------------------------------------------
// PAGE
// ---------------------------------------------------------------------------

class EBNLandingPage extends StatefulWidget {
  final VoidCallback? onOpenSearch;

  /// Normally null — this page is the guest entry point. `RoleGateScreen`
  /// can pass a real user when it renders the same feed for someone who is
  /// already signed in, which is what makes the claim path on the order
  /// sheet reachable for an actual agent rather than dead code.
  final AppUser? user;

  const EBNLandingPage({super.key, this.onOpenSearch, this.user});

  @override
  State<EBNLandingPage> createState() => _EBNLandingPageState();
}

class _EBNLandingPageState extends State<EBNLandingPage> {
  // Only used by the static fallback banner (`_buildInspectionBanner`),
  // shown when there are no admin-authored company ads yet.
  final int _bannerIndex = 0;

  final AssetService _assetService = AssetService();
  final AdminSettingsService _settingsService = AdminSettingsService();
  final CompanyAdService _companyAdService = CompanyAdService();
  final OrderRequestService _orderRequestService = OrderRequestService();

  // Empty until the real `GET /api/assets` response lands — the trending
  // section shows a loading/empty state rather than made-up listings in
  // the meantime.
  List<Asset> _assets = [];
  bool _assetsLoading = true;
  // True only when the load actually failed (backend unreachable / no
  // internet) — kept separate from "loaded fine, just zero results" so
  // the empty state can tell a visitor which one they're looking at.
  bool _assetsError = false;

  // Admin-authored ad cards for the promo carousel (was a single static
  // "Order Verified Inspection" card — see `_buildInspectionBanner`,
  // now `_CompanyAdsCarousel`). Empty list until the real
  // `GET /api/company-ads` response lands.
  List<CompanyAd> _companyAds = [];
  bool _companyAdsLoading = true;

  // Recent orders placed by users on the platform — loaded from
  // `/api/order-requests/admin/broadcasting` to show public orders.
  List<OrderRequest> _orders = [];
  bool _ordersLoading = true;
  // Same distinction as `_assetsError` — see its doc comment.
  bool _ordersError = false;

  /// App name / support phone / support email, used by the order sheet to
  /// show real platform contact details on unclaimed orders. Null until
  /// `GET /api/admin-settings/general` lands (or if it fails) — the sheet
  /// falls back to pointing at the in-app Support screen in that case.
  AdminGeneralSettings? _generalSettings;

  /// Whoever is looking at this page. Guest unless `RoleGateScreen` handed
  /// us a real session.
  AppUser get _viewer => widget.user ?? _kGuestUser;
  bool get _isGuest => widget.user == null;

  @override
  void initState() {
    super.initState();
    _loadAssets();
    _loadCompanyAds();
    _loadOrders();
    _loadGeneralSettings();
  }

  Future<void> _loadGeneralSettings() async {
    try {
      final settings = await _settingsService.fetchPublicGeneralSettings();
      if (!mounted) return;
      setState(() => _generalSettings = settings);
    } on AdminSettingsServiceException catch (_) {
      // Non-fatal — the order sheet points at the in-app Support screen
      // instead of showing a phone number.
    }
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
        _assetsError = false;
      });
    } on AssetException catch (_) {
      // Backend down / unreachable (this is also what a dropped or
      // never-connected internet connection looks like from here) —
      // stop the spinner and show a distinct "couldn't load, check your
      // connection" state with a Retry button, rather than silently
      // falling into the same empty state as "there's genuinely nothing
      // to show yet".
      if (!mounted) return;
      setState(() {
        _assetsLoading = false;
        _assetsError = true;
      });
    }
  }

  /// Bound to the Retry button in the "couldn't load" state — re-arms the
  /// loading flags (safe here since this always runs after the first
  /// build, unlike the initial call from `initState`) and fetches again.
  void _retryLoadAssets() {
    setState(() {
      _assetsLoading = true;
      _assetsError = false;
    });
    _loadAssets();
  }

  Future<void> _loadOrders() async {
    try {
      // Fetch all orders (any status) from the platform to showcase
      // the variety of services offered to new users
      final orders = await _orderRequestService.publicOrderList();
      if (!mounted) return;
      setState(() {
        // Show only the most recent 4-5 orders as a preview
        _orders = orders.take(5).toList();
        _ordersLoading = false;
        _ordersError = false;
      });
    } catch (e) {
      // Catches OrderRequestException (backend down/unreachable) *and*
      // any other unexpected error (e.g. a malformed row failing to
      // parse) — previously this only caught OrderRequestException, so
      // anything else left `_ordersLoading` stuck at true forever
      // (a spinner that never resolves) instead of settling into an
      // end state. Now it settles into the "couldn't load" state so a
      // visitor with no internet sees that, not a page that looks
      // permanently empty.
      if (!mounted) return;
      setState(() {
        _ordersLoading = false;
        _ordersError = true;
      });
    }
  }

  /// Bound to the Retry button in the orders section's "couldn't load"
  /// state — see `_retryLoadAssets` doc comment for why this can safely
  /// call setState up front while the initial `initState` call can't.
  void _retryLoadOrders() {
    setState(() {
      _ordersLoading = true;
      _ordersError = false;
    });
    _loadOrders();
  }

  // Horizontal category tab strip — same tab labels/order/filters as the
  // logged-in visitor home (`CustomerHomeScreen._categoryTabs`), so guests
  // see the exact same category list once they sign in.
  int _categoryTabIndex = 0;

  static const _categoryTabKeys = [
    'categoryForYou',
    'categoryApartments',
    'categoryVehicles',
    'categoryCondominium',
    'categoryMachinery',
    'categoryHouse',
    'categoryWarehouse',
    'categoryBuilding',
    'categoryConstructionMaterials',
    'categoryShop',
    'categoryRealEstate',
    'categoryBrokerList',
  ];

  String _categoryTabLabel(BuildContext context, int index) =>
      AppLocalizations.of(context).text(_categoryTabKeys[index]);
  static const _categoryFilters = <AssetCategorySlug?>[
    null,
    AssetCategorySlug.apartments,
    AssetCategorySlug.vehicles,
    AssetCategorySlug.condominium,
    AssetCategorySlug.machinery,
    AssetCategorySlug.house,
    AssetCategorySlug.warehouse,
    AssetCategorySlug.building,
    AssetCategorySlug.constructionMaterials,
    AssetCategorySlug.others,
    AssetCategorySlug.realEstate,
    null,
  ];
  static const _categoryIcons = <IconData>[
    Icons.explore_outlined,
    Icons.apartment_outlined,
    Icons.directions_car_outlined,
    Icons.apartment_outlined,
    Icons.terrain_outlined,
    Icons.home_outlined,
    Icons.warehouse_outlined,
    Icons.domain_outlined,
    Icons.swap_horiz,
    Icons.shopping_bag_outlined,
    Icons.home_work_outlined,
    Icons.groups_outlined,
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

  void _handleCategoryTabChange(int index) {
    if (index == _categoryTabKeys.length - 1) {
      // "Broker List" — same destination as the old grid's Brokers tile.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BrokerMapScreen(
            category: AssetCategorySlug.others,
            categoryLabel: AppLocalizations.of(context).text('allLabel'),
            showAllBrokers: true,
          ),
        ),
      );
      return;
    }
    setState(() => _categoryTabIndex = index);
    final slug = _categoryFilters[index];
    if (slug == null) return; // "For You" — stay on this feed.
    _goToCategory(slug, _categoryTabLabel(context, index), _categoryIcons[index]);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          // Clamping (not bouncing) physics — the list stays put at the
          // top/bottom instead of rubber-banding, which was stretching the
          // header into blank space on iOS pull-down overscroll.
          physics: const ClampingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // Header stays first, then the "Stay safe with verified
            // listings" promo banner directly beneath it (both untouched).
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildSafetyBanner()),
            // "Order us" / "Sell With Us" now sits directly below that
            // banner, matching the logged-in visitor layout.
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(child: _buildOrderSellRow()),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            if (_companyAdsLoading)
              const SliverToBoxAdapter(child: SizedBox.shrink())
            else if (_companyAds.isNotEmpty)
              SliverToBoxAdapter(child: _CompanyAdsCarousel(ads: _companyAds))
            else
              SliverToBoxAdapter(child: _buildInspectionBanner()),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            // Horizontal-scrolling category list (replaces the old static
            // image-tile grid) — same tab set as the logged-in visitor home.
            SliverToBoxAdapter(child: _buildCategoryScrollList()),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
            // "Latest Properties" — most recently added listings, fetched
            // straight from the assets table (already newest-first) and
            // horizontally scrollable so users can swipe for more.
            SliverToBoxAdapter(child: _buildFeaturedHeader()),
            SliverToBoxAdapter(child: _buildFeaturedList()),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
            // Live activity ticker — rotates through the real orders we
            // already fetched below, newest first. In release builds this
            // stays hidden whenever there's nothing real to show, so an
            // empty platform reads as empty rather than faking traffic. In
            // debug builds only (see _LiveActivityTicker), an empty feed
            // falls back to clearly-labeled sample rows so the UI can be
            // exercised before there's any real activity to test against.
            if (!_ordersLoading) ...[
              SliverToBoxAdapter(
                child: _LiveActivityTicker(
                  orders: _orders,
                  onTap: _openUnclaimedOrdersQueue,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
            SliverToBoxAdapter(child: _buildOrderListHeader()),
            SliverToBoxAdapter(child: _buildOrderListGrid()),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
            SliverToBoxAdapter(child: _buildCTASection()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // --- Bottom Navigation Bar -------------------------------------------------

  Widget _buildBottomNavBar() {
    final t = AppLocalizations.of(context);
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
              label: t.text('landingNavMain'),
              onTap: () {
                // Home / Main - stay on landing page
              },
            ),
            _buildBottomNavItem(
              icon: Icons.add_circle_outline,
              label: t.text('postAd'),
              onTap: () => _handleQuickAction(0),
            ),
            _buildBottomNavItem(
              icon: Icons.people_outlined,
              label: t.text('landingNavBrokers'),
              onTap: () => _handleQuickAction(7),
            ),
            _buildBottomNavItem(
              icon: Icons.shopping_bag_outlined,
              label: t.text('landingNavOrder'),
              onTap: _openOrderFlow,
            ),
            _buildBottomNavItem(
              icon: Icons.help_outline,
              label: t.text('landingNavSupport'),
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
                child: Text(
                  AppLocalizations.of(context).text('mobileLogIn'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.search, size: 24),
                onPressed: widget.onOpenSearch,
              ),
              IconButton(
                icon: const Icon(Icons.language, size: 22),
                onPressed: () => _openLanguageMenu(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Language picker ---------------------------------------------------

  /// The four languages the app actually ships strings for (see
  /// `assets/i18n/*.json` and `AppLocalizations.supportedLocales`), paired
  /// with the display-name key for each.
  static const _kLanguageOptions = [
    (code: 'en', nameKey: 'languageEnglish'),
    (code: 'am', nameKey: 'languageAmharic'),
    (code: 'om', nameKey: 'languageAfanOromo'),
    (code: 'ti', nameKey: 'languageTigrinya'),
  ];

  void _openLanguageMenu(BuildContext context) {
    final localeController = context.read<LocaleController>();
    final t = AppLocalizations.of(context);
    final currentCode =
        localeController.locale?.languageCode ?? Localizations.localeOf(context).languageCode;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(
                t.text('navLanguage'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              for (final option in _kLanguageOptions)
                ListTile(
                  leading: Icon(
                    Icons.language,
                    color: option.code == currentCode ? EBNColors.red : EBNColors.grey,
                  ),
                  title: Text(t.text(option.nameKey)),
                  trailing: option.code == currentCode
                      ? const Icon(Icons.check, color: EBNColors.red)
                      : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    localeController.setLocale(Locale(option.code));
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  // --- Safety strip ------------------------------------------------------------

  Widget _buildSafetyBanner() {
    final t = AppLocalizations.of(context);
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
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Colors.black87,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: '${t.text('landingSafetyBannerTitle')} ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: EBNColors.red,
                    ),
                  ),
                  TextSpan(text: t.text('landingSafetyBannerBody')),
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
    final t = AppLocalizations.of(context);
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
                      Text(
                        t.text('landingInspectionTitle'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        t.text('landingInspectionSubtitle'),
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
                        child: Text(
                          t.text('landingInspectionCta'),
                          style: const TextStyle(
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

  // --- Category scroll list (matches the logged-in visitor home) --------------

  Widget _buildCategoryScrollList() {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categoryTabKeys.length,
        itemBuilder: (context, i) {
          final active = i == _categoryTabIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 20),
            child: InkWell(
              onTap: () => _handleCategoryTabChange(i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _categoryTabLabel(context, i),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active ? EBNColors.red : EBNColors.grey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 2.5,
                    width: 26,
                    color: active ? EBNColors.red : Colors.transparent,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- Order us / Sell with us cards --------------------------------------------

  Widget _buildOrderSellRow() {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _openOrderFlow,
              child: _infoCard(
                icon: Icons.verified_outlined,
                title: t.text('heroOrderUs'),
                subtitle: t.text('landingOrderUsSubtitle'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _openSellFlow,
              child: _infoCard(
                icon: Icons.attach_money,
                title: t.text('quickActionSellWithUs'),
                subtitle: t.text('landingSellWithUsSubtitle'),
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
    // Icon + text as one centered group — both axes — instead of the old
    // left-pinned row, per the "center of the card" feedback.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EBNColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
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
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: EBNColors.grey),
          ),
        ],
      ),
    );
  }

  // --- Latest Properties (most recently added) -----------------------------------

  Widget _buildFeaturedHeader() {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            t.text('landingLatestProperties'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          GestureDetector(
            onTap: () {
              _goToCategory(
                AssetCategorySlug.house,
                t.text('landingLatestProperties'),
                Icons.new_releases_outlined,
              );
            },
            child: Row(
              children: [
                Text(
                  t.text('landingSeeAll'),
                  style: const TextStyle(
                    color: EBNColors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Icon(Icons.chevron_right, color: EBNColors.green, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Horizontally-scrolling row of the most recently added listings — the
  // backend already returns `/api/assets` newest-first (`ORDER BY
  // created_at DESC`), so the first N entries are simply the latest ones.
  static const double _kFeaturedCardWidth = 168;

  Widget _buildFeaturedList() {
    if (_assetsLoading) {
      return const _FeaturedListSkeleton();
    }
    if (_assetsError) {
      return _ConnectionErrorNotice(onRetry: _retryLoadAssets);
    }
    if (_assets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Text(
          AppLocalizations.of(context).text('landingNoListings'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: EBNColors.grey, fontSize: 13),
        ),
      );
    }
    final latest = _assets.take(10).toList();
    return SizedBox(
      height: 262,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: latest.length,
        itemBuilder: (context, i) {
          final asset = latest[i];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              width: _kFeaturedCardWidth,
              child: Align(
                alignment: Alignment.topCenter,
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
            ),
          );
        },
      ),
    );
  }

  // --- CTA + footer -----------------------------------------------------------

  Widget _buildCTASection() {
    final t = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      color: Colors.white,
      child: Column(
        children: [
          Text(
            t.text('landingCtaTitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            t.text('landingCtaSubtitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: EBNColors.grey),
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
              child: Text(
                t.text('getStartedSignUp'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Order list section -------------------------------------------

  Widget _buildOrderListHeader() {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            t.text('landingOrderList'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          GestureDetector(
            onTap: () {
              // TODO: Navigate to full order list page
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.text('landingViewAllOrders'))),
              );
            },
            child: Row(
              children: [
                Text(
                  t.text('landingSeeAll'),
                  style: const TextStyle(
                    color: EBNColors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Icon(Icons.chevron_right, color: EBNColors.green, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Single tap on an order card — opens a read-only details sheet. No
  /// backend state changes here; claiming is a separate, explicit button
  /// inside the sheet (see `_OrderDetailsSheet`).
  void _openOrderSheet(OrderRequest order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderDetailsSheet(
        order: order,
        viewer: _viewer,
        isGuest: _isGuest,
        settings: _generalSettings,
        onClaim: _claimOrder,
        onClaimed: _applyClaimedOrder,
        onSignIn: _goToSignIn,
      ),
    );
  }

  /// Tapping the live activity ticker jumps straight into a focused queue
  /// of open (unclaimed) requests — no navigation to a new page, no
  /// sign-in prompt. If everything happens to be claimed right now, we
  /// fall back to showing the full recent list rather than an empty
  /// sheet, since seeing *something* is more useful than a dead end.
  void _openUnclaimedOrdersQueue() {
    final unclaimed = _orders
        .where((o) => o.status == OrderRequestStatus.broadcasting)
        .toList();
    final showing = unclaimed.isNotEmpty ? unclaimed : _orders;
    if (showing.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrdersQueueSheet(
        orders: showing,
        onlyUnclaimed: unclaimed.isNotEmpty,
        onOrderTap: (order) {
          Navigator.of(context).pop(); // close the queue sheet first
          _openOrderSheet(order);
        },
      ),
    );
  }

  /// Swap a freshly-claimed row into the feed so the card behind the sheet
  /// reflects its new status without a full refetch.
  void _applyClaimedOrder(OrderRequest updated) {
    if (!mounted) return;
    setState(() {
      final i = _orders.indexWhere((o) => o.id == updated.id);
      if (i != -1) _orders[i] = updated;
    });
  }

  void _goToSignIn() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RoleSelectScreen()));
  }

  /// Only ever called from the sheet's Claim button, after the sheet has
  /// checked the viewer is a signed-in agent and taken a second explicit
  /// confirmation. Returns the updated request, or throws so the sheet can
  /// surface the reason (409 when someone else got there first).
  Future<OrderRequest> _claimOrder(OrderRequest order, AppUser agent) {
    return _orderRequestService.claim(
      order.id,
      agentId: agent.id,
      agentName: agent.fullName,
      agentPhone: agent.phone ?? '',
    );
  }

  static const double _kOrderGridSpacing = 16;

  Widget _buildOrderListGrid() {
    if (_ordersLoading) {
      return const _OrderListSkeleton();
    }
    if (_ordersError) {
      return _ConnectionErrorNotice(onRetry: _retryLoadOrders);
    }
    if (_orders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Text(
          AppLocalizations.of(context).text('landingNoOrders'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: EBNColors.grey, fontSize: 13),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = (constraints.maxWidth - _kOrderGridSpacing) / 2;
          // Built one at a time (not as a single list literal) and wrapped
          // in its own try/catch: a `Wrap`'s children are constructed
          // eagerly as one expression, so if any single order's widget
          // throws while building, the whole list literal throws and the
          // *entire* grid silently vanishes in a release build (Flutter
          // swaps in a blank/near-invisible box for a widget that throws
          // during build, with no visible error — same reasoning as the
          // try/catch around `AgentListingEditScreen`'s body). Isolating
          // each card means one bad row is skipped instead of blanking
          // out every other order that loaded fine.
          final cards = <Widget>[];
          for (final order in _orders) {
            try {
              cards.add(
                SizedBox(
                  width: cardWidth,
                  child: _OrderCard(
                    order: order,
                    viewer: _viewer,
                    isGuest: _isGuest,
                    onClaim: _claimOrder,
                    onClaimed: _applyClaimedOrder,
                    onSignIn: _goToSignIn,
                    onTap: () => _openOrderSheet(order),
                  ),
                ),
              );
            } catch (e, stack) {
              debugPrint('Order card build error for ${order.id}: $e\n$stack');
            }
          }
          if (cards.isEmpty) {
            // Every order in this batch failed to render — fall back to
            // the same empty-state copy rather than an empty gap.
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                AppLocalizations.of(context).text('landingNoOrders'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: EBNColors.grey, fontSize: 13),
              ),
            );
          }
          return Wrap(
            spacing: _kOrderGridSpacing,
            runSpacing: 20,
            children: cards,
          );
        },
      ),
    );
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
  Timer? _autoSlideTimer;
  late List<ImageProvider<Object>?> _imageProviders;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.92);
    _imageProviders = _providersFor(widget.ads);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final image in _imageProviders) {
        if (image != null) precacheImage(image, context);
      }
    });
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || widget.ads.length < 2 || !_controller.hasClients) return;
      final nextIndex = (_index + 1) % widget.ads.length;
      _controller.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  List<ImageProvider<Object>?> _providersFor(List<CompanyAd> ads) {
    return ads
        .map((ad) => dataUrlOrNetworkImage(ad.imageUrl))
        .toList(growable: false);
  }

  @override
  void didUpdateWidget(covariant _CompanyAdsCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ads != widget.ads) {
      _imageProviders = _providersFor(widget.ads);
      _index = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
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
            height: 202,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.ads.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final ad = widget.ads[i];
                return Padding(
                  key: ValueKey(ad.id),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: CompanyAdCard(
                    title: ad.title,
                    description: ad.description,
                    imageUrl: ad.imageUrl,
                    hasLink: ad.linkUrl != null,
                    imageProvider: _imageProviders[i],
                    onTap: () => _handleTap(ad),
                  ),
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
              icon: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 28),
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
        mainAxisSize: MainAxisSize.min,
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

// ---------------------------------------------------------------------------
// ORDER CARD WIDGET
// ---------------------------------------------------------------------------

class _OrderCard extends StatefulWidget {
  final OrderRequest order;
  final AppUser viewer;
  final bool isGuest;
  final VoidCallback? onTap;
  final Future<OrderRequest> Function(OrderRequest, AppUser) onClaim;
  final ValueChanged<OrderRequest> onClaimed;
  final VoidCallback onSignIn;

  const _OrderCard({
    required this.order,
    required this.viewer,
    required this.isGuest,
    required this.onClaim,
    required this.onClaimed,
    required this.onSignIn,
    this.onTap,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _claiming = false;

  bool get _isOpen => widget.order.status == OrderRequestStatus.broadcasting;

  /// Single tap on the inline action button. For a signed-in agent this is
  /// the "single-click claim" entry point (the card doesn't need to be
  /// opened first) and goes through the one shared confirmation dialog in
  /// [_confirmAndClaimOrder]. For a guest, the button now opens the order
  /// details sheet (same as tapping the card) instead of jumping straight
  /// to sign-in — the sheet is where they actually see what's being
  /// requested and, once claimed, the broker's contact info.
  Future<void> _handleClaimTap() async {
    if (widget.isGuest) {
      widget.onTap?.call();
      return;
    }
    setState(() => _claiming = true);
    final updated = await _confirmAndClaimOrder(
      context,
      order: widget.order,
      viewer: widget.viewer,
      onClaim: widget.onClaim,
    );
    if (!mounted) return;
    setState(() => _claiming = false);
    if (updated != null) widget.onClaimed(updated);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final order = widget.order;
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
          // Header with category icon and status badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            color: EBNColors.lightGrey,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getCategoryIcon(order.category),
                        size: 18,
                        color: EBNColors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order.category.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(order.status),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _getStatusLabel(order.status),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Order details - NO personal info (name, phone, etc)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // What they're looking for
                Text(
                  order.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                // Budget info
                Text(
                  order.budgetSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: EBNColors.green,
                  ),
                ),
                const SizedBox(height: 6),
                // Location info only - no requester details
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 12,
                      color: EBNColors.grey,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _getLocationLabel(order),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: EBNColors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Open orders get a one-tap action right on the card — no need
          // to open the sheet first. For a guest this is just "View
          // Details" so it's styled as a quieter dark-outline button
          // rather than the same red as the real Claim action, which
          // stays solid since that's an agent actually committing to
          // something. Anything else (claimed, closed, disputed) just
          // keeps the "tap for details" hint.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: _isOpen
                ? SizedBox(
                    width: double.infinity,
                    child: widget.isGuest
                        ? OutlinedButton.icon(
                            onPressed: _claiming ? null : _handleClaimTap,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              side: const BorderSide(
                                color: Colors.black87,
                                width: 1.2,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.info_outline, size: 15),
                            label: const Text(
                              'View Details',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: _claiming ? null : _handleClaimTap,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: EBNColors.red,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: EBNColors.grey,
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: _claiming
                                ? const SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.handshake_outlined,
                                    size: 15,
                                  ),
                            label: Text(
                              _claiming ? 'Claiming...' : 'Claim',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  )
                : Row(
                    children: [
                      const Icon(
                        Icons.touch_app_outlined,
                        size: 12,
                        color: EBNColors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Tap for details',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: EBNColors.grey.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

IconData _getCategoryIcon(AssetCategorySlug category) {
  return switch (category) {
    AssetCategorySlug.house => Icons.home_outlined,
    AssetCategorySlug.apartments => Icons.apartment_outlined,
    AssetCategorySlug.condominium => Icons.apartment_outlined,
    AssetCategorySlug.building => Icons.domain_outlined,
    AssetCategorySlug.warehouse => Icons.warehouse_outlined,
    AssetCategorySlug.vehicles => Icons.directions_car_outlined,
    AssetCategorySlug.machinery => Icons.terrain_outlined,
    AssetCategorySlug.constructionMaterials => Icons.storage_outlined,
    _ => Icons.shopping_bag_outlined,
  };
}

String _getStatusLabel(OrderRequestStatus status) {
  return switch (status) {
    OrderRequestStatus.broadcasting => 'FINDING',
    OrderRequestStatus.agentConfirmed => 'CONFIRMED',
    OrderRequestStatus.disputed => 'REPORTED',
    OrderRequestStatus.closed => 'CLOSED',
  };
}

Color _getStatusColor(OrderRequestStatus status) {
  return switch (status) {
    OrderRequestStatus.broadcasting => EBNColors.red,
    OrderRequestStatus.agentConfirmed => EBNColors.green,
    OrderRequestStatus.disputed => Colors.orange,
    OrderRequestStatus.closed => Colors.grey,
  };
}

/// Area/city only — never the full street address the requester typed.
String _getLocationLabel(OrderRequest order) {
  if (order.addressText != null && order.addressText!.isNotEmpty) {
    final parts = order.addressText!.split(',');
    return parts.isNotEmpty ? parts[0].trim() : 'Location specified';
  }
  return 'GPS location';
}

/// "12m ago" / "3h ago" / "2d ago" — used by the ticker and the sheet.
String _relativeTime(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}

/// Shared single-click claim flow used by both the order card's inline
/// Claim button and the details sheet's Claim button. Role/phone gating
/// stays the same as before, but this now takes exactly *one* confirmation
/// dialog instead of the old two-dialog gauntlet — claiming is still
/// irreversible and shares the agent's contact info with the requester, so
/// zero confirmation would be reckless, but two sequential dialogs was more
/// friction than "single-click claim interactions" calls for.
///
/// Callers are responsible for the guest case (redirecting to sign-in)
/// before calling this, since what "guest" should do differs by call site
/// (the sheet closes itself first; the card doesn't have anything to close).
Future<OrderRequest?> _confirmAndClaimOrder(
  BuildContext context, {
  required OrderRequest order,
  required AppUser viewer,
  required Future<OrderRequest> Function(OrderRequest, AppUser) onClaim,
}) async {
  if (viewer.role != UserRole.agent) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Only agents can claim an order request.'),
      ),
    );
    return null;
  }
  if ((viewer.phone ?? '').trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Add a phone number to your profile before claiming orders.',
        ),
      ),
    );
    return null;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Claim this order?'),
      content: Text(
        'This assigns the ${order.category.label} request to you. Your '
        "name and phone are shared with the requester, and no other agent "
        "can take it after that. This can't be undone.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: EBNColors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Yes, claim it'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return null;

  try {
    final updated = await onClaim(order, viewer);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order claimed. It is assigned to you.')),
      );
    }
    return updated;
  } on OrderRequestException catch (e) {
    // Most likely a 409 — another agent got there first.
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
    return null;
  }
}


// ---------------------------------------------------------------------------
// LIVE ACTIVITY TICKER
// ---------------------------------------------------------------------------

/// Rotates through the real orders already loaded for the feed below, one
/// at a time, so the page shows actual platform activity.
///
/// Deliberately *not* a simulator: it invents no orders, no counts, and no
/// timestamps. Every line is a row that came back from the API, and the
/// whole strip is hidden by the caller when there are none. An empty
/// platform should look empty — fake traffic is the kind of thing users
/// notice eventually, and it costs more trust than it buys attention.
///
/// The one exception is `kDebugMode`: when there are no real orders to show
/// *and* the app is running a debug build, this falls back to a handful of
/// placeholder rows purely so the ticker's UI (rotation, animation, layout)
/// can be exercised before there's real data. That fallback is visually
/// distinct on purpose — amber instead of green, an explicit "Sample data"
/// tag — and `kDebugMode` is false in every release build, so it cannot
/// reach a real device a real visitor is using.
class _LiveActivityTicker extends StatefulWidget {
  const _LiveActivityTicker({required this.orders, this.onTap});

  final List<OrderRequest> orders;

  /// Tapping the ticker opens a focused queue of open requests — see
  /// `_openUnclaimedOrdersQueue` on the landing page state. Null (only in
  /// practice during tests) just makes the ticker inert.
  final VoidCallback? onTap;

  @override
  State<_LiveActivityTicker> createState() => _LiveActivityTickerState();
}

/// One row the ticker can rotate through — either a real order (via
/// [_TickerItem.fromOrder]) or, in debug-only preview mode, a placeholder
/// (via [_TickerItem.sample]). [isSample] drives the visual treatment so
/// the two are never presented the same way.
class _TickerItem {
  final Object key;
  final IconData icon;
  final String label;
  final String timeLabel;
  final bool isSample;

  _TickerItem.fromOrder(OrderRequest order)
    : key = order.id,
      icon = _getCategoryIcon(order.category),
      label = '${order.category.label} request in '
          '${_getLocationLabel(order)}',
      timeLabel = _relativeTime(order.submittedAt),
      isSample = false;

  _TickerItem.sample(String key, this.icon, this.label, this.timeLabel)
    : key = 'sample-$key',
      isSample = true;
}

/// Debug-preview-only placeholder rows. Never shown in release builds —
/// see the [_LiveActivityTicker] doc comment — and always labeled as
/// sample data when they do appear.
final List<_TickerItem> _kSampleTickerItems = [
  _TickerItem.sample(
    '1',
    Icons.home_outlined,
    'House request in Bole',
    '2m ago',
  ),
  _TickerItem.sample(
    '2',
    Icons.apartment_outlined,
    'Apartment request in Kazanchis',
    '14m ago',
  ),
  _TickerItem.sample(
    '3',
    Icons.directions_car_outlined,
    'Vehicle request in Sarbet',
    '31m ago',
  ),
];

class _LiveActivityTickerState extends State<_LiveActivityTicker>
    with SingleTickerProviderStateMixin {
  Timer? _rotateTimer;
  late final AnimationController _pulse;
  int _index = 0;

  List<_TickerItem> get _items {
    if (widget.orders.isNotEmpty) {
      return widget.orders.map(_TickerItem.fromOrder).toList();
    }
    // Only reached with zero real orders, and only ever renders the
    // fallback in a debug build (checked again in build()).
    return kDebugMode ? _kSampleTickerItems : const [];
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _maybeStartRotation();
  }

  void _maybeStartRotation() {
    _rotateTimer?.cancel();
    _rotateTimer = null;
    if (_items.length > 1) {
      _rotateTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        setState(() => _index = (_index + 1) % _items.length);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _LiveActivityTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orders.length != widget.orders.length) {
      _index = 0;
      _maybeStartRotation();
    }
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) return const SizedBox.shrink();
    final item = items[_index % items.length];
    final accent = item.isSample ? Colors.amber.shade800 : EBNColors.green;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: item.isSample
              ? const Color(0xFFFFF8E8)
              : const Color(0xFFF6FBF7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0.25).animate(_pulse),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.45),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  key: ValueKey(item.key),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(item.icon, size: 14, color: accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.timeLabel,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: EBNColors.grey,
                          ),
                        ),
                      ],
                    ),
                    if (item.isSample) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Sample data — debug preview only, not a real order',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: accent),
            ],
          ],
        ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// UNCLAIMED / OPEN ORDERS QUEUE (opened by tapping the live activity ticker)
// ---------------------------------------------------------------------------

/// Half-screen slide-up list of open requests, reached by tapping the green
/// live activity ticker. Deliberately just a queue — no sign-in wall, no
/// navigation away from the landing page. Tapping a row hands off to the
/// existing read-only [_OrderDetailsSheet].
class _OrdersQueueSheet extends StatelessWidget {
  const _OrdersQueueSheet({
    required this.orders,
    required this.onlyUnclaimed,
    required this.onOrderTap,
  });

  final List<OrderRequest> orders;
  final bool onlyUnclaimed;
  final ValueChanged<OrderRequest> onOrderTap;

  @override
  Widget build(BuildContext context) {
    final mediaHeight = MediaQuery.of(context).size.height;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: EBNColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bolt_outlined,
                      color: EBNColors.green,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        onlyUnclaimed
                            ? 'Open Requests'
                            : 'Recent Requests (all claimed)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
              if (!onlyUnclaimed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Nothing unclaimed right now — here are the most '
                    'recent requests instead.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: EBNColors.grey,
                    ),
                  ),
                ),
              const Divider(height: 1, color: EBNColors.border),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final order = orders[i];
                    final open =
                        order.status == OrderRequestStatus.broadcasting;
                    return _QueueRow(
                      order: order,
                      open: open,
                      onTap: () => onOrderTap(order),
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 6),
            ],
          ),
        );
      },
    );
  }
}

/// Compact single-line-ish row used inside [_OrdersQueueSheet] — lighter
/// weight than the full grid [_OrderCard] since this is a scan-and-tap list.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.order,
    required this.open,
    required this.onTap,
  });

  final OrderRequest order;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = open ? EBNColors.green : EBNColors.grey;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: EBNColors.lightGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Icon(
                _getCategoryIcon(order.category),
                size: 17,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getLocationLabel(order),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: EBNColors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                open ? 'Open' : 'Claimed',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// BROKER CONTACT CARD (same avatar + pill-button structure as the Profile
// screen's contact row — see broker_profile_screen.dart's _ProfileHeader)
// ---------------------------------------------------------------------------

/// Shown in the order details sheet once a broker has claimed the request.
/// Deliberately no sign-in gate on Call/Text — see [_contactSection]'s doc
/// comment for why. Chat is the one action that needs an account, since it
/// routes through the platform's own messaging.
class _BrokerContactCard extends StatelessWidget {
  const _BrokerContactCard({
    required this.name,
    required this.phone,
    required this.onCall,
    required this.onText,
    required this.onChat,
  });

  final String name;
  final String? phone;
  final ValueChanged<String> onCall;
  final ValueChanged<String> onText;
  final VoidCallback onChat;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = phone != null && phone!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EBNColors.lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: EBNColors.green,
            child: Text(
              _initials,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Broker handling this request',
                  style: TextStyle(fontSize: 11, color: EBNColors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (hasPhone) ...[
                  const SizedBox(height: 2),
                  Text(
                    phone!,
                    style: const TextStyle(fontSize: 12, color: EBNColors.grey),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (hasPhone)
                      _PillButton(
                        icon: Icons.call,
                        label: 'Call',
                        onTap: () => onCall(phone!),
                      ),
                    if (hasPhone)
                      _PillButton(
                        icon: Icons.sms_outlined,
                        label: 'Text',
                        onTap: () => onText(phone!),
                      ),
                    _PillButton(
                      icon: Icons.chat_bubble_outline,
                      label: 'Chat',
                      onTap: onChat,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded, outlined action button — matches the pill shape used by the
/// Profile screen's Call/Message/Chat buttons so contact actions look the
/// same wherever they show up in the app.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: EBNColors.border),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.black87),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ORDER DETAILS SHEET
// ---------------------------------------------------------------------------

/// Read-only expansion of an order card. Opening this changes nothing on the
/// backend — the only mutating path is the explicit "Claim this order"
/// button, which is gated on being a signed-in agent and takes a second
/// confirmation before it fires.
///
/// Requester name and phone are deliberately never rendered here even though
/// they're present on [OrderRequest]. This sheet is reachable by anyone,
/// signed in or not.
class _OrderDetailsSheet extends StatefulWidget {
  const _OrderDetailsSheet({
    required this.order,
    required this.viewer,
    required this.isGuest,
    required this.settings,
    required this.onClaim,
    required this.onClaimed,
    required this.onSignIn,
  });

  final OrderRequest order;
  final AppUser viewer;
  final bool isGuest;
  final AdminGeneralSettings? settings;
  final Future<OrderRequest> Function(OrderRequest, AppUser) onClaim;
  final ValueChanged<OrderRequest> onClaimed;
  final VoidCallback onSignIn;

  @override
  State<_OrderDetailsSheet> createState() => _OrderDetailsSheetState();
}

class _OrderDetailsSheetState extends State<_OrderDetailsSheet> {
  late OrderRequest _order;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  bool get _isOpen => _order.status == OrderRequestStatus.broadcasting;
  bool get _isClaimed => _order.status == OrderRequestStatus.agentConfirmed;

  Future<void> _launch(String scheme, String value) async {
    final uri = Uri(scheme: scheme, path: value);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open $value on this device.")),
      );
    }
  }

  // ── Claim flow ────────────────────────────────────────────────────────
  // Role/phone gating and the (single) confirmation dialog now live in the
  // shared `_confirmAndClaimOrder` helper, reused by the order card's
  // inline Claim button — see that function for why it's one dialog, not
  // the old two.

  Future<void> _handleClaimPressed() async {
    // Not signed in at all — close the sheet and send them to sign in.
    if (widget.isGuest) {
      Navigator.of(context).pop();
      widget.onSignIn();
      return;
    }

    setState(() => _claiming = true);
    final updated = await _confirmAndClaimOrder(
      context,
      order: _order,
      viewer: widget.viewer,
      onClaim: widget.onClaim,
    );
    if (!mounted) return;
    setState(() => _claiming = false);
    if (updated != null) {
      setState(() => _order = updated);
      widget.onClaimed(updated);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.68,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: EBNColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: [
                    _header(),
                    const SizedBox(height: 18),
                    Text(
                      _order.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _detailRow(
                      Icons.payments_outlined,
                      'Budget',
                      _order.budgetSummary,
                      valueColor: EBNColors.green,
                    ),
                    _detailRow(
                      Icons.location_on_outlined,
                      'Area',
                      _getLocationLabel(_order),
                    ),
                    _detailRow(
                      Icons.schedule_outlined,
                      'Submitted',
                      _relativeTime(_order.submittedAt),
                    ),
                    if (_order.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Requirements',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _order.description.trim(),
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _contactSection(),
                    const SizedBox(height: 20),
                    if (_isOpen) _claimButton(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: EBNColors.lightGrey,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getCategoryIcon(_order.category),
            size: 22,
            color: EBNColors.red,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _order.category.label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: _getStatusColor(_order.status),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _getStatusLabel(_order.status),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: EBNColors.grey),
          const SizedBox(width: 10),
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: EBNColors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Claimed → the assigned broker's details, visible to everyone (no
  /// sign-in wall) so a guest can Call or Text them directly, per how this
  /// is actually meant to be used: someone with a matching item can reach
  /// the broker who claimed the request without an account. Chat is the
  /// one exception — it goes through the platform's messaging, so it
  /// still requires signing in. Unclaimed → the platform's own contact
  /// details, which is what a guest should be reaching out to at that
  /// stage anyway.
  Widget _contactSection() {
    if (_order.status == OrderRequestStatus.closed) {
      return _contactCard(
        icon: Icons.lock_outline,
        title: 'This request is closed',
        body: 'It is no longer taking responses.',
      );
    }

    if (_isClaimed) {
      final name = _order.assignedAgentName;
      final phone = _order.assignedAgentPhone;
      return _BrokerContactCard(
        name: (name == null || name.isEmpty) ? 'Assigned broker' : name,
        phone: phone,
        onCall: (p) => _launch('tel', p),
        onText: (p) => _launch('sms', p),
        onChat: () {
          Navigator.of(context).pop();
          widget.onSignIn();
        },
      );
    }

    // Unclaimed — platform contact.
    final phone = widget.settings?.supportPhone?.trim();
    final email = widget.settings?.supportEmail?.trim();
    final appName = widget.settings?.appName ?? 'EBN';
    final hasContact =
        (phone != null && phone.isNotEmpty) ||
        (email != null && email.isNotEmpty);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEDEB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.support_agent_outlined,
                size: 18,
                color: EBNColors.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No agent assigned yet',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasContact
                ? 'Talk to $appName directly about this request.'
                : 'Reach $appName through the Support screen and we will '
                      'pick it up from there.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (phone != null && phone.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _launch('tel', phone),
                  icon: const Icon(Icons.call, size: 16),
                  label: Text(phone),
                ),
              if (email != null && email.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _launch('mailto', email),
                  icon: const Icon(Icons.mail_outline, size: 16),
                  label: Text(email),
                ),
              if (!hasContact)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SupportScreen(user: widget.viewer),
                      ),
                    );
                  },
                  icon: const Icon(Icons.help_outline, size: 16),
                  label: const Text('Open Support'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contactCard({
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EBNColors.lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: EBNColors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Colors.black87,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 4), action],
        ],
      ),
    );
  }

  Widget _claimButton() {
    if (widget.isGuest) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _claiming ? null : _handleClaimPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black87,
            side: const BorderSide(color: Colors.black87, width: 1.2),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
          ),
          icon: const Icon(Icons.login, size: 18),
          label: const Text(
            'Sign in to claim',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _claiming ? null : _handleClaimPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: EBNColors.red,
          foregroundColor: Colors.white,
          disabledBackgroundColor: EBNColors.grey,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        icon: _claiming
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.handshake_outlined, size: 18),
        label: Text(
          _claiming ? 'Claiming...' : 'Claim this order',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// --- Shimmer skeleton loaders -------------------------------------------
//
// Used in place of a bare CircularProgressIndicator for the "Latest
// Properties" and "Order List" sections: a spinner centered in that much
// horizontal space reads as oversized/awkward, and gives no sense of what's
// about to appear. These placeholders are shaped like the real cards and
// carry a soft left-to-right shimmer sweep — the standard "skeleton
// loading" pattern — so the loading state feels intentional and lightweight
// instead of a big spinning circle sitting in empty space.

/// A rounded box that sweeps a soft light band across itself on a loop.
/// The building block every skeleton card below is made of.
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Sweeps the gradient's center from -1.5 to 1.5 across the box.
        final t = _controller.value * 3 - 1.5;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(t - 0.3, 0),
              end: Alignment(t + 0.3, 0),
              colors: const [
                Color(0xFFEDEDED),
                Color(0xFFF7F7F7),
                Color(0xFFEDEDED),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton for a single [_AdCard]-shaped slot in the "Latest Properties"
/// horizontal row: an image block plus a couple of text-line bars.
class _FeaturedCardSkeleton extends StatelessWidget {
  const _FeaturedCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: _EBNLandingPageState._kFeaturedCardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShimmerBox(
              width: _EBNLandingPageState._kFeaturedCardWidth,
              height: 140,
              borderRadius: 12,
            ),
            const SizedBox(height: 10),
            _ShimmerBox(
                width: _EBNLandingPageState._kFeaturedCardWidth * 0.75, height: 13),
            const SizedBox(height: 8),
            _ShimmerBox(
                width: _EBNLandingPageState._kFeaturedCardWidth * 0.5, height: 13),
            const SizedBox(height: 10),
            _ShimmerBox(
                width: _EBNLandingPageState._kFeaturedCardWidth * 0.4, height: 15),
          ],
        ),
      ),
    );
  }
}

/// Row of [_FeaturedCardSkeleton]s standing in for the "Latest Properties"
/// list while it's loading.
/// Shown in place of a section's content when its fetch actually failed
/// (backend unreachable — which, from the app's point of view, is exactly
/// what "no internet" looks like too), so a visitor with no connection
/// sees a reason and a way to try again instead of a page that just looks
/// permanently empty and gives no clue whether it's broken or slow.
class _ConnectionErrorNotice extends StatelessWidget {
  const _ConnectionErrorNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EBNColors.lightGrey,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 26,
              color: EBNColors.grey,
            ),
            const SizedBox(height: 8),
            const Text(
              "Couldn't load — check your connection",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: const BorderSide(color: Colors.black87, width: 1.2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text(
                'Retry',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedListSkeleton extends StatelessWidget {
  const _FeaturedListSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 262,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3,
        itemBuilder: (context, i) => const _FeaturedCardSkeleton(),
      ),
    );
  }
}

/// Skeleton for a single order card slot in the "Order List" grid.
class _OrderCardSkeleton extends StatelessWidget {
  const _OrderCardSkeleton({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ShimmerBox(width: width - 24, height: 14),
          const SizedBox(height: 10),
          _ShimmerBox(width: (width - 24) * 0.6, height: 12),
          const SizedBox(height: 16),
          _ShimmerBox(width: (width - 24) * 0.45, height: 12),
          const SizedBox(height: 12),
          _ShimmerBox(width: width - 24, height: 32, borderRadius: 16),
        ],
      ),
    );
  }
}

/// 2-column grid of [_OrderCardSkeleton]s standing in for the "Order List"
/// section while it's loading — mirrors the real grid's card-width math.
class _OrderListSkeleton extends StatelessWidget {
  const _OrderListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth =
              (constraints.maxWidth - _EBNLandingPageState._kOrderGridSpacing) /
                  2;
          return Wrap(
            spacing: _EBNLandingPageState._kOrderGridSpacing,
            runSpacing: _EBNLandingPageState._kOrderGridSpacing,
            children: List.generate(
              4,
              (_) => _OrderCardSkeleton(width: cardWidth),
            ),
          );
        },
      ),
    );
  }
}
