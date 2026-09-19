import 'package:flutter/material.dart';

import '../models/investor_membership_plan.dart';
import '../services/admin_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';

/// Admin page to configure the Investor "Shareholder & Investor
/// Membership" plan — the price, benefits list, and copy shown on the
/// Investor signup/upgrade screen. Mirrors [AdminMembershipPricingScreen].
class AdminInvestorMembershipPlanScreen extends StatefulWidget {
  const AdminInvestorMembershipPlanScreen({super.key, required this.token});

  final String token;

  @override
  State<AdminInvestorMembershipPlanScreen> createState() =>
      _AdminInvestorMembershipPlanScreenState();
}

class _AdminInvestorMembershipPlanScreenState
    extends State<AdminInvestorMembershipPlanScreen> {
  final _service = AdminSettingsService();
  late Future<InvestorMembershipPlan> _future = _load();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _footerController = TextEditingController();
  final List<TextEditingController> _benefitControllers = [];

  bool _saving = false;

  Future<InvestorMembershipPlan> _load() =>
      _service.fetchInvestorMembershipPlan(token: widget.token);

  @override
  void initState() {
    super.initState();
    _future.then((plan) {
      if (mounted) setState(() => _updateControllers(plan));
    });
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    final plan = await next;
    if (!mounted) return;
    _updateControllers(plan);
  }

  void _updateControllers(InvestorMembershipPlan plan) {
    _titleController.text = plan.title;
    _descriptionController.text = plan.description;
    _priceController.text = plan.priceEtb.toStringAsFixed(0);
    _footerController.text = plan.footerNote;
    for (final c in _benefitControllers) {
      c.dispose();
    }
    _benefitControllers
      ..clear()
      ..addAll(plan.benefits.map((b) => TextEditingController(text: b)));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _footerController.dispose();
    for (final c in _benefitControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addBenefit() {
    setState(() => _benefitControllers.add(TextEditingController()));
  }

  void _removeBenefit(int index) {
    setState(() {
      _benefitControllers[index].dispose();
      _benefitControllers.removeAt(index);
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final footerNote = _footerController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final benefits = _benefitControllers
        .map((c) => c.text.trim())
        .where((b) => b.isNotEmpty)
        .toList();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Title is required.')));
      return;
    }
    if (price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid, non-negative price.')));
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.updateInvestorMembershipPlan(
        title: title,
        description: description,
        priceEtb: price,
        benefits: benefits,
        footerNote: footerNote,
        token: widget.token,
      );
      if (!mounted) return;
      await _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Investor membership plan updated.')),
      );
    } on AdminSettingsServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        title: const Text('Investor Membership Plan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: FutureBuilder<InvestorMembershipPlan>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error is AdminSettingsServiceException
                  ? (snapshot.error as AdminSettingsServiceException).message
                  : 'Something went wrong.',
              onRetry: _refresh,
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const _FieldLabel('Title'),
                const SizedBox(height: 6),
                TextField(
                  controller: _titleController,
                  maxLines: 2,
                  decoration: _decoration(
                      hint:
                          'e.g. SHAREHOLDER & INVESTOR\\nMEMBERSHIP (use \\n for a line break)'),
                ),
                const SizedBox(height: AppSpacing.md),
                const _FieldLabel('Description'),
                const SizedBox(height: 6),
                TextField(
                  controller: _descriptionController,
                  maxLines: 2,
                  decoration:
                      _decoration(hint: 'Shown under the title.'),
                ),
                const SizedBox(height: AppSpacing.md),
                const _FieldLabel('Price (ETB)'),
                const SizedBox(height: 6),
                TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: _decoration(hint: '1500000', suffixText: 'ETB'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const _FieldLabel('Benefits'),
                    TextButton.icon(
                      onPressed: _addBenefit,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                for (int i = 0; i < _benefitControllers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _benefitControllers[i],
                            decoration:
                                _decoration(hint: 'Benefit ${i + 1}'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: AppColors.slate, size: 20),
                          onPressed: () => _removeBenefit(i),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                const _FieldLabel('Footer note'),
                const SizedBox(height: 6),
                TextField(
                  controller: _footerController,
                  decoration: _decoration(
                      hint: 'e.g. Join the exclusive investor circle.'),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: _saving ? 'Saving...' : 'Save Changes',
                    onPressed: _saving ? null : _save,
                    isLoading: _saving,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

InputDecoration _decoration({required String hint, String? suffixText}) {
  return InputDecoration(
    hintText: hint,
    suffixText: suffixText,
    contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.sm),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink));
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: AppColors.slate),
            const SizedBox(height: AppSpacing.md),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: AppColors.slate)),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
