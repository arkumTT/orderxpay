import 'package:shared_preferences/shared_preferences.dart';

/// Local session persistence. Standing in for real OTP-issued session
/// handling (Section 4.1) — see api_client.dart's dev-token bootstrap.
class Session {
  Session._();
  static final Session instance = Session._();

  static const _kToken = 'session_token';
  static const _kMerchantId = 'session_merchant_id';
  static const _kBusinessName = 'session_business_name';

  String? token;
  String? merchantId;
  String? businessName;

  bool get isSignedIn => token != null && merchantId != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_kToken);
    merchantId = prefs.getString(_kMerchantId);
    businessName = prefs.getString(_kBusinessName);
  }

  Future<void> save({
    required String token,
    required String merchantId,
    required String businessName,
  }) async {
    this.token = token;
    this.merchantId = merchantId;
    this.businessName = businessName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kMerchantId, merchantId);
    await prefs.setString(_kBusinessName, businessName);
  }

  Future<void> clear() async {
    token = null;
    merchantId = null;
    businessName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kMerchantId);
    await prefs.remove(_kBusinessName);
  }
}
