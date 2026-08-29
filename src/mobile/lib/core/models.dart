// Mirrors JSON produced by src/api's sqlc models. pgtype.UUID/Text/Int8/Int4
// all marshal to a plain value, or null when unset.

int _int(dynamic v) => v == null ? 0 : (v as num).toInt();
int? _intOrNull(dynamic v) => v == null ? null : (v as num).toInt();
String _str(dynamic v) => v == null ? '' : v as String;
String? _strOrNull(dynamic v) => v as String?;

class Merchant {
  Merchant({
    required this.id,
    required this.businessName,
    required this.category,
    required this.phone,
    required this.kycTier,
    required this.status,
    required this.serviceChargeAllocation,
    required this.serviceChargeSplitBps,
    required this.payoutFeeAbsorption,
    required this.whatsappAutoReplyEnabled,
    required this.whatsappGreetingMessage,
    required this.deliveryEnabled,
  });

  final String id;
  final String businessName;
  final String? category;
  final String phone;
  final int kycTier;
  final String status;
  final String serviceChargeAllocation;
  final int? serviceChargeSplitBps;
  final String payoutFeeAbsorption; // merchant_absorbed | blended_into_rate
  final bool whatsappAutoReplyEnabled;
  final String? whatsappGreetingMessage; // null = use the app's generated default
  final bool deliveryEnabled;

  factory Merchant.fromJson(Map<String, dynamic> j) => Merchant(
    id: _str(j['id']),
    businessName: _str(j['business_name']),
    category: _strOrNull(j['category']),
    phone: _str(j['phone']),
    kycTier: _int(j['kyc_tier']),
    status: _str(j['status']),
    serviceChargeAllocation: _str(j['service_charge_allocation']),
    serviceChargeSplitBps: _intOrNull(j['service_charge_split_bps']),
    payoutFeeAbsorption: j['payout_fee_absorption'] == null
        ? 'merchant_absorbed'
        : _str(j['payout_fee_absorption']),
    whatsappAutoReplyEnabled: j['whatsapp_auto_reply_enabled'] as bool? ?? true,
    whatsappGreetingMessage: _strOrNull(j['whatsapp_greeting_message']),
    deliveryEnabled: j['delivery_enabled'] as bool? ?? true,
  );
}

/// Section 4.8 (revised): the blended commission_bps the invoice engine and
/// checkout read is always collectionFeeBps + payoutFeeBps + marginBps,
/// enforced server-side — the breakdown here is what the merchant-facing
/// "How this is calculated" card explains.
class FeeRule {
  FeeRule({
    required this.commissionBps,
    required this.collectionFeeBps,
    required this.payoutFeeBps,
    required this.marginBps,
    required this.allocationType,
  });

  final int commissionBps;
  final int collectionFeeBps;
  final int payoutFeeBps;
  final int marginBps;
  final String allocationType;

  factory FeeRule.fromJson(Map<String, dynamic> j) => FeeRule(
    commissionBps: _int(j['commission_bps']),
    collectionFeeBps: _int(j['collection_fee_bps']),
    payoutFeeBps: _int(j['payout_fee_bps']),
    marginBps: _int(j['margin_bps']),
    allocationType: _str(j['allocation_type']),
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
    required this.requestedItems,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String customerContact;
  final List<dynamic> requestedItems;
  final String status;
  final DateTime createdAt;

  factory OrderRequest.fromJson(Map<String, dynamic> j) => OrderRequest(
    id: _str(j['id']),
    customerContact: _str(j['customer_contact']),
    requestedItems: (j['requested_items'] as List<dynamic>?) ?? const [],
    status: _str(j['status']),
    createdAt: DateTime.tryParse(_str(j['created_at'])) ?? DateTime.now(),
  );
}

class KYCSubmission {
  KYCSubmission({
    required this.id,
    required this.status,
    required this.ghanaCardNumber,
    required this.businessRegNumber,
    required this.notes,
    required this.reviewerNotes,
    required this.createdAt,
  });

  final String id;
  final String status; // pending | approved | rejected | more_info_requested
  final String ghanaCardNumber;
  final String? businessRegNumber;
  final String? notes;
  final String? reviewerNotes;
  final DateTime createdAt;

  factory KYCSubmission.fromJson(Map<String, dynamic> j) => KYCSubmission(
    id: _str(j['id']),
    status: _str(j['status']),
    ghanaCardNumber: _str(j['ghana_card_number']),
    businessRegNumber: _strOrNull(j['business_reg_number']),
    notes: _strOrNull(j['notes']),
    reviewerNotes: _strOrNull(j['reviewer_notes']),
    createdAt: DateTime.tryParse(_str(j['created_at'])) ?? DateTime.now(),
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
  });

  final String id;
  final String label;
  final String address;
  final String? phone;
  final bool isDefault;
  final String status;

  factory MerchantLocation.fromJson(Map<String, dynamic> j) => MerchantLocation(
    id: _str(j['id']),
    label: _str(j['label']),
    address: _str(j['address']),
    phone: _strOrNull(j['phone']),
    isDefault: j['is_default'] == true,
    status: _str(j['status']),
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
