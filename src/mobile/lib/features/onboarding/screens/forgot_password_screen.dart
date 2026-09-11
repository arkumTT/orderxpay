import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';
import '../../../core/phone_format.dart';

/// Phone-OTP password reset — the self-service recovery path phone-first
/// accounts have needed since registration and staff both stopped
/// requiring an email (see OnboardingScreen and CreateStaff): there was no
/// way back into an account with a forgotten password, on any channel.
///
/// Mirrors OnboardingScreen's staged single-screen shape on purpose: enter
/// the phone and the new password up front, send the code, then one tap
/// both verifies it and resets the password — no second screen, no
/// re-entering anything already typed. Works for a merchant owner or a
/// staff phone; ApiClient.resetPassword doesn't need to know which.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _codeController = TextEditingController();
  final _api = ApiClient();

  bool _otpRequested = false;
  bool _requestingOtp = false;
  bool _resetting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _devOtp;
  int? _attemptsRemaining;

  @override
  void dispose() {
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

  /// Verifies the OTP, then immediately resets the password to whatever's
  /// already sitting in the form — a single tap covers both, same as
  /// OnboardingScreen's verify-and-create. If the reset call fails after a
  /// successful OTP verify, the phone stays verified server-side for 30
  /// minutes, so retrying this button after fixing the password works
  /// without sending another code.
  Future<void> _verifyOtpAndReset() async {
    if (_codeController.text.trim().isEmpty) {
      setState(() => _error = 'Enter the code you received');
      return;
    }
    setState(() {
      _resetting = true;
      _error = null;
    });
    try {
      await _api.verifyOtp(_fullPhone, _codeController.text.trim());
      await _api.resetPassword(_fullPhone, _passwordController.text);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Password reset'),
          content: const Text(
            'Log in with your phone number and new password.',
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
      if (mounted) setState(() => _resetting = false);
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
                  'Reset your password',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 36),
                OxpCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FORGOT PASSWORD',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 18),
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
                        label: 'New password',
                        controller: _passwordController,
                        hintText: 'At least 8 characters',
                        obscureText: _obscurePassword,
                        readOnly: _otpRequested,
                        validator: (v) => (v == null || v.length < 8)
                            ? 'At least 8 characters'
                            : null,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: _otpRequested
                              ? null
                              : () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OxpField(
                        label: 'Confirm new password',
                        controller: _confirmController,
                        hintText: 'Re-enter your new password',
                        obscureText: _obscureConfirm,
                        readOnly: _otpRequested,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                        suffix: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: _otpRequested
                              ? null
                              : () => setState(
                                  () => _obscureConfirm = !_obscureConfirm),
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
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
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
                          label: _requestingOtp ? 'Sending…' : 'Send Code',
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
                          label: _resetting
                              ? 'Resetting…'
                              : 'Verify & Reset Password',
                          loading: _resetting,
                          onPressed: _resetting ? null : _verifyOtpAndReset,
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
                GestureDetector(
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, '/login'),
                  child: const Text.rich(
                    TextSpan(
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                      children: [
                        TextSpan(text: 'Remembered it after all? '),
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
