# src/mobile — OrderxPay merchant app (Flutter)

Merchant-facing mobile app — architecture doc Section 4 (module breakdown)
and 12 (user flows).

## Important: platform folders not generated yet

The Flutter SDK isn't installed in the environment this was scaffolded in,
so only the Dart source (`lib/`, `pubspec.yaml`, `analysis_options.yaml`)
exists — there's no `android/`, `ios/`, `test/`, or `.metadata`, and none of
this has been run through `flutter analyze` or `flutter pub get`. Before
anything else:

```bash
cd src/mobile
flutter create . --project-name orderxpay_mobile --org com.orderxpay --platforms android,ios
flutter pub get
flutter analyze
```

`flutter create .` fills in the platform folders around the existing
`lib/`/`pubspec.yaml` without overwriting them. Review the diff it produces
against `pubspec.yaml` (it may add a `flutter.assets`/version bump) before
committing.

## Layout

```
lib/main.dart                  MaterialApp + named routes
lib/core/                      api_client, config (API_BASE_URL), theme,
                                modules list, shared PlaceholderScreen
lib/features/<module>/screens/ one folder per Section 4 module
```

## Running against the local API

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:8080
```

(`http://10.0.2.2:8080` is the default, correct for the Android emulator
talking to a host-machine API; override for iOS simulator/physical device.)

## What's wired vs. placeholder

- Onboarding (Section 4.1) calls the real `CreateMerchant` endpoint. OTP
  verification is skipped — it's stubbed server-side pending SMS provider
  selection (Section 9).
- Every other module screen (`lib/features/*/screens/*.dart`) is a
  structural placeholder using the shared `PlaceholderScreen` widget.
- No session/token persistence yet (no `flutter_secure_storage` dependency
  added) — add it once the OTP + PASETO token flow is built end-to-end.
