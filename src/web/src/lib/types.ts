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

export type CheckoutResponse = {
  invoice: Invoice;
  line_items: InvoiceLineItem[];
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
