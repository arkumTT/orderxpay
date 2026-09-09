// Mirrors JSON produced by src/api's sqlc models. pgtype.UUID/Text/Int8/Int4
// all marshal to a plain value, or null when unset.

int _int(dynamic v) => v == null ? 0 : (v as num).toInt();
int? _intOrNull(dynamic v) => v == null ? null : (v as num).toInt();
double? _doubleOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
String _str(dynamic v) => v == null ? '' : v as String;
String? _strOrNull(dynamic v) => v as String?;

class Merchant {
  Merchant({
    required this.id,
    required this.businessName,
    required this.category,
    required this.phone,
    required this.email,
    required this.kycTier,
    required this.businessType,
    required this.status,
    required this.serviceChargeAllocation,
    required this.serviceChargeSplitBps,
    required this.payoutAccountType,
    required this.payoutAccountRef,
    required this.payoutBankCode,
    required this.payoutAccountName,
    required this.payoutAccountVerifiedAt,
    required this.whatsappAutoReplyEnabled,
    required this.whatsappGreetingMessage,
    required this.whatsappCatalogId,
    required this.whatsappPhoneNumberId,
    required this.deliveryEnabled,
  });

  final String id;
  final String businessName;
  final String? category;
  final String phone;
  /// Null for a merchant who registered phone-first and never added one
  /// from Settings (Section 4.1) — see OnboardingScreen and CreateMerchant,
  /// which no longer require it at signup.
  final String? email;
  final int kycTier;
  /// informal | registered, or null until a submission is approved — an
  /// unverified merchant hasn't told us which kind of business they are.
  final String? businessType;
  final String status;
  final String serviceChargeAllocation;
  final int? serviceChargeSplitBps;

  /// Section 4.1: momo | bank, or null until a payout account is verified.
  final String? payoutAccountType;
  /// The wallet/account number — set together with payoutAccountType.
  final String? payoutAccountRef;
  /// The network/bank code from ApiClient.listPayoutBanks.
  final String? payoutBankCode;
  /// The name Paystack resolved for this account — never merchant-typed
  /// text. Set (and cleared) together with payoutAccountVerifiedAt.
  final String? payoutAccountName;
  final DateTime? payoutAccountVerifiedAt;

  bool get hasVerifiedPayoutAccount => payoutAccountVerifiedAt != null;

  final bool whatsappAutoReplyEnabled;
  final String? whatsappGreetingMessage; // null = use the app's generated default
  final String? whatsappCatalogId; // null = no Meta catalog connected yet (Section 6.2, admin-provisioned)
  final String? whatsappPhoneNumberId; // null = no WhatsApp number connected yet (Section 4.4, admin-provisioned)
  final bool deliveryEnabled;

  factory Merchant.fromJson(Map<String, dynamic> j) => Merchant(
    id: _str(j['id']),
    businessName: _str(j['business_name']),
    category: _strOrNull(j['category']),
    phone: _str(j['phone']),
    email: _strOrNull(j['email']),
    kycTier: _int(j['kyc_tier']),
    businessType: _strOrNull(j['business_type']),
    status: _str(j['status']),
    serviceChargeAllocation: _str(j['service_charge_allocation']),
    serviceChargeSplitBps: _intOrNull(j['service_charge_split_bps']),
    payoutAccountType: _strOrNull(j['payout_account_type']),
    payoutAccountRef: _strOrNull(j['payout_account_ref']),
    payoutBankCode: _strOrNull(j['payout_bank_code']),
    payoutAccountName: _strOrNull(j['payout_account_name']),
    payoutAccountVerifiedAt: j['payout_account_verified_at'] == null
        ? null
        : DateTime.tryParse(_str(j['payout_account_verified_at'])),
    whatsappAutoReplyEnabled: j['whatsapp_auto_reply_enabled'] as bool? ?? true,
    whatsappGreetingMessage: _strOrNull(j['whatsapp_greeting_message']),
    whatsappCatalogId: _strOrNull(j['whatsapp_catalog_id']),
    whatsappPhoneNumberId: _strOrNull(j['whatsapp_phone_number_id']),
    deliveryEnabled: j['delivery_enabled'] as bool? ?? true,
  );
}

