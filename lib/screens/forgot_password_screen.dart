import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/app_buttons.dart';

/// "Forgot password?" flow off the Login screen. Two steps in one screen:
///
/// 1. Enter email -> POST /api/auth/forgot-password. The backend always
///    replies with the same generic message (see the route's own
///    comments), so this step just moves on to step 2 once the request
///    completes — it never claims to know whether the email exists.
/// 2. Enter the code that arrived by email + a new password ->
///    POST /api/auth/reset-password, then back to Login.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _authService = AuthService();

  final _requestFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _codeRequested = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _infoMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (!_requestFormKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final message = await _authService.forgotPassword(_emailCtrl.text);
      if (!mounted) return;
      setState(() {
        _codeRequested = true;
        _infoMessage = message;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_resetFormKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await _authService.resetPassword(
        email: _emailCtrl.text,
        code: _codeCtrl.text,
        newPassword: _newPasswordCtrl.text,
      );
      if (!mounted) return;
      AppToast.showSuccess(
          context, 'Password reset. Please log in with your new password.');
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Forgot password?',
                  style: textTheme.displayLarge?.copyWith(fontSize: 28)),
              const SizedBox(height: 6),
              Text(
                _codeRequested
                    ? 'Enter the code we sent and choose a new password.'
                    : "Enter your account email and we'll send you a reset code.",
                style: textTheme.bodyLarge?.copyWith(color: AppColors.slate),
              ),
              const SizedBox(height: AppSpacing.xl),

              if (!_codeRequested) ...[
                Form(
                  key: _requestFormKey,
                  child: TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Email', hintText: 'you@example.com'),
                    validator: Validators.email,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  label: 'Send Reset Code',
                  isLoading: _isSubmitting,
                  onPressed: _requestCode,
                ),
              ] else ...[
                if (_infoMessage != null) ...[
                  Text(
                    _infoMessage!,
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.slate),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Form(
                  key: _resetFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _codeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Reset Code',
                          hintText: '6-digit code from your email',
                        ),
                        validator: (v) =>
                            Validators.notEmpty(v, label: 'Reset code'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _newPasswordCtrl,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          hintText: 'At least 6 characters',
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: Validators.password,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _confirmPasswordCtrl,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: 'Confirm New Password',
                          hintText: 'Re-enter your new password',
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirmPassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded),
                            onPressed: () => setState(() =>
                                _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                        validator: (v) => Validators.confirmPassword(
                            v, _newPasswordCtrl.text),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  label: 'Reset Password',
                  isLoading: _isSubmitting,
                  onPressed: _resetPassword,
                ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: GestureDetector(
                    onTap: _isSubmitting
                        ? null
                        : () => setState(() {
                              _codeRequested = false;
                              _infoMessage = null;
                            }),
                    child: Text(
                      'Use a different email',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
