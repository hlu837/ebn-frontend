import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/broker.dart';
import '../models/asset.dart';
import '../models/auth_response.dart';
import '../models/user_role.dart';
import '../providers/favorites_controller.dart';
import '../services/asset_service.dart';
import '../theme/landing_colors.dart';
import '../utils/media_encoding.dart';
import '../widgets/asset_list_card.dart';
import 'asset_detail_screen.dart';
import 'broker_chat_screen.dart';
import 'signup_screen.dart';

/// A broker's public profile — reached by tapping a broker from the
/// "Find brokers" list or from a pin on [BrokerMapScreen].
///
/// Shows their membership tier and, per the platform's posting rules, only
/// the listings they're actually allowed to have live:
///  - Gold / Diamond brokers: listings across every category they work in.
///  - Silver / Bronze brokers: listings in a single locked category only.
class BrokerProfileScreen extends StatefulWidget {
  final Broker broker;

  /// The signed-in visitor, if any. When present, "Chat about this
  /// listing" opens a real conversation via [BrokerChatScreen]; when
  /// absent (guest browsing), it still routes to sign-up as before.
  final AppUser? currentUser;

  const BrokerProfileScreen(
      {super.key, required this.broker, this.currentUser});

  @override
  State<BrokerProfileScreen> createState() => _BrokerProfileScreenState();
}

class _BrokerProfileScreenState extends State<BrokerProfileScreen> {
  final _assetService = AssetService();
  List<Asset> _listings = const [];
  bool _loading = true;
  String? _error;

