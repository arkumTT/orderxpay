import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Section 4.7 — simple merchant analytics: best-selling items, daily
/// collections, average order value, and repeat customers. All figures are
/// computed server-side over the trailing 30 days from the merchant's own
/// paid/partially-paid invoices.
class RecordsInsightsScreen extends StatefulWidget {
  const RecordsInsightsScreen({super.key});

  @override
  State<RecordsInsightsScreen> createState() => _RecordsInsightsScreenState();
}

class _RecordsInsightsScreenState extends State<RecordsInsightsScreen> {
  final _api = ApiClient();
  late Future<MerchantAnalytics> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<MerchantAnalytics> _load() => _api.getMerchantAnalytics(Session.instance.merchantId!);

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<MerchantAnalytics>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(
                      child: Text('Could not load insights', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                ],
              );
            }
            final a = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
                const Text(
                  'Last 30 days',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(label: 'Orders', value: '${a.orderCount}'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(label: 'Avg. order value', value: formatPesewas(a.averageOrderValuePesewas)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(label: 'Total collected', value: formatPesewas(a.totalCollectedPesewas)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(label: 'Customers', value: '${a.uniqueCustomerCount}'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Daily collections', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 10),
                if (a.dailyCollections.isEmpty)
                  const _EmptySection(text: 'No collections yet in this period.')
                else
                  OxpCard(child: _DailyCollectionsChart(daily: a.dailyCollections)),
                const SizedBox(height: 24),
                const Text('Best-selling items', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 10),
                if (a.bestSellingItems.isEmpty)
                  const _EmptySection(text: 'No paid orders yet in this period.')
                else
                  OxpCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < a.bestSellingItems.length; i++)
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
                                    a.bestSellingItems[i].description,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ),
                                Text(
                                  '×${a.bestSellingItems[i].totalQuantity}',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  formatPesewas(a.bestSellingItems[i].totalRevenuePesewas),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                const Text('Repeat customers', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 10),
                if (a.repeatCustomers.isEmpty)
                  const _EmptySection(text: 'No repeat customers yet in this period.')
                else
                  OxpCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < a.repeatCustomers.length; i++)
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
                                    a.repeatCustomers[i].customerContact,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ),
                                Text(
                                  '${a.repeatCustomers[i].orderCount} orders',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  formatPesewas(a.repeatCustomers[i].totalSpentPesewas),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                      ],
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

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return OxpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return OxpCard(
      child: Center(
        child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      ),
    );
  }
}

/// Simple bar chart with no external charting dependency — a row of bars
/// scaled against the period's peak day, with the collected amount labeled
/// above each bar and the day-of-month below.
class _DailyCollectionsChart extends StatelessWidget {
  const _DailyCollectionsChart({required this.daily});
  final List<DailyCollection> daily;

  @override
  Widget build(BuildContext context) {
    final maxPesewas = daily.fold<int>(1, (m, d) => d.collectedPesewas > m ? d.collectedPesewas : m);
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in daily)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      formatPesewasShort(d.collectedPesewas),
                      style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 90 * (d.collectedPesewas / maxPesewas).clamp(0.04, 1.0),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.control / 2),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('d').format(d.day),
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
