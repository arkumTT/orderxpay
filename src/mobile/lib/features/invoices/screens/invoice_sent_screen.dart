import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/config.dart';
import '../../../core/format.dart';
import '../../../core/models.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// What "Send Invoice" actually produces: a reference and a checkout link
/// (src/web) — this stands in for the WhatsApp/SMS "Send via" step (Section
/// 4.4), which isn't built yet, by just surfacing the link to copy/share
/// through the OS share sheet manually.
class InvoiceSentScreen extends StatelessWidget {
  const InvoiceSentScreen({super.key, required this.invoice});

  final Invoice invoice;

  String get _checkoutLink => '${AppConfig.webBaseUrl}/checkout/${invoice.reference}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Invoice Sent'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(AppSpace.lg),
              decoration: BoxDecoration(
                color: AppColors.statusPaid.withValues(alpha: 0.1),
                border: Border.all(color: AppColors.statusPaid.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.statusPaid),
                  SizedBox(width: 10),
                  Text(
                    'Invoice created',
                    style: TextStyle(
                      color: AppColors.statusPaid,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            OxpCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoice.reference,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total due ${formatPesewas(invoice.totalPesewas)}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.fieldFill,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Text(
                      _checkoutLink,
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OxpButton(
              label: 'Copy Link',
              variant: OxpButtonVariant.secondary,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _checkoutLink));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied')),
                );
              },
            ),
            const Spacer(),
            OxpButton(
              label: 'Done',
              onPressed: () =>
                  Navigator.popUntil(context, ModalRoute.withName('/')),
            ),
          ],
        ),
      ),
    );
  }
}
