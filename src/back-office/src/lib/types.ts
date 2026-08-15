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

export type KYCSubmission = {
  id: string;
  merchant_id: string;
  requested_tier: number;
  ghana_card_number: string;
  business_reg_number: string | null;
  notes: string | null;
  status: "pending" | "approved" | "rejected" | "more_info_requested";
  reviewer_notes: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  created_at: string;
  updated_at: string;
};

// The cross-merchant admin list joins in the merchant's name — matches
// ListKYCSubmissionsAdminRow, not the plain KYCSubmission shape above.
export type KYCSubmissionWithMerchant = KYCSubmission & {
  merchant_business_name: string;
};

export type DisputeReason =
  | "not_received"
  | "wrong_item"
  | "damaged"
  | "duplicate_charge"
  | "not_as_described"
  | "other";

export type Dispute = {
  id: string;
  invoice_id: string;
  reason_category: DisputeReason;
  description: string | null;
  status: "open" | "investigating" | "resolved_refunded" | "resolved_denied";
  resolution_notes: string | null;
  refund_payment_id: string | null;
  refund_amount_pesewas: number | null;
  created_by: string | null;
  resolved_by: string | null;
  resolved_at: string | null;
  created_at: string;
  updated_at: string;
};

// The cross-merchant admin list joins in invoice/merchant context — matches
// ListDisputesAdminRow, not the plain Dispute shape above.
export type DisputeWithContext = Dispute & {
  invoice_reference: string;
  customer_contact: string;
  merchant_business_name: string;
};

export type RefundablePayment = {
  id: string;
  invoice_id: string;
  psp_reference: string;
  method: "momo" | "card" | "ussd";
  amount_pesewas: number;
  status: "pending" | "success" | "failed";
  refunded_amount_pesewas: number;
  refundable_pesewas: number;
  paid_at: string | null;
  created_at: string;
};

export type DisputeDetail = {
  dispute: Dispute;
  refundable_payments: RefundablePayment[];
};

export type RiskFlag = {
  id: string;
  merchant_id: string;
  flag_type: "duplicate_ghana_card" | "velocity_spike";
  dedupe_key: string;
  details: string;
  status: "open" | "dismissed" | "escalated";
  resolution_notes: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  created_at: string;
  updated_at: string;
};

// The cross-merchant admin list joins in the merchant's name — matches
// ListRiskFlagsAdminRow, not the plain RiskFlag shape above.
export type RiskFlagWithMerchant = RiskFlag & {
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
