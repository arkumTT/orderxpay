import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/decline_reasons.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Section 4.6 decline flow, step 2: let them know. Mirrors
/// InvoiceSentScreen's WhatsApp/SMS deep links — the merchant's own app
/// opens pre-filled with a message, the same reason the confirm path
/// doesn't do a backend send (see that screen's doc comment: no WhatsApp
/// template, no real SMS credential). A customer who submitted an order
/// request has no account and no other way to hear back, so this is the
/// only way they ever find out — before this screen existed, a decline was
/// completely silent to them.
///
/// A nudge, not a gate: the merchant can back out without messaging, same
/// as every other best-effort notification in this app. For a suspected
/// -spam decline specifically, the framing flips — see
/// declineDeemphasizesNotifying — since replying to a probably-fake
/// contact just confirms it's live.
class DeclineSentScreen extends StatelessWidget {
  const DeclineSentScreen({
    super.key,
    required this.customerContact,
    required this.customerName,
    required this.category,
    required this.note,
  });

  final String customerContact;
  final String customerName;
  final String category;
  final String note;

  String get _messageText => declineMessageFor(category, note);

  bool get _deemphasize => declineDeemphasizesNotifying(category);

  /// customerContact digits only, no "+" — mirrors
  /// InvoiceSentScreen._customerDigits.
  String get _customerDigits => customerContact.replaceAll(RegExp(r'\D'), '');

  bool get _hasUsablePhone =>
      _customerDigits.length >= 11; // 233 + 9-digit local number

  Future<void> _launch(
      BuildContext context, Uri uri, String failureMessage) async {
    bool launched;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  void _sendViaWhatsApp(BuildContext context) {
    final uri = Uri.parse(
        'https://wa.me/$_customerDigits?text=${Uri.encodeComponent(_messageText)}');
    _launch(context, uri, 'Could not open WhatsApp.');
  }

  void _sendViaSms(BuildContext context) {
    // Same iOS "&body=" vs. "?body=" quirk as InvoiceSentScreen._sendViaSms.
    final separator = Platform.isIOS ? '&' : '?';
    final encodedBody = Uri.encodeComponent(_messageText);
    final uri = Uri.parse('sms:+$_customerDigits${separator}body=$encodedBody');
    _launch(context, uri, 'Could not open Messages.');
  }

  @override
  Widget build(BuildContext context) {
    final notifyButtons = _hasUsablePhone
        ? [
            OxpButton(
              label: 'Message via WhatsApp',
              variant: _deemphasize
                  ? OxpButtonVariant.secondary
                  : OxpButtonVariant.primary,
              icon: _deemphasize
                  ? null
                  : const Icon(Icons.chat_bubble_outline,
                      color: Colors.white, size: 16),
              onPressed: () => _sendViaWhatsApp(context),
            ),
            const SizedBox(height: 10),
            OxpButton(
              label: 'Message via SMS',
              variant: OxpButtonVariant.secondary,
              icon: _deemphasize
                  ? null
                  : const Icon(Icons.sms_outlined,
                      color: AppColors.primaryBlack, size: 16),
              onPressed: () => _sendViaSms(context),
            ),
          ]
        : const <Widget>[
            Text(
              "No usable phone number on file for this customer — there's no channel to message them on.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ];

    final doneButton = OxpButton(
      label: _deemphasize ? "Skip — don't message them" : 'Done',
      variant: _deemphasize && _hasUsablePhone
          ? OxpButtonVariant.primary
          : OxpButtonVariant.secondary,
      onPressed: () => Navigator.pop(context),
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Request Declined'),
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpace.xl,
          AppSpace.xl,
          AppSpace.xl,
          AppSpace.xl + bottomSafeInset(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(AppSpace.lg),
              decoration: BoxDecoration(
                color: AppColors.statusDeclined.withValues(alpha: 0.1),
                border: Border.all(
                    color: AppColors.statusDeclined.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Row(
                children: [
                  const Icon(Icons.block, color: AppColors.statusDeclined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Declined — ${declineReasonLabels[category] ?? category}',
                      style: const TextStyle(
                        color: AppColors.statusDeclined,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_messageText.isNotEmpty) ...[
              OxpCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName.isNotEmpty ? customerName : customerContact,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.fieldFill,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Text(_messageText,
                          style: const TextStyle(fontSize: 13.5)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (_deemphasize) ...[
              const Text(
                "This looked like spam or the contact couldn't be verified — you probably don't need to message them back.",
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              doneButton,
              const SizedBox(height: 10),
              ...notifyButtons,
            ] else ...[
              ...notifyButtons,
              const Spacer(),
              doneButton,
            ],
          ],
        ),
      ),
    );
  }
}
