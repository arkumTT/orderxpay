import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiClient();
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final merchantId = Session.instance.merchantId!;
    final results = await Future.wait([
      _api.listInvoices(merchantId),
      _api.listOrderRequests(merchantId),
    ]);
    final invoices = results[0] as List<Invoice>;
    final requests = results[1] as List<OrderRequest>;

    final now = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;

    final todaysInvoices = invoices.where((i) => isToday(i.createdAt)).toList();
    final collectedToday = todaysInvoices
        .where((i) => i.status == 'paid')
        .fold<int>(0, (sum, i) => sum + i.totalPesewas);
    final pendingToday = todaysInvoices
        .where((i) => i.status == 'sent' || i.status == 'viewed')
        .length;

    return _HomeData(
      invoices: invoices.take(3).toList(),
      pendingRequests: requests,
      collectedTodayPesewas: collectedToday,
      ordersToday: todaysInvoices.length,
      pendingToday: pendingToday,
    );
  }

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
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<_HomeData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(
                  padding: const EdgeInsets.all(AppSpace.xl),
                  children: [
                    Text('Failed to load: ${snapshot.error}'),
                  ],
                );
              }
              final data = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl,
                  74,
                  AppSpace.xl,
                  AppSpace.lg,
                ),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Good morning',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              Session.instance.businessName ?? 'Merchant',
                              style: const TextStyle(
                                color: AppColors.primaryBlack,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: const Text(
                          'Tier 0 · Verify to withdraw',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OxpButton(
                          label: '+ New Order',
                          onPressed: () => Navigator.pushNamed(context, '/new-order'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OxpButton(
                          label: 'Send Invoice',
                          variant: OxpButtonVariant.secondary,
                          onPressed: () => Navigator.pushNamed(context, '/new-order'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  OxpCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 18,
                    ),
                    child: Row(
                      children: [
                        _StatColumn(
                          label: 'Collected today',
                          value: formatPesewas(data.collectedTodayPesewas),
                        ),
                        const _StatDivider(),
                        _StatColumn(
                          label: 'Orders today',
                          value: '${data.ordersToday}',
                        ),
                        const _StatDivider(),
                        _StatColumn(
                          label: 'Pending',
                          value: '${data.pendingToday}',
                          valueColor: AppColors.accent,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  OxpCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
                          child: Text(
                            'Recent activity',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryBlack,
                            ),
                          ),
                        ),
                        if (data.pendingRequests.isEmpty && data.invoices.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Text(
                              'Nothing yet — send your first invoice.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        for (final r in data.pendingRequests)
                          _ActivityRow(
                            title: r.customerContact,
                            subtitle: 'Order request · new',
                            trailing: const StatusPill(
                              label: 'Review',
                              color: AppColors.statusPartial,
                            ),
                            onTap: () => Navigator.pushNamed(context, '/order-requests'),
                          ),
                        for (final inv in data.invoices)
                          _ActivityRow(
                            title: inv.customerContact,
                            subtitle: inv.reference,
                            trailing: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatPesewas(inv.totalPesewas),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                StatusPill.forInvoiceStatus(inv.status),
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
      ),
      bottomNavigationBar: OxpBottomNav(
        current: OxpTab.home,
        onNewOrder: () => Navigator.pushNamed(context, '/new-order'),
      ),
    );
  }
}

class _HomeData {
  _HomeData({
    required this.invoices,
    required this.pendingRequests,
    required this.collectedTodayPesewas,
    required this.ordersToday,
    required this.pendingToday,
  });

  final List<Invoice> invoices;
  final List<OrderRequest> pendingRequests;
  final int collectedTodayPesewas;
  final int ordersToday;
  final int pendingToday;
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.label,
    required this.value,
    this.valueColor = AppColors.primaryBlack,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 34, color: AppColors.border);
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            AvatarInitials(name: title),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}
