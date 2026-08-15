import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

export async function DELETE(
  _request: Request,
  ctx: RouteContext<"/api/feature-flags/[id]/merchants/[merchantId]">,
) {
  const { id, merchantId } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const res = await fetch(
    `${API_URL}/api/v1/admin/feature-flags/${id}/merchants/${merchantId}`,
    {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}` },
    },
  );

  if (res.status === 204) return new Response(null, { status: 204 });
  const data = await res.json().catch(() => ({}));
  return Response.json(
    { error: data.error ?? "failed to remove merchant" },
    { status: res.status },
  );
}
