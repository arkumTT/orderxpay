// Mirrors JSON produced by src/api's sqlc models (internal/db/sqlc/models.go).
// pgtype.UUID/Text/Int8 all marshal to a plain string, or null when unset.

export type Invoice = {
  id: string;
  merchant_id: string;
  order_request_id: string | null;
  reference: string;
  customer_contact: string;
  subtotal_pesewas: number;
  service_charge_pesewas: number;
  service_charge_allocation: "customer_only" | "merchant_only" | "split";
  total_pesewas: number;
  status:
    | "draft"
    | "sent"
    | "viewed"
    | "partially_paid"
    | "paid"
    | "expired"
    | "cancelled"
    | "refunded";
  delivery_option_id: string | null;
  delivery_address: string | null;
  delivery_fee_handling: "bundled" | "external" | null;
  delivery_fee_pesewas: number | null;
  expires_at: string | null;
  created_at: string;
  updated_at: string;
};

export type InvoiceLineItem = {
  id: string;
  invoice_id: string;
  item_id: string | null;
  description: string;
  unit_price_pesewas: number;
  quantity: number;
  line_total_pesewas: number;
};

// Resolved from invoice.delivery_option_id (Section 4.11/5.1, Prompt 6) —
// present only when the invoice has a delivery option attached.
export type DeliveryHandoff = {
  type: "own_contact" | "verified_provider";
  contact_name: string | null;
  contact_phone: string | null;
  provider_key: string | null;
  deep_link_template: string | null;
  flat_fee_pesewas: number | null;
  service_zone: string | null;
  fee_handling_default: "bundled" | "external";
  delivery_address: string | null;
  merchant_business_name?: string;
  // The real pickup point for a third-party deep link (e.g. Bolt Send's
  // pickup= param) — the merchant's actual address/coordinates from their
  // saved locations, when this invoice has one attached. Falls back to
  // merchant_business_name (a name, not an address) only when the
  // merchant hasn't set a pickup location — see pickup_location below,
  // and buildDeepLink in delivery-handoff.tsx.
  pickup_address?: string | null;
  pickup_lat?: number | null;
  pickup_lng?: number | null;
};

// Resolved from invoice.pickup_location_id, independent of any delivery
// option (Section 4.11 feedback item 4) — a merchant can have this set
// even on an order with no delivery attached, e.g. to tell a customer
// picking up in person where to go.
export type PickupLocation = {
  label: string;
  address: string;
  phone: string | null;
  lat?: number | null;
  lng?: number | null;
};

export type CheckoutResponse = {
  invoice: Invoice;
  line_items: InvoiceLineItem[];
  amount_paid_pesewas: number;
  amount_owed_pesewas: number;
  merchant?: { business_name: string };
  delivery?: DeliveryHandoff;
  pickup_location?: PickupLocation;
};

export type InitiatePaymentResponse = {
  authorization_url: string;
  reference: string;
};

export type MerchantPublicProfile = {
  id: string;
  business_name: string;
  category?: string;
  status: "pending" | "active" | "restricted" | "suspended";
};

export type Item = {
  id: string;
  merchant_id: string;
  name: string;
  unit_price_pesewas: number;
  qty_unit: string | null;
  image_url: string | null;
  availability_status: "in_stock" | "out_of_stock" | "made_to_order";
  archived_at: string | null;
  created_at: string;
  updated_at: string;
};
