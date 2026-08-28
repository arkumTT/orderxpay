import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Real email+password login (Section 4.1/4.9) — the app's default
/// signed-out landing page, ahead of onboarding. Shared by merchant owners
/// and staff; the backend (MerchantLogin) figures out which one an email
/// belongs to and returns the right actor_type.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = ApiClient();

  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await _api.login(_emailController.text.trim(), _passwordController.text);
      await Session.instance.save(
        token: res['access_token'] as String,
        merchantId: res['merchant_id'] as String,
        businessName: res['business_name'] as String? ?? 'Merchant',
        actorType: res['actor_type'] as String? ?? 'merchant',
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            AppSpace.xxl,
            AppSpace.xl,
            AppSpace.xl,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const OxpWordmark(fontSize: 34),
                const SizedBox(height: 14),
                const Text(
                  'Invoice your customers. Get paid instantly.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 36),
                OxpCard(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LOG IN',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 18),
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
                        hintText: '••••••••',
                        obscureText: _obscure,
                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        suffix: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: AppColors.statusDeclined, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 20),
                      OxpButton(
                        label: _submitting ? 'Logging in…' : 'Log In',
                        loading: _submitting,
                        icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                        onPressed: _submitting ? null : _submit,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/onboarding'),
                  child: const Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      children: [
                        TextSpan(text: "New here? "),
                        TextSpan(
                          text: 'Register',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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
