import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Biometric app unlock (Face ID/fingerprint) — a local gate in front of
/// the session that's already logged in via email+password (session.dart).
/// This is NOT passwordless auth: nothing is registered with the backend,
/// no credential changes, no new server-side infra. It's purely "if
/// enabled, prove it's you again before showing the app," using whatever
/// biometric the OS already trusts.
///
/// Deliberately allows the device passcode/PIN as a fallback
/// (biometricOnly: false in [authenticate]) — the same posture as banking
/// apps: Face ID/fingerprint is the fast path, not the only path, so a
/// sensor hiccup or an unenrolled face never locks someone out of their
/// own already-authenticated session.
class BiometricLock {
  BiometricLock._();
  static final BiometricLock instance = BiometricLock._();

  static const _kEnabled = 'biometric_unlock_enabled';

  final _auth = LocalAuthentication();
  bool _enabled = false;

  bool get enabled => _enabled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
  }

  /// Whether this device can do biometric/passcode auth at all — check
  /// before offering the toggle in Security settings. `false` on an
  /// emulator with no biometrics enrolled and no passcode set, or if the
  /// platform channel isn't available.
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Prompts for biometric/passcode auth. Returns false on cancel, a
  /// failed attempt, or any platform error — never throws, since every
  /// caller treats "not authenticated" as the only outcome that matters.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
