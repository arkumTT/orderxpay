import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/api_client.dart';
import '../../../core/config.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Section 4.4/6.2: WhatsApp auto-reply settings and the merchant's public
/// catalog link. The catalog link, its copy action, and its share action are
/// real — that page (src/web/app/catalog/[merchantId]) actually exists.
/// The auto-reply toggle and greeting message are real, persisted merchant
/// preferences too, but nothing acts on them yet: there's no WhatsApp
/// Business Solution Provider connection in this codebase (Back Office
/// Integrations lists it as "Not built"), so no bot is actually replying to
/// customers. That's surfaced honestly via the status card below rather than
/// implied by a working-looking toggle.
class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  final _api = ApiClient();
  bool _loading = true;
  bool _autoReplyEnabled = true;
  String? _greetingOverride;
  Merchant? _merchant;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final merchant = await _api.getMerchant(Session.instance.merchantId!);
    setState(() {
      _merchant = merchant;
      _autoReplyEnabled = merchant.whatsappAutoReplyEnabled;
      _greetingOverride = merchant.whatsappGreetingMessage;
      _loading = false;
    });
  }

  String get _catalogLink => '${AppConfig.webBaseUrl}/catalog/${_merchant!.id}';

  String get _greeting =>
      _greetingOverride ??
      "Akwaaba! 👋 Thanks for messaging ${_merchant!.businessName}. Here's our "
          "menu — browse & order what you like: $_catalogLink";

  Future<void> _toggleAutoReply(bool value) async {
    final previous = _autoReplyEnabled;
    setState(() => _autoReplyEnabled = value);
    try {
      await _api.updateWhatsAppSettings(
        Session.instance.merchantId!,
        autoReplyEnabled: value,
        greetingMessage: _greetingOverride,
      );
    } on ApiException catch (e) {
      setState(() => _autoReplyEnabled = previous);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _editGreeting() async {
    final controller = TextEditingController(text: _greeting);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Greeting Message', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              OxpField(label: 'Message', controller: controller, maxLines: 5),
              const SizedBox(height: 20),
              OxpButton(
                label: 'Save',
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;

    final text = controller.text.trim();
    setState(() => _greetingOverride = text.isEmpty ? null : text);
    try {
      await _api.updateWhatsAppSettings(
        Session.instance.merchantId!,
        autoReplyEnabled: _autoReplyEnabled,
        greetingMessage: _greetingOverride,
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
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
                      Text('WhatsApp Business', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      SizedBox(height: 2),
                      Text('Not connected', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          OxpCard(
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Auto-reply', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      SizedBox(height: 2),
                      Text(
                        'Greets customers instantly, 24/7.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _autoReplyEnabled,
                  activeTrackColor: AppColors.statusPaid,
                  onChanged: _toggleAutoReply,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          OxpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Greeting message', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                    TextButton.icon(
                      onPressed: _editGreeting,
                      icon: const Icon(Icons.edit, size: 14, color: AppColors.accent),
                      label: const Text('Edit', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _GreetingPreview(text: _greeting, link: _catalogLink),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const Text('Quick replies', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          const OxpCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _QuickReplyRow(trigger: 'Is this available?', action: 'Auto-checks your catalog', showDivider: false),
                _QuickReplyRow(trigger: 'Send menu', action: 'Sends your catalog link', showDivider: true),
                _QuickReplyRow(
                  trigger: 'How do I pay?',
                  action: 'Explains Mobile Money, card & USSD',
                  showDivider: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const Text('Your catalog link', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          OxpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.fieldFill,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(_catalogLink, style: const TextStyle(fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OxpButton(
                        label: 'Copy link',
                        variant: OxpButtonVariant.secondary,
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _catalogLink));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied')),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OxpButton(
                        label: 'Share to Status',
                        onPressed: () => Share.share(
                          'Check out ${_merchant!.businessName} on OrderxPay: $_catalogLink',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "Transactional replies send instantly once WhatsApp Business is connected. "
            "Marketing broadcasts need Meta template approval.",
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _GreetingPreview extends StatelessWidget {
  const _GreetingPreview({required this.text, required this.link});

  final String text;
  final String link;

  @override
  Widget build(BuildContext context) {
    final linkIndex = text.indexOf(link);
    if (linkIndex == -1) {
      return Text(text, style: const TextStyle(fontSize: 13, height: 1.4));
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.primaryBlack),
        children: [
          TextSpan(text: text.substring(0, linkIndex)),
          TextSpan(
            text: text.substring(linkIndex, linkIndex + link.length),
            style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: text.substring(linkIndex + link.length)),
        ],
      ),
    );
  }
}

class _QuickReplyRow extends StatelessWidget {
  const _QuickReplyRow({required this.trigger, required this.action, required this.showDivider});

  final String trigger;
  final String action;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: showDivider ? const Border(top: BorderSide(color: AppColors.border)) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text('"$trigger"', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward, size: 14, color: AppColors.textDisabled),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              action,
              textAlign: TextAlign.end,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
