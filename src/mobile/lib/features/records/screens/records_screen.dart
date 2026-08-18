import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';
import 'invoice_detail_screen.dart';

const _filters = ['All', 'Paid', 'Pending', 'Partial', 'Declined'];

String? _statusFor(String filter) => switch (filter) {
  'Paid' => 'paid',
  'Partial' => 'partially_paid',
  'Declined' => 'cancelled',
  _ => null, // All / Pending — Pending has no single backend status, filtered client-side
};

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final _api = ApiClient();
  String _filter = 'All';
  late Future<List<Invoice>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Invoice>> _load() async {
    final invoices = await _api.listInvoices(Session.instance.merchantId!);
    if (_filter == 'Pending') {
      return invoices.where((i) => i.status == 'sent' || i.status == 'viewed').toList();
    }
    final status = _statusFor(_filter);
    return status == null ? invoices : invoices.where((i) => i.status == status).toList();
  }

  void _setFilter(String f) {
    setState(() {
      _filter = f;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Records')),
      body: RefreshIndicator(
        onRefresh: () async {
          final next = _load();
          setState(() {
            _future = next;
          });
          await next;
        },
        child: FutureBuilder<List<Invoice>>(
          future: _future,
          builder: (context, snapshot) {
            final invoices = snapshot.data ?? [];
            final now = DateTime.now();
            final weekAgo = now.subtract(const Duration(days: 7));
            final collectedThisWeek = invoices
                .where((i) => i.status == 'paid' && i.createdAt.isAfter(weekAgo))
                .fold<int>(0, (sum, i) => sum + i.totalPesewas);

            return ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
                OxpCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Collected this week',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      Text(
                        formatPesewas(collectedThisWeek),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final f = _filters[i];
                      final active = f == _filter;
                      return GestureDetector(
                        onTap: () => _setFilter(f),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active ? AppColors.primaryBlack : Colors.transparent,
                            border: active ? null : Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            f,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: active ? Colors.white : AppColors.primaryBlack,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (snapshot.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (invoices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text('No records', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  )
                else
                  OxpCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < invoices.length; i++)
                          GestureDetector(
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => InvoiceDetailScreen(invoiceId: invoices[i].id),
                                ),
                              );
                              if (context.mounted) {
                                setState(() {
                                  _future = _load();
                                });
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                border: i == 0
                                    ? null
                                    : const Border(top: BorderSide(color: AppColors.border)),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          invoices[i].customerContact,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                        ),
                                        Text(
                                          invoices[i].reference,
                                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        formatPesewas(invoices[i].totalPesewas),
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                      ),
                                      const SizedBox(height: 5),
                                      StatusPill.forInvoiceStatus(invoices[i].status),
                                    ],
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
                                ],
                              ),
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
      bottomNavigationBar: OxpBottomNav(
        current: OxpTab.records,
        onNewOrder: () => Navigator.pushNamed(context, '/new-order'),
      ),
    );
  }
}
