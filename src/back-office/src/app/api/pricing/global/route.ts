import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies the global commission rate update (Section 7.4) — same
// server-side-token pattern as api/settlements/route.ts.
export async function POST(request: Request) {
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (
    body?.collection_fee_bps == null ||
    body?.payout_fee_bps == null ||
    body?.margin_bps == null ||
    !body?.allocation_type
  ) {
    return Response.json(
      {
        error:
          "collection_fee_bps, payout_fee_bps, margin_bps, and allocation_type are required",
      },
      { status: 400 },
    );
  }

  const res = await fetch(`${API_URL}/api/v1/admin/fee-rules/global`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    return Response.json(
      { error: data.error ?? "failed to update global fee rule" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