/// Section 4.1: one entry from ApiClient.listPayoutBanks — a bank or, for
/// momo, a mobile money network (MTN, Telecel Cash, AirtelTigo Money).
class PayoutBank {
  PayoutBank({required this.name, required this.code});
  final String name;
  final String code;

  factory PayoutBank.fromJson(Map<String, dynamic> j) =>
      PayoutBank(name: _str(j['name']), code: _str(j['code']));
}

/// Section 4.8 (revised): the blended commissionBps the invoice engine and
/// checkout read is always collectionFeeBps + marginBps, enforced
/// server-side. Payouts are priced separately and flat, because the payment
/// provider charges a flat amount per transfer rather than a percentage.
/// The breakdown here is what the merchant-facing "How this is calculated"
/// card explains.
class FeeRule {
  FeeRule({
    required this.commissionBps,
    required this.collectionFeeBps,
    required this.marginBps,
    required this.allocationType,
    required this.marginFloorPesewas,
    required this.marginCapPesewas,
    required this.withdrawalFeeMomoPesewas,
    required this.withdrawalFeeBankPesewas,
    required this.withdrawalFeeWaiverPesewas,
  });

  /// The blended rate quoted to the merchant: collection + margin.
  final int commissionBps;

  /// Passed straight through to the payment provider.
  final int collectionFeeBps;

  /// OrderxPay's own take, clamped per invoice by the floor and cap below
  /// (0 on either means unclamped). Only the margin is ever clamped — the
  /// provider's share is always passed through in full.
  final int marginBps;
  final int marginFloorPesewas;
  final int marginCapPesewas;

  final String allocationType;

  /// Withdrawals are priced flat, matching what the provider actually
  /// charges per transfer, and waived above the waiver threshold.
  final int withdrawalFeeMomoPesewas;
  final int withdrawalFeeBankPesewas;
  final int withdrawalFeeWaiverPesewas;

  factory FeeRule.fromJson(Map<String, dynamic> j) => FeeRule(
    commissionBps: _int(j['commission_bps']),
    collectionFeeBps: _int(j['collection_fee_bps']),
    marginBps: _int(j['margin_bps']),
    allocationType: _str(j['allocation_type']),
    marginFloorPesewas: _int(j['margin_floor_pesewas']),
    marginCapPesewas: _int(j['margin_cap_pesewas']),
    withdrawalFeeMomoPesewas: _int(j['withdrawal_fee_momo_pesewas']),
    withdrawalFeeBankPesewas: _int(j['withdrawal_fee_bank_pesewas']),
    withdrawalFeeWaiverPesewas: _int(j['withdrawal_fee_waiver_pesewas']),
  );
}

class Item {
  Item({
    required this.id,
    required this.merchantId,
    required this.name,
    required this.unitPricePesewas,
    required this.qtyUnit,
    required this.imageUrl,
    required this.availabilityStatus,
    required this.archived,
  });

  final String id;
  final String merchantId;
  final String name;
  final int unitPricePesewas;
  final String? qtyUnit;
  final String? imageUrl;
  final String availabilityStatus;
  final bool archived;

  factory Item.fromJson(Map<String, dynamic> j) => Item(
    id: _str(j['id']),
    merchantId: _str(j['merchant_id']),
    name: _str(j['name']),
    unitPricePesewas: _int(j['unit_price_pesewas']),
    qtyUnit: _strOrNull(j['qty_unit']),
    imageUrl: _strOrNull(j['image_url']),
    availabilityStatus: _str(j['availability_status']),
    archived: j['archived_at'] != null,
  );
}

class InvoiceLineItem {
  InvoiceLineItem({
    required this.description,
    required this.unitPricePesewas,
    required this.quantity,
    required this.lineTotalPesewas,
  });

  final String description;
  final int unitPricePesewas;
  final int quantity;
  final int lineTotalPesewas;

  factory InvoiceLineItem.fromJson(Map<String, dynamic> j) => InvoiceLineItem(
    description: _str(j['description']),
    unitPricePesewas: _int(j['unit_price_pesewas']),
    quantity: _int(j['quantity']),
    lineTotalPesewas: _int(j['line_total_pesewas']),
  );
}

