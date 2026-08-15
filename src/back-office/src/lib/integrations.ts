import "server-only";
import { apiFetchServer } from "./session";
import type { DeliveryProvider, Integration, WebhookDelivery } from "./types";

export function listIntegrations(): Promise<Integration[]> {
  return apiFetchServer<Integration[]>("/api/v1/admin/integrations");
}

export function listWebhookDeliveries(): Promise<WebhookDelivery[]> {
  return apiFetchServer<WebhookDelivery[]>(
    "/api/v1/admin/webhook-deliveries?limit=25",
  );
}

export function listDeliveryProviders(): Promise<DeliveryProvider[]> {
  return apiFetchServer<DeliveryProvider[]>("/api/v1/admin/delivery-providers");
}
