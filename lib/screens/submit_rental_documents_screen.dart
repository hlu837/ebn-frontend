import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/auth_response.dart';
import '../services/rental_agreement_service.dart';
import '../theme/app_theme.dart';
import 'my_rental_agreements_screen.dart';

/// Shown right after a renter taps "Rent this property" — the digital
/// ID + supporting-documents step of the Review tab pipeline (see
/// `backend/src/models/rentalAgreements.js`). Submitting here reserves
/// the listing (hides it from other users) and files it in the owner's
/// Review tab for a decision.
///
/// There's no file-storage service wired up in this build, so picked
/// images are embedded as base64 data URIs — fine for a couple of
/// document photos, same tradeoff the rest of this app makes wherever
/// it doesn't yet have a real upload endpoint.
class SubmitRentalDocumentsScreen extends StatefulWidget {
  const SubmitRentalDocumentsScreen({super.key, required this.user, required this.propertyRequestId, required this.assetTitle});

  final AppUser user;
  final String propertyRequestId;
  final String assetTitle;

  @override
  State<SubmitRentalDocumentsScreen> createState() => _SubmitRentalDocumentsScreenState();
}

class _SubmitRentalDocumentsScreenState extends State<SubmitRentalDocumentsScreen> {
  final _picker = ImagePicker();
  final _service = RentalAgreementService();
  final _noteController = TextEditingController();

  _PickedDoc? _idDoc;
  final List<_PickedDoc> _supportingDocs = [];
  bool _submitting = false;
  String? _error;

  String get _token => widget.user.token ?? '';

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<_PickedDoc?> _pickOne() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      final ext = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      final dataUri = 'data:image/$ext;base64,${base64Encode(bytes)}';
      return _PickedDoc(bytes: bytes, dataUri: dataUri);
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not pick image: $e')));
      return null;
    }
  }

  Future<void> _pickIdDoc() async {
    final picked = await _pickOne();
    if (picked == null) return;
    setState(() => _idDoc = picked);
  }

  Future<void> _addSupportingDoc() async {
    final picked = await _pickOne();
    if (picked == null) return;
    setState(() => _supportingDocs.add(picked));
  }

  void _removeSupportingDoc(int i) => setState(() => _supportingDocs.removeAt(i));

  Future<void> _submit() async {
    if (_idDoc == null) {
      setState(() => _error = 'A digital ID photo is required.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _service.submitDocuments(
        token: _token,
        propertyRequestId: widget.propertyRequestId,
        idDocumentUrl: _idDoc!.dataUri,
        documentUrls: _supportingDocs.map((d) => d.dataUri).toList(),
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => MyRentalAgreementsScreen(user: widget.user),
      ));
    } on RentalAgreementException catch (e) {
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
        title: const Text('Submit Documents', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(widget.assetTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 6),
            const Text(
              "To move this rental forward, send the owner your digital ID and any supporting documents. "
              "They'll review these and send you a rental agreement — you'll then have a set window to pay and confirm. "
              "Anything else you want to ask, use the chat.",
              style: TextStyle(fontSize: 13, color: AppColors.slate, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Digital ID *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            _DocSlot(doc: _idDoc, label: 'Upload ID', onTap: _pickIdDoc, onRemove: () => setState(() => _idDoc = null)),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Expanded(
                  child: Text('Supporting documents', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ),
                TextButton.icon(
                  onPressed: _addSupportingDoc,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const Text(
              'Proof of income, reference letter, previous lease — anything that helps the owner decide. Optional.',
              style: TextStyle(fontSize: 12, color: AppColors.slate),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _supportingDocs.length; i++)
                  _DocThumb(doc: _supportingDocs[i], onRemove: () => _removeSupportingDoc(i)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Note to owner (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'e.g. I can move in as soon as the agreement is signed.',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
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
                    : const Text('Submit for review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedDoc {
  final Uint8List bytes;
  final String dataUri;
  const _PickedDoc({required this.bytes, required this.dataUri});
}

class _DocSlot extends StatelessWidget {
  const _DocSlot({required this.doc, required this.label, required this.onTap, required this.onRemove});

  final _PickedDoc? doc;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (doc == null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, style: BorderStyle.solid),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.badge_outlined, size: 28, color: AppColors.slate),
                SizedBox(height: 8),
                Text('Tap to upload', style: TextStyle(fontSize: 12.5, color: AppColors.slate, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            doc!.bytes,
            height: 140,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: _RemoveButton(onTap: onRemove),
        ),
      ],
    );
  }
}

class _DocThumb extends StatelessWidget {
  const _DocThumb({required this.doc, required this.onRemove});

  final _PickedDoc doc;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(doc.bytes, width: 84, height: 84, fit: BoxFit.cover),
        ),
        Positioned(top: 4, right: 4, child: _RemoveButton(onTap: onRemove, size: 18)),
      ],
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap, this.size = 22});
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: Icon(Icons.close_rounded, size: size * 0.7, color: Colors.white),
      ),
    );
  }
}
