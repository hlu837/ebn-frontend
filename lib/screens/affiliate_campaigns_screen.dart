import 'package:flutter/material.dart';
import '../models/auth_response.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';
import '../services/affiliate_service.dart';

const _kAccentRed = AppColors.primaryYellow;

/// Maps the `icon` key string the backend stores (e.g. `wb_sunny_outlined`)
/// to a Flutter `IconData`. Keep in sync with whatever keys admins pick
/// when creating a campaign (`POST /api/affiliates/campaigns`).
const Map<String, IconData> _kIconByKey = {
  'campaign': Icons.campaign_outlined,
  'wb_sunny_outlined': Icons.wb_sunny_outlined,
  'person_add_alt_1_outlined': Icons.person_add_alt_1_outlined,
  'directions_car_outlined': Icons.directions_car_outlined,
  'celebration_outlined': Icons.celebration_outlined,
  'local_offer_outlined': Icons.local_offer_outlined,
  'star_outline': Icons.star_outline,
  'trending_up': Icons.trending_up,
};

IconData _iconFor(String key) => _kIconByKey[key] ?? Icons.campaign_outlined;

/// Promotional campaigns the Affiliater can join and share.
/// Loaded from `GET /api/affiliates/campaigns` (see `affiliate_service.dart`
/// / `backend/src/routes/affiliates.js`).
class AffiliateCampaignsScreen extends StatefulWidget {
  const AffiliateCampaignsScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<AffiliateCampaignsScreen> createState() => _AffiliateCampaignsScreenState();
}

class _AffiliateCampaignsScreenState extends State<AffiliateCampaignsScreen> {
  final _affiliateService = AffiliateService();

  List<AffiliateCampaign> _campaigns = const [];
  bool _loading = true;
  String? _error;

  String? _token() => widget.user.token != null && widget.user.token!.isNotEmpty ? widget.user.token : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = _token();
    if (token == null) {
      setState(() { _error = 'Not logged in.'; _loading = false; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final campaigns = await _affiliateService.getCampaigns(token);
      if (!mounted) return;
      setState(() { _campaigns = campaigns; _loading = false; });
    } on AffiliateException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Failed to load campaigns.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _campaigns.where((c) => c.status == 'active').toList();
    final upcoming = _campaigns.where((c) => c.status == 'upcoming').toList();
    final ended = _campaigns.where((c) => c.status == 'ended').toList();
    final hasAny = active.isNotEmpty || upcoming.isNotEmpty || ended.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        title: const Text('Campaigns', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : !hasAny
                  ? const _EmptyCampaigns()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        children: [
                          if (active.isNotEmpty) ...[
                            const _SectionLabel('Active'),
                            const SizedBox(height: AppSpacing.sm),
                            ...active.map((c) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: _CampaignCard(campaign: c))),
                          ],
                          if (upcoming.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            const _SectionLabel('Upcoming'),
                            const SizedBox(height: AppSpacing.sm),
                            ...upcoming.map((c) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: _CampaignCard(campaign: c))),
                          ],
                          if (ended.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            const _SectionLabel('Ended'),
                            const SizedBox(height: AppSpacing.sm),
                            ...ended.map((c) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: _CampaignCard(campaign: c))),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: AppColors.slate.withOpacity(0.5)),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.slate)),
            const SizedBox(height: AppSpacing.md),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyCampaigns extends StatelessWidget {
  const _EmptyCampaigns();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined, size: 40, color: AppColors.slate.withOpacity(0.5)),
            const SizedBox(height: AppSpacing.md),
            const Text('No campaigns right now',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text('Check back later for promotions you can share.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.slate.withOpacity(0.9))),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.slate, letterSpacing: 0.3));
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.campaign});

  final AffiliateCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final ended = campaign.status == 'ended';
    final upcoming = campaign.status == 'upcoming';

    return Opacity(
      opacity: ended ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: _kAccentRed.withOpacity(0.1), borderRadius: BorderRadius.circular(AppRadii.md)),
                  child: Icon(_iconFor(campaign.icon), color: _kAccentRed, size: 22),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(campaign.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: ended
                              ? AppColors.border
                              : upcoming
                                  ? const Color(0xFFFFF3D6)
                                  : const Color(0xFFE3F6EA),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(
                          ended ? 'Ended' : (upcoming ? 'Upcoming' : campaign.badge),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: ended
                                ? AppColors.slate
                                : upcoming
                                    ? const Color(0xFFB8860B)
                                    : AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(campaign.description, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.slate, height: 1.4)),
            if (campaign.status == 'active') ...[
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: SecondaryButton(
                  label: 'Share Campaign',
                  borderColor: _kAccentRed,
                  textColor: _kAccentRed,
                  onPressed: () => AppToast.showSuccess(context, '"${campaign.title}" link copied — share it anywhere.'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
