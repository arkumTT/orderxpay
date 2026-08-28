import 'package:shared_preferences/shared_preferences.dart';

/// Local session persistence for real email+password login (Section
/// 4.1/4.9) — a session is either a merchant owner or a staff member,
/// distinguished by [actorType].
class Session {
  Session._();
  static final Session instance = Session._();

  static const _kToken = 'session_token';
  static const _kMerchantId = 'session_merchant_id';
  static const _kBusinessName = 'session_business_name';
  static const _kActorType = 'session_actor_type';

  String? token;
  String? merchantId;
  String? businessName;
  String? actorType; // 'merchant' (owner) or 'staff' — see auth.go MerchantLogin

  bool get isSignedIn => token != null && merchantId != null;
  bool get isStaff => actorType == 'staff';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_kToken);
    merchantId = prefs.getString(_kMerchantId);
    businessName = prefs.getString(_kBusinessName);
    actorType = prefs.getString(_kActorType);
  }

  Future<void> save({
    required String token,
    required String merchantId,
    required String businessName,
    String actorType = 'merchant',
  }) async {
    this.token = token;
    this.merchantId = merchantId;
    this.businessName = businessName;
    this.actorType = actorType;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kMerchantId, merchantId);
    await prefs.setString(_kBusinessName, businessName);
    await prefs.setString(_kActorType, actorType);
  }

  Future<void> clear() async {
    token = null;
    merchantId = null;
    businessName = null;
    actorType = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kMerchantId);
    await prefs.remove(_kBusinessName);
    await prefs.remove(_kActorType);
  }
}
