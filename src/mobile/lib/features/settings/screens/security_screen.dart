import 'package:flutter/material.dart';

import '../../../core/biometric_lock.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/design/widgets.dart';

/// Biometric app unlock toggle (Section 4.9-adjacent — not spec'd, added
/// on request). Purely local: enabling this never touches the backend or
/// the stored session token, it just gates showing the app behind a
/// device biometric/passcode check on launch — see biometric_lock_screen.dart.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _loading = true;
  bool _supported = false;
  bool _enabled = false;
  bool _busy = false;
  String? _error;
  late AutoLockDuration _autoLock;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final supported = await BiometricLock.instance.isDeviceSupported();
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _enabled = BiometricLock.instance.enabled;
      _autoLock = BiometricLock.instance.autoLock;
      _loading = false;
    });
  }

  Future<void> _setAutoLock(AutoLockDuration value) async {
    setState(() => _autoLock = value);
    await BiometricLock.instance.setAutoLock(value);
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    if (value) {
      // Confirm biometrics actually work on this device before turning
      // the gate on — otherwise a broken sensor could lock the merchant
      // out of their own already-logged-in session.
      final ok = await BiometricLock.instance.authenticate(
        'Confirm to enable biometric unlock',
      );
      if (!ok) {
        setState(() {
          _busy = false;
          _error = "Couldn't verify — biometric unlock wasn't enabled.";
        });
        return;
      }
    }
    await BiometricLock.instance.setEnabled(value);
    if (!mounted) return;
    setState(() {
      _enabled = value;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
                OxpCard(
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Unlock with Face ID / Fingerprint',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Confirm it\'s you when opening the app, instead of '
                              'typing your password every time.',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (_busy)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Switch(
                          value: _enabled,
                          activeTrackColor: AppColors.statusPaid,
                          onChanged: _supported ? _toggle : null,
                        ),
                    ],
                  ),
                ),
                if (!_supported) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'This device has no biometric or passcode lock set up, so '
                    'this can\'t be enabled here — set one up in your phone\'s '
                    'settings first.',
                    style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
                  ),
                ],
                if (_enabled) ...[
                  const SizedBox(height: 16),
                  OxpCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lock after leaving the app',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Switching to another app briefly won\'t ask again until '
                          'this much time has passed.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final option in AutoLockDuration.values)
                              ChoiceChip(
                                label: Text(option.label),
                                selected: _autoLock == option,
                                onSelected: (_) => _setAutoLock(option),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, color: AppColors.statusDeclined),
                  ),
                ],
              ],
            ),
    );
  }
}
