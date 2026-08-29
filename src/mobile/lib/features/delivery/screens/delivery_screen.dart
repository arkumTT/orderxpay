import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Section 4.11 / 7.3 / 9.4: master "Offer delivery" switch, the merchant's
/// own delivery contacts (Tier 1 — can be more than one rider, each with an
/// optional flat fee per zone), and verified third-party providers (Tier 2 —
/// Bolt/Uber/Yango etc. from the admin-maintained catalog, toggled on/off,
/// plus room for one-off providers not in that catalog). What gets
/// configured here is what shows up in New Order's "Add Delivery" sheet —
/// hidden there entirely when the master switch is off. Fee handling
/// ("Bundled into invoice" vs "Customer arranges") is intentionally NOT
/// configured here — it's asked fresh every time delivery is added to an
/// order, since who pays can vary order to order even for the same rider.
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryData {
  _DeliveryData({required this.options, required this.catalog, required this.merchant});
  final List<DeliveryOption> options;
  final List<DeliveryProvider> catalog;
  final Merchant merchant;
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final _api = ApiClient();
  late Future<_DeliveryData> _future;
  final Set<String> _pendingProviderKeys = {};
  bool _togglingMaster = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DeliveryData> _load() async {
    final merchantId = Session.instance.merchantId!;
    final results = await Future.wait([
      _api.listDeliveryOptions(merchantId),
      _api.listDeliveryProviders(merchantId),
      _api.getMerchant(merchantId),
    ]);
    return _DeliveryData(
      options: results[0] as List<DeliveryOption>,
      catalog: results[1] as List<DeliveryProvider>,
      merchant: results[2] as Merchant,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _toggleMaster(bool value) async {
    setState(() => _togglingMaster = true);
    try {
      await _api.updateDeliverySettings(Session.instance.merchantId!, enabled: value);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _togglingMaster = false);
    }
  }

  Future<void> _toggleCatalogProvider(
    DeliveryProvider provider, {
    required bool enable,
    DeliveryOption? existing,
  }) async {
    setState(() => _pendingProviderKeys.add(provider.key));
    try {
      if (enable) {
        await _api.createDeliveryOption(
          Session.instance.merchantId!,
          type: 'verified_provider',
          contactName: provider.name,
          providerKey: provider.key,
          deepLinkTemplate: provider.deepLinkTemplate,
          feeHandlingDefault: 'external',
        );
      } else if (existing != null) {
        await _api.setDeliveryOptionStatus(Session.instance.merchantId!, existing.id, 'inactive');
      }
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _pendingProviderKeys.remove(provider.key));
    }
  }

  /// One sheet for both add and edit — pass [existing] to pre-fill and
  /// reveal a Remove action; omit it to create a new one.
  Future<void> _openOptionSheet({required String type, DeliveryOption? existing}) async {
    final isContact = type == 'own_contact';
    final nameController = TextEditingController(text: existing?.contactName);
    final phoneController = TextEditingController(text: existing?.contactPhone);
    final feeController = TextEditingController(
      text: existing?.flatFeePesewas != null ? (existing!.flatFeePesewas! / 100).toStringAsFixed(2) : '',
    );
    final zoneController = TextEditingController(text: existing?.serviceZone);

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Builder(
        builder: (context) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing != null
                      ? (isContact ? 'Edit Delivery Contact' : 'Edit Delivery Provider')
                      : (isContact ? 'Add Delivery Contact' : 'Add Delivery Provider'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                if (existing == null && !isContact) ...[
                  const SizedBox(height: 4),
                  const Text(
                    "For a provider not already listed above.",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                OxpField(
                  label: isContact ? 'Contact name' : 'Provider name',
                  controller: nameController,
                  hintText: isContact ? 'Kojo — rider' : 'Glovo',
                ),
                const SizedBox(height: 12),
                OxpField(
                  label: 'Phone (optional)',
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                ),
                if (isContact) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OxpField(
                          label: 'Flat fee (optional)',
                          controller: feeController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          hintText: '15.00',
                          prefix: const Text('GH₵ '),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OxpField(
                          label: 'Zone (optional)',
                          controller: zoneController,
                          hintText: 'Osu / Labone',
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                OxpButton(
                  label: 'Save',
                  onPressed: () async {
                    final feePesewas = feeController.text.trim().isEmpty
                        ? null
                        : ((double.tryParse(feeController.text) ?? 0) * 100).round();
                    try {
                      if (existing != null) {
                        await _api.updateDeliveryOption(
                          Session.instance.merchantId!,
                          existing.id,
                          contactName: nameController.text,
                          contactPhone: phoneController.text,
                          flatFeePesewas: feePesewas,
                          serviceZone: zoneController.text,
                          // Fee handling ("Bundled" vs "Customer arranges") is
                          // no longer a preset configured here — it's asked
                          // fresh each time delivery is added to an order.
                          // This stored default is unused by the order flow
                          // now; kept only because the column is NOT NULL.
                          feeHandlingDefault: 'external',
                          status: 'active',
                        );
                      } else {
                        await _api.createDeliveryOption(
                          Session.instance.merchantId!,
                          type: type,
                          contactName: nameController.text,
                          contactPhone: phoneController.text,
                          flatFeePesewas: feePesewas,
                          serviceZone: zoneController.text,
                          feeHandlingDefault: 'external',
                        );
                      }
                      if (context.mounted) Navigator.pop(context, 'saved');
                    } on ApiException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    }
                  },
                ),
                if (existing != null) ...[
                  const SizedBox(height: 8),
                  OxpButton(
                    label: 'Remove',
                    variant: OxpButtonVariant.secondary,
                    onPressed: () async {
                      try {
                        await _api.setDeliveryOptionStatus(Session.instance.merchantId!, existing.id, 'inactive');
                        if (context.mounted) Navigator.pop(context, 'saved');
                      } on ApiException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (result == 'saved') _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Settings')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_DeliveryData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return const Center(
                child: Text('Could not load delivery settings', style: TextStyle(color: AppColors.textSecondary)),
              );
            }
            final data = snapshot.data!;
            final contacts = data.options.where((o) => o.type == 'own_contact').toList();
            final providerOptions = data.options.where((o) => o.type == 'verified_provider').toList();
            final catalogKeys = data.catalog.map((p) => p.key).toSet();
            final customProviders = providerOptions.where((o) => !catalogKeys.contains(o.providerKey)).toList();

            DeliveryOption? enabledOptionFor(String providerKey) {
              for (final opt in providerOptions) {
                if (opt.providerKey == providerKey && opt.status == 'active') return opt;
              }
              return null;
            }

            return ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
                OxpCard(
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Offer delivery', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            SizedBox(height: 2),
                            Text(
                              'Let customers choose delivery on eligible orders.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (_togglingMaster)
                        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Switch(
                          value: data.merchant.deliveryEnabled,
                          activeTrackColor: AppColors.statusPaid,
                          onChanged: _toggleMaster,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  "Merchant's Own Delivery Contact",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Riders you coordinate with directly — add as many as you use.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (contacts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No delivery contacts yet. These are what customers see as a '
                      '"Call rider" option after payment.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  for (final opt in contacts)
                    _DeliveryOptionCard(
                      opt,
                      onTap: () => _openOptionSheet(type: 'own_contact', existing: opt),
                    ),
                const SizedBox(height: 8),
                OxpButton(
                  label: '+ Add Contact',
                  variant: OxpButtonVariant.secondary,
                  onPressed: () => _openOptionSheet(type: 'own_contact'),
                ),

                const SizedBox(height: 28),
                const Text(
                  'Third-Party Delivery Providers',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Verified apps a customer can be handed off to after payment.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (data.catalog.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No verified providers configured on the platform yet.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  for (final provider in data.catalog)
                    _CatalogProviderRow(
                      provider: provider,
                      enabledOption: enabledOptionFor(provider.key),
                      loading: _pendingProviderKeys.contains(provider.key),
                      onChanged: (v) => _toggleCatalogProvider(
                        provider,
                        enable: v,
                        existing: enabledOptionFor(provider.key),
                      ),
                    ),
                if (customProviders.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  for (final opt in customProviders)
                    _DeliveryOptionCard(
                      opt,
                      onTap: () => _openOptionSheet(type: 'verified_provider', existing: opt),
                    ),
                ],
                const SizedBox(height: 8),
                OxpButton(
                  label: '+ Add Provider',
                  variant: OxpButtonVariant.secondary,
                  onPressed: () => _openOptionSheet(type: 'verified_provider'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CatalogProviderRow extends StatelessWidget {
  const _CatalogProviderRow({
    required this.provider,
    required this.enabledOption,
    required this.loading,
    required this.onChanged,
  });

  final DeliveryProvider provider;
  final DeliveryOption? enabledOption;
  final bool loading;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = enabledOption != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OxpCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(provider.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  const Text(
                    'Verified delivery provider',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (loading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(
                value: enabled,
                activeTrackColor: AppColors.statusPaid,
                onChanged: onChanged,
              ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryOptionCard extends StatelessWidget {
  const _DeliveryOptionCard(this.option, {this.onTap});

  final DeliveryOption option;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: OxpCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.contactName?.isNotEmpty == true ? option.contactName! : option.type,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    if (option.contactPhone?.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(option.contactPhone!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                    if (option.flatFeePesewas != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        option.serviceZone?.isNotEmpty == true
                            ? '${formatPesewas(option.flatFeePesewas!)} flat fee · ${option.serviceZone}'
                            : '${formatPesewas(option.flatFeePesewas!)} flat fee',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              StatusPill(
                label: option.status,
                color: option.status == 'active' ? AppColors.statusPaid : AppColors.textSecondary,
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppColors.textDisabled),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
