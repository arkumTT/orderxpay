import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Self-serve sign-up (Section 4.1, Tier 0 KYC), styled per the OrderxPay
/// Onboarding Design. Wired to the real CreateMerchant endpoint; "Send OTP"
/// is a stand-in label — OTP delivery is stubbed server-side pending SMS
/// provider selection (Section 9), so this calls the dev-token bootstrap
/// (api_client.dart / cmd/devtoken's HTTP twin) to get a session instead.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _phoneController = TextEditingController();
  final _api = ApiClient();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _businessNameController.dispose();
    _categoryController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final phone = '+233${_phoneController.text.replaceAll(RegExp(r'\s'), '')}';
      final merchant = await _api.post('/api/v1/public/merchants', {
        'business_name': _businessNameController.text,
        'category': _categoryController.text,
        'phone': phone,
      });
      final merchantId = merchant['id'] as String;

      final tokenRes = await _api.post('/api/v1/public/dev/token', {
        'merchant_id': merchantId,
      });
      await Session.instance.save(
        token: tokenRes['access_token'] as String,
        merchantId: merchantId,
        businessName: _businessNameController.text,
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
                Image.asset(
                  'assets/images/orderxpay_logo.png',
                  width: 162,
                  height: 104,
                  fit: BoxFit.contain,
                ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 22,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'STEP 1 OF 2 · MINIMUM KYC',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 18),
                      OxpField(
                        label: 'Business name',
                        controller: _businessNameController,
                        hintText: 'Hand2Muff',
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      OxpField(
                        label: 'Business category',
                        controller: _categoryController,
                        hintText: 'Restaurant — Food & Dining',
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppColors.fieldFill,
                              borderRadius: BorderRadius.circular(
                                AppRadius.control,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              '🇬🇭 +233',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryBlack,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OxpField(
                              label: 'Mobile number',
                              controller: _phoneController,
                              hintText: '20 553 7712',
                              keyboardType: TextInputType.phone,
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.statusDeclined,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      OxpButton(
                        label: _submitting ? 'Creating…' : 'Send OTP',
                        loading: _submitting,
                        icon: const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 16,
                        ),
                        onPressed: _submitting ? null : _submit,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textDisabled,
                      height: 1.6,
                    ),
                    children: [
                      TextSpan(text: 'By continuing you agree to the '),
                      TextSpan(
                        text: 'Terms of Use',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Data Privacy Notice',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      TextSpan(
                        text:
                            ". We register as a Data Controller with Ghana's Data Protection Commission.",
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
