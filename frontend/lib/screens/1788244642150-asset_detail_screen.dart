import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/broker.dart';
import '../models/asset.dart';
import '../models/auth_response.dart';
import '../providers/loop_controller.dart';
import '../providers/favorites_controller.dart';
import '../services/agent_service.dart';
import '../theme/app_theme.dart';
import '../utils/media_encoding.dart';
import 'broker_chat_screen.dart';
import 'broker_profile_screen.dart';

/// Mock office details shown when a listing has no assigned broker (i.e. it
/// was posted directly by Admin rather than through a broker). There's no
/// backend field for this yet, so it's hard-coded here as a stand-in.
class _EbnOffice {
  static const name = 'EBN Head Office';
  static const addressLine = 'Bole Road, Friendship Building, 4th Floor';
  static const city = 'Addis Ababa';
  static const phone = '+251 11 662 0000';
}

/// Full-page detail view for a single listing — reached by tapping any
/// listing card (Featured listings on the Visitor dashboard, or a category
/// page). Shows the full listing details plus who to reach about it: the
/// assigned broker, or EBN's office when Admin posted it directly with
/// no broker attached. Clicking the "Book Your Visit" button shows a
/// dialog with Call/Text options plus a real "Tour Request" option that
/// submits via `LoopController.customerRequest` (POST /api/tour-requests)
/// — this is what makes the request show up under "My Tour Requests"
/// afterward.
class AssetDetailScreen extends StatefulWidget {
  const AssetDetailScreen({super.key, required this.asset, required this.user});

  final Asset asset;
  final AppUser user;

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  final AgentService _agentService = AgentService();
  Broker? _broker;

  @override
  void initState() {
    super.initState();
    _loadBroker();
  }

