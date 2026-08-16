import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'models.dart';
import 'session.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thin, typed wrapper around the Go API (src/api). Attaches the session
/// token (see session.dart) to every /app request automatically.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static final Uri _base = Uri.parse(AppConfig.apiBaseUrl);

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (Session.instance.token != null)
      'Authorization': 'Bearer ${Session.instance.token}',
  };

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final uri = _base.resolve(path);
    final http.Response res;
    switch (method) {
      case 'GET':
        res = await _client.get(uri, headers: _headers);
      case 'POST':
        res = await _client.post(
          uri,
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        );
      case 'PATCH':
        res = await _client.patch(
          uri,
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        );
      case 'PUT':
        res = await _client.put(
          uri,
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        );
      case 'DELETE':
        res = await _client.delete(uri, headers: _headers);
      default:
        throw ArgumentError('unsupported method $method');
    }
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode >= 400) {
      final body = res.body.isNotEmpty
          ? jsonDecode(res.body) as Map<String, dynamic>
          : <String, dynamic>{};
      throw ApiException(
        res.statusCode,
        body['error']?.toString() ?? res.reasonPhrase ?? 'request failed',
      );
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  // --- generic escape hatches, used by onboarding (no session yet) ---

  Future<Map<String, dynamic>> get(String path) async =>
      (await _send('GET', path)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async => (await _send('POST', path, body: body)) as Map<String, dynamic>;

  // --- typed calls, all merchant-session-scoped ---

  Future<List<Item>> listItems(String merchantId) async {
    final res = await _send('GET', '/api/v1/app/merchants/$merchantId/items');
    return (res as List).map((e) => Item.fromJson(e)).toList();
  }

  /// Whether a feature flag (Section 7.4 staged rollout) is on for this
  /// merchant right now — enabled globally, or opted in specifically.
  Future<bool> getFeatureFlagStatus(String merchantId, String key) async {
    final res = await _send(
      'GET',
      '/api/v1/app/merchants/$merchantId/feature-flags/$key',
    );
    return (res as Map<String, dynamic>)['enabled'] as bool;
  }

  Future<Item> createItem(
    String merchantId, {
    required String name,
    required int unitPricePesewas,
    String? qtyUnit,
    String availabilityStatus = 'in_stock',
  }) async {
    final res = await _send(
      'POST',
      '/api/v1/app/merchants/$merchantId/items',
      body: {
        'name': name,
        'unit_price_pesewas': unitPricePesewas,
        'qty_unit': qtyUnit ?? '',
        'availability_status': availabilityStatus,
      },
    );
    return Item.fromJson(res as Map<String, dynamic>);
  }

  Future<Item> updateItem(
    String merchantId,
    String itemId, {
    required String name,
    required int unitPricePesewas,
    String? qtyUnit,
    required String availabilityStatus,
  }) async {
    final res = await _send(
      'PUT',
      '/api/v1/app/merchants/$merchantId/items/$itemId',
      body: {
        'name': name,
        'unit_price_pesewas': unitPricePesewas,
        'qty_unit': qtyUnit ?? '',
        'availability_status': availabilityStatus,
      },
    );
    return Item.fromJson(res as Map<String, dynamic>);
  }

  Future<void> archiveItem(String merchantId, String itemId) => _send(
    'DELETE',
    '/api/v1/app/merchants/$merchantId/items/$itemId',
  );

  Future<List<Invoice>> listInvoices(String merchantId, {String? status}) async {
    final query = status != null ? '?status=$status' : '';
    final res = await _send(
      'GET',
      '/api/v1/app/merchants/$merchantId/invoices$query',
    );
    return (res as List).map((e) => Invoice.fromJson(e)).toList();
  }

  Future<InvoiceDetail> getInvoiceDetail(String merchantId, String invoiceId) async {
    final res = await _send(
      'GET',
      '/api/v1/app/merchants/$merchantId/invoices/$invoiceId',
    );
    return InvoiceDetail.fromJson(res as Map<String, dynamic>);
  }

  Future<Invoice> createInvoice(
    String merchantId, {
    required String customerContact,
    required List<Map<String, dynamic>> lineItems,
    String? deliveryOptionId,
    String? deliveryAddress,
    String? deliveryFeeHandling,
    int? deliveryFeePesewas,
  }) async {
    final res = await _send(
      'POST',
      '/api/v1/app/merchants/$merchantId/invoices',
      body: {
        'customer_contact': customerContact,
        'line_items': lineItems,
        if (deliveryOptionId != null) 'delivery_option_id': deliveryOptionId,
        if (deliveryAddress != null) 'delivery_address': deliveryAddress,
        if (deliveryFeeHandling != null)
          'delivery_fee_handling': deliveryFeeHandling,
        if (deliveryFeePesewas != null)
          'delivery_fee_pesewas': deliveryFeePesewas,
      },
    );
    final map = res as Map<String, dynamic>;
    final invoice = Invoice.fromJson(map['invoice'] as Map<String, dynamic>);
    final lines = (map['line_items'] as List)
        .map((e) => InvoiceLineItem.fromJson(e))
        .toList();
    return Invoice(
      id: invoice.id,
      reference: invoice.reference,
      customerContact: invoice.customerContact,
      subtotalPesewas: invoice.subtotalPesewas,
      serviceChargePesewas: invoice.serviceChargePesewas,
      totalPesewas: invoice.totalPesewas,
      status: invoice.status,
      createdAt: invoice.createdAt,
      lineItems: lines,
    );
  }

  Future<List<OrderRequest>> listOrderRequests(String merchantId) async {
    final res = await _send(
      'GET',
      '/api/v1/app/merchants/$merchantId/order-requests',
    );
    return (res as List).map((e) => OrderRequest.fromJson(e)).toList();
  }

  Future<void> declineOrderRequest(
    String merchantId,
    String requestId,
    String reason,
  ) => _send(
    'PATCH',
    '/api/v1/app/merchants/$merchantId/order-requests/$requestId',
    body: {'status': 'declined', 'decline_reason': reason},
  );

  Future<Invoice> confirmOrderRequest(
    String merchantId,
    String requestId, {
    required List<Map<String, dynamic>> lineItems,
    String? deliveryOptionId,
    String? deliveryAddress,
    String? deliveryFeeHandling,
    int? deliveryFeePesewas,
  }) async {
    final res = await _send(
      'PATCH',
      '/api/v1/app/merchants/$merchantId/order-requests/$requestId',
      body: {
        'status': 'confirmed',
        'line_items': lineItems,
        if (deliveryOptionId != null) 'delivery_option_id': deliveryOptionId,
        if (deliveryAddress != null) 'delivery_address': deliveryAddress,
        if (deliveryFeeHandling != null)
          'delivery_fee_handling': deliveryFeeHandling,
        if (deliveryFeePesewas != null)
          'delivery_fee_pesewas': deliveryFeePesewas,
      },
    );
    final map = res as Map<String, dynamic>;
    return Invoice.fromJson(map['invoice'] as Map<String, dynamic>);
  }

  Future<List<DeliveryOption>> listDeliveryOptions(String merchantId) async {
    final res = await _send(
      'GET',
      '/api/v1/app/merchants/$merchantId/delivery-options',
    );
    return (res as List).map((e) => DeliveryOption.fromJson(e)).toList();
  }

  Future<DeliveryOption> createDeliveryOption(
    String merchantId, {
    required String type,
    String? contactName,
    String? contactPhone,
    String feeHandlingDefault = 'external',
  }) async {
    final res = await _send(
      'POST',
      '/api/v1/app/merchants/$merchantId/delivery-options',
      body: {
        'type': type,
        'contact_name': contactName ?? '',
        'contact_phone': contactPhone ?? '',
        'fee_handling_default': feeHandlingDefault,
      },
    );
    return DeliveryOption.fromJson(res as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> listStaff(String merchantId) async {
    final res = await _send('GET', '/api/v1/app/merchants/$merchantId/staff');
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Merchant> getMerchant(String merchantId) async {
    final res = await _send('GET', '/api/v1/app/merchants/$merchantId');
    return Merchant.fromJson(res as Map<String, dynamic>);
  }

  /// commission_bps for this merchant (their own override, else the global
  /// default) — used to preview the invoice total client-side before
  /// submitting; the server recomputes authoritatively either way.
  Future<int> getCommissionBps(String merchantId) async {
    final res = await _send('GET', '/api/v1/app/merchants/$merchantId/fee-rule');
    return (res as Map<String, dynamic>)['commission_bps'] as int;
  }

  /// Full fee-rule breakdown (Section 4.8, revised) for the Service Charge
  /// settings screen's "How this is calculated" card.
  Future<FeeRule> getFeeRule(String merchantId) async {
    final res = await _send('GET', '/api/v1/app/merchants/$merchantId/fee-rule');
    return FeeRule.fromJson(res as Map<String, dynamic>);
  }

  Future<List<KYCSubmission>> listKYCSubmissions(String merchantId) async {
    final res = await _send(
      'GET',
      '/api/v1/app/merchants/$merchantId/kyc-submissions',
    );
    return (res as List).map((e) => KYCSubmission.fromJson(e)).toList();
  }

  Future<KYCSubmission> submitKYC(
    String merchantId, {
    required String ghanaCardNumber,
    String? businessRegNumber,
    String? notes,
  }) async {
    final res = await _send(
      'POST',
      '/api/v1/app/merchants/$merchantId/kyc-submissions',
      body: {
        'ghana_card_number': ghanaCardNumber,
        if (businessRegNumber != null) 'business_reg_number': businessRegNumber,
        if (notes != null) 'notes': notes,
      },
    );
    return KYCSubmission.fromJson(res as Map<String, dynamic>);
  }

  Future<Merchant> updateFeeSettings(
    String merchantId, {
    required String allocation,
    int? splitBps,
    String? payoutFeeAbsorption,
  }) async {
    final res = await _send(
      'PATCH',
      '/api/v1/app/merchants/$merchantId/fee-settings',
      body: {
        'service_charge_allocation': allocation,
        if (splitBps != null) 'service_charge_split_bps': splitBps,
        if (payoutFeeAbsorption != null) 'payout_fee_absorption': payoutFeeAbsorption,
      },
    );
    return Merchant.fromJson(res as Map<String, dynamic>);
  }

  /// Section 4.4/6.2 — real, persisted preferences; see the doc comment on
  /// UpdateMerchantWhatsAppSettings (src/api) for what they don't do yet.
  Future<Merchant> updateWhatsAppSettings(
    String merchantId, {
    required bool autoReplyEnabled,
    String? greetingMessage,
  }) async {
    final res = await _send(
      'PATCH',
      '/api/v1/app/merchants/$merchantId/whatsapp-settings',
      body: {
        'auto_reply_enabled': autoReplyEnabled,
        'greeting_message': greetingMessage,
      },
    );
    return Merchant.fromJson(res as Map<String, dynamic>);
  }
}
