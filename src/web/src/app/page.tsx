export default function Home() {
  return (
    <div className="mx-auto max-w-md px-4 py-16 text-center">
      <h1 className="text-xl font-semibold text-neutral-900">OrderxPay</h1>
      <p className="mt-2 text-sm text-neutral-500">
        This app has no general landing page by design (Section 5: no
        account, no login). Customers arrive here via a merchant&apos;s
        payment link (<code>/checkout/[reference]</code>) or catalog link (
        <code>/catalog/[merchantId]</code>).
      </p>
    </div>
  );
}
