import 'package:flutter/material.dart';

import '../models/admin_settings_models.dart';
import '../services/admin_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';

/// Admin > Settings > Specialist Wallets. Lists every service provider
/// with their current specialist_wallet_transactions balance (credited
/// automatically on escrow release, Phase 6); drilling into one shows
/// the full ledger and a form to record an offline payout already made —
/// see 085_specialist_wallet_transactions.sql's note on why this is a
/// manual-record flow rather than a self-service withdrawal.
class AdminSpecialistWalletsScreen extends StatefulWidget {
  const AdminSpecialistWalletsScreen({super.key, required this.token});
  final String token;

  @override
  State<AdminSpecialistWalletsScreen> createState() => _AdminSpecialistWalletsScreenState();
}

class _AdminSpecialistWalletsScreenState extends State<AdminSpecialistWalletsScreen> {
  final _service = AdminSettingsService();
  List<AdminServiceProviderBalance> _rows = const [];
  bool _loading = true;
  String? _error;

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
      final rows = await _service.fetchServiceProviderWallets(token: widget.token);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on AdminSettingsServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(title: const Text('Specialist Wallets'), backgroundColor: AppColors.cloud, foregroundColor: AppColors.ink),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.slate)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _rows.isEmpty
                        ? ListView(
                            children: const [
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                                child: Center(child: Text('No specialists yet.', style: TextStyle(color: AppColors.slate))),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: _rows.length,
                            itemBuilder: (context, i) {
                              final row = _rows[i];
                              return Container(
                                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(AppRadii.lg),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: ListTile(
                                  title: Text(row.provider.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(row.provider.phone, style: const TextStyle(fontSize: 12, color: AppColors.slate)),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${row.balanceBirr.toStringAsFixed(0)} ETB',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: row.balanceCents > 0 ? AppColors.success : AppColors.slate,
                                        ),
                                      ),
                                      const Text('owed', style: TextStyle(fontSize: 10.5, color: AppColors.slate)),
                                    ],
                                  ),
                                  onTap: () async {
                                    await Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => _SpecialistWalletDetailScreen(token: widget.token, provider: row.provider),
                                    ));
                                    _load();
                                  },
                                ),
                              );
                            },
                          ),
                  ),
      ),
    );
  }
}

class _SpecialistWalletDetailScreen extends StatefulWidget {
  const _SpecialistWalletDetailScreen({required this.token, required this.provider});
  final String token;
  final AdminServiceProvider provider;

  @override
  State<_SpecialistWalletDetailScreen> createState() => _SpecialistWalletDetailScreenState();
}

class _SpecialistWalletDetailScreenState extends State<_SpecialistWalletDetailScreen> {
  final _service = AdminSettingsService();
  int _balanceCents = 0;
  List<AdminSpecialistWalletTransaction> _transactions = const [];
  bool _loading = true;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _service.fetchServiceProviderWallet(widget.provider.id, token: widget.token);
      if (!mounted) return;
      setState(() {
        _balanceCents = result.balanceCents;
        _transactions = result.transactions;
        _loading = false;
      });
    } on AdminSettingsServiceException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.showError(context, e.message);
    }
  }

  Future<void> _recordPayout() async {
    final amountController = TextEditingController(text: _balanceCents > 0 ? (_balanceCents / 100).toStringAsFixed(0) : '');
    final labelController = TextEditingController(text: 'Bank transfer');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Record payout'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Only record this after you\'ve actually paid ${widget.provider.name} outside the app.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(prefixText: 'ETB ', labelText: 'Amount paid'),
            ),
            const SizedBox(height: 10),
            TextField(controller: labelController, decoration: const InputDecoration(labelText: 'How (bank, cash, mobile money…)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Record')),
        ],
      ),
    );
    if (confirmed != true) return;
    final birr = double.tryParse(amountController.text.trim());
    if (birr == null || birr <= 0) {
      if (mounted) AppToast.showError(context, 'Enter a valid amount.');
      return;
    }
    setState(() => _recording = true);
    try {
      await _service.recordSpecialistPayout(
        widget.provider.id,
        amountCents: (birr * 100).round(),
        label: labelController.text.trim().isEmpty ? 'Manual payout' : labelController.text.trim(),
        token: widget.token,
      );
      await _load();
    } on AdminSettingsServiceException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(title: Text(widget.provider.name), backgroundColor: AppColors.cloud, foregroundColor: AppColors.ink),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    margin: const EdgeInsets.all(AppSpacing.lg),
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadii.lg)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Current balance', style: TextStyle(fontSize: 12, color: AppColors.slate)),
                              Text('${(_balanceCents / 100).toStringAsFixed(0)} ETB',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: _balanceCents <= 0 || _recording ? null : _recordPayout,
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryYellow, foregroundColor: AppColors.ink),
                          child: const Text('Record payout'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _transactions.isEmpty
                        ? const Center(child: Text('No transactions yet.', style: TextStyle(color: AppColors.slate)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                            itemCount: _transactions.length,
                            itemBuilder: (context, i) {
                              final tx = _transactions[i];
                              final credit = tx.type == 'credit';
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  credit ? Icons.add_circle_outline : Icons.remove_circle_outline,
                                  color: credit ? AppColors.success : AppColors.slate,
                                ),
                                title: Text(tx.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                subtitle: Text('${tx.createdAt.toLocal()}'.split('.').first, style: const TextStyle(fontSize: 11, color: AppColors.slate)),
                                trailing: Text(
                                  '${credit ? '+' : ''}${tx.amountBirr.toStringAsFixed(0)} ETB',
                                  style: TextStyle(fontWeight: FontWeight.w800, color: credit ? AppColors.success : AppColors.ink),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
