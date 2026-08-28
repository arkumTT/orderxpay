import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';
import 'register_credentials_screen.dart';

/// Registration Page 1 (Section 4.1, Tier 0 KYC): business name/category/
/// phone, then a real phone-OTP verification loop. Only once VerifyPhoneOTP
/// succeeds does Page 2 (username/email/password) become reachable — see
/// RegisterCredentialsScreen.
///
/// No SMS provider is wired up server-side (Section 9 — not yet selected),
/// so the API can't actually text the code to the merchant. In dev builds
/// the request response includes dev_otp directly (see otp.go), shown here
/// as a clearly-labeled dev hint so the whole loop is genuinely testable —
/// this must be replaced by real SMS delivery before real users register.
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
  final _codeController = TextEditingController();
  final _api = ApiClient();

  bool _otpRequested = false;
  bool _requestingOtp = false;
  bool _verifying = false;
  String? _error;
  String? _devOtp;
  int? _attemptsRemaining;

  @override
  void dispose() {
    _businessNameController.dispose();
    _categoryController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _fullPhone => '+233${_phoneController.text.replaceAll(RegExp(r'\s'), '')}';

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _requestingOtp = true;
      _error = null;
    });
    try {
      final res = await _api.requestOtp(_fullPhone);
      setState(() {
        _otpRequested = true;
        _devOtp = res['dev_otp'] as String?;
        _attemptsRemaining = null;
        _codeController.clear();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _requestingOtp = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_codeController.text.trim().isEmpty) {
      setState(() => _error = 'Enter the code you received');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await _api.verifyOtp(_fullPhone, _codeController.text.trim());
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RegisterCredentialsScreen(
            businessName: _businessNameController.text,
            category: _categoryController.text,
            phone: _fullPhone,
          ),
        ),
      );
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _attemptsRemaining = (e.body?['attempts_remaining'] as num?)?.toInt();
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
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
                        readOnly: _otpRequested,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      OxpField(
                        label: 'Business category',
                        controller: _categoryController,
                        hintText: 'Restaurant — Food & Dining',
                        readOnly: _otpRequested,
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
                              readOnly: _otpRequested,
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      if (_otpRequested) ...[
                        const SizedBox(height: 16),
                        OxpField(
                          label: 'Enter code',
                          controller: _codeController,
                          hintText: '6-digit code',
                          keyboardType: TextInputType.number,
                        ),
                        if (_devOtp != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'DEV: code is $_devOtp (no SMS provider wired up)',
                            style: const TextStyle(
                              color: AppColors.textDisabled,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        if (_attemptsRemaining != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '$_attemptsRemaining attempt(s) remaining',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ],
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
                      if (!_otpRequested)
                        OxpButton(
                          label: _requestingOtp ? 'Sending…' : 'Send OTP',
                          loading: _requestingOtp,
                          icon: const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 16,
                          ),
                          onPressed: _requestingOtp ? null : _sendOtp,
                        )
                      else ...[
                        OxpButton(
                          label: _verifying ? 'Verifying…' : 'Verify Code',
                          loading: _verifying,
                          onPressed: _verifying ? null : _verifyOtp,
                        ),
                        const SizedBox(height: 10),
                        OxpButton(
                          label: 'Resend Code',
                          variant: OxpButtonVariant.secondary,
                          onPressed: _requestingOtp ? null : _sendOtp,
                        ),
                      ],
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
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                  child: const Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      children: [
                        TextSpan(text: 'Already have an account? '),
                        TextSpan(
                          text: 'Log in',
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
