import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';
import '../../order_requests/screens/order_requests_screen.dart';
import '../../records/screens/invoice_detail_screen.dart';
import '../../verify/screens/verify_screen.dart';

/// Section 4.10 — real, persisted in-app alerts: payment received, a new
/// order request, a payout settled, or a KYC review decision. There's no
/// push/SMS/WhatsApp delivery behind this — no push provider is wired up,
/// and SMS/WhatsApp both depend on integrations this platform doesn't have
/// yet (Section 7.3) — so this screen is honestly the in-app feed only.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _api = ApiClient();
  late Future<NotificationFeed> _future;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<NotificationFeed> _load() => _api.listNotifications(Session.instance.merchantId!);

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    try {
      await _api.markAllNotificationsRead(Session.instance.merchantId!);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _openNotification(AppNotification notification) async {
    if (notification.isUnread) {
      try {
        await _api.markNotificationRead(Session.instance.merchantId!, notification.id);
        _refresh();
      } on ApiException {
        // Non-fatal — still navigate even if the read-marking call fails.
      }
    }
    if (!mounted) return;

    switch (notification.targetEntity) {
      case 'invoice':
        if (notification.targetId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: notification.targetId!)),
          );
        }
      case 'order_request':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderRequestsScreen()));
      case 'kyc_submission':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const VerifyScreen()));
      default:
        // 'settlement' has no dedicated mobile screen yet — marking read is
        // itself the whole action for that type.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          FutureBuilder<NotificationFeed>(
            future: _future,
            builder: (context, snapshot) {
              final hasUnread = (snapshot.data?.unreadCount ?? 0) > 0;
              return TextButton(
                onPressed: !hasUnread || _markingAll ? null : _markAllRead,
                child: Text(
                  'Mark all read',
                  style: TextStyle(
                    color: hasUnread ? AppColors.accent : AppColors.textDisabled,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<NotificationFeed>(
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
                      child: Text('Could not load notifications', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                ],
              );
            }
            final notifications = snapshot.data!.notifications;
            if (notifications.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(
                      child: Text(
                        "Nothing yet — you'll see payments, order requests, "
                        "payouts, and verification updates here.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
                for (final n in notifications)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _NotificationCard(notification: n, onTap: () => _openNotification(n)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  IconData get _icon => switch (notification.type) {
    'payment_received' => Icons.payments_outlined,
    'order_request_pending' => Icons.inbox_outlined,
    'payout_processed' => Icons.account_balance_wallet_outlined,
    'kyc_status_change' => Icons.verified_outlined,
    _ => Icons.notifications_none,
  };

  @override
  Widget build(BuildContext context) {
    final unread = notification.isUnread;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: OxpCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: unread ? AppColors.accent.withValues(alpha: 0.1) : AppColors.fieldFill,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Icon(_icon, size: 18, color: unread ? AppColors.accent : AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(notification.body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35)),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('d MMM, h:mm a').format(notification.createdAt),
                    style: const TextStyle(color: AppColors.textDisabled, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (unread) ...[
              const SizedBox(width: 8),
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
