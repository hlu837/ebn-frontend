import 'package:flutter/material.dart';

import '../models/admin_settings_models.dart';
import '../models/service_provider.dart';
import '../services/admin_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';

/// Admin > Settings > Service Providers. Review/edit/remove for the local
/// specialist directory backing Phase 3 of the maintenance-request
/// workflow. Onboarding is self-service now -- an Affiliater submits their
/// own Expert profile from the app (Affiliate dashboard → More → Expert),
/// which lands here inactive; this screen's job is to approve (or edit,
/// or remove) what they submitted, not to create new entries from
/// scratch. See 086_service_provider_user_link.sql.
class AdminServiceProvidersScreen extends StatefulWidget {
  const AdminServiceProvidersScreen({super.key, required this.token});

  final String token;

  @override
  State<AdminServiceProvidersScreen> createState() => _AdminServiceProvidersScreenState();
}

class _AdminServiceProvidersScreenState extends State<AdminServiceProvidersScreen> {
  final AdminSettingsService _service = AdminSettingsService();

  List<AdminServiceProvider> _providers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _service.fetchServiceProviders(token: widget.token);
      if (!mounted) return;
      setState(() {
        _providers = rows;
        _loading = false;
      });
    } on AdminSettingsServiceException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.showError(context, e.message);
    }
  }

  /// Edits an existing self-submitted profile. There's no "create new"
  /// path anymore -- see the class doc comment -- so this always takes an
  /// existing row.
  Future<void> _openEditor(AdminServiceProvider existing) async {
    final nameController = TextEditingController(text: existing.name);
    final phoneController = TextEditingController(text: existing.phone);
    final cityController = TextEditingController(text: existing.city);
    final rateController = TextEditingController(
      text: existing.rateCents > 0 ? existing.rateBirr.toStringAsFixed(0) : '',
    );
    final ratingController = TextEditingController(
      text: existing.rating != null ? existing.rating!.toStringAsFixed(1) : '',
    );
    ServiceProviderCategory category = ServiceProviderCategoryX.fromWire(existing.category);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
          title: const Text('Edit Specialist'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
                  autofocus: true,
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<ServiceProviderCategory>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Trade', border: OutlineInputBorder()),
                  items: ServiceProviderCategory.values
                      .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => category = v ?? category),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: cityController,
                  decoration: const InputDecoration(labelText: 'City', border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: rateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Call-out rate (Birr, optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: ratingController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Rating out of 5 (optional)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    final city = cityController.text.trim();
    if (name.isEmpty || phone.isEmpty || city.isEmpty) {
      if (!mounted) return;
      AppToast.showError(context, 'Name, phone, and city are required.');
      return;
    }
    final rateBirr = double.tryParse(rateController.text.trim()) ?? 0;
    final rateCents = (rateBirr * 100).round();
    final rating = double.tryParse(ratingController.text.trim());

    try {
      await _service.updateServiceProvider(
        existing.id,
        name: name,
        category: category.wireValue,
        phone: phone,
        city: city,
        rateCents: rateCents,
        rating: rating,
        token: widget.token,
      );
      await _load();
    } on AdminSettingsServiceException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message);
    }
  }

  Future<void> _toggleActive(AdminServiceProvider provider) async {
    try {
      await _service.updateServiceProvider(provider.id, isActive: !provider.isActive, token: widget.token);
      await _load();
    } on AdminSettingsServiceException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message);
    }
  }

  Future<void> _remove(AdminServiceProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove specialist?'),
        content: Text('"${provider.name}" will no longer be listed in the directory.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.removeServiceProvider(provider.id, token: widget.token);
      if (!mounted) return;
      setState(() => _providers.removeWhere((p) => p.id == provider.id));
    } on AdminSettingsServiceException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        title: const Text('Service Providers'),
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _providers.isEmpty
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                            child: Center(
                              child: Text(
                                'No specialists yet.\nThey show up here once an Affiliater sets up\nan Expert profile in the app.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.slate),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
                        itemCount: _providers.length,
                        itemBuilder: (context, index) {
                          final provider = _providers[index];
                          final category = ServiceProviderCategoryX.fromWire(provider.category);
                          return Container(
                            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(AppRadii.lg),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: ListTile(
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      provider.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: provider.isActive ? AppColors.ink : AppColors.slate,
                                        decoration: provider.isActive ? null : TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ),
                                  if (!provider.isActive) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryYellow.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(AppRadii.pill),
                                      ),
                                      child: const Text(
                                        'Pending review',
                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primaryYellowDark),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                '${category.label} · ${provider.city} · ${provider.phone}'
                                '${provider.rating != null ? ' · ★${provider.rating!.toStringAsFixed(1)}' : ''}'
                                '${provider.userId != null ? ' · Affiliater profile' : ''}',
                                style: const TextStyle(fontSize: 12, color: AppColors.slate),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                    onPressed: () => _openEditor(provider),
                                    tooltip: 'Edit',
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      provider.isActive ? Icons.visibility_off_outlined : Icons.check_circle_outline_rounded,
                                      size: 20,
                                      color: provider.isActive ? AppColors.danger : AppColors.success,
                                    ),
                                    onPressed: () => _toggleActive(provider),
                                    tooltip: provider.isActive ? 'Hide from directory' : 'Approve & publish',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger),
                                    onPressed: () => _remove(provider),
                                    tooltip: 'Remove',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}
