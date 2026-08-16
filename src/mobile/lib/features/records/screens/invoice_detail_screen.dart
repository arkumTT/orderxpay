import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/api_client.dart';
import '../../../core/config.dart';
import '../../../core/format.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

const _terminalStatuses = {'paid', 'expired', 'cancelled', 'refunded'};

String _formatDateTime(DateTime d) => DateFormat('d MMM, h:mm a').format(d.toLocal());

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final _api = ApiClient();
  late Future<InvoiceDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<InvoiceDetail> _load() =>
      _api.getInvoiceDetail(Session.instance.merchantId!, widget.invoiceId);

  String _checkoutLink(String reference) =>
      '${AppConfig.webBaseUrl}/checkout/$reference';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record')),
      body: FutureBuilder<InvoiceDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(
              child: Text('Could not load this record', style: TextStyle(color: AppColors.textSecondary)),
            );
          }

          final detail = snapshot.data!;
          final invoice = detail.invoice;
          final canPay = !_terminalStatuses.contains(invoice.status);

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _load());
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
                OxpCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            invoice.reference,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          StatusPill.forInvoiceStatus(invoice.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        invoice.customerContact,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      Text(
                        _formatDateTime(invoice.createdAt),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const Divider(height: 24),
                      _row('Subtotal', formatPesewas(invoice.subtotalPesewas)),
                      _row('Service charge', formatPesewas(invoice.serviceChargePesewas)),
                      _row('Total', formatPesewas(invoice.totalPesewas), bold: true),
                      if (invoice.status == 'partially_paid') ...[
                        const SizedBox(height: 8),
                        _row('Paid so far', formatPesewas(detail.amountPaidPesewas), color: AppColors.statusPaid),
                        _row('Still owed', formatPesewas(detail.amountOwedPesewas), color: AppColors.statusPartial),
                      ],
                    ],
                  ),
                ),

                if (canPay) ...[
                  const SizedBox(height: 16),
                  OxpCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Payment link',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.fieldFill,
                            borderRadius: BorderRadius.circular(AppRadius.control),
                          ),
                          child: Text(
                            _checkoutLink(invoice.reference),
                            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OxpButton(
                          label: 'Copy Link',
                          variant: OxpButtonVariant.secondary,
                          icon: const Icon(Icons.copy, size: 16),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _checkoutLink(invoice.reference)));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Link copied')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                Text(
                  'Items',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                OxpCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < detail.lineItems.length; i++)
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
                                  '${detail.lineItems[i].description} × ${detail.lineItems[i].quantity}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Text(
                                formatPesewas(detail.lineItems[i].lineTotalPesewas),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                if (detail.payments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Payment attempts',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  OxpCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < detail.payments.length; i++)
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
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        detail.payments[i].method.toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                      Text(
                                        detail.payments[i].paidAt != null
                                            ? _formatDateTime(detail.payments[i].paidAt!)
                                            : _formatDateTime(detail.payments[i].createdAt),
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatPesewas(detail.payments[i].amountPesewas),
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                    if (detail.payments[i].refundedAmountPesewas > 0)
                                      Text(
                                        '-${formatPesewas(detail.payments[i].refundedAmountPesewas)} refunded',
                                        style: const TextStyle(color: Colors.red, fontSize: 11),
                                      )
                                    else
                                      Text(
                                        detail.payments[i].status,
                                        style: TextStyle(
                                          color: detail.payments[i].status == 'success'
                                              ? AppColors.statusPaid
                                              : AppColors.textSecondary,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 16 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: color ?? AppColors.primaryBlack,
            ),
          ),
        ],
      ),
    );
  }
}
