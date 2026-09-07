package com.orderxpay.orderxpay_mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not the default FlutterActivity) is required by
// local_auth's Android implementation — the biometric prompt is a
// DialogFragment, which needs a FragmentActivity to attach to. Biometric
// app unlock (see core/biometric_lock.dart) is the reason this changed.
class MainActivity : FlutterFragmentActivity()
