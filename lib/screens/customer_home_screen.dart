import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/asset.dart';
import '../models/auth_response.dart';
import '../models/broker.dart';
import '../models/company_ad.dart';
import '../providers/favorites_controller.dart';
import '../providers/loop_controller.dart';
import '../services/agent_service.dart';
import '../services/asset_service.dart';
import '../services/chat_service.dart';
import '../services/company_ad_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../utils/media_encoding.dart';
import '../widgets/listing_intent_sheet.dart';
import '../widgets/order_category_sheet.dart';
import 'asset_detail_screen.dart';
import 'broker_directory_screen.dart';
import 'chat_inbox_screen.dart';
import 'my_rental_agreements_screen.dart';
import 'notifications_screen.dart';
import 'order_request_form_screen.dart';
import 'rent_property_form_screen.dart';
import 'sell_property_form_screen.dart';
import 'visitor_account_screen.dart';
import '../widgets/notification_alert_overlay.dart';
import '../utils/nav_utils.dart';

const _kAccentRed = Color(0xFFFF2636);

/// Visual & interactive redesign of the Visitor home screen: matching the
/// "EBN Visitor Dashboard" reference mock: search bar with quick-scan
/// icons, a category tab strip, an inspection promo banner, a "Find your
/// desire" order card, and a Top picks grid on a bottom-tabbed feed —
/// closed off with a 5-tab bottom navigation bar.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  int _categoryTabIndex = 0;
  int _picksTabIndex = 0;
  int _navIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final AssetService _assetService = AssetService();
  final AgentService _agentService = AgentService();
  final ChatService _chatService = ChatService();
  final NotificationService _notificationService = NotificationService();

  // Populated from `GET /api/agents`, keyed by user id, so each pick
  // card can resolve its listing's `broker_id` to a poster name — same
  // client-side lookup pattern as `category_listing_screen.dart`.
  Map<String, Broker> _brokersById = {};

  // "Order Verified Inspection" promo, now a sliding carousel of
  // admin-authored text promotions (same source the landing page's ad
  // carousel uses — see `_PromoCarousel` below). Falls back to the
  // original single "Order Verified Inspection" message if none are
  // configured yet or the fetch fails, so the banner never just vanishes.
  List<CompanyAd> _promoAds = [];
  final CompanyAdService _companyAdService = CompanyAdService();

  // Loaded from the real `GET /api/assets` response.
  List<Asset> _assets = [];
  bool _loadingAssets = true;
  String? _assetsError;

  // Total unread messages across all threads, for the Chat tab's badge.
  // The inbox itself isn't kept mounted (it's pushed as its own route,
  // unlike the agent side's persistent tab), so this polls independently
  // just for the count.
  int _unreadChatCount = 0;
  Timer? _unreadPollTimer;

  // Same idea for the generic notifications feed (order updates, etc)
  // behind the bell icon — polled independently since there's no socket
  // client wired up yet (see notification_service.dart).
  int _unreadNotificationsCount = 0;
  Timer? _notificationsPollTimer;
  // Ids we've already alerted on, so a poll doesn't re-show a banner for
  // something the user already saw. Seeded (not alerted) on the very
  // first load so opening the app doesn't dump the whole history as
  // banners — only notifications that arrive *after* that count.
  Set<String> _seenNotificationIds = {};
  bool _seenNotificationsSeeded = false;

  static const _categoryTabs = [
    'For You',
    'Apartments',
    'Vehicles',
    'Condominium',
    'Machinery',
    'House',
    'Warehouse',
    'Building',
    'Construction Materials',
    'Shop',
    'Real Estate',
    'Broker List',
  ];
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
  static const _picksTabs = ['Top picks', 'Nearby', 'Certified', 'Free Items'];

  @override
  void initState() {
    super.initState();
    _loadAssets();
    _loadBrokers();
    // Keeps the "waiting on an agent" screen honest — without this, the
    // customer only ever sees a local countdown guess, never the real
    // accept/decline/broadcasting status the server actually has.
    context.read<LoopController>().startCustomerPolling(widget.user.id);
    context.read<FavoritesController>().attachUser(widget.user);
    _refreshUnreadCount();
    _unreadPollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshUnreadCount(),
    );
    _refreshUnreadNotifications();
    _notificationsPollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshUnreadNotifications(),
    );
    _loadPromoAds();
  }

  /// Best-effort — a failed fetch just leaves [_promoAds] empty and the
  /// carousel falls back to the static "Order Verified Inspection" slide,
  /// so this never needs its own error UI.
  Future<void> _loadPromoAds() async {
    try {
      final ads = await _companyAdService.list();
      if (!mounted) return;
      setState(() => _promoAds = ads);
    } on CompanyAdException {
      // Fall back silently — see doc comment above.
    }
  }

  Future<void> _refreshUnreadNotifications() async {
    final token = widget.user.token;
    if (token == null) return;
    try {
      final notifications = await _notificationService.getNotifications(token);
      if (!mounted) return;
      final unread = notifications.where((n) => !n.isRead).length;
      if (unread != _unreadNotificationsCount) {
        setState(() => _unreadNotificationsCount = unread);
      }
      _alertOnNewNotifications(notifications);
    } on NotificationException {
      // Same as chat's unread poll — transient hiccup, next tick retries.
    }
  }

  /// Pops a top-of-screen banner for any notification not seen in an
  /// earlier poll. The first poll after opening the app only seeds
  /// [_seenNotificationIds] — it doesn't alert on the whole backlog.
  void _alertOnNewNotifications(List<AppNotification> notifications) {
    if (!_seenNotificationsSeeded) {
      _seenNotificationIds = notifications.map((n) => n.id).toSet();
      _seenNotificationsSeeded = true;
      return;
    }
    final fresh = notifications
        .where((n) => !_seenNotificationIds.contains(n.id))
        .toList();
    if (fresh.isEmpty) return;
    _seenNotificationIds.addAll(fresh.map((n) => n.id));
    if (!mounted) return;
    NotificationAlertOverlay.show(
      context,
      notification: fresh.first,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          // A rental-agreement banner goes straight to that agreement;
          // everything else opens the notifications feed as before.
          builder: (_) => fresh.first.kind == AppNotificationKind.rentalAgreement
              ? MyRentalAgreementsScreen(user: widget.user, openAgreementId: fresh.first.relatedId)
              : NotificationsScreen(
            token: widget.user.token ?? '',
            user: widget.user,
            onUnreadCountChanged: (count) {
              if (mounted) setState(() => _unreadNotificationsCount = count);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _refreshUnreadCount() async {
    final token = widget.user.token;
    if (token == null) return;
    try {
      final threads = await _chatService.listThreads(token: token);
      if (!mounted) return;
      final total = threads.fold<int>(0, (sum, t) => sum + t.unreadCount);
      if (total != _unreadChatCount) setState(() => _unreadChatCount = total);
    } on ChatException {
      // Transient network hiccup — the next poll tick will retry; not
      // worth surfacing a badge-count fetch failure to the user.
    }
  }

  /// Best-effort — a failed fetch just leaves [_brokersById] empty and
  /// pick cards fall back to the "Posted by EBN" label, same as
  /// `asset_detail_screen.dart` does when a listing has no broker.
  Future<void> _loadBrokers() async {
    try {
      final rows = await _agentService.fetchDirectory();
      final brokers = rows.map(Broker.fromDirectoryJson).toList();
      if (!mounted) return;
      setState(() {
        _brokersById = {for (final b in brokers) b.id: b};
      });
    } on AgentServiceException {
      // Leave the map empty — see doc comment above.
    }
  }

  Future<void> _loadAssets() async {
    setState(() {
      _loadingAssets = true;
      _assetsError = null;
    });
    try {
      final assets = await _assetService.fetchAssets(limit: 100);
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _loadingAssets = false;
      });
    } on AssetException catch (e) {
      if (!mounted) return;
      setState(() {
        _assetsError = e.message;
        _loadingAssets = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _unreadPollTimer?.cancel();
    _notificationsPollTimer?.cancel();
    context.read<LoopController>().stopCustomerPolling();
    super.dispose();
  }

  Future<void> _openOrderUs(BuildContext context) async {
    final category = await showOrderCategorySheet(context);
    if (category == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OrderRequestFormScreen(user: widget.user, category: category),
      ),
    );
  }

  Future<void> _openListingIntent(BuildContext context) async {
    final intent = await showListingIntentSheet(context);
    if (intent == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => intent == ListingIntent.sell
            ? SellPropertyFormScreen(user: widget.user)
            : RentPropertyFormScreen(user: widget.user),
      ),
    );
  }

  /// Tapping a promo slide shows its full title/description rather than
  /// immediately jumping into a flow — the slide itself is just a teaser.
  void _showPromoDetail(BuildContext context, _PromoSlideData slide) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFF0F0EE),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.verified_rounded,
                    size: 20, color: Color(0xFF4A4A45)),
              ),
              const SizedBox(height: 14),
              Text(
                slide.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                slide.description,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.slate,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _openOrderUs(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccentRed,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.button),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Order Us',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleCategoryTabChange(int index) {
    if (index == _categoryTabs.length - 1) {
      // Broker List tapped
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BrokerDirectoryScreen(
            category: AssetCategorySlug.others,
            categoryLabel: 'All',
            showAllBrokers: true,
            currentUser: widget.user,
          ),
        ),
      );
      return;
    }
    setState(() => _categoryTabIndex = index);
  }

  List<Asset> get _filteredAssets {
    final query = _searchController.text.trim().toLowerCase();

    final searchedAndCategorized = _assets.where((asset) {
      final matchesQuery = query.isEmpty ||
          (asset.city?.toLowerCase().contains(query) ?? false) ||
          (asset.addressLine?.toLowerCase().contains(query) ?? false) ||
          asset.title.toLowerCase().contains(query);

      final categoryFilter = _categoryFilters[_categoryTabIndex];
      final matchesCategory =
          categoryFilter == null || asset.category == categoryFilter;

      return matchesQuery && matchesCategory;
    }).toList();

    // "Top picks / Nearby / Certified / Free Items" now each apply their
    // own real ordering/filter on top of search + category, instead of all
    // four showing the identical list. None of these exclude listings down
    // to zero the way the old per-tab filters did — Nearby and Certified
    // only *sort*, they don't drop listings, so a tab is never emptier than
    // Top picks just because of missing data.
    switch (_picksTabs[_picksTabIndex]) {
      case 'Nearby':
        // No device geolocation or per-listing "city center" in the app
        // yet, so this sorts by distance from Addis Ababa's coordinates
        // (same reference point already used for broker sorting) rather
        // than excluding anything whose city string isn't an exact match.
        const addisLat = 9.0192;
        const addisLng = 38.7525;
        final sorted = [...searchedAndCategorized]
          ..sort((a, b) => _distanceKm(addisLat, addisLng, a.latitude, a.longitude)
              .compareTo(_distanceKm(addisLat, addisLng, b.latitude, b.longitude)));
        return sorted;
      case 'Certified':
        // There's no dedicated "certified"/"verified" flag on Asset yet.
        // Using "has an assigned broker" as the closest available proxy —
        // brokered listings first, everything else after (nothing is
        // dropped). Swap this for a real certified flag once the backend
        // has one.
        final sorted = [...searchedAndCategorized]
          ..sort((a, b) {
            final aHas = a.brokerId != null ? 0 : 1;
            final bHas = b.brokerId != null ? 0 : 1;
            return aHas.compareTo(bHas);
          });
        return sorted;
      case 'Free Items':
        return searchedAndCategorized
            .where((asset) => asset.priceAmount <= 0)
            .toList();
      case 'Top picks':
      default:
        // Highest rated first; unrated listings keep their original order
        // at the end.
        final sorted = [...searchedAndCategorized]
          ..sort((a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1));
        return sorted;
    }
  }

  static double _distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lng2 - lng1) * p)) /
            2;
    return 12742 * (2 * math.asin(math.sqrt(a)));
  }

  void _handleBottomNavChange(int index) {
    if (index == 2) {
      // Raised center '+' Sell button
      _openListingIntent(context);
      return;
    }
    if (index == 1) {
      // Chat / Messages — "Interests" used to live here, but Saved
      // Listings is already reachable from the "Me" tab, so this slot
      // now opens the real chat inbox instead.
      Navigator.of(context)
          .push(
        MaterialPageRoute(
          builder: (_) => ChatInboxScreen(user: widget.user),
        ),
      )
          .then((_) {
        if (mounted) _refreshUnreadCount();
      });
      return;
    }
    if (index == 3) {
      // Agents
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BrokerDirectoryScreen(
            category: AssetCategorySlug.others,
            categoryLabel: 'All',
            showAllBrokers: true,
            currentUser: widget.user,
          ),
        ),
      );
      return;
    }
    if (index == 4) {
      // Me / Account hub (includes My Sell Requests as a section)
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VisitorAccountScreen(user: widget.user),
        ),
      );
      return;
    }
    setState(() => _navIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final loop = context.watch<LoopController>();
    final assets = _filteredAssets;

    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) safePop(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.cloud,
        body: SafeArea(
          child: Builder(
            builder: (scaffoldContext) {
              return Column(
                children: [
                  _TopBar(
                    searchController: _searchController,
                    onSearchChanged: (_) => setState(() {}),
                    unreadNotifications: _unreadNotificationsCount,
                    onNotificationsTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => NotificationsScreen(
                          token: widget.user.token ?? '',
                          user: widget.user,
                          onUnreadCountChanged: (count) {
                            if (mounted) {
                              setState(() => _unreadNotificationsCount = count);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  _CategoryTabStrip(
                    tabs: _categoryTabs,
                    activeIndex: _categoryTabIndex,
                    onChanged: _handleCategoryTabChange,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Text promotion carousel only makes sense on the
                          // unfiltered "For You" feed — hide it once the
                          // visitor has drilled into a specific category.
                          if (_categoryTabIndex == 0)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 0),
                              child: _PromoCarousel(
                                slides: _promoAds.isNotEmpty
                                    ? _promoAds
                                        .map((ad) => _PromoSlideData(
                                            title: ad.title,
                                            description: ad.description))
                                        .toList()
                                    : const [
                                        _PromoSlideData(
                                          title: 'Order Verified Inspection',
                                          description:
                                              'Get an on-site asset report before making any transaction',
                                        ),
                                      ],
                                onTapSlide: (slide) =>
                                    _showPromoDetail(context, slide),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                            child: _OrderSellRow(
                              onOrderUs: () => _openOrderUs(context),
                              onSellWithUs: () => _openListingIntent(context),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                            child: _PicksTabStrip(
                              tabs: _picksTabs,
                              activeIndex: _picksTabIndex,
                              onChanged: (i) =>
                                  setState(() => _picksTabIndex = i),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                            child: _loadingAssets
                                ? const Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : _assetsError != null
                                    ? Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.cloud_off_rounded,
                                              size: 34,
                                              color: AppColors.slate,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              _assetsError!,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: AppColors.slate,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 14),
                                            OutlinedButton(
                                              onPressed: _loadAssets,
                                              child: const Text('Try again'),
                                            ),
                                          ],
                                        ),
                                      )
                                    : assets.isEmpty
                                        ? const Padding(
                                            padding: EdgeInsets.all(32),
                                            child: Center(
                                              child: Text(
                                                'No listings found',
                                                style: TextStyle(
                                                  color: AppColors.slate,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          )
                                        : _PicksGrid(
                                            assets: assets,
                                            user: widget.user,
                                            brokersById: _brokersById,
                                          ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: _BottomNavBar(
          activeIndex: _navIndex,
          onChanged: _handleBottomNavChange,
          unreadChatCount: _unreadChatCount,
        ),
      ),
    );
  }
}

/// Search bar row + notification bell + globe icon.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.searchController,
    required this.onSearchChanged,
    this.unreadNotifications = 0,
    this.onNotificationsTap,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final int unreadNotifications;
  final VoidCallback? onNotificationsTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F3F1),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppColors.slate,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.ink,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _IconCircleButton(
            icon: Icons.notifications_outlined,
            onTap: onNotificationsTap,
            badgeCount: unreadNotifications,
          ),
          const SizedBox(width: 8),
          const _IconCircleButton(icon: Icons.language_rounded),
        ],
      ),
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  const _IconCircleButton({
    required this.icon,
    this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F3F1),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, size: 17, color: AppColors.ink),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                decoration: const BoxDecoration(
                  color: _kAccentRed,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  badgeCount > 9 ? '9+' : '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "For You / Real Estate / Vehicles / Machinery / Broker List" tabs with a
/// red underline on the active tab, horizontally scrollable.
class _CategoryTabStrip extends StatelessWidget {
  const _CategoryTabStrip({
    required this.tabs,
    required this.activeIndex,
    required this.onChanged,
  });

  final List<String> tabs;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        itemBuilder: (context, i) {
          final active = i == activeIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 20),
            child: InkWell(
              onTap: () => onChanged(i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    tabs[i],
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active ? _kAccentRed : AppColors.slate,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 2.5,
                    width: 26,
                    color: active ? _kAccentRed : Colors.transparent,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A single slide of text-only promotional content (title + description).
/// Sourced from the admin-authored company ads when any are configured,
/// falling back to the original static "Order Verified Inspection" copy
/// otherwise — see `_loadPromoAds` in `_CustomerHomeScreenState`.
class _PromoSlideData {
  const _PromoSlideData({required this.title, required this.description});

  final String title;
  final String description;
}

/// Auto-sliding carousel of text promotions — replaces the old static
/// "Order Verified Inspection" banner. Advances one slide every 3 seconds
/// (looping back to the start), and tapping a slide opens a detail sheet
/// with its full title/description instead of navigating straight into a
/// flow, since the slide itself is only meant as a teaser.
class _PromoCarousel extends StatefulWidget {
  const _PromoCarousel({required this.slides, required this.onTapSlide});

  final List<_PromoSlideData> slides;
  final ValueChanged<_PromoSlideData> onTapSlide;

  @override
  State<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<_PromoCarousel> {
  late final PageController _controller;
  Timer? _autoSlideTimer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || widget.slides.length < 2 || !_controller.hasClients) {
        return;
      }
      final nextIndex = (_index + 1) % widget.slides.length;
      _controller.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void didUpdateWidget(covariant _PromoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slides != widget.slides) {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 84,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final slide = widget.slides[i];
              return InkWell(
                onTap: () => widget.onTapSlide(slide),
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E8),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                      color: AppColors.primaryYellow.withValues(alpha: 0.5),
                    ),
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
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.verified_rounded,
                          size: 20,
                          color: Color(0xFF4A4A45),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              slide.title,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              slide.description,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.slate,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: AppColors.slate),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.slides.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.slides.length, (i) {
              final active = i == _index;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active
                      ? _kAccentRed
                      : AppColors.slate.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

/// "Order us" / "Sell with us" card pair — replaces the old "Find your
/// desire" card with its single red "Order Us" button, matching the same
/// pair already used on the public landing page (`ebn_landing_page.dart`).
class _OrderSellRow extends StatelessWidget {
  const _OrderSellRow({required this.onOrderUs, required this.onSellWithUs});

  final VoidCallback onOrderUs;
  final VoidCallback onSellWithUs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onOrderUs,
            child: _card(
              icon: Icons.verified_outlined,
              title: 'Order us',
              subtitle: 'get what you want',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: onSellWithUs,
            child: _card(
              icon: Icons.attach_money,
              title: 'Sell With Us',
              subtitle: 'Meet a broker',
            ),
          ),
        ),
      ],
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
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
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.slate),
          ),
        ],
      ),
    );
  }
}

/// "Top picks / Nearby / Certified / Free Items" tab row above the grid.
class _PicksTabStrip extends StatelessWidget {
  const _PicksTabStrip({
    required this.tabs,
    required this.activeIndex,
    required this.onChanged,
  });

  final List<String> tabs;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(tabs.length, (i) {
        final active = i == activeIndex;
        return Padding(
          padding: const EdgeInsets.only(right: 18),
          child: InkWell(
            onTap: () => onChanged(i),
            child: Text(
              tabs[i],
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: active ? _kAccentRed : AppColors.slate,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// 2-column grid of listing cards, styled to match the reference mock:
/// photo with heart icon, ETB price (plus a "For Rent" pill for rental
/// listings), title, location line, and who posted it.
class _PicksGrid extends StatelessWidget {
  const _PicksGrid({
    required this.assets,
    required this.user,
    this.brokersById = const {},
  });

  final List<Asset> assets;
  final AppUser user;
  final Map<String, Broker> brokersById;

  @override
  Widget build(BuildContext context) {
    // Two independent columns (left gets even indices, right gets odd)
    // instead of a fixed-aspect-ratio GridView, so each card's height
    // follows its own content — a short card doesn't get stretched to
    // match a tall neighbor, and a tall card doesn't get clipped to
    // match a short one.
    final left = <Asset>[];
    final right = <Asset>[];
    for (var i = 0; i < assets.length; i++) {
      (i.isEven ? left : right).add(assets[i]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              for (final asset in left) ...[
                _PickCard(
                  asset: asset,
                  user: user,
                  broker: asset.brokerId != null
                      ? brokersById[asset.brokerId]
                      : null,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              for (final asset in right) ...[
                _PickCard(
                  asset: asset,
                  user: user,
                  broker: asset.brokerId != null
                      ? brokersById[asset.brokerId]
                      : null,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({required this.asset, required this.user, this.broker});

  final Asset asset;
  final AppUser user;

  /// The listing's assigned broker, resolved by the parent from
  /// `asset.brokerId`. Null when the listing has no broker attached
  /// (posted directly by Admin) or the directory fetch hasn't
  /// resolved it yet — the card falls back to "Posted by EBN" for
  /// that case, same as `asset_detail_screen.dart`.
  final Broker? broker;

  @override
  Widget build(BuildContext context) {
    final isFavorite = context.select<FavoritesController, bool>(
      (f) => f.isFavorite(asset.id),
    );

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AssetDetailScreen(asset: asset, user: user),
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (dataUrlOrNetworkImage(asset.imageUrl) != null)
                    Image(
                      image: dataUrlOrNetworkImage(asset.imageUrl)!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Container(
                        color: AppColors.primaryYellow.withValues(alpha: 0.18),
                      ),
                    )
                  else
                    Container(
                      color: AppColors.primaryYellow.withValues(alpha: 0.18),
                    ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () =>
                          context.read<FavoritesController>().toggle(asset.id),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 14,
                          color: isFavorite ? _kAccentRed : AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          asset.formattedPrice,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (asset.isForRent) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryYellow.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                          child: const Text(
                            'For Rent',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    asset.title,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 11,
                        color: AppColors.slate,
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          asset.city ?? '',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.slate,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_rounded,
                        size: 12,
                        color: AppColors.slate,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          broker != null
                              ? broker!.name
                              : 'Posted by EBN',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.slate,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom nav bar: Explore / Chat / Sell (raised red "+") / Agents / Me.
class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.activeIndex,
    required this.onChanged,
    this.unreadChatCount = 0,
  });

  final int activeIndex;
  final ValueChanged<int> onChanged;
  final int unreadChatCount;

  static const _items = [
    (Icons.explore_outlined, Icons.explore_rounded, 'Explore'),
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chat'),
    (Icons.add_rounded, Icons.add_rounded, 'Sell'),
    (Icons.groups_outlined, Icons.groups_rounded, 'Agents'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Me'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_items.length, (i) {
            final (outline, filled, label) = _items[i];
            final active = i == activeIndex;

            if (i == 2) {
              // Center "Sell" tab: raised red circular button, no label.
              return InkWell(
                onTap: () => onChanged(i),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 48,
                  height: 48,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: const BoxDecoration(
                    color: _kAccentRed,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x33E84C3D),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(filled, color: Colors.white, size: 26),
                ),
              );
            }

            return InkWell(
              onTap: () => onChanged(i),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        active ? filled : outline,
                        size: 22,
                        color: active ? _kAccentRed : AppColors.slate,
                      ),
                      if (i == 1 && unreadChatCount > 0)
                        Positioned(
                          right: -7,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            constraints: const BoxConstraints(minWidth: 15),
                            decoration: BoxDecoration(
                              color: _kAccentRed,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              unreadChatCount > 9 ? '9+' : '$unreadChatCount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? _kAccentRed : AppColors.slate,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}
