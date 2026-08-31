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
/// Business/Meta Commerce catalog (the shoppable product catalog Meta
/// shows inside a WhatsApp chat) — distinct from basic messaging, which
/// is built (see api/internal/whatsapp: real send/receive, auto-reply).
///
/// Real now: once an admin has provisioned merchant.whatsappCatalogId
/// (Back Office, after manually creating the catalog in Meta Commerce
/// Manager and connecting it to the merchant's WhatsApp Business
/// Account — there's no API to automate that creation step), "Sync now"
/// actually pushes items to Meta via the Catalog Batch API
/// (SyncMerchantWhatsAppCatalog / whatsapp.SyncCatalogItems). Before
/// that's provisioned, the screen says so plainly rather than pretending
/// a sync happened — same honesty this screen always had, just a
/// narrower gap now.
class CatalogSyncScreen extends StatefulWidget {
  const CatalogSyncScreen({super.key});

  @override
  State<CatalogSyncScreen> createState() => _CatalogSyncScreenState();
}

class _CatalogSyncScreenState extends State<CatalogSyncScreen> {
  final _api = ApiClient();
  late Future<_SyncData> _future;
  bool _syncing = false;

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
      _api.getMerchant(merchantId),
    ]);
    return _SyncData(
      items: results[0] as List<Item>,
      earlyAccess: results[1] as bool,
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

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final result = await _api.syncWhatsAppCatalog(Session.instance.merchantId!);
      final synced = result['synced_items'] as int? ?? 0;
      final errors = result['errors'] as int? ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errors > 0
                  ? 'Synced $synced items — $errors had errors, check Meta Commerce Manager'
                  : 'Synced $synced items to your WhatsApp catalog',
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
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
          final connected = data.merchant.whatsappCatalogId != null && data.merchant.whatsappCatalogId!.isNotEmpty;

          return RefreshIndicator(
            onRefresh: _refresh,
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
                          color: connected
                              ? AppColors.statusPaid.withValues(alpha: 0.12)
                              : AppColors.fieldFill,
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                        child: Icon(
                          connected ? Icons.link : Icons.link_off,
                          size: 18,
                          color: connected ? AppColors.statusPaid : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'WhatsApp Business',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              connected ? 'Connected' : 'Not connected',
                              style: TextStyle(
                                color: connected ? AppColors.statusPaid : AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: connected ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (!connected && data.earlyAccess) ...[
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
                      "be among the first merchants to get it once your WhatsApp "
                      "catalog is connected.",
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
                  label: connected ? 'Sync to WhatsApp' : 'WhatsApp not connected',
                  loading: _syncing,
                  onPressed: (!connected || data.items.isEmpty || _syncing) ? null : _sync,
                ),
                if (!connected) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Ask support to connect your WhatsApp catalog — once it is, '
                    'this button will push your current items, prices, and '
                    'availability automatically.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SyncData {
  _SyncData({required this.items, required this.earlyAccess, required this.merchant});
  final List<Item> items;
  final bool earlyAccess;
  final Merchant merchant;
}
