import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';
import 'item_form_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _api = ApiClient();
  late Future<List<Item>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.listItems(Session.instance.merchantId!);
  }

  Future<void> _refresh() async {
    final next = _api.listItems(Session.instance.merchantId!);
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _openForm([Item? item]) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ItemFormScreen(item: item)),
    );
    if (created == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalog & Items'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.accent),
            onPressed: () => _openForm(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Item>>(
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
            final items = snapshot.data!;
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(AppSpace.xl),
                children: [
                  const SizedBox(height: 60),
                  const Text(
                    'No items yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add what you sell so you can build orders from your catalog.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  OxpButton(label: 'Add your first item', onPressed: () => _openForm()),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpace.xl),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final item = items[i];
                return OxpCard(
                  onTap: () => _openForm(item),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        child: Container(
                          width: 44,
                          height: 44,
                          color: AppColors.fieldFill,
                          child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                              ? Image.network(
                                  item.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Icon(
                                    Icons.image_not_supported_outlined,
                                    size: 18,
                                    color: AppColors.textDisabled,
                                  ),
                                )
                              : const Icon(
                                  Icons.image_outlined,
                                  size: 18,
                                  color: AppColors.textDisabled,
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatPesewas(item.unitPricePesewas) +
                                  (item.qtyUnit != null && item.qtyUnit!.isNotEmpty
                                      ? ' / ${item.qtyUnit}'
                                      : ''),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (item.availabilityStatus != 'in_stock')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.statusDeclined.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            item.availabilityStatus.replaceAll('_', ' '),
                            style: const TextStyle(
                              color: AppColors.statusDeclined,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: OxpBottomNav(
        current: OxpTab.items,
        onNewOrder: () => Navigator.pushNamed(context, '/new-order'),
      ),
    );
  }
}
