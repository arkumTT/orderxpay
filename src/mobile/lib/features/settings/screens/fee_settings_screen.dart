import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/invoice_calc.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

const _allocations = [
  ('customer_only', 'Customer Only', 'Default — added on top of the price'),
  ('merchant_only', 'Merchant Only', 'Absorbed from your sale price'),
  ('split', 'Split', 'Share it with your customer'),
];

/// Section 4.8 — wired to the real UpdateMerchantFeeSettings endpoint, which
/// is what the invoice engine reads at invoice-creation time.
class FeeSettingsScreen extends StatefulWidget {
  const FeeSettingsScreen({super.key});

  @override
  State<FeeSettingsScreen> createState() => _FeeSettingsScreenState();
}

class _FeeSettingsScreenState extends State<FeeSettingsScreen> {
  final _api = ApiClient();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _allocation = 'customer_only';
  int _commissionBps = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final merchantId = Session.instance.merchantId!;
    try {
      final results = await Future.wait([
        _api.getMerchant(merchantId),
        _api.getCommissionBps(merchantId),
      ]);
      final merchant = results[0] as Merchant;
      setState(() {
        _allocation = merchant.serviceChargeAllocation;
        _commissionBps = results[1] as int;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.updateFeeSettings(
        Session.instance.merchantId!,
        allocation: _allocation,
        splitBps: _allocation == 'split' ? 5000 : null,
      );
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    const exampleSubtotal = 10000; // GH₵100.00, matches the design's example
    final amounts = computeInvoiceAmounts(
      subtotalPesewas: exampleSubtotal,
      commissionBps: _commissionBps,
      allocation: _allocation,
      splitBps: 5000,
    );
    final merchantReceives = exampleSubtotal -
        (_allocation == 'merchant_only' || _allocation == 'split'
            ? (amounts.commissionPesewas - amounts.serviceChargePesewas)
            : 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Charge'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text(
              'Save',
              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          OxpCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _allocations.length; i++)
                  _AllocationRow(
                    value: _allocations[i].$1,
                    title: _allocations[i].$2,
                    subtitle: _allocations[i].$3,
                    selected: _allocation == _allocations[i].$1,
                    showDivider: i != 0,
                    onTap: () => setState(() => _allocation = _allocations[i].$1),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OxpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Example — ${formatPesewas(exampleSubtotal)} order, ${(_commissionBps / 100).toStringAsFixed(1)}% charge',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Customer pays', style: TextStyle(color: AppColors.textSecondary)),
                    Text(formatPesewas(amounts.totalPesewas), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('You receive', style: TextStyle(color: AppColors.textSecondary)),
                    Text(
                      formatPesewas(merchantReceives),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.statusPaid),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.statusDeclined)),
          ],
          const SizedBox(height: 20),
          OxpButton(label: 'Save Setting', loading: _saving, onPressed: _saving ? null : _save),
        ],
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  final String value;
  final String title;
  final String subtitle;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: showDivider ? const Border(top: BorderSide(color: AppColors.border)) : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: 1.5),
              ),
              alignment: Alignment.center,
              child: selected
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
