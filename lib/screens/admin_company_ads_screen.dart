import 'package:flutter/material.dart';

import '../models/company_ad.dart';
import '../services/company_ad_service.dart';
import '../theme/app_theme.dart';
import '../utils/media_encoding.dart';
import '../widgets/app_buttons.dart';
import '../widgets/company_ad_card.dart';

/// Admin-only screen: author/edit/delete the company ad cards shown in
/// the landing page's promo carousel (title, description, image, and an
/// optional link — see `_CompanyAdsCarousel` in `ebn_landing_page.dart`).
/// The guest/customer side reads the same `/api/company-ads` feed
/// read-only, active ads only.
class AdminCompanyAdsScreen extends StatefulWidget {
  const AdminCompanyAdsScreen({super.key, required this.token});

  final String token;

  @override
  State<AdminCompanyAdsScreen> createState() => _AdminCompanyAdsScreenState();
}

class _AdminCompanyAdsScreenState extends State<AdminCompanyAdsScreen> {
  final CompanyAdService _service = CompanyAdService();

  List<CompanyAd> _ads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // includeInactive: true — the management screen needs to show ads
      // that have been toggled off, not just what's currently live.
      final ads = await _service.list(includeInactive: true);
      if (!mounted) return;
      setState(() {
        _ads = ads;
        _loading = false;
      });
    } on CompanyAdException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.showError(context, e.message);
    }
  }

  Future<void> _openComposeSheet({CompanyAd? editing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdComposeSheet(
        token: widget.token,
        service: _service,
        editing: editing,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _toggleActive(CompanyAd ad) async {
    try {
      await _service.update(token: widget.token, id: ad.id, isActive: !ad.isActive);
      await _load();
    } on CompanyAdException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message);
    }
  }

  Future<void> _delete(CompanyAd ad) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete ad?'),
        content: Text('"${ad.title}" will be removed from the carousel.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.delete(token: widget.token, id: ad.id);
      if (!mounted) return;
      setState(() => _ads.removeWhere((a) => a.id == ad.id));
    } on CompanyAdException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        title: const Text('Company Ads'),
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openComposeSheet(),
        backgroundColor: AppColors.ink,
        icon: const Icon(Icons.add, color: AppColors.primaryYellow),
        label: const Text('New Ad', style: TextStyle(color: AppColors.primaryYellow)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _ads.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    children: const [
                      SizedBox(height: 80),
                      Center(
                        child: Text(
                          'No ads yet. Tap "New Ad" to post one for the\nlanding page carousel.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.slate),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      88,
                    ),
                    itemCount: _ads.length,
                    itemBuilder: (context, i) {
                      final ad = _ads[i];
                      return _AdListTile(
                        ad: ad,
                        onEdit: () => _openComposeSheet(editing: ad),
                        onToggleActive: () => _toggleActive(ad),
                        onDelete: () => _delete(ad),
                      );
                    },
                  ),
      ),
    );
  }
}

class _AdListTile extends StatelessWidget {
  const _AdListTile({
    required this.ad,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final CompanyAd ad;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final image = dataUrlOrNetworkImage(ad.imageUrl);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: SizedBox(
              width: 64,
              height: 64,
              child: image != null
                  ? Image(image: image, fit: BoxFit.cover)
                  : Container(
                      color: AppColors.cloud,
                      child: const Icon(Icons.image_outlined, color: AppColors.slate),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ad.title,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: AppColors.slate),
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'toggle') onToggleActive();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(ad.isActive ? 'Deactivate' : 'Activate'),
                        ),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ],
                ),
                if (ad.description.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      ad.description,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.slate),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: ad.isActive
                            ? AppColors.success.withOpacity(0.12)
                            : AppColors.slate.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        ad.isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: ad.isActive ? AppColors.success : AppColors.slate,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (ad.linkUrl != null)
                      const Icon(Icons.link_rounded, size: 14, color: AppColors.slate)
                    else
                      const Icon(Icons.zoom_in_rounded, size: 14, color: AppColors.slate),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        ad.linkUrl ?? 'No link — tap zooms the image',
                        style: const TextStyle(fontSize: 11, color: AppColors.slate),
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
    );
  }
}

/// Bottom sheet form used both to create a new ad and to edit an existing
/// one (pass [editing] to prefill).
class _AdComposeSheet extends StatefulWidget {
  const _AdComposeSheet({
    required this.token,
    required this.service,
    this.editing,
  });

