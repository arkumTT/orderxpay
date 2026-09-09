import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';
import '../../../core/phone_format.dart';

/// Registration (Section 4.1, Tier 0 KYC) — one screen, phone-first.
/// Business info, phone, and a password are all collected up front; "Send
/// OTP" validates the whole form before a code ever goes out, and the
/// merchant account is created the instant VerifyPhoneOTP succeeds — no
/// second screen, no re-entering anything.
///
/// Deliberately does NOT collect a username or email here — both are
/// optional on CreateMerchant (a merchant can add either later from
/// Settings) precisely so signup doesn't ask for more than a phone number
/// and a password. Login still accepts email for merchants who add one,
/// but phone-only is a fully working account from the moment this screen
/// finishes — see LoginScreen and ApiClient.login for the phone/email
/// auto-detect that makes that work.
///
/// Real SMS delivery is wired up server-side (Arkesel, see otp.go) when
/// the API is configured with an SMS_API_KEY — falls back to log-only
/// delivery otherwise. In dev builds the request response also includes
/// dev_otp directly regardless of whether SMS actually sent, shown here as
/// a clearly-labeled dev hint so the whole loop stays testable without
/// burning real SMS credits on every local run.
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
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _codeController = TextEditingController();
  final _api = ApiClient();

  bool _otpRequested = false;
  bool _requestingOtp = false;
  bool _verifying = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _devOtp;
  int? _attemptsRemaining;

  @override
  void dispose() {
    _businessNameController.dispose();
    _categoryController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _fullPhone => normalizeGhPhone(_phoneController.text);

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
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

  /// Verifies the OTP, then immediately creates the merchant with just the
  /// business info, phone, and password already sitting in the form — a
  /// single tap covers both. No username/email is sent (see this screen's
  /// doc comment), so there's nothing to verify a link against; a short
  /// confirmation replaces the old "check your email" dialog.
  ///
  /// If account creation fails after a successful OTP verify, the phone
  /// stays verified server-side for 30 minutes, so retrying this button
  /// after fixing a field works without sending another code.
  Future<void> _verifyOtpAndCreateAccount() async {
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
      await _api.registerMerchant(
        businessName: _businessNameController.text,
        category: _categoryController.text,
        phone: _fullPhone,
        password: _passwordController.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Account created'),
          content: const Text(
            'Log in with your phone number and password to get started. '
            'You can add an email later from Settings.',
          ),
          actions: [
            OxpButton(
              label: 'Go to Login',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
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
                const OxpWordmark(height: 34),
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
                        'CREATE YOUR ACCOUNT · MINIMUM KYC',
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
                      const SizedBox(height: 16),
                      OxpField(
                        label: 'Password',
                        controller: _passwordController,
                        hintText: 'At least 8 characters',
                        obscureText: _obscurePassword,
                        readOnly: _otpRequested,
                        validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: _otpRequested
                              ? null
                              : () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OxpField(
                        label: 'Confirm password',
                        controller: _confirmController,
                        hintText: 'Re-enter your password',
                        obscureText: _obscureConfirm,
                        readOnly: _otpRequested,
                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        suffix: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: _otpRequested
                              ? null
                              : () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
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
                          label: _verifying ? 'Creating account…' : 'Verify & Create Account',
                          loading: _verifying,
                          onPressed: _verifying ? null : _verifyOtpAndCreateAccount,
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
