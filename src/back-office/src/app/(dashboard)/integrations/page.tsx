import {
  listIntegrations,
  listWebhookDeliveries,
  listDeliveryProviders,
} from "@/lib/integrations";
import { ApiError } from "@/lib/session";
import { IntegrationCard } from "./integration-card";
import { DeliveryProviderManager } from "./delivery-provider-manager";

function formatDateTime(d: string) {
  return new Date(d).toLocaleString("en-GH", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export default async function IntegrationsPage() {
  let integrations, deliveries, providers;
  try {
    [integrations, deliveries, providers] = await Promise.all([
      listIntegrations(),
      listWebhookDeliveries(),
      listDeliveryProviders(),
    ]);
  } catch (err) {
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to manage integrations (requires
          integrations.manage).
        </p>
      );
    }
    throw err;
  }

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">
            System Integrations Hub
          </h1>
          <span className="text-xs font-mono text-neutral-400">
            Section 7.3
          </span>
        </div>
        <p className="text-sm text-neutral-500">
          Paystack is the only integration with real code behind it — the
          other four are configuration placeholders for tracking vendor
          decisions, not working connections.
        </p>
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Providers
        </h2>
        <div className="grid gap-3 sm:grid-cols-2">
          {integrations.map((i) => (
            <IntegrationCard key={i.id} integration={i} />
          ))}
        </div>
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Webhook delivery log
        </h2>
        {deliveries.length === 0 ? (
          <p className="text-sm text-neutral-500">
            No webhook deliveries recorded yet.
          </p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-2">Received</th>
                  <th className="px-4 py-2">Provider</th>
                  <th className="px-4 py-2">Event</th>
                  <th className="px-4 py-2">Reference</th>
                  <th className="px-4 py-2">Signature</th>
                  <th className="px-4 py-2">Processed</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {deliveries.map((d) => (
                  <tr key={d.id} className="hover:bg-neutral-50">
                    <td className="px-4 py-2 text-neutral-600">
                      {formatDateTime(d.received_at)}
                    </td>
                    <td className="px-4 py-2 text-neutral-900">
                      {d.provider}
                    </td>
                    <td className="px-4 py-2 text-neutral-600">
                      {d.event_type ?? "—"}
                    </td>
                    <td className="px-4 py-2 font-mono text-xs text-neutral-500">
                      {d.reference ?? "—"}
                    </td>
                    <td className="px-4 py-2">
                      <span
                        className={
                          d.signature_valid
                            ? "text-green-700"
                            : "text-red-700"
                        }
                      >
                        {d.signature_valid ? "Valid" : "Invalid"}
                      </span>
                    </td>
                    <td className="px-4 py-2">
                      <span
                        className={
                          d.processed_ok ? "text-green-700" : "text-red-700"
                        }
                      >
                        {d.processed_ok ? "OK" : d.error_message ?? "Failed"}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Verified delivery providers (Section 4.11 / 9.4)
        </h2>
        <p className="mb-2 text-xs text-neutral-500">
          The source merchants&apos; delivery-option deep links are meant to
          be drawn from — editable here without a release.
        </p>
        <DeliveryProviderManager providers={providers} />
      </div>
    </div>
  );
}