  Future<void> _loadBroker() async {
    final brokerId = widget.asset.brokerId;
    if (brokerId == null) return;

    try {
      final rows = await _agentService.fetchDirectory(userId: brokerId);
      if (!mounted) return;
      setState(() {
        _broker = rows.isNotEmpty ? Broker.fromDirectoryJson(rows.first) : null;
      });
    } on AgentServiceException {
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agent phone number not available')),
      );
      return;
    }

    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      await launchUrl(phoneUri);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch call: $e')),
        );
      }
    }
  }

  Future<void> _sendSMS(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agent phone number not available')),
      );
      return;
    }

    final Uri smsUri = Uri(
      scheme: 'sms',
      path: phoneNumber,
      queryParameters: {
        'body': 'Hi, I am interested in your listing: ${widget.asset.title}',
      },
    );
    try {
      await launchUrl(smsUri);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch SMS: $e')),
        );
      }
    }
  }

  void _showContactOptionsDialog(String? phoneNumber, String agentName) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Contact $agentName',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _makePhoneCall(phoneNumber);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                ),
              ),
              icon: const Icon(Icons.phone, size: 20),
              label: const Text('Call'),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _sendSMS(phoneNumber);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                ),
              ),
              icon: const Icon(Icons.message, size: 20),
              label: const Text('Text Message'),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _handleTourRequest();
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                ),
              ),
              icon: const Icon(Icons.event, size: 20),
              label: const Text('Tour Request'),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: AppColors.border),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  void _requestTour() {
    // Show contact options dialog for the property's assigned agent
    if (_broker != null) {
      _showContactOptionsDialog(_broker!.phone, _broker!.name);
    } else {
      // Fallback to EBN office if no broker assigned
      _showContactOptionsDialog(_EbnOffice.phone, _EbnOffice.name);
    }
  }

  Future<void> _handleTourRequest() async {
    // Check if user is logged in
    if (widget.user.id.isEmpty) {
      // User not logged in - navigate to sign up page
      Navigator.of(context).pushNamed('/signup');
      return;
    }
    // Real POST /api/tour-requests via LoopController — this is what makes
    // the request actually show up under "My Tour Requests" afterward.
    // LoopController drives its own searching/dispatched UI elsewhere (see
    // `loop.stage` above), so this just fires it off and reports any error;
    // success is reflected by the button switching to "Visit Booked".
    final loop = context.read<LoopController>();
    if (loop.hasActiveCustomerRequest &&
        loop.requestedAsset?.id != widget.asset.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Finish your current visit request before booking another one.'),
        ),
      );
      return;
    }
    await loop.customerRequest(
      widget.asset,
      customerId: widget.user.id,
      customerName: widget.user.fullName,
    );
    if (!mounted) return;
    if (loop.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not send tour request: ${loop.lastError}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tour request sent to agent!')),
      );
    }
  }

  static Color _statusColor(AssetStatus status) {
    switch (status) {
      case AssetStatus.active:
        return AppColors.success;
      case AssetStatus.underInspection:
        return AppColors.primaryYellowDark;
      case AssetStatus.sold:
        return AppColors.danger;
      case AssetStatus.draft:
      case AssetStatus.archived:
        return AppColors.slate;
    }
  }

  static IconData _categoryIcon(AssetCategorySlug category) {
    switch (category) {
      case AssetCategorySlug.apartments:
        return Icons.apartment_rounded;
      case AssetCategorySlug.vehicles:
        return Icons.directions_car_filled_rounded;
      case AssetCategorySlug.machinery:
        return Icons.precision_manufacturing_rounded;
      case AssetCategorySlug.realEstate:
        return Icons.villa_rounded;
      case AssetCategorySlug.condominium:
        return Icons.location_city_rounded;
      case AssetCategorySlug.house:
        return Icons.house_rounded;
      case AssetCategorySlug.warehouse:
        return Icons.warehouse_rounded;
      case AssetCategorySlug.building:
        return Icons.business_rounded;
      case AssetCategorySlug.constructionMaterials:
        return Icons.construction_rounded;
      case AssetCategorySlug.others:
        return Icons.category_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loop = context.watch<LoopController>();
    final isFavorite = context.select<FavoritesController, bool>(
        (f) => f.isFavorite(widget.asset.id));
    final isThisRequested = loop.requestedAsset?.id == widget.asset.id &&
        loop.stage != LoopStage.idle;
    final hasActiveRequest = loop.hasActiveCustomerRequest;

    return Scaffold(
      backgroundColor: AppColors.cloud,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFFFF2636),
            expandedHeight: 260,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFFFF2636)),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            actions: [
              if (widget.user.id != 'guest')
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _FavoriteAppBarButton(
                    isFavorite: isFavorite,
                    onTap: () => context
                        .read<FavoritesController>()
                        .toggle(widget.asset.id),
                  ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _HeroImageCarousel(
                imageUrls: widget.asset.galleryUrls,
                categoryIcon: _categoryIcon(widget.asset.category),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(widget.asset.formattedPrice,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink)),
                      const SizedBox(width: 10),
                      Icon(Icons.circle,
                          size: 9, color: _statusColor(widget.asset.status)),
                      const SizedBox(width: 4),
                      Text(widget.asset.status.label,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _statusColor(widget.asset.status))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(widget.asset.title,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                  if (widget.asset.specLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(widget.asset.specLine,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.slate)),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 18, color: AppColors.slate),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [
                            if (widget.asset.addressLine != null)
                              widget.asset.addressLine!,
                            if (widget.asset.city != null) widget.asset.city!
                          ].join(', '),
                          style: const TextStyle(
                              fontSize: 13.5,
                              color: AppColors.ink,
                              height: 1.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: AppSpacing.lg),
                  if (widget.asset.description?.trim().isNotEmpty == true) ...[
                    const Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      widget.asset.description!,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.slate,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  _ContactSection(
                      asset: widget.asset, currentUser: widget.user),
                  if (widget.asset.attributes.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _AssetDetailsSection(asset: widget.asset),
                  ],
                  if (hasActiveRequest && !isThisRequested) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        'You already have an active request. Finish or wait for it to complete before starting a new one.',
                        style:
                            TextStyle(fontSize: 12.5, color: AppColors.slate),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
          child: FilledButton(
            onPressed: isThisRequested ? null : () => _requestTour(),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryYellow,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.border,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button)),
            ),
            child: Text(
              isThisRequested ? 'Visit Booked' : 'Book Your Visit',
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssetDetailsSection extends StatelessWidget {
  const _AssetDetailsSection({required this.asset});

  final Asset asset;

  static String _label(String key) {
    final words = key.replaceAll('_', ' ').split(' ');
    return words
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  static String _value(dynamic value) {
    if (value is bool) return value ? 'Yes' : 'No';
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final entries = asset.attributes.entries
        .where((entry) => entry.value != null && '$entry'.trim().isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Asset details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: const BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: AppColors.border),
            ),
          ),
          child: Column(
            children: [
              for (var index = 0; index < entries.length; index++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _label(entries[index].key),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.slate,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: Text(
                          _value(entries[index].value),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < entries.length - 1)
                  const Divider(height: 1, color: AppColors.border),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Hero image area in the detail screen's app bar. Shows a single static
/// image when the listing only has one photo (unchanged from before), or
/// a horizontally-swipeable, snapping page carousel with dot indicators
/// when there's more than one — listing cards elsewhere in the app are
/// deliberately untouched by this and keep showing only the first photo.
class _HeroImageCarousel extends StatefulWidget {
  const _HeroImageCarousel(
      {required this.imageUrls, required this.categoryIcon});

  final List<String> imageUrls;
  final IconData categoryIcon;

  @override
  State<_HeroImageCarousel> createState() => _HeroImageCarouselState();
}

class _HeroImageCarouselState extends State<_HeroImageCarousel> {
  final PageController _controller = PageController();
  late List<ImageProvider<Object>?> _providers;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _providers = _buildProviders(widget.imageUrls);
  }

  List<ImageProvider<Object>?> _buildProviders(List<String> urls) {
    return urls.map(dataUrlOrNetworkImage).toList();
  }

  @override
  void didUpdateWidget(covariant _HeroImageCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.imageUrls, widget.imageUrls)) {
      _providers = _buildProviders(widget.imageUrls);
      if (_page >= _providers.length) _page = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;

    if (urls.isEmpty) {
      return _ImageFallback(icon: widget.categoryIcon);
    }

    if (urls.length == 1) {
      final provider = _providers.first;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (provider != null)
            Image(
              image: provider,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) =>
                  _ImageFallback(icon: widget.categoryIcon),
            )
          else
            _ImageFallback(icon: widget.categoryIcon),
          const _HeroGradientOverlay(),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: urls.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (context, index) {
            final provider = _providers[index];
            return provider != null
                ? Image(
                    image: provider,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stack) =>
                        _ImageFallback(icon: widget.categoryIcon),
                  )
                : _ImageFallback(icon: widget.categoryIcon);
          },
        ),
        const _HeroGradientOverlay(),
        // "2 / 4" counter badge, top-right — clearer at a glance than dots
        // alone once there are more than ~5 photos.
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x99000000),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_page + 1} / ${urls.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        // Dot indicators, bottom-center.
        Positioned(
          bottom: 14,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(urls.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? Colors.white : const Color(0x99FFFFFF),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

/// Shared top-to-center darkening gradient so the back/favorite buttons in
/// the app bar stay legible over any photo.
class _HeroGradientOverlay extends StatelessWidget {
  const _HeroGradientOverlay();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment(0, -0.2),
            colors: [Color(0x55000000), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

/// Circular white heart button floating over the hero image in the app
/// bar — toggles this listing's saved state via [FavoritesController].
class _FavoriteAppBarButton extends StatelessWidget {
  const _FavoriteAppBarButton({required this.isFavorite, required this.onTap});

  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration:
            const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Icon(
          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 19,
          color: isFavorite ? AppColors.danger : AppColors.ink,
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.inkSoft,
      alignment: Alignment.center,
      child: Icon(icon,
          color: AppColors.primaryYellow.withOpacity(0.85), size: 64),
    );
  }
}

/// Resolves and shows "who to contact about this listing": the assigned
/// broker (fetched from the real `GET /api/agents?userId=` lookup via
/// [AgentService]), or EBN's office if there is none / the broker id
/// doesn't resolve to a real agent account yet (e.g. a legacy mock id
/// like `b1` left over on an older seeded listing — see
/// `routes/chat.js` on the backend for the same fallback logic).
class _ContactSection extends StatefulWidget {
  const _ContactSection({required this.asset, required this.currentUser});

  final Asset asset;
  final AppUser currentUser;

  @override
  State<_ContactSection> createState() => _ContactSectionState();
}

class _ContactSectionState extends State<_ContactSection> {
  final _agentService = AgentService();
  bool _loading = true;
  Broker? _broker;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final brokerId = widget.asset.brokerId;
    if (brokerId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final rows = await _agentService.fetchDirectory(userId: brokerId);
      if (!mounted) return;
      setState(() {
        _broker = rows.isNotEmpty ? Broker.fromDirectoryJson(rows.first) : null;
        _loading = false;
      });
    } on AgentServiceException {
      // Network hiccup — fall back to the office card rather than
      // blocking the whole listing page on this one section.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final broker = _broker;
    return broker != null
        ? _BrokerSection(
            broker: broker,
            asset: widget.asset,
            currentUser: widget.currentUser)
        : const _OfficeSection();
  }
}

/// Shown when the listing has an assigned broker — who to contact, plus
/// quick actions to view their full profile or start a chat about this
/// specific listing.
class _BrokerSection extends StatelessWidget {
  const _BrokerSection(
      {required this.broker, required this.asset, required this.currentUser});

  final Broker broker;
  final Asset asset;
  final AppUser currentUser;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Listed by',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.slate)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primaryYellow,
              backgroundImage: brokerAvatarImage(broker),
              child: brokerAvatarImage(broker) == null
                  ? Text(broker.initials,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: AppColors.ink))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(broker.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('${broker.company} · ${broker.city}',
                      style: const TextStyle(
                          color: AppColors.slate, fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 15, color: AppColors.primaryYellowDark),
                      const SizedBox(width: 2),
                      Text(broker.rating.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.slate)),
                      const SizedBox(width: 10),
                      Icon(broker.tier.icon, size: 14, color: AppColors.ink),
                      const SizedBox(width: 2),
                      Text(broker.tier.label,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BrokerProfileScreen(
                      broker: broker, currentUser: currentUser),
                )),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  side: const BorderSide(color: AppColors.ink, width: 1.2),
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                icon: const Icon(Icons.person_outline, size: 16),
                label: const Text('View profile'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BrokerChatScreen(
                      broker: broker, asset: asset, currentUser: currentUser),
                )),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryYellow,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Chat'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shown when the listing has no assigned broker — meaning it was posted
/// directly by Admin, or its `broker_id` is a legacy mock id that doesn't
/// resolve to a real agent account yet — pointing the Visitor to EBN's
/// office instead.
class _OfficeSection extends StatelessWidget {
  const _OfficeSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Posted by EBN',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.slate)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                  color: AppColors.primaryYellow, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.storefront_rounded, color: AppColors.ink),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_EbnOffice.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          fontSize: 15)),
                  SizedBox(height: 4),
                  Text('${_EbnOffice.addressLine}, ${_EbnOffice.city}',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.slate, height: 1.3)),
                  SizedBox(height: 2),
                  Text(_EbnOffice.phone,
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'This listing was posted directly by EBN — request a tour and an agent will be dispatched from the office above.',
          style: TextStyle(fontSize: 12, color: AppColors.slate, height: 1.4),
        ),
      ],
    );
  }
}
