import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

const _featureFlagKey = 'whatsapp_catalog_sync';

/// Section 6.2: syncing the merchant's OrderxPay catalog into a WhatsApp
/// Business catalog. The catalog preview and early-access enrollment status
/// below are real — they read the merchant's actual items and their actual
/// feature-flag opt-in. What isn't real: there's no WhatsApp Business
/// Platform integration anywhere in this codebase yet (the Back Office
/// Integrations page lists it as "Not built"), so "Sync now" can't actually
/// send anything. It's left tappable to preview the intended flow, and says
/// so plainly rather than pretending a sync happened.
class CatalogSyncScreen extends StatefulWidget {
  const CatalogSyncScreen({super.key});

  @override
  State<CatalogSyncScreen> createState() => _CatalogSyncScreenState();
}

class _CatalogSyncScreenState extends State<CatalogSyncScreen> {
  final _api = ApiClient();
  late Future<_SyncData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SyncData> _load() async {
    final merchantId = Session.instance.merchantId!;
    final results = await Future.wait([
      _api.listItems(merchantId),
      _api.getFeatureFlagStatus(merchantId, _featureFlagKey),
    ]);
    return _SyncData(
      items: results[0] as List<Item>,
      earlyAccess: results[1] as bool,
    );
  }

  void _showNotConnectedSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text(
              'WhatsApp Business isn\'t connected',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'OrderxPay doesn\'t have a WhatsApp Business Platform connection '
              'set up yet, so nothing was sent. Once that\'s live, this button '
              'will push your current items, prices, and availability into '
              'your WhatsApp catalog automatically.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            OxpButton(
              label: 'Got it',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catalog Sync')),
      body: FutureBuilder<_SyncData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(
              child: Text('Could not load catalog sync', style: TextStyle(color: AppColors.textSecondary)),
            );
          }

          final data = snapshot.data!;

          return RefreshIndicator(
            onRefresh: () async {
              final next = _load();
              setState(() {
                _future = next;
              });
              await next;
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
                const Text(
                  'Section 6.2',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Keep the items customers see on WhatsApp in sync with your '
                  'OrderxPay catalog — same names, prices, and availability, '
                  'without updating them twice.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 20),

                OxpCard(
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.fieldFill,
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                        child: const Icon(Icons.link_off, size: 18, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WhatsApp Business',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Not connected',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (data.earlyAccess) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.statusPending.withValues(alpha: 0.1),
                      border: Border.all(color: AppColors.statusPending.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: const Text(
                      "You're on the early-access list for this feature — you'll "
                      "be among the first merchants to get it once WhatsApp "
                      "Business is connected.",
                      style: TextStyle(color: AppColors.statusPending, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Catalog preview',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${data.items.length} item${data.items.length == 1 ? '' : 's'}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (data.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Add items to your catalog before syncing.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  OxpCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < data.items.length; i++)
                          Container(
                            decoration: BoxDecoration(
                              border: i == 0
                                  ? null
                                  : const Border(top: BorderSide(color: AppColors.border)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    data.items[i].name,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ),
                                Text(
                                  formatPesewas(data.items[i].unitPricePesewas),
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),
                OxpButton(
                  label: 'Sync to WhatsApp',
                  onPressed: data.items.isEmpty ? null : _showNotConnectedSheet,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SyncData {
  _SyncData({required this.items, required this.earlyAccess});
  final List<Item> items;
  final bool earlyAccess;
}
