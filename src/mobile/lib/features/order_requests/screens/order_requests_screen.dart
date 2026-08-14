import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';
import '../../invoices/screens/new_order_screen.dart';

/// Section 4.6 pending-request queue. Approving pre-fills New Order
/// (Section 4.6: "confirm as-is, adjust quantities/items, or decline") so
/// the merchant reviews before an invoice is actually generated.
class OrderRequestsScreen extends StatefulWidget {
  const OrderRequestsScreen({super.key});

  @override
  State<OrderRequestsScreen> createState() => _OrderRequestsScreenState();
}

class _OrderRequestsScreenState extends State<OrderRequestsScreen> {
  final _api = ApiClient();
  late Future<List<OrderRequest>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.listOrderRequests(Session.instance.merchantId!);
  }

  Future<void> _refresh() async {
    setState(() => _future = _api.listOrderRequests(Session.instance.merchantId!));
    await _future;
  }

  Future<void> _approve(OrderRequest request) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => NewOrderScreen(sourceRequest: request)),
    );
    // A successful send pops the whole stack back to Home (see
    // InvoiceSentScreen), which may dispose this screen before we get here —
    // guard before touching state. If the merchant just backed out of New
    // Order instead, this refreshes normally.
    if (mounted) _refresh();
  }

  Future<void> _decline(OrderRequest request) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline request'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: 'Reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, reasonController.text),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await _api.declineOrderRequest(Session.instance.merchantId!, request.id, reason);
      _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order Requests')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<OrderRequest>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final requests = snapshot.data ?? [];
            if (requests.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(AppSpace.xl),
                children: const [
                  SizedBox(height: 60),
                  Text(
                    'No pending requests',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpace.xl),
              itemCount: requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final req = requests[i];
                return OxpCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AvatarInitials(name: req.customerContact),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  req.customerContact,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                const Text(
                                  'via catalog link',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final raw in req.requestedItems)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            '${raw['name'] ?? raw['description'] ?? 'Item'} × ${raw['quantity'] ?? 1}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      const SizedBox(height: 10),
                      const Text(
                        'Adjust availability, then confirm to auto-generate the invoice.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OxpButton(
                              label: 'Decline',
                              variant: OxpButtonVariant.secondary,
                              onPressed: () => _decline(req),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: OxpButton(
                              label: 'Approve & Send Invoice',
                              onPressed: () => _approve(req),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
