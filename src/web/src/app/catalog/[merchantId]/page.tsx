import { notFound } from "next/navigation";
import { ApiError, apiFetch } from "@/lib/api";
import type { Item, MerchantPublicProfile } from "@/lib/types";
import { CatalogBrowser } from "./catalog-browser";

// Hosted catalog page (Section 4.6): shareable via WhatsApp broadcast,
// WhatsApp status, or SMS. No account or app install required.
export default async function CatalogPage(
  props: PageProps<"/catalog/[merchantId]">,
) {
  const { merchantId } = await props.params;

  let merchant: MerchantPublicProfile;
  let items: Item[];
  try {
    [merchant, items] = await Promise.all([
      apiFetch<MerchantPublicProfile>(`/api/v1/public/merchants/${merchantId}`),
      apiFetch<Item[]>(`/api/v1/public/merchants/${merchantId}/items`),
    ]);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    throw err;
  }

  return (
    <div className="mx-auto max-w-md px-4 py-8">
      <h1 className="text-xl font-semibold text-neutral-900">
        {merchant.business_name}
      </h1>
      {merchant.category && (
        <p className="text-sm text-neutral-500">{merchant.category}</p>
      )}

      <div className="mt-6">
        <CatalogBrowser merchantId={merchantId} items={items} />
      </div>
    </div>
  );
}
