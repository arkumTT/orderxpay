import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_contacts/flutter_contacts.dart';
import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/phone.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Section 4.3 order flow revision — a real saved-customer list, managed
/// here and offered as a quick-pick on New Order. Most rows arrive
/// automatically (the API upserts one on every invoice send); this screen
/// also lets a merchant add one directly, or edit/delete an existing one.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _api = ApiClient();
  final _searchController = TextEditingController();
  late Future<List<Customer>> _future;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Customer>> _load() => _api.listCustomers(Session.instance.merchantId!);

  /// Opens the native contact picker (same permission handling as New
  /// Order's — see NewOrderScreen._pickFromContacts) and fills the
  /// Add/Edit Customer sheet's name and phone fields separately, not a
  /// blended string.
  Future<void> _pickFromContacts(
    TextEditingController nameController,
    TextEditingController phoneController,
    StateSetter setSheetState,
  ) async {
    if (Platform.isAndroid) {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Contacts permission is needed to pick a customer.')),
          );
        }
        return;
      }
    }
    try {
      final contact = await FlutterContacts.native.showPicker(properties: {ContactProperty.phone});
      if (contact == null) return;
      final name = contact.displayName ?? '';
      final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';
      setSheetState(() {
        nameController.text = name;
        phoneController.text = localDigitsFrom(phone);
      });
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open contacts.')),
        );
      }
    }
  }

  Future<void> _refresh() async {
    final next = _load();
    // Block body, not an arrow — see LocationsScreen._refresh for why an
    // arrow body here trips Flutter's "setState callback returned a
    // Future" check and silently skips the repaint.
    setState(() {
      _future = next;
    });
    await next;
  }

  /// One sheet for both add and edit — pass [existing] to pre-fill and
  /// reveal a Delete action; omit it to create a new one.
  Future<void> _openCustomerSheet([Customer? existing]) async {
    final nameController = TextEditingController(text: existing?.name);
    final phoneController = TextEditingController(
      text: existing != null ? localDigitsFrom(existing.contact) : '',
    );
    String? error;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: bottomSafeInset(context)),
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
                    existing != null ? 'Edit Customer' : 'Add Customer',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  OxpField(
                    label: 'Name (optional)',
                    controller: nameController,
                    hintText: 'e.g. Ama',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Phone number',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryBlack),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.fieldFill,
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '$kCountryFlag $kCountryCode',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primaryBlack),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: '20 553 7712',
                            filled: true,
                            fillColor: AppColors.fieldFill,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.control))),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.contact_page_outlined, color: AppColors.textSecondary, size: 20),
                              tooltip: 'Pick from contacts',
                              onPressed: () =>
                                  _pickFromContacts(nameController, phoneController, setSheetState),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: AppColors.statusDeclined, fontSize: 12)),
                  ],
                  const SizedBox(height: 20),
                  OxpButton(
                    label: 'Save',
                    onPressed: () async {
                      final digits = localDigitsFrom(phoneController.text);
                      if (digits.isEmpty) {
                        setSheetState(() => error = 'Phone number is required');
                        return;
                      }
                      try {
                        if (existing != null) {
                          await _api.updateCustomer(
                            Session.instance.merchantId!,
                            existing.id,
                            contact: toE164(digits),
                            name: nameController.text.trim(),
                          );
                        } else {
                          await _api.createCustomer(
                            Session.instance.merchantId!,
                            contact: toE164(digits),
                            name: nameController.text.trim(),
                          );
                        }
                        if (context.mounted) Navigator.pop(context, 'saved');
                      } on ApiException catch (e) {
                        setSheetState(() => error = e.message);
                      }
                    },
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: 8),
                    OxpButton(
                      label: 'Delete',
                      variant: OxpButtonVariant.secondary,
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete customer?'),
                            content: Text('Remove ${existing.displayName} from your saved customers.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        try {
                          await _api.deleteCustomer(Session.instance.merchantId!, existing.id);
                          if (context.mounted) Navigator.pop(context, 'saved');
                        } on ApiException catch (e) {
                          setSheetState(() => error = e.message);
                        }
                      },
                    ),
                  ],
                ],
              ),
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
      appBar: AppBar(title: const Text('Customers')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Customer>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: EdgeInsets.fromLTRB(
                AppSpace.xl, AppSpace.xl, AppSpace.xl,
                AppSpace.xl + bottomSafeInset(context),
              ),
                children: [Text('Failed to load: ${snapshot.error}')],
              );
            }
            final all = snapshot.data!;
            final customers = _query.isEmpty
                ? all
                : all
                      .where((c) => c.displayName.toLowerCase().contains(_query.toLowerCase()))
                      .toList();
            return ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpace.xl, AppSpace.xl, AppSpace.xl,
                AppSpace.xl + bottomSafeInset(context),
              ),
              children: [
                const Text(
                  'Saved customers',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Saved automatically whenever you send an invoice — add one '
                  'directly here too.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (all.isNotEmpty) ...[
                  TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search name or number',
                      hintStyle: const TextStyle(color: AppColors.textDisabled),
                      prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                      filled: true,
                      fillColor: AppColors.fieldFill,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (customers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      all.isEmpty
                          ? 'No saved customers yet — they\'ll appear here as you send invoices.'
                          : 'No customers match "$_query".',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  for (final customer in customers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OxpCard(
                        onTap: () => _openCustomerSheet(customer),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customer.displayName,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  if (customer.name?.isNotEmpty ?? false) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      customer.contact,
                                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 8),
                OxpButton(
                  label: '+ Add Customer',
                  variant: OxpButtonVariant.secondary,
                  onPressed: () => _openCustomerSheet(),
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
