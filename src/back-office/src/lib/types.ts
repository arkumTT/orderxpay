// Mirrors JSON produced by src/api's sqlc models — pgtype.UUID/Text/Int8/Int4
// all marshal to a plain value, or null when unset.

export type Settlement = {
  id: string;
  merchant_id: string;
  period_start: string;
  period_end: string;
  gross_collections_pesewas: number;
  psp_fees_pesewas: number;
  commission_pesewas: number;
  net_payout_pesewas: number;
  status: "pending" | "processing" | "paid" | "failed";
  created_at: string;
  updated_at: string;
};

// The cross-merchant admin list joins in the merchant's name — matches
// ListSettlementsAdminRow, not the plain Settlement shape above.
export type SettlementWithMerchant = Settlement & {
  merchant_business_name: string;
};

export type Merchant = {
  id: string;
  business_name: string;
  category: string | null;
  phone: string;
  kyc_tier: number;
  status: "pending" | "active" | "restricted" | "suspended";
  service_charge_allocation: "customer_only" | "merchant_only" | "split";
  service_charge_split_bps: number | null;
  payout_account_type: "momo" | "bank" | null;
  payout_account_ref: string | null;
  payout_schedule: "on_demand" | "scheduled";
  payout_min_threshold_pesewas: number;
  created_at: string;
  updated_at: string;
};
