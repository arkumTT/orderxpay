import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config.dart';
import '../../../core/format.dart';
import '../../../core/models.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// What "Send Invoice" actually produces: a reference and a checkout link
/// (src/web) — Section 4.4's "Send via" step.
///
/// WhatsApp and SMS are the primary actions (Section 4.3 order flow
/// revision): both are device deep links the merchant's own WhatsApp/
/// Messages app opens pre-filled with the customer's number and the
/// invoice text, letting the merchant review and send it themselves —
/// deliberately NOT a backend send. Two real constraints rule that out
/// today: WhatsApp's Cloud API only allows a business-initiated message
/// (no prior inbound message from this customer) via a pre-approved
/// message template, which nothing in this codebase has set up; and the
/// SMS provider credential in this environment is a placeholder
/// (`SMS_API_KEY=test_fake_arkesel_key_not_real` in src/api/.env), so a
/// real backend send would just fail. Deep links sidestep both — no
/// template, no provider account, works for every merchant today.
///
/// Share Link and Copy Link remain as secondary, general-purpose options
/// (any other channel, or manually pasting into a chat).
class InvoiceSentScreen extends StatelessWidget {
  const InvoiceSentScreen({super.key, required this.invoice});

  final Invoice invoice;

  String get _checkoutLink => '${AppConfig.webBaseUrl}/checkout/${invoice.reference}';

  String get _messageText =>
      'Pay ${invoice.reference} — ${formatPesewas(invoice.totalPesewas)}\n$_checkoutLink';

  /// customer_contact digits only, no "+" — e.g. "233241234567". Older
  /// invoices predating the split name/phone field could in principle
  /// carry a messier string, so anything left with too few digits to be a
  /// real phone number is treated as unusable rather than guessed at.
  String get _customerDigits => invoice.customerContact.replaceAll(RegExp(r'\D'), '');

  bool get _hasUsablePhone => _customerDigits.length >= 11; // 233 + 9-digit local number

  Future<void> _launch(BuildContext context, Uri uri, String failureMessage) async {
    bool launched;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  void _sendViaWhatsApp(BuildContext context) {
    final uri = Uri.parse('https://wa.me/$_customerDigits?text=${Uri.encodeComponent(_messageText)}');
    _launch(context, uri, 'Could not open WhatsApp.');
  }

  void _sendViaSms(BuildContext context) {
    // iOS's Messages app has a long-standing quirk where "?body=" (the
    // otherwise-standard sms: URI format, and what Android expects) is
    // silently ignored — it needs "&body=" instead, even as the only
    // query parameter.
    final separator = Platform.isIOS ? '&' : '?';
    final encodedBody = Uri.encodeComponent(_messageText);
    final uri = Uri.parse('sms:+$_customerDigits${separator}body=$encodedBody');
    _launch(context, uri, 'Could not open Messages.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Invoice Sent'),
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpace.xl, AppSpace.xl, AppSpace.xl,
          AppSpace.xl + bottomSafeInset(context),
        ),
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
            const SizedBox(height: 20),
            if (_hasUsablePhone) ...[
              OxpButton(
                label: 'Send via WhatsApp',
                icon: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 16),
                onPressed: () => _sendViaWhatsApp(context),
              ),
              const SizedBox(height: 10),
              OxpButton(
                label: 'Send via SMS',
                icon: const Icon(Icons.sms_outlined, color: Colors.white, size: 16),
                onPressed: () => _sendViaSms(context),
              ),
              const SizedBox(height: 20),
              const Text(
                'Or share another way',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
            ],
            OxpButton(
              label: 'Share Link',
              variant: OxpButtonVariant.secondary,
              icon: const Icon(Icons.share_outlined, size: 16),
              onPressed: () {
                Share.share(_messageText, subject: 'Invoice ${invoice.reference}');
              },
            ),
            const SizedBox(height: 10),
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