class Invoice {
  Invoice({
    required this.id,
    required this.reference,
    required this.customerContact,
    required this.subtotalPesewas,
    required this.serviceChargePesewas,
    required this.totalPesewas,
    required this.status,
    required this.createdAt,
    this.lineItems = const [],
  });

  final String id;
  final String reference;
  final String customerContact;
  final int subtotalPesewas;
  final int serviceChargePesewas;
  final int totalPesewas;
  final String status;
  final DateTime createdAt;
  final List<InvoiceLineItem> lineItems;

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
    id: _str(j['id']),
    reference: _str(j['reference']),
    customerContact: _str(j['customer_contact']),
    subtotalPesewas: _int(j['subtotal_pesewas']),
    serviceChargePesewas: _int(j['service_charge_pesewas']),
    totalPesewas: _int(j['total_pesewas']),
    status: _str(j['status']),
    createdAt: DateTime.tryParse(_str(j['created_at'])) ?? DateTime.now(),
  );
}

class PaymentAttempt {
  PaymentAttempt({
    required this.id,
    required this.pspReference,
    required this.method,
    required this.amountPesewas,
    required this.status,
    required this.refundedAmountPesewas,
    required this.paidAt,
    required this.createdAt,
  });

  final String id;
  final String pspReference;
  final String method; // momo | card | ussd
  final int amountPesewas;
  final String status; // pending | success | failed
  final int refundedAmountPesewas;
  final DateTime? paidAt;
  final DateTime createdAt;

  factory PaymentAttempt.fromJson(Map<String, dynamic> j) => PaymentAttempt(
    id: _str(j['id']),
    pspReference: _str(j['psp_reference']),
    method: _str(j['method']),
    amountPesewas: _int(j['amount_pesewas']),
    status: _str(j['status']),
    refundedAmountPesewas: _int(j['refunded_amount_pesewas']),
    paidAt: j['paid_at'] == null ? null : DateTime.tryParse(_str(j['paid_at'])),
    createdAt: DateTime.tryParse(_str(j['created_at'])) ?? DateTime.now(),
  );
}

class InvoiceDetail {
  InvoiceDetail({
    required this.invoice,
    required this.lineItems,
    required this.payments,
    required this.amountPaidPesewas,
    required this.amountOwedPesewas,
  });

  final Invoice invoice;
  final List<InvoiceLineItem> lineItems;
  final List<PaymentAttempt> payments;
  final int amountPaidPesewas;
  final int amountOwedPesewas;

