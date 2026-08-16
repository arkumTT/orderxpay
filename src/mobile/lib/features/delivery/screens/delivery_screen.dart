import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Section 4.11 / 7.3: the merchant's own delivery contacts (Tier 1 — can be
/// more than one rider, each shown as its own card) + verified third-party
/// providers (Tier 2). What gets configured here is what shows up in New
/// Order's "Add Delivery" sheet.
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final _api = ApiClient();
  late Future<List<DeliveryOption>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.listDeliveryOptions(Session.instance.merchantId!);
  }

  Future<void> _refresh() async {
    setState(() => _future = _api.listDeliveryOptions(Session.instance.merchantId!));
    await _future;
  }

  Future<void> _addOption(String type) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String feeHandling = 'bundled';
    final isContact = type == 'own_contact';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isContact ? 'Add Delivery Contact' : 'Add Delivery Provider',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 16),
              OxpField(
                label: isContact ? 'Contact name' : 'Provider name',
                controller: nameController,
                hintText: isContact ? 'Kojo — rider' : 'Bolt Send',
              ),
              const SizedBox(height: 12),
              OxpField(
                label: 'Phone (optional)',
                controller: phoneController,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Bundled into invoice'),
                      selected: feeHandling == 'bundled',
                      onSelected: (_) => setSheetState(() => feeHandling = 'bundled'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Customer arranges'),
                      selected: feeHandling == 'external',
                      onSelected: (_) => setSheetState(() => feeHandling = 'external'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              OxpButton(
                label: 'Save',
                onPressed: () async {
                  try {
                    await _api.createDeliveryOption(
                      Session.instance.merchantId!,
                      type: type,
                      contactName: nameController.text,
                      contactPhone: phoneController.text,
                      feeHandlingDefault: feeHandling,
                    );
                    if (context.mounted) Navigator.pop(context, true);
                  } on ApiException catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Settings')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<DeliveryOption>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final options = snapshot.data ?? [];
            final contacts = options.where((o) => o.type == 'own_contact').toList();
            final providers = options.where((o) => o.type == 'verified_provider').toList();

            return ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
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
                  for (final opt in contacts) _DeliveryOptionCard(opt),
                const SizedBox(height: 8),
                OxpButton(
                  label: '+ Add Contact',
                  variant: OxpButtonVariant.secondary,
                  onPressed: () => _addOption('own_contact'),
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
                if (providers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No third-party providers added yet.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  for (final opt in providers) _DeliveryOptionCard(opt),
                const SizedBox(height: 8),
                OxpButton(
                  label: '+ Add Provider',
                  variant: OxpButtonVariant.secondary,
                  onPressed: () => _addOption('verified_provider'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DeliveryOptionCard extends StatelessWidget {
  const _DeliveryOptionCard(this.option);

  final DeliveryOption option;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
                  const SizedBox(height: 2),
                  Text(
                    option.feeHandlingDefault == 'bundled'
                        ? 'Bundled into invoice by default'
                        : 'Customer arranges & pays separately',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            StatusPill(
              label: option.status,
              color: option.status == 'active' ? AppColors.statusPaid : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
