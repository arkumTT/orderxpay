import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Section 4.1 — where a merchant who registered phone-first (see
/// OnboardingScreen, CreateMerchant) adds an email afterwards. Reached
/// from the home-screen nudge (home_screen.dart) for any merchant whose
/// Merchant.email is still null.
///
/// Deliberately just the one field — this isn't a general "edit your
/// profile" screen, it exists because the home-screen nudge needs
/// somewhere real to send a merchant, not a stub. No verification email
/// is sent (see UpdateMerchantEmail's own doc comment): email stays
/// advisory here exactly like it already is right after signup.
class AddEmailScreen extends StatefulWidget {
  const AddEmailScreen({super.key});

  @override
  State<AddEmailScreen> createState() => _AddEmailScreenState();
}

class _AddEmailScreenState extends State<AddEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _api = ApiClient();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.updateMerchantEmail(
        Session.instance.merchantId!,
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Your Email')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.xl),
          children: [
            const Text(
              "You signed up with just your phone number — add an email so "
              'you have a second way in, and a place to get receipts and '
              'account notices.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 20),
            Form(
              key: _formKey,
              child: OxpCard(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OxpField(
                      label: 'Email',
                      controller: _emailController,
                      hintText: 'you@business.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
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
                      label: _submitting ? 'Saving…' : 'Save Email',
                      loading: _submitting,
                      onPressed: _submitting ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
