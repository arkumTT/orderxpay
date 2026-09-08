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

String _pct(int bps) => (bps / 100).toStringAsFixed(1);

/// Section 4.8 (revised) — wired to the real UpdateMerchantFeeSettings and
/// GetMerchantFeeRuleOrGlobal endpoints. The blended commission_bps the
/// invoice engine and checkout actually read never changes here — this
/// screen only explains what it's built from (collection + payout + margin)
/// and lets the merchant choose who covers the collection fee and whether
/// they absorb the payout-fee component themselves.
class FeeSettingsScreen extends StatefulWidget {
  const FeeSettingsScreen({super.key});

  @override
  State<FeeSettingsScreen> createState() => _FeeSettingsScreenState();
}

class _FeeSettingsScreenState extends State<FeeSettingsScreen> {
  final _api = ApiClient();
  bool _loading = true;
  bool _saving = false;
  bool _breakdownExpanded = false;
  String? _error;
  String _allocation = 'customer_only';
  FeeRule? _feeRule;

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
        _api.getFeeRule(merchantId),
      ]);
      final merchant = results[0] as Merchant;
      setState(() {
        _allocation = merchant.serviceChargeAllocation;
        _feeRule = results[1] as FeeRule;
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
    final feeRule = _feeRule!;
    const exampleSubtotal = 10000; // GH₵100.00, matches the design's example
    final amounts = computeInvoiceAmounts(
      subtotalPesewas: exampleSubtotal,
      collectionFeeBps: feeRule.collectionFeeBps,
      marginBps: feeRule.marginBps,
      marginFloorPesewas: feeRule.marginFloorPesewas,
      marginCapPesewas: feeRule.marginCapPesewas,
      allocation: _allocation,
      splitBps: 5000,
    );
    // What lands in the merchant's settlement for this example invoice —
    // taken straight off the shared calculator rather than re-derived here,
    // so it can never drift from the figure the server actually settles.
    final merchantReceives = amounts.merchantNetPesewas;

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
        padding: EdgeInsets.fromLTRB(
          AppSpace.xl, AppSpace.xl, AppSpace.xl,
          AppSpace.xl + bottomSafeInset(context),
        ),
        children: [
          OxpCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                InkWell(
                  onTap: () => setState(() => _breakdownExpanded = !_breakdownExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'How this is calculated',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                        Icon(
                          _breakdownExpanded ? Icons.expand_less : Icons.expand_more,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_breakdownExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BreakdownRow('Payment provider fee', '${_pct(feeRule.collectionFeeBps)}%'),
                        const SizedBox(height: 8),
                        _BreakdownRow('OrderxPay', '${_pct(feeRule.marginBps)}%'),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(height: 1, color: AppColors.border),
                        ),
                        _BreakdownRow(
                          'Your blended rate',
                          '${_pct(feeRule.commissionBps)}%',
                          valueColor: AppColors.accent,
                          bold: true,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Never less than ${formatPesewas(feeRule.marginFloorPesewas)} '
                          'or more than ${formatPesewas(feeRule.marginCapPesewas)} to '
                          'OrderxPay on a single order, so large orders cost you '
                          'proportionally less.',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Collection fee',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 2),
          const Text(
            'Who covers the fee charged when a customer pays an invoice.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
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
          const Text(
            'Withdrawals',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 2),
          const Text(
            'What it costs to move money from OrderxPay to your wallet or bank.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          OxpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BreakdownRow(
                  'To Mobile Money',
                  formatPesewas(feeRule.withdrawalFeeMomoPesewas),
                ),
                const SizedBox(height: 8),
                _BreakdownRow(
                  'To a bank account',
                  formatPesewas(feeRule.withdrawalFeeBankPesewas),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: AppColors.border),
                ),
                _BreakdownRow(
                  'Free above',
                  formatPesewas(feeRule.withdrawalFeeWaiverPesewas),
                  valueColor: AppColors.statusPaid,
                  bold: true,
                ),
                const SizedBox(height: 10),
                Text(
                  'This is a flat charge per withdrawal, not a percentage, so '
                  'fewer larger withdrawals cost you less than many small ones. '
                  'Withdraw ${formatPesewas(feeRule.withdrawalFeeWaiverPesewas)} '
                  'or more and it is free.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
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
                  'Example — ${formatPesewas(exampleSubtotal)} order, ${_pct(feeRule.commissionBps)}% charge',
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

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow(this.label, this.value, {this.valueColor, this.bold = false});

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: valueColor ?? AppColors.primaryBlack,
          ),
        ),
      ],
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
