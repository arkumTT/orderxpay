import { PlaceholderPage } from "@/components/placeholder-page";

export default async function MerchantDetailPage(
  props: PageProps<"/merchants/[id]">,
) {
  const { id } = await props.params;
  return (
    <PlaceholderPage
      title={`Merchant ${id}`}
      section="7.1"
      description="Profile, catalog snapshot, transaction history, payout history, notes/flags from support or compliance staff. Suspend action blocks new invoice creation and payouts without deleting historical data."
    />
  );
}