  final String token;
  final CompanyAdService service;
  final CompanyAd? editing;

  @override
  State<_AdComposeSheet> createState() => _AdComposeSheetState();
}

class _AdComposeSheetState extends State<_AdComposeSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _linkController;

  String? _imageDataUrl;
  bool _submitting = false;
  bool _pickingImage = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _titleController = TextEditingController(text: editing?.title ?? '');
    _descriptionController = TextEditingController(text: editing?.description ?? '');
    _linkController = TextEditingController(text: editing?.linkUrl ?? '');
    _imageDataUrl = editing?.imageUrl;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _pickingImage = true);
    try {
      final encoded = await pickAndEncodeImage();
      if (encoded != null) setState(() => _imageDataUrl = encoded);
    } on FormatException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.showError(context, 'Could not pick that image.');
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final link = _linkController.text.trim();

    if (title.isEmpty) {
      AppToast.showError(context, 'Title is required.');
      return;
    }
    if (_imageDataUrl == null || _imageDataUrl!.isEmpty) {
      AppToast.showError(context, 'Please add an image for the ad.');
      return;
    }
    if (link.isNotEmpty && Uri.tryParse(link)?.hasScheme != true) {
      AppToast.showError(context, 'Link must be a full URL, e.g. https://example.com');
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_isEditing) {
        await widget.service.update(
          token: widget.token,
          id: widget.editing!.id,
          title: title,
          description: description,
          imageUrl: _imageDataUrl,
          linkUrl: link.isEmpty ? null : link,
          clearLink: link.isEmpty,
        );
      } else {
        await widget.service.create(
          token: widget.token,
          title: title,
          description: description,
          imageUrl: _imageDataUrl!,
          linkUrl: link.isEmpty ? null : link,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CompanyAdException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppToast.showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _imageDataUrl != null ? dataUrlOrNetworkImage(_imageDataUrl) : null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.cloud,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _isEditing ? 'Edit Ad' : 'New Company Ad',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Image
              GestureDetector(
                onTap: _pickingImage ? null : _pickImage,
                child: Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _pickingImage
                      ? const Center(child: CircularProgressIndicator())
                      : image != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image(image: image, fit: BoxFit.cover),
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(AppRadii.pill),
                                    ),
                                    child: const Text(
                                      'Change image',
                                      style: TextStyle(color: Colors.white, fontSize: 11.5),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined,
                                      color: AppColors.slate, size: 28),
                                  SizedBox(height: 6),
                                  Text('Add image', style: TextStyle(color: AppColors.slate)),
                                ],
                              ),
                            ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Best results: a portrait/tall photo (e.g. 800×1000px) with the '
                'main subject centered — it fills a cropped panel on the card, '
                'see preview below. Max 4MB.',
                style: TextStyle(fontSize: 11, color: AppColors.slate, height: 1.3),
              ),
              const SizedBox(height: AppSpacing.md),

              // Live preview — renders with the exact same widget used on
              // the landing page, so what admin sees here is exactly what
              // gets published (title/description truncation, image crop,
              // and all).
              Text(
                'Preview',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppColors.slate),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 190,
                width: double.infinity,
                child: CompanyAdCard(
                  title: _titleController.text,
                  description: _descriptionController.text,
                  imageUrl: _imageDataUrl ?? '',
                  hasLink: _linkController.text.trim().isNotEmpty,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'The photo is cropped to fill a tall rectangle on the right '
                'side of the card (roughly a 4:5 portrait shape). Center the '
                'main subject and keep text/logos away from the edges — '
                'wide landscape photos will have their sides trimmed, and '
                'tall photos will have their top/bottom trimmed.',
                style: TextStyle(fontSize: 11.5, color: AppColors.slate, height: 1.4),
              ),

              const SizedBox(height: AppSpacing.md),

              TextField(
                controller: _titleController,
                onChanged: (_) => setState(() {}),
                decoration:
                    const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _descriptionController,
                onChanged: (_) => setState(() {}),
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Description', border: OutlineInputBorder()),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _linkController,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Link (optional)',
                  hintText: 'https://example.com',
                  helperText:
                      'If set, tapping the ad opens this link. Leave empty to just zoom the image.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: _submitting
                    ? 'Saving…'
                    : _isEditing
                        ? 'Save Changes'
                        : 'Post Ad',
                onPressed: _submitting ? null : _submit,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
