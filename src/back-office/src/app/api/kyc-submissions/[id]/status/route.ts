import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies KYC approve/reject/request-more-info (Section 7.1) — same
// server-side-token pattern as api/settlements/[id]/status/route.ts.
export async function PATCH(
  request: Request,
  ctx: RouteContext<"/api/kyc-submissions/[id]/status">,
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

  const res = await fetch(
    `${API_URL}/api/v1/admin/kyc-submissions/${id}/status`,
    {
      method: "PATCH",
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
      { error: data.error ?? "failed to update submission" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
