import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies dispute resolution — investigate/deny/refund (Section 7.7). Same
// server-side-token pattern as api/settlements/[id]/status/route.ts.
export async function PATCH(
  request: Request,
  ctx: RouteContext<"/api/disputes/[id]/status">,
) {
  const { id } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.status) {
    return Response.json({ error: "status is required" }, { status: 400 });
  }

  const res = await fetch(`${API_URL}/api/v1/admin/disputes/${id}/status`, {
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
      { error: data.error ?? "failed to update dispute" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
