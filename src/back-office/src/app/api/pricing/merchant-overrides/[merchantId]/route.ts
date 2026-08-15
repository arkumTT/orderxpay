import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

export async function POST(
  request: Request,
  ctx: RouteContext<"/api/pricing/merchant-overrides/[merchantId]">,
) {
  const { merchantId } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (body?.commission_bps == null || !body?.allocation_type) {
    return Response.json(
      { error: "commission_bps and allocation_type are required" },
      { status: 400 },
    );
  }

  const res = await fetch(
    `${API_URL}/api/v1/admin/merchants/${merchantId}/fee-rule`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(body),
    },
  );

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    return Response.json(
      { error: data.error ?? "failed to set merchant override" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}

export async function DELETE(
  _request: Request,
  ctx: RouteContext<"/api/pricing/merchant-overrides/[merchantId]">,
) {
  const { merchantId } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const res = await fetch(
    `${API_URL}/api/v1/admin/merchants/${merchantId}/fee-rule`,
    {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}` },
    },
  );

  if (res.status === 204) return new Response(null, { status: 204 });
  const data = await res.json().catch(() => ({}));
  return Response.json(
    { error: data.error ?? "failed to remove merchant override" },
    { status: res.status },
  );
}
