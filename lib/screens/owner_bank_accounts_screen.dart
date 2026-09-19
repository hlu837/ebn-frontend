import 'package:flutter/material.dart';

import '../models/auth_response.dart';
import '../models/owner_bank_account.dart';
import '../services/owner_bank_account_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';

/// Property Owner > Account > "Bank Accounts" — the accounts a tenant
/// sees on the payment screen once they accept a rental agreement (see
/// my_rental_agreements_screen.dart's payment step). Only banks the
/// platform currently accepts (GET /api/owner-bank-accounts/banks) can
/// be picked here, so nothing added here can ever fail to show up for a
/// tenant.
class OwnerBankAccountsScreen extends StatefulWidget {
  const OwnerBankAccountsScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<OwnerBankAccountsScreen> createState() => _OwnerBankAccountsScreenState();
}

class _OwnerBankAccountsScreenState extends State<OwnerBankAccountsScreen> {
  final _service = OwnerBankAccountService();
  String get _token => widget.user.token ?? '';

  List<OwnerBankAccount> _accounts = const [];
  List<PlatformBank> _banks = const [];
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
      final results = await Future.wait([_service.listMine(token: _token), _service.fetchBanks(token: _token)]);
      if (!mounted) return;
      setState(() {
        _accounts = results[0] as List<OwnerBankAccount>;
        _banks = results[1] as List<PlatformBank>;
        _loading = false;
      });
    } on OwnerBankAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _addAccount() async {
    if (_banks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No banks are accepted on the platform right now — contact support.')),
      );
      return;
    }
    final draft = await showModalBottomSheet<_AccountDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AccountSheet(banks: _banks, hasExisting: _accounts.isNotEmpty),
    );
    if (draft == null) return;
    try {
      await _service.create(
        token: _token,
        bankId: draft.bankId,
        accountName: draft.accountName,
        accountNumber: draft.accountNumber,
        isDefault: draft.isDefault,
      );
      await _load();
    } on OwnerBankAccountException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _setDefault(OwnerBankAccount account) async {
    try {
      await _service.update(token: _token, id: account.id, isDefault: true);
      await _load();
    } on OwnerBankAccountException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(OwnerBankAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove this account?'),
        content: Text('Tenants will no longer see ${account.bankName} — ${account.accountName} on the payment screen.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.delete(token: _token, id: account.id);
      await _load();
    } on OwnerBankAccountException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: const Text('Bank Accounts', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(child: _body()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAccount,
        backgroundColor: AppColors.primaryYellow,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add account', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 12),
              SecondaryButton(label: 'Try again', onPressed: _load),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "These accounts are shown to a tenant on the payment screen after they accept a rental agreement — only banks the platform currently accepts can be added.",
            style: TextStyle(fontSize: 12.5, color: AppColors.slate, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (_accounts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.border)),
              child: const Column(
                children: [
                  Icon(Icons.account_balance_outlined, color: AppColors.slate, size: 30),
                  SizedBox(height: 10),
                  Text(
                    "No bank accounts yet — add one so tenants have somewhere to send rent.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.slate),
                  ),
                ],
              ),
            )
          else
            ..._accounts.map((a) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _AccountCard(account: a, onSetDefault: () => _setDefault(a), onDelete: () => _delete(a)))),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.onSetDefault, required this.onDelete});

  final OwnerBankAccount account;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: account.isDefault ? AppColors.primaryYellow : AppColors.border, width: account.isDefault ? 1.4 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: AppColors.primaryYellow.withValues(alpha: 0.1), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.account_balance_rounded, size: 19, color: AppColors.primaryYellow),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        account.bankShortCode?.isNotEmpty == true ? account.bankShortCode! : account.bankName,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (account.isDefault)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.primaryYellow, borderRadius: BorderRadius.circular(AppRadii.pill)),
                        child: const Text('Default', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(account.accountName, style: const TextStyle(fontSize: 12.5, color: AppColors.slate)),
                const SizedBox(height: 2),
                Text(account.accountNumber, style: const TextStyle(fontSize: 12.5, color: AppColors.ink, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'default') onSetDefault();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              if (!account.isDefault) const PopupMenuItem(value: 'default', child: Text('Make default')),
              const PopupMenuItem(value: 'delete', child: Text('Remove', style: TextStyle(color: AppColors.danger))),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountDraft {
  final String bankId;
  final String accountName;
  final String accountNumber;
  final bool isDefault;
  const _AccountDraft({required this.bankId, required this.accountName, required this.accountNumber, required this.isDefault});
}

class _AccountSheet extends StatefulWidget {
  const _AccountSheet({required this.banks, required this.hasExisting});
  final List<PlatformBank> banks;
  final bool hasExisting;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  final _nameController = TextEditingController();
  final _numberController = TextEditingController();
  String? _bankId;
  bool _isDefault = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bankId = widget.banks.first.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final number = _numberController.text.trim();
    if (_bankId == null) {
      setState(() => _error = 'Pick a bank.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Enter the name that should show on the account — e.g. your company name.');
      return;
    }
    if (number.isEmpty) {
      setState(() => _error = 'Enter the account number.');
      return;
    }
    Navigator.of(context).pop(_AccountDraft(bankId: _bankId!, accountName: name, accountNumber: number, isDefault: _isDefault));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(color: AppColors.cloud, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.lg, bottom: AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Add bank account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink))),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Bank', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _bankId,
                decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                items: widget.banks.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                onChanged: (v) => setState(() => _bankId = v),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Account name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(hintText: 'e.g. Noh Real Estate', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Account number', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 6),
              TextField(
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(hintText: 'e.g. 1000123456789', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
              if (widget.hasExisting) ...[
                const SizedBox(height: 6),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v ?? false),
                  title: const Text('Make this the default account', style: TextStyle(fontSize: 13, color: AppColors.ink)),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: 'Save account', backgroundColor: AppColors.primaryYellow, foregroundColor: Colors.white, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
