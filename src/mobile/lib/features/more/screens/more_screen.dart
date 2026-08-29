import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/session.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

class _MoreItem {
  const _MoreItem(this.label, this.route, this.icon);
  final String label;
  final String route;
  final IconData icon;
}

const _items = [
  _MoreItem('Order Requests', '/order-requests', Icons.inbox_outlined),
  _MoreItem('Staff', '/staff', Icons.people_outline),
  _MoreItem('Delivery Settings', '/delivery', Icons.local_shipping_outlined),
  _MoreItem('Locations', '/locations', Icons.storefront_outlined),
  _MoreItem('Service Charge', '/settings', Icons.percent_outlined),
  _MoreItem('WhatsApp Settings', '/messaging', Icons.chat_bubble_outline),
  _MoreItem('Catalog Sync', '/catalog-sync', Icons.sync_outlined),
  _MoreItem('Notifications', '/notifications', Icons.notifications_none),
  _MoreItem('Verify & Withdraw', '/verify', Icons.verified_outlined),
];

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _api = ApiClient();
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final feed = await _api.listNotifications(Session.instance.merchantId!);
      if (mounted) setState(() => _unreadNotifications = feed.unreadCount);
    } on ApiException {
      // Non-fatal — the badge just stays at whatever it was.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          OxpCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _items.length; i++)
                  InkWell(
                    onTap: () async {
                      await Navigator.pushNamed(context, _items[i].route);
                      if (_items[i].route == '/notifications') _loadUnreadCount();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        border: i == 0
                            ? null
                            : const Border(top: BorderSide(color: AppColors.border)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(_items[i].icon, size: 20, color: AppColors.primaryBlack),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _items[i].label,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                          if (_items[i].route == '/notifications' && _unreadNotifications > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text(
                                _unreadNotifications > 99 ? '99+' : '$_unreadNotifications',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OxpButton(
            label: 'Sign Out',
            variant: OxpButtonVariant.secondary,
            onPressed: () async {
              await Session.instance.clear();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
              }
            },
          ),
        ],
      ),
      bottomNavigationBar: OxpBottomNav(
        current: OxpTab.more,
        onNewOrder: () => Navigator.pushNamed(context, '/new-order'),
      ),
    );
  }
}
