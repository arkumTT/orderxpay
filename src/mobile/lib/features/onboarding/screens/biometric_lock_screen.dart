import 'package:flutter/material.dart';

import '../../../core/biometric_lock.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';
import '../../../core/push_notifications.dart';
import '../../../core/session.dart';

/// Gates access behind biometric/passcode auth when a session is already
/// signed in AND biometric unlock is on (More > Security). This is a local
/// gate only — the underlying session/token never changes here.
///
/// Two ways this gets shown, distinguished by [isOverlay]:
/// - Cold start (main.dart's initial route, isOverlay: false): a successful
///   unlock replaces this route with Home, since there's nothing meaningful
///   underneath to return to.
/// - Resumed from background past the configured auto-lock grace period
///   (pushed on top of whatever screen was showing, isOverlay: true): a
///   successful unlock just pops back to that screen.
///
/// Either way, the system back gesture is blocked — a lock screen you can
/// dismiss without authenticating isn't a lock screen. Prompts
/// automatically on first frame so most opens are a single Face ID/
/// fingerprint glance with no tap required — the "Unlock" button and "Sign
/// out instead" link exist for when that auto-prompt is dismissed, fails,
/// or the device has no working biometric/passcode at all.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key, this.isOverlay = false});

  final bool isOverlay;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _authenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isOverlay) BiometricLock.instance.lockOverlayVisible = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    if (widget.isOverlay) BiometricLock.instance.lockOverlayVisible = false;
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _authenticating = true;
      _error = null;
    });
    final ok = await BiometricLock.instance.authenticate(
      'Unlock OrderxPay',
    );
    if (!mounted) return;
    setState(() => _authenticating = false);
    if (ok) {
      BiometricLock.instance.backgroundedAt = null;
      if (widget.isOverlay) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacementNamed('/');
      }
    } else {
      setState(() => _error = "Couldn't verify — try again.");
    }
  }

  Future<void> _signOutInstead() async {
    await PushNotifications.instance.unregisterToken();
    await Session.instance.clear();
    BiometricLock.instance.backgroundedAt = null;
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const OxpWordmark(height: 34),
                const SizedBox(height: 8),
                Text(
                  Session.instance.businessName ?? 'Welcome back',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 40),
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(
                    color: AppColors.fieldFill,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.fingerprint,
                    size: 44,
                    color: _error != null ? AppColors.statusDeclined : AppColors.primaryBlack,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _error ?? 'Unlocking…',
                  style: TextStyle(
                    fontSize: 13,
                    color: _error != null ? AppColors.statusDeclined : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                OxpButton(
                  label: _authenticating ? 'Unlocking…' : 'Unlock',
                  loading: _authenticating,
                  onPressed: _authenticating ? null : _unlock,
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _authenticating ? null : _signOutInstead,
                  child: const Text('Sign out instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
