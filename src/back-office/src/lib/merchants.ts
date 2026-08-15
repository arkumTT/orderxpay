import "server-only";
import { apiFetchServer } from "./session";
import type {
  Merchant,
  Item,
  Invoice,
  Settlement,
  RiskFlag,
  MerchantNote,
} from "./types";

export function listMerchants(params?: { status?: string }): Promise<Merchant[]> {
  const query = params?.status ? `?status=${encodeURIComponent(params.status)}` : "";
  return apiFetchServer<Merchant[]>(`/api/v1/admin/merchants${query}`);
}

export function getMerchant(id: string): Promise<Merchant> {
  return apiFetchServer<Merchant>(`/api/v1/admin/merchants/${id}`);
}

export function getMerchantItems(id: string): Promise<Item[]> {
  return apiFetchServer<Item[]>(`/api/v1/admin/merchants/${id}/items`);
}

export function getMerchantInvoices(id: string): Promise<Invoice[]> {
  return apiFetchServer<Invoice[]>(`/api/v1/admin/merchants/${id}/invoices`);
}

export function getMerchantSettlements(id: string): Promise<Settlement[]> {
  return apiFetchServer<Settlement[]>(`/api/v1/admin/merchants/${id}/settlements`);
}

export function getMerchantRiskFlags(id: string): Promise<RiskFlag[]> {
  return apiFetchServer<RiskFlag[]>(`/api/v1/admin/merchants/${id}/risk-flags`);
}

export function getMerchantNotes(id: string): Promise<MerchantNote[]> {
  return apiFetchServer<MerchantNote[]>(`/api/v1/admin/merchants/${id}/notes`);
}
