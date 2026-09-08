import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies a KYC tier limit update (Section 4.1/7.1) — same
// server-side-token pattern as the pricing routes.
//
// null is a meaningful value here and must survive the round trip: it means
// "no cap", and is the only way to clear a limit. That is why the body is
// forwarded as-is rather than being filtered for falsy values.
export async function PATCH(
  request: Request,
  ctx: RouteContext<"/api/kyc-tier-limits/[tier]">,
) {
  const { tier } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (body === null) {
    return Response.json({ error: "invalid request body" }, { status: 400 });
  }

  const res = await fetch(`${API_URL}/api/v1/admin/kyc-tier-limits/${tier}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    return Response.json(
      { error: data.error ?? "failed to update tier limit" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
