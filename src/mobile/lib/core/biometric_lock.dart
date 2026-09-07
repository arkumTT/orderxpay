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
/// Auto-lock grace period: how long the app can sit backgrounded before a
/// resume requires biometric re-auth again. [immediately] locks on every
/// single resume, no matter how brief — the rest are a deliberately small,
/// fixed set (not a free-typed duration) so this reads as a short list of
/// sensible choices rather than an open-ended settings field.
enum AutoLockDuration {
  immediately(Duration.zero, 'Immediately'),
  seconds10(Duration(seconds: 10), 'After 10 seconds'),
  seconds20(Duration(seconds: 20), 'After 20 seconds'),
  seconds30(Duration(seconds: 30), 'After 30 seconds'),
  minute1(Duration(minutes: 1), 'After 1 minute');

  const AutoLockDuration(this.duration, this.label);
  final Duration duration;
  final String label;
}

class BiometricLock {
  BiometricLock._();
  static final BiometricLock instance = BiometricLock._();

  static const _kEnabled = 'biometric_unlock_enabled';
  static const _kAutoLockSeconds = 'biometric_auto_lock_seconds';

  final _auth = LocalAuthentication();
  bool _enabled = false;
  AutoLockDuration _autoLock = AutoLockDuration.seconds30;

  bool get enabled => _enabled;
  AutoLockDuration get autoLock => _autoLock;

  // Transient, in-memory only — when the app was last backgrounded, and
  // whether the lock overlay is currently up. Neither needs to survive a
  // process restart: a cold start is always gated by the initial route in
  // main.dart regardless of these.
  DateTime? backgroundedAt;
  bool lockOverlayVisible = false;

  /// Whether a resume happening right now, given [backgroundedAt], should
  /// show the lock overlay. False if never backgrounded, if the overlay is
  /// already up, or if the elapsed time is under the configured grace
  /// period.
  bool shouldRelockNow() {
    if (lockOverlayVisible) return false;
    final since = backgroundedAt;
    if (since == null) return false;
    return DateTime.now().difference(since) >= _autoLock.duration;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? false;
    final seconds = prefs.getInt(_kAutoLockSeconds);
    _autoLock = AutoLockDuration.values.firstWhere(
      (d) => d.duration.inSeconds == seconds,
      orElse: () => AutoLockDuration.seconds30,
    );
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
  }

  Future<void> setAutoLock(AutoLockDuration value) async {
    _autoLock = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAutoLockSeconds, value.duration.inSeconds);
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
