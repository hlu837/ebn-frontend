import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/auth_response.dart';
import '../models/maintenance_request.dart';
import '../services/maintenance_request_service.dart';
import '../theme/app_theme.dart';
import 'my_maintenance_requests_screen.dart';

/// Reached only from a "Report a maintenance issue" button on an active
/// lease (see `_AgreementCard` in `my_rental_agreements_screen.dart`),
/// which is only shown once `MaintenanceRequestService.fetchEligibleAssets`
/// confirms the caller actually has an active lease on this asset. The
/// backend re-checks that same condition on submit — this screen doesn't
/// need to re-verify it, only pass the asset id through.
class MaintenanceRequestFormScreen extends StatefulWidget {
  const MaintenanceRequestFormScreen({
    super.key,
    required this.user,
    required this.assetId,
    required this.assetTitle,
  });

  final AppUser user;
  final String assetId;
  final String assetTitle;

  @override
  State<MaintenanceRequestFormScreen> createState() => _MaintenanceRequestFormScreenState();
}

class _MaintenanceRequestFormScreenState extends State<MaintenanceRequestFormScreen> {
  final _picker = ImagePicker();
  final _service = MaintenanceRequestService();
  final _descriptionController = TextEditingController();

  MaintenanceCategory _category = MaintenanceCategory.electrical;
  final List<_PickedPhoto> _photos = [];
  bool _submitting = false;
  String? _error;

  String get _token => widget.user.token ?? '';

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final ext = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      final dataUri = 'data:image/$ext;base64,${base64Encode(bytes)}';
      setState(() => _photos.add(_PickedPhoto(bytes: bytes, dataUri: dataUri)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not pick image: $e')));
    }
  }

  void _removePhoto(int i) => setState(() => _photos.removeAt(i));

  Future<void> _submit() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      setState(() => _error = 'Describe the issue before submitting.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _service.submit(
        token: _token,
        assetId: widget.assetId,
        category: _category,
        description: description,
        photoUrls: _photos.map((p) => p.dataUri).toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => MyMaintenanceRequestsScreen(user: widget.user),
      ));
    } on MaintenanceRequestException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text('Report an Issue', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(widget.assetTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 6),
            const Text(
              "Tell your property owner what's wrong. They'll review it and either handle it themselves "
              "or let you know so you can assign a specialist yourself.",
              style: TextStyle(fontSize: 13, color: AppColors.slate, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Category *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in MaintenanceCategory.values)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Describe the issue *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'e.g. Kitchen tap has been leaking steadily since Monday.',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Expanded(
                  child: Text('Photos (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ),
                TextButton.icon(
                  onPressed: _addPhoto,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const Text(
              'A photo of the issue helps the owner (or specialist) understand it faster.',
              style: TextStyle(fontSize: 12, color: AppColors.slate),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  _PhotoThumb(photo: _photos[i], onRemove: () => _removePhoto(i)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryYellow,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Submit request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedPhoto {
  final Uint8List bytes;
  final String dataUri;
  const _PickedPhoto({required this.bytes, required this.dataUri});
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.photo, required this.onRemove});

  final _PickedPhoto photo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(photo.bytes, width: 84, height: 84, fit: BoxFit.cover),
        ),
        Positioned(top: 4, right: 4, child: _RemovePhotoButton(onTap: onRemove)),
      ],
    );
  }
}

class _RemovePhotoButton extends StatelessWidget {
  const _RemovePhotoButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 18,
        height: 18,
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
      ),
    );
  }
}