  factory InvoiceDetail.fromJson(Map<String, dynamic> j) => InvoiceDetail(
    invoice: Invoice.fromJson(j['invoice'] as Map<String, dynamic>),
    lineItems: (j['line_items'] as List<dynamic>? ?? const [])
        .map((e) => InvoiceLineItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    payments: (j['payments'] as List<dynamic>? ?? const [])
        .map((e) => PaymentAttempt.fromJson(e as Map<String, dynamic>))
        .toList(),
    amountPaidPesewas: _int(j['amount_paid_pesewas']),
    amountOwedPesewas: _int(j['amount_owed_pesewas']),
  );
}

class OrderRequest {
  OrderRequest({
    required this.id,
    required this.customerContact,
    required this.customerName,
    required this.requestedItems,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String customerContact;
  // Optional — empty when the customer didn't give one. Prefer this over
  // customerContact for display; there's no customers table backing this,
  // so the phone number remains the fallback identifier.
  final String customerName;
  final List<dynamic> requestedItems;
  final String status;
  final DateTime createdAt;

  /// What to show the merchant: the customer's name if they gave one,
  /// otherwise the phone number they ordered from.
  String get displayName => customerName.isNotEmpty ? customerName : customerContact;

  factory OrderRequest.fromJson(Map<String, dynamic> j) => OrderRequest(
    id: _str(j['id']),
    customerContact: _str(j['customer_contact']),
    customerName: _str(j['customer_name']),
    requestedItems: (j['requested_items'] as List<dynamic>?) ?? const [],
    status: _str(j['status']),
    createdAt: DateTime.tryParse(_str(j['created_at'])) ?? DateTime.now(),
  );
}

/// Section 4.1: the two verification paths. An informal trader submits a
/// Ghana Card number and a liveness check and reaches Tier 1; a registered
/// business submits the same plus a TIN, registration number, entity type
/// and certificate, and reaches Tier 2. The requested tier follows the
/// business type server-side — the app never sends one.
///
/// No image of the Ghana Card is captured on either path. The card is
/// verified by number plus liveness check only, because copying or scanning
/// Ghana Card IDs is restricted. A business registration certificate is an
/// ordinary commercial document and is uploaded normally.
class BusinessTypes {
  static const informal = 'informal';
  static const registered = 'registered';
}

/// Ghanaian business forms, matching the kyc_submissions.entity_type CHECK.
const kEntityTypes = <String, String>{
  'sole_proprietorship': 'Sole proprietorship',
  'partnership': 'Partnership',
  'company_limited_by_shares': 'Company limited by shares',
  'company_limited_by_guarantee': 'Company limited by guarantee',
  'ngo': 'NGO',
};

class KYCSubmission {
  KYCSubmission({
    required this.id,
    required this.status,
    required this.businessType,
    required this.requestedTier,
    required this.ghanaCardNumber,
    required this.businessRegNumber,
    required this.tin,
    required this.entityType,
    required this.registrationCertPath,
    required this.notes,
    required this.reviewerNotes,
    required this.createdAt,
  });

  final String id;
  final String status; // pending | approved | rejected | more_info_requested
  final String businessType; // informal | registered
  final int requestedTier;
  final String ghanaCardNumber;
  final String? businessRegNumber;
  final String? tin;
  final String? entityType;
  final String? registrationCertPath;
  final String? notes;
  final String? reviewerNotes;
  final DateTime createdAt;

  bool get isRegistered => businessType == BusinessTypes.registered;

  factory KYCSubmission.fromJson(Map<String, dynamic> j) => KYCSubmission(
    id: _str(j['id']),
    status: _str(j['status']),
    businessType: _str(j['business_type']),
    requestedTier: _int(j['requested_tier']),
    ghanaCardNumber: _str(j['ghana_card_number']),
    businessRegNumber: _strOrNull(j['business_reg_number']),
    tin: _strOrNull(j['tin']),
    entityType: _strOrNull(j['entity_type']),
    registrationCertPath: _strOrNull(j['registration_cert_path']),
    notes: _strOrNull(j['notes']),
    reviewerNotes: _strOrNull(j['reviewer_notes']),
    createdAt: DateTime.tryParse(_str(j['created_at'])) ?? DateTime.now(),
  );
}

/// Section 4.1: what this merchant's tier allows them to collect, and how
/// much of it they've used. Every limit is 0 when uncapped, matching the
/// API — the tier limits ship unset because the thresholds are governed by
/// Bank of Ghana guidance and are entered in Back Office once confirmed.
class MerchantLimits {
  MerchantLimits({
    required this.kycTier,
    required this.businessType,
    required this.perTransactionLimitPesewas,
    required this.dailyLimitPesewas,
    required this.cumulativeLimitPesewas,
    required this.todayPesewas,
    required this.cumulativePesewas,
    required this.dailyRemainingPesewas,
    required this.cumulativeRemainingPesewas,
  });

  final int kycTier;
  final String? businessType;
  final int perTransactionLimitPesewas;
  final int dailyLimitPesewas;
  final int cumulativeLimitPesewas;
  final int todayPesewas;
  final int cumulativePesewas;
  final int dailyRemainingPesewas;
  final int cumulativeRemainingPesewas;

  /// True when nothing is capped at this tier, which is the shipped state.
  /// The app says so plainly rather than drawing three empty progress bars.
  bool get isUncapped =>
      perTransactionLimitPesewas == 0 &&
      dailyLimitPesewas == 0 &&
      cumulativeLimitPesewas == 0;

  factory MerchantLimits.fromJson(Map<String, dynamic> j) => MerchantLimits(
    kycTier: _int(j['kyc_tier']),
    businessType: _strOrNull(j['business_type']),
    perTransactionLimitPesewas: _int(j['per_transaction_limit_pesewas']),
    dailyLimitPesewas: _int(j['daily_limit_pesewas']),
    cumulativeLimitPesewas: _int(j['cumulative_limit_pesewas']),
    todayPesewas: _int(j['today_pesewas']),
    cumulativePesewas: _int(j['cumulative_pesewas']),
    dailyRemainingPesewas: _int(j['daily_remaining_pesewas']),
    cumulativeRemainingPesewas: _int(j['cumulative_remaining_pesewas']),
  );
}

class DeliveryOption {
  DeliveryOption({
    required this.id,
    required this.type,
    required this.contactName,
    required this.contactPhone,
    required this.providerKey,
    required this.feeHandlingDefault,
    required this.flatFeePesewas,
    required this.serviceZone,
    required this.status,
  });

  final String id;
  final String type; // own_contact | verified_provider
  final String? contactName;
  final String? contactPhone;
  final String? providerKey; // set when type == verified_provider and drawn from the catalog
  final String feeHandlingDefault; // bundled | external
  final int? flatFeePesewas;
  final String? serviceZone;
  final String status;

  factory DeliveryOption.fromJson(Map<String, dynamic> j) => DeliveryOption(
    id: _str(j['id']),
    type: _str(j['type']),
    contactName: _strOrNull(j['contact_name']),
    contactPhone: _strOrNull(j['contact_phone']),
    providerKey: _strOrNull(j['provider_key']),
    feeHandlingDefault: _str(j['fee_handling_default']),
    flatFeePesewas: _intOrNull(j['flat_fee_pesewas']),
    serviceZone: _strOrNull(j['service_zone']),
    status: _str(j['status']),
  );
}

/// Feedback item 4 — a pickup/delivery reference point a merchant manages
/// under More → Locations. Deliberately flat: not tied to a specific
/// DeliveryOption, so it works as a reference for a third-party provider,
/// a merchant's own rider, or a customer arranging their own pickup alike.
class MerchantLocation {
  MerchantLocation({
    required this.id,
    required this.label,
    required this.address,
    required this.phone,
    required this.isDefault,
    required this.status,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String label;
  final String address;
  final String? phone;
  final bool isDefault;
  final String status;
  final double? lat; // set when the address was filled via "Use current location"
  final double? lng;

  factory MerchantLocation.fromJson(Map<String, dynamic> j) => MerchantLocation(
    id: _str(j['id']),
    label: _str(j['label']),
    address: _str(j['address']),
    phone: _strOrNull(j['phone']),
    isDefault: j['is_default'] == true,
    status: _str(j['status']),
    lat: _doubleOrNull(j['lat']),
    lng: _doubleOrNull(j['lng']),
  );
}

/// A saved customer (Section 4.3 order flow revision) — managed under
/// More → Customers, and offered as a quick-pick on New Order. Upserted
/// automatically by the API whenever an invoice is sent; [name] is
/// optional since a customer may never have given one.
class Customer {
  Customer({
    required this.id,
    required this.name,
    required this.contact,
  });

  final String id;
  final String? name;
  final String contact;

  /// What to show in a picker row: the name if we have one, else the
  /// phone number — same fallback as OrderRequest.displayName.
  String get displayName => (name?.isNotEmpty ?? false) ? name! : contact;

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
    id: _str(j['id']),
    name: _strOrNull(j['name']),
    contact: _str(j['contact']),
  );
}

/// Section 4.11/9.4: the admin-maintained catalog of verified delivery
/// providers (Bolt, Uber, Yango, ...) — the merchant-app side just reads
/// it to offer pre-populated toggles instead of merchants typing names in.
class DeliveryProvider {
  DeliveryProvider({required this.id, required this.key, required this.name, required this.deepLinkTemplate});

  final String id;
  final String key;
  final String name;
  final String deepLinkTemplate;

  factory DeliveryProvider.fromJson(Map<String, dynamic> j) => DeliveryProvider(
    id: _str(j['id']),
    key: _str(j['key']),
    name: _str(j['name']),
    deepLinkTemplate: _str(j['deep_link_template']),
  );
}

/// Section 4.10: real, persisted in-app alerts. Push/SMS/WhatsApp delivery
/// isn't built — see the doc comment on the API's ListNotifications handler
/// for why — this is the in-app feed only.
class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.targetEntity,
    required this.targetId,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String type; // payment_received | order_request_pending | payout_processed | kyc_status_change
  final String title;
  final String body;
  final String? targetEntity;
  final String? targetId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: _str(j['id']),
    type: _str(j['type']),
    title: _str(j['title']),
    body: _str(j['body']),
    targetEntity: _strOrNull(j['target_entity']),
    targetId: _strOrNull(j['target_id']),
    readAt: j['read_at'] == null ? null : DateTime.tryParse(_str(j['read_at'])),
    createdAt: DateTime.tryParse(_str(j['created_at'])) ?? DateTime.now(),
  );
}

class NotificationFeed {
  NotificationFeed({required this.notifications, required this.unreadCount});
  final List<AppNotification> notifications;
  final int unreadCount;
}

/// Section 4.7 — merchant-facing analytics, all computed server-side.
class BestSellingItem {
  BestSellingItem({
    required this.description,
    required this.totalQuantity,
    required this.totalRevenuePesewas,
  });
  final String description;
  final int totalQuantity;
  final int totalRevenuePesewas;

