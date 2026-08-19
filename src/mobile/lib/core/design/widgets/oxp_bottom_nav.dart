import 'package:flutter/material.dart';
import '../app_colors.dart';

enum OxpTab { home, items, records, more }

/// Persistent bottom nav — Home / Items / (FAB) / Records / More — matching
/// the design's tab bar. Each tab screen owns its own Scaffold and swaps via
/// pushReplacementNamed rather than an IndexedStack, so state isn't
/// preserved across tabs; acceptable for how lightweight these screens are.
class OxpBottomNav extends StatelessWidget {
  const OxpBottomNav({super.key, required this.current, required this.onNewOrder});

  final OxpTab current;
  final VoidCallback onNewOrder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: Icons.storefront_outlined,
                    label: 'Home',
                    active: current == OxpTab.home,
                    onTap: () => _go(context, '/', OxpTab.home),
                  ),
                  _NavItem(
                    icon: Icons.grid_view_outlined,
                    label: 'Items',
                    active: current == OxpTab.items,
                    onTap: () => _go(context, '/catalog', OxpTab.items),
                  ),
                  const SizedBox(width: 52),
                  _NavItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'Records',
                    active: current == OxpTab.records,
                    onTap: () => _go(context, '/records', OxpTab.records),
                  ),
                  _NavItem(
                    icon: Icons.more_horiz,
                    label: 'More',
                    active: current == OxpTab.more,
                    onTap: () => _go(context, '/more', OxpTab.more),
                  ),
                ],
              ),
            ),
            Positioned(
              top: -24,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: onNewOrder,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 24),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Order',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _go(BuildContext context, String route, OxpTab tab) {
    if (tab == current) return;
    Navigator.pushReplacementNamed(context, route);
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
