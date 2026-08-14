import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Section 4.11 / 7.3: the merchant's own delivery contact + verified
/// third-party providers. What gets configured here is what shows up in New
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

  Future<void> _addOption() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String type = 'own_contact';
    String feeHandling = 'bundled';

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
              const Text('Add Delivery Option', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Own contact'),
                      selected: type == 'own_contact',
                      onSelected: (_) => setSheetState(() => type = 'own_contact'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Verified provider'),
                      selected: type == 'verified_provider',
                      onSelected: (_) => setSheetState(() => type = 'verified_provider'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OxpField(
                label: type == 'own_contact' ? 'Contact name' : 'Provider name',
                controller: nameController,
                hintText: type == 'own_contact' ? 'Kojo — rider' : 'Bolt Send',
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
      appBar: AppBar(
        title: const Text('Delivery Settings'),
        actions: [
          IconButton(icon: const Icon(Icons.add, color: AppColors.accent), onPressed: _addOption),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<DeliveryOption>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final options = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
                if (options.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No delivery options yet. These are what merchants can pick '
                      'between on the Add Delivery sheet when sending an invoice.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  for (final opt in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OxpCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    opt.contactName?.isNotEmpty == true
                                        ? opt.contactName!
                                        : opt.type,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    opt.feeHandlingDefault == 'bundled'
                                        ? 'Bundled into invoice by default'
                                        : 'Customer arranges & pays separately',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            StatusPill(
                              label: opt.status,
                              color: opt.status == 'active'
                                  ? AppColors.statusPaid
                                  : AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
