import 'package:flutter/material.dart';

import '../../../core/biometric_lock.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';
import '../../../core/push_notifications.dart';
import '../../../core/session.dart';

/// Shown at launch instead of Home when the merchant already has a valid
/// session (session.dart) AND has opted into biometric unlock (More >
/// Security). This is a local gate only — the underlying session/token
/// never changes here; a successful unlock just proceeds to Home.
///
/// Prompts automatically on first frame so most opens are a single Face
/// ID/fingerprint glance with no tap required — the "Unlock" button and
/// "Sign out instead" link exist for when that auto-prompt is dismissed,
/// fails, or the device has no working biometric/passcode at all.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _authenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
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
      Navigator.of(context).pushReplacementNamed('/');
    } else {
      setState(() => _error = "Couldn't verify — try again.");
    }
  }

  Future<void> _signOutInstead() async {
    await PushNotifications.instance.unregisterToken();
    await Session.instance.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }
}
