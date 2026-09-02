import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/asset.dart';
import '../models/auth_response.dart';
import '../services/asset_service.dart';
import '../theme/app_theme.dart';

/// Lets agents edit their property listings — update price, title,
/// description, photos, and basic details. Backed by
/// `PATCH /api/assets/:id`.
class AgentListingEditScreen extends StatefulWidget {
  const AgentListingEditScreen({
    super.key,
    required this.asset,
    required this.user,
  });

  final Asset asset;
  final AppUser user;

  @override
  State<AgentListingEditScreen> createState() => _AgentListingEditScreenState();
}

class _AgentListingEditScreenState extends State<AgentListingEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _assetService = AssetService();
  final _imagePicker = ImagePicker();

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _priceController;
  late TextEditingController _cityController;
  late TextEditingController _addressController;

  List<String> _imageUrls = [];
  List<XFile> _newImages = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.asset.title);
    _descriptionController =
        TextEditingController(text: widget.asset.description ?? '');
    _priceController =
        TextEditingController(text: widget.asset.priceAmount.toString());
    _cityController = TextEditingController(text: widget.asset.city ?? '');
    _addressController =
        TextEditingController(text: widget.asset.addressLine ?? '');
    _imageUrls = List.from(widget.asset.imageUrls);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final files = await _imagePicker.pickMultiImage(
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (files.isEmpty || !mounted) return;
      setState(() {
        _newImages.addAll(files);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking images: $e')),
      );
    }
  }

  Future<void> _removeImage(int index) async {
    setState(() {
      if (index < _imageUrls.length) {
        _imageUrls.removeAt(index);
      } else {
        _newImages.removeAt(index - _imageUrls.length);
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final price = double.tryParse(_priceController.text) ?? 0;

      // Convert new images to base64
      final newImageDataUrls = <String>[];
      for (final file in _newImages) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          throw FormatException('Image ${file.name} is too large (max 5MB)');
        }
        final mimeType = file.mimeType ?? 'image/jpeg';
        newImageDataUrls.add('data:$mimeType;base64,${base64Encode(bytes)}');
      }

      // Combine kept existing URLs with new data URLs
      final allImageUrls = [..._imageUrls, ...newImageDataUrls];

      // Update asset via API
      await _assetService.updateAsset(
        widget.asset.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        priceAmount: price,
        city: _cityController.text.trim(),
        addressLine: _addressController.text.trim(),
        imageUrls: allImageUrls,
        token: widget.user.token ?? '',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing updated successfully!')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving listing: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        title: const Text('Edit Listing',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryYellow)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category Badge (read-only)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  widget.asset.category.label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Title
              const Text('Title',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _titleController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Property title',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Title is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Description
              const Text('Description',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Detailed description of the property',
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Price
              const Text('Price (ETB)',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixText: '₦ ',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Price is required';
                  }
                  if (double.tryParse(v) == null) {
                    return 'Enter a valid price';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // City
              const Text('City',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _cityController,
                decoration: const InputDecoration(
                  hintText: 'e.g., Addis Ababa',
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Address
              const Text('Address',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Street address or landmark',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Photos Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Photos',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                  OutlinedButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 18),
                    label: const Text('Add Photos'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_imageUrls.isEmpty && _newImages.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: const Center(
                    child: Text('No photos yet',
                        style: TextStyle(color: AppColors.slate)),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: _imageUrls.length + _newImages.length,
                  itemBuilder: (context, index) {
                    final isExisting = index < _imageUrls.length;
                    final isString = isExisting;
                    final imageUrlOrFile = isExisting
                        ? _imageUrls[index]
                        : _newImages[index - _imageUrls.length];

                    return Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            color: AppColors.border,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            child: isString
                                ? Image.network(
                                    imageUrlOrFile as String,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stack) =>
                                        const Icon(Icons.broken_image_outlined),
                                  )
                                : Image.file(
                                    File((imageUrlOrFile as XFile).path),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stack) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(Icons.close,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: AppSpacing.xl),

              // Status Info
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Status',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.slate)),
                    const SizedBox(height: 4),
                    Text(widget.asset.status.label,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
