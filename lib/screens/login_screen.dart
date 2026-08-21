import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_role.dart';
import '../providers/pending_form_store.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/app_buttons.dart';
import 'agent_membership_plan_select_screen.dart';
import 'investor_membership_plan_select_screen.dart';
import 'order_request_form_screen.dart';
import 'role_router.dart';
import 'role_select_screen.dart';
import 'sell_property_form_screen.dart';
import 'verification_pending_screen.dart';

/// The standard, single login page — plain email + password, no role
/// picker in sight. All the role logic happens after "Login" is pressed:
/// authenticate, look up the account's saved role, then redirect straight
/// into that role's workspace. This is the smart router described in the
/// spec — Visitor → Marketplace Feed, Affiliater → Token Dashboard,
/// Agent/Broker → Listing Manager, Investor → Portfolio Portal.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _authService = AuthService();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      // 1. Authenticate.
      final user = await _authService.login(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (!mounted) return;

      final pendingStore = context.read<PendingFormStore>();
      if (pendingStore.hasPending) {
        if (pendingStore.pendingFormType == PendingFormType.order) {
          final cat = pendingStore.pendingCategory!;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => OrderRequestFormScreen(
                user: user,
                category: cat,
                resumeAfterAuth: true,
              ),
            ),
            (route) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => SellPropertyFormScreen(
                user: user,
                resumeAfterAuth: true,
              ),
            ),
            (route) => false,
          );
        }
        return;
      }

      // 2. Smart router — the account's saved role decides the destination.
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => dashboardForRole(user.role, user)),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      final pendingRoleStr = e.pendingRole ?? e.user?.pendingRole;
      final isPendingPayment = e.accountStatus == 'pending_payment' || e.user?.accountStatus == 'pending_payment' || pendingRoleStr != null;

      if (isPendingPayment) {
        final userToPass = e.user ?? AppUser(
          id: '',
          fullName: 'Pending User',
          email: _emailCtrl.text.trim(),
          role: UserRole.user,
          accountStatus: 'pending_payment',
          pendingRole: pendingRoleStr ?? 'agent',
        );
        AppToast.showInfo(
            context, 'Please complete payment to activate your account.');
        final roleToPay = pendingRoleStr ?? 'agent';
        if (roleToPay == 'agent') {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => AgentMembershipPlanSelectScreen(
                user: userToPass,
                pendingUserPayload: e.pendingUserData,
              ),
            ),
            (route) => false,
          );
          return;
        } else if (roleToPay == 'investor') {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => InvestorMembershipPlanSelectScreen(
                user: userToPass,
                pendingUserPayload: e.pendingUserData,
              ),
            ),
            (route) => false,
          );
          return;
        }
      } else if (e.accountStatus == 'pending_approval' && e.user != null) {
        final targetRole = e.pendingRole == 'agent'
            ? UserRole.agent
            : e.pendingRole == 'investor'
                ? UserRole.investor
                : UserRole.user;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VerificationPendingScreen(
                user: e.user!, targetRole: targetRole),
          ),
        );
        return;
      }

      AppToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome back',
                    style: textTheme.displayLarge?.copyWith(fontSize: 28)),
                const SizedBox(height: 6),
                Text(
                  "We'll take you straight to your workspace.",
                  style: textTheme.bodyLarge?.copyWith(color: AppColors.slate),
                ),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email', hintText: 'you@example.com'),
                  validator: Validators.email,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => Validators.notEmpty(v, label: 'Password'),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                    label: 'Log In', isLoading: _isLoading, onPressed: _submit),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: GestureDetector(
                    onTap: _isLoading
                        ? null
                        : () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => const RoleSelectScreen()),
                            ),
                    child: RichText(
                      text: TextSpan(
                        style: textTheme.bodyMedium,
                        children: const [
                          TextSpan(text: "Don't have an account?  "),
                          TextSpan(
                              text: 'Choose your path',
                              style: TextStyle(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
