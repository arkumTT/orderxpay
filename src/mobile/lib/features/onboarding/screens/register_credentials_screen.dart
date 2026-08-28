import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Registration Page 2 (Section 4.1) — reached only after OnboardingScreen
/// (Page 1) gets a real phone-OTP verification. Creates the merchant with
/// real login credentials; does NOT auto-login — the merchant is prompted
/// to verify their email, then sent to the Login screen to sign in
/// themselves, matching the intended flow.
///
/// Email verification itself is real (a live token flips
/// email_verified_at — see otp.go's VerifyMerchantEmail), but no email
/// provider is wired up server-side (Section 9), so nothing actually
/// emails the link. In dev builds the create-merchant response carries the
/// token directly, surfaced here as a clearly-labeled dev shortcut so the
/// loop is genuinely testable without a real inbox.
class RegisterCredentialsScreen extends StatefulWidget {
  const RegisterCredentialsScreen({
    super.key,
    required this.businessName,
    required this.category,
    required this.phone,
  });

  final String businessName;
  final String category;
  final String phone;

  @override
  State<RegisterCredentialsScreen> createState() => _RegisterCredentialsScreenState();
}

class _RegisterCredentialsScreenState extends State<RegisterCredentialsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _api = ApiClient();

  bool _submitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await _api.registerMerchant(
        businessName: widget.businessName,
        category: widget.category,
        phone: widget.phone,
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      await _showVerifyEmailPrompt(res['dev_email_verify_token'] as String?);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showVerifyEmailPrompt(String? devToken) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Account created'),
        content: Text(
          "Go to your email (${_emailController.text.trim()}) and tap the "
          "verification link to confirm your address, then log in.",
        ),
        actions: [
          if (devToken != null)
            TextButton(
              onPressed: () async {
                try {
                  await _api.get('/api/v1/public/email/verify?token=$devToken');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('DEV: email marked verified')),
                    );
                  }
                } on ApiException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
              child: const Text('DEV: Verify email now'),
            ),
          OxpButton(
            label: 'Go to Login',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Your Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Form(
            key: _formKey,
            child: OxpCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'STEP 2 OF 2 · CREATE YOUR USER ACCESS',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 18),
                  OxpField(
                    label: 'Username',
                    controller: _usernameController,
                    hintText: 'hand2muff',
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  OxpField(
                    label: 'Email',
                    controller: _emailController,
                    hintText: 'you@business.com',
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  OxpField(
                    label: 'Password',
                    controller: _passwordController,
                    hintText: 'At least 8 characters',
                    obscureText: _obscurePassword,
                    validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OxpField(
                    label: 'Confirm password',
                    controller: _confirmController,
                    hintText: 'Re-enter your password',
                    obscureText: _obscureConfirm,
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    suffix: IconButton(
                      icon: Icon(
                        _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.statusDeclined, fontSize: 13)),
                  ],
                  const SizedBox(height: 20),
                  OxpButton(
                    label: _submitting ? 'Creating…' : 'Enter',
                    loading: _submitting,
                    icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                    onPressed: _submitting ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
