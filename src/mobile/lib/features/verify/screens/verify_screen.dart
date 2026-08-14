import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Section 4.1/4.9's Tier 1 upgrade — shows the merchant's real KYC tier,
/// but document upload and payout request have no backend yet, so those
/// actions stay disabled rather than pretending to work.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _api = ApiClient();
  Merchant? _merchant;

  @override
  void initState() {
    super.initState();
    _api.getMerchant(Session.instance.merchantId!).then((m) {
      if (mounted) setState(() => _merchant = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tier1 = _merchant?.kycTier == 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify & Withdraw')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: AppColors.primaryBlack,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available to withdraw',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                SizedBox(height: 6),
                Text(
                  'GH₵0.00',
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  'Held securely by our licensed payment partner',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OxpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ChecklistRow(label: 'Phone verified', done: true),
                const _ChecklistRow(label: 'Business info', done: true),
                _ChecklistRow(label: 'Ghana Card upload', done: tier1),
                _ChecklistRow(label: 'Selfie liveness check', done: tier1),
                const _ChecklistRow(label: 'Payout account (Mobile Money/Bank)', done: false),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const OxpButton(
            label: 'Request Payout — complete verification first',
            onPressed: null,
          ),
          const SizedBox(height: 8),
          const Text(
            'Document upload and payout aren\'t built yet — this reflects '
            'your real KYC tier from the API, but the actions above are '
            'not functional.',
            style: TextStyle(color: AppColors.textDisabled, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.label, required this.done});
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: done ? AppColors.statusPaid : AppColors.textDisabled,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: done ? AppColors.primaryBlack : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
