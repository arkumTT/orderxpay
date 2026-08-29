import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Feedback item 4 — pickup/delivery reference locations. Deliberately a
/// flat, merchant-managed list for this first cut (no per-delivery-option
/// binding, no map/lat-lng picker yet — see the PR discussion for the
/// phased plan). One location can be marked default, which pre-fills the
/// picker on New Order's "Add Delivery" sheet; the merchant can still pick
/// a different one per order.
class LocationsScreen extends StatefulWidget {
  const LocationsScreen({super.key});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  final _api = ApiClient();
  late Future<List<MerchantLocation>> _future;
  final Set<String> _pendingDefaultIds = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MerchantLocation>> _load() => _api.listMerchantLocations(Session.instance.merchantId!);

  Future<void> _refresh() async {
    final next = _load();
    // Block body, not `() => _future = next` — an arrow body returns the
    // assignment's value (the Future itself), which trips Flutter's
    // debug-mode "setState() callback argument returned a Future" check
    // and throws before markNeedsBuild() runs, so the list silently never
    // repaints until some unrelated rebuild happens to come along. Caught
    // live: new locations only appeared after navigating away and back.
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _makeDefault(MerchantLocation location) async {
    setState(() => _pendingDefaultIds.add(location.id));
    try {
      await _api.setDefaultMerchantLocation(Session.instance.merchantId!, location.id);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _pendingDefaultIds.remove(location.id));
    }
  }

  /// One sheet for both add and edit — pass [existing] to pre-fill and
  /// reveal a Deactivate action; omit it to create a new one.
  Future<void> _openLocationSheet([MerchantLocation? existing]) async {
    final labelController = TextEditingController(text: existing?.label);
    final addressController = TextEditingController(text: existing?.address);
    final phoneController = TextEditingController(text: existing?.phone);

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing != null ? 'Edit Location' : 'Add Location',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 16),
                OxpField(
                  label: 'Label',
                  controller: labelController,
                  hintText: 'Osu Kitchen / Main Branch',
                ),
                const SizedBox(height: 12),
                OxpField(
                  label: 'Address',
                  controller: addressController,
                  hintText: '12 Volta Street, Osu',
                ),
                const SizedBox(height: 12),
                OxpField(
                  label: 'Phone (optional)',
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 20),
                OxpButton(
                  label: 'Save',
                  onPressed: () async {
                    if (labelController.text.trim().isEmpty || addressController.text.trim().isEmpty) {
                      return;
                    }
                    try {
                      if (existing != null) {
                        await _api.updateMerchantLocation(
                          Session.instance.merchantId!,
                          existing.id,
                          label: labelController.text.trim(),
                          address: addressController.text.trim(),
                          phone: phoneController.text.trim(),
                          status: 'active',
                        );
                      } else {
                        await _api.createMerchantLocation(
                          Session.instance.merchantId!,
                          label: labelController.text.trim(),
                          address: addressController.text.trim(),
                          phone: phoneController.text.trim(),
                        );
                      }
                      if (context.mounted) Navigator.pop(context, 'saved');
                    } on ApiException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    }
                  },
                ),
                if (existing != null) ...[
                  const SizedBox(height: 8),
                  OxpButton(
                    label: 'Deactivate',
                    variant: OxpButtonVariant.secondary,
                    onPressed: () async {
                      try {
                        await _api.updateMerchantLocation(
                          Session.instance.merchantId!,
                          existing.id,
                          label: existing.label,
                          address: existing.address,
                          phone: existing.phone,
                          status: 'inactive',
                        );
                        if (context.mounted) Navigator.pop(context, 'saved');
                      } on ApiException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
      appBar: AppBar(title: const Text('Locations')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<MerchantLocation>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(AppSpace.xl),
                children: [Text('Failed to load: ${snapshot.error}')],
              );
            }
            final locations = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
                const Text(
                  'Pickup / branch locations',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Reference points a third-party provider or a customer can '
                  'use for pickup. Add one per branch or kitchen.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (locations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No locations yet. The first one you add becomes your default.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  for (final location in locations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OxpCard(
                        onTap: () => _openLocationSheet(location),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        location.label,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                      ),
                                      if (location.isDefault) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.statusPaid.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(AppRadius.pill),
                                          ),
                                          child: const Text(
                                            'Default',
                                            style: TextStyle(
                                              color: AppColors.statusPaid,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    location.address,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                  ),
                                  if (location.phone?.isNotEmpty == true) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      location.phone!,
                                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (!location.isDefault)
                              _pendingDefaultIds.contains(location.id)
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : TextButton(
                                      onPressed: () => _makeDefault(location),
                                      child: const Text('Set default', style: TextStyle(fontSize: 12)),
                                    ),
                            const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 8),
                OxpButton(
                  label: '+ Add Location',
                  variant: OxpButtonVariant.secondary,
                  onPressed: () => _openLocationSheet(),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: OxpBottomNav(
        current: OxpTab.more,
        onNewOrder: () => Navigator.pushNamed(context, '/new-order'),
      ),
    );
  }
}