  factory BestSellingItem.fromJson(Map<String, dynamic> j) => BestSellingItem(
    description: _str(j['description']),
    totalQuantity: _int(j['total_quantity']),
    totalRevenuePesewas: _int(j['total_revenue_pesewas']),
  );
}

class DailyCollection {
  DailyCollection({
    required this.day,
    required this.collectedPesewas,
    required this.paymentCount,
  });
  final DateTime day;
  final int collectedPesewas;
  final int paymentCount;

  factory DailyCollection.fromJson(Map<String, dynamic> j) => DailyCollection(
    day: DateTime.tryParse(_str(j['day'])) ?? DateTime.now(),
    collectedPesewas: _int(j['collected_pesewas']),
    paymentCount: _int(j['payment_count']),
  );
}

class RepeatCustomer {
  RepeatCustomer({
    required this.customerContact,
    required this.orderCount,
    required this.totalSpentPesewas,
  });
  final String customerContact;
  final int orderCount;
  final int totalSpentPesewas;

  factory RepeatCustomer.fromJson(Map<String, dynamic> j) => RepeatCustomer(
    customerContact: _str(j['customer_contact']),
    orderCount: _int(j['order_count']),
    totalSpentPesewas: _int(j['total_spent_pesewas']),
  );
}

class MerchantAnalytics {
  MerchantAnalytics({
    required this.periodStart,
    required this.periodEnd,
    required this.bestSellingItems,
    required this.dailyCollections,
    required this.orderCount,
    required this.averageOrderValuePesewas,
    required this.totalCollectedPesewas,
    required this.uniqueCustomerCount,
    required this.repeatCustomers,
  });
  final String periodStart;
  final String periodEnd;
  final List<BestSellingItem> bestSellingItems;
  final List<DailyCollection> dailyCollections;
  final int orderCount;
  final int averageOrderValuePesewas;
  final int totalCollectedPesewas;
  final int uniqueCustomerCount;
  final List<RepeatCustomer> repeatCustomers;

  factory MerchantAnalytics.fromJson(Map<String, dynamic> j) {
    final stats = j['order_stats'] as Map<String, dynamic>? ?? {};
    return MerchantAnalytics(
      periodStart: _str(j['period_start']),
      periodEnd: _str(j['period_end']),
      bestSellingItems: (j['best_selling_items'] as List? ?? [])
          .map((e) => BestSellingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      dailyCollections: (j['daily_collections'] as List? ?? [])
          .map((e) => DailyCollection.fromJson(e as Map<String, dynamic>))
          .toList(),
      orderCount: _int(stats['order_count']),
      averageOrderValuePesewas: _int(stats['average_order_value_pesewas']),
      totalCollectedPesewas: _int(stats['total_collected_pesewas']),
      uniqueCustomerCount: _int(stats['unique_customer_count']),
      repeatCustomers: (j['repeat_customers'] as List? ?? [])
          .map((e) => RepeatCustomer.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