  /// Null means "All categories". Set from the horizontal category strip
  /// above the listing list so a multi-category (Gold/Diamond) broker's
  /// properties can be narrowed down by type.
  AssetCategorySlug? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _assetService.fetchByBroker(widget.broker.id);
      if (!mounted) return;
      setState(() {
        // Only show what a visitor should actually see on a public
        // profile — same rule the visitor feed applies elsewhere.
        _listings = rows.where((a) => a.status == AssetStatus.active).toList();
        _loading = false;
      });
    } on AssetException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final broker = widget.broker;
    final currentUser = widget.currentUser;
    // Enforce the membership-tier posting restriction even defensively here,
    // in case a broker's real listings ever drift from their tier rules.
    final tierListings = broker.tier.canPostAnyCategory
        ? _listings
        : _listings
            .where((a) => a.category == (broker.lockedCategory ?? a.category))
            .toList();

    // Distinct categories actually present, in category-enum order, so the
    // horizontal strip only ever offers categories this broker really has
    // active listings in.
    final availableCategories = AssetCategorySlug.values
        .where((c) => tierListings.any((a) => a.category == c))
        .toList();

    final selected = _selectedCategory;
    final listings = selected == null
        ? tierListings
        : tierListings.where((a) => a.category == selected).toList();

    return Scaffold(
      backgroundColor: LandingColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Color(0xFFFF2636), width: 3),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon:
                        const Icon(Icons.arrow_back, color: Color(0xFFFF2636)),
                  ),
                  const Text('Broker profile',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A))),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _ProfileHeader(
                    broker: broker,
                    currentUser: currentUser,
                    // First active listing, if any — lets "Chat" open a
                    // real thread even when tapped from the header rather
                    // than from a specific listing card below.
                    chatAsset: tierListings.isEmpty ? null : tierListings.first,
                  ),
                  const SizedBox(height: 16),
                  _TierCard(broker: broker),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text(
                          '${listings.length} listing${listings.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: LandingColors.foreground)),
                      const Spacer(),
                      if (!broker.tier.canPostAnyCategory &&
                          broker.lockedCategory != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: LandingColors.card,
                              border: Border.all(color: LandingColors.border),
                              borderRadius: BorderRadius.circular(999)),
                          child: Text(
                              'Only posts ${broker.lockedCategory!.label}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: LandingColors.muted)),
                        ),
                    ],
                  ),
                  if (availableCategories.length > 1) ...[
                    const SizedBox(height: 12),
                    _CategoryStrip(
                      categories: availableCategories,
                      selected: _selectedCategory,
                      onSelected: (c) =>
                          setState(() => _selectedCategory = c),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (_error != null)
                    Container(
                      decoration: BoxDecoration(
                          color: LandingColors.card,
                          border: Border.all(color: LandingColors.border),
                          borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 32, horizontal: 16),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: LandingColors.muted, fontSize: 13)),
                          const SizedBox(height: 10),
                          OutlinedButton(
                              onPressed: _load, child: const Text('Try again')),
                        ],
                      ),
                    )
                  else if (listings.isEmpty)
                    Container(
                      decoration: BoxDecoration(
                          color: LandingColors.card,
                          border: Border.all(color: LandingColors.border),
                          borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      alignment: Alignment.center,
                      child: Text(
                          selected == null
                              ? 'No active listings from this broker yet.'
                              : 'No ${selected.label.toLowerCase()} listings from this broker yet.',
                          style: const TextStyle(color: LandingColors.muted)),
                    )
                  else
                    ...listings.map((asset) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _ListingWithChat(
                              broker: broker,
                              asset: asset,
                              currentUser: currentUser),
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final Broker broker;
  final AppUser? currentUser;

  /// One of the broker's active listings, if any — when present, "Chat"
  /// opens a thread scoped to that listing (matching a listing card's
  /// "Chat about this listing"); when null (no active listings yet),
  /// "Chat" opens the one general thread with this broker instead.
  final Asset? chatAsset;

  const _ProfileHeader(
      {required this.broker, this.currentUser, this.chatAsset});

  // Uses the cached helper so the same ImageProvider instance is reused
  // across rebuilds instead of re-decoding base64 every time (which made
  // the picture visibly flicker/reload whenever this screen rebuilt).
  ImageProvider<Object>? get _avatarImage =>
      dataUrlOrNetworkImage(broker.avatarUrl);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: LandingColors.gold,
          backgroundImage: _avatarImage,
          child: _avatarImage == null
              ? Text(broker.initials,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: LandingColors.goldFg))
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(broker.name,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: LandingColors.foreground)),
              const SizedBox(height: 2),
              Text('${broker.company} · ${broker.city}',
                  style: const TextStyle(
                      fontSize: 13, color: LandingColors.muted)),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      size: 16, color: LandingColors.gold),
                  const SizedBox(width: 2),
                  Text(broker.rating.toStringAsFixed(1),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: LandingColors.foreground)),
                  const SizedBox(width: 10),
                  Icon(broker.tier.icon, size: 15, color: broker.tier.color),
                  const SizedBox(width: 3),
                  Text('${broker.tier.label} member',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: broker.tier.color)),
                ],
              ),
              if (broker.addressLine != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 15, color: LandingColors.muted),
                    const SizedBox(width: 4),
                    Expanded(
                        child: Text(broker.addressLine!,
                            style: const TextStyle(
                                fontSize: 12.5, color: LandingColors.muted))),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (broker.phone != null) _CallButton(broker: broker),
                  if (broker.phone != null) _MessageButton(broker: broker),
                  _ChatButton(
                    broker: broker,
                    asset: chatAsset,
                    currentUser: currentUser,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageButton extends StatelessWidget {
  final Broker broker;
  const _MessageButton({required this.broker});

  Future<void> _sendText(BuildContext context) async {
    final phoneNumber = broker.phone;
    if (phoneNumber == null || phoneNumber.isEmpty) return;
    final cleanedNumber = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final uri = Uri(scheme: 'sms', path: cleanedNumber);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Text messaging not supported on this device')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open messages: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _sendText(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: LandingColors.card,
            border: Border.all(color: LandingColors.border),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sms_outlined,
                  size: 15, color: LandingColors.foreground),
              SizedBox(width: 6),
              Text('Message',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: LandingColors.foreground)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatButton extends StatelessWidget {
  final Broker broker;
  final Asset? asset;
  final AppUser? currentUser;
  const _ChatButton({required this.broker, this.asset, this.currentUser});

  void _openChat(BuildContext context) {
    final user = currentUser;
    if (user == null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const SignUpScreen(initialRole: UserRole.user),
      ));
      return;
    }
    final listing = asset;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => listing != null
          ? BrokerChatScreen(broker: broker, asset: listing, currentUser: user)
          : BrokerChatScreen.general(broker: broker, currentUser: user),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _openChat(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: LandingColors.foreground,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 15, color: LandingColors.primaryFg),
              SizedBox(width: 6),
              Text('Chat',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: LandingColors.primaryFg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final Broker broker;
  const _CallButton({required this.broker});

  Future<void> _makePhoneCall(BuildContext context) async {
    final phoneNumber = broker.phone;
    if (phoneNumber == null || phoneNumber.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Broker phone number not available')),
      );
      return;
    }
    // Format phone number: remove spaces, dashes, and parentheses
    final cleanedNumber = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final Uri phoneUri = Uri(scheme: 'tel', path: cleanedNumber);
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Phone calls not supported on this device')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch call: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _makePhoneCall(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: LandingColors.gold,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_rounded, size: 15, color: LandingColors.goldFg),
              SizedBox(width: 6),
              Text('Call',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: LandingColors.goldFg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal, scrollable "All" + category chips shown when a broker has
/// active listings across more than one category (Gold/Diamond tiers) —
/// lets a visitor narrow the listings below to just one property type.
class _CategoryStrip extends StatelessWidget {
  final List<AssetCategorySlug> categories;
  final AssetCategorySlug? selected;
  final ValueChanged<AssetCategorySlug?> onSelected;

  const _CategoryStrip({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _CategoryChip(
              label: 'All',
              isSelected: selected == null,
              onTap: () => onSelected(null),
            );
          }
          final category = categories[i - 1];
          return _CategoryChip(
            label: category.label,
            isSelected: selected == category,
            onTap: () => onSelected(category),
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

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
            color: isSelected ? LandingColors.foreground : LandingColors.card,
            border: Border.all(
                color: isSelected
                    ? LandingColors.foreground
                    : LandingColors.border),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color:
                  isSelected ? LandingColors.primaryFg : LandingColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final Broker broker;
  const _TierCard({required this.broker});

  @override
  Widget build(BuildContext context) {
    if (broker.bio != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(broker.bio!,
              style: const TextStyle(
                  fontSize: 13.5,
                  color: LandingColors.foreground,
                  height: 1.4)),
          const SizedBox(height: 14),
          _MembershipBanner(broker: broker),
        ],
      );
    }
    return _MembershipBanner(broker: broker);
  }
}

class _MembershipBanner extends StatelessWidget {
  final Broker broker;
  const _MembershipBanner({required this.broker});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: broker.tier.color.withOpacity(0.12),
        border: Border.all(color: broker.tier.color.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(broker.tier.icon, color: broker.tier.color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${broker.tier.label} membership',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: broker.tier.color)),
                const SizedBox(height: 3),
                Text(broker.tier.description,
                    style: const TextStyle(
                        fontSize: 12, color: LandingColors.muted, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingWithChat extends StatelessWidget {
  final Broker broker;
  final Asset asset;
  final AppUser? currentUser;
  const _ListingWithChat(
      {required this.broker, required this.asset, this.currentUser});

  void _onChatTap(BuildContext context) {
    final user = currentUser;
    if (user == null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const SignUpScreen(initialRole: UserRole.user),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          BrokerChatScreen(broker: broker, asset: asset, currentUser: user),
    ));
  }

  void _onViewDetails(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AssetDetailScreen(
        asset: asset,
        user: currentUser ??
            const AppUser(
                id: '', fullName: 'Guest', email: '', role: UserRole.user),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isSaved = context
        .select<FavoritesController, bool>((f) => f.isFavorite(asset.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AssetListCard(
          asset: asset,
          actionLabel: 'View details',
          isSaved: isSaved,
          onSaveToggle: (_) =>
              context.read<FavoritesController>().toggle(asset.id),
          onActionPressed: () => _onViewDetails(context),
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _onChatTap(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: LandingColors.foreground,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline_rounded,
                      size: 16, color: LandingColors.primaryFg),
                  SizedBox(width: 8),
                  Text('Chat about this listing',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: LandingColors.primaryFg)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
