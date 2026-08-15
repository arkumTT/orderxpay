import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies dispute detail (with refundable payments) for the Client
// Component refund picker — apiFetchServer is server-only, so the "Refund"
// action fetches this on demand rather than the Server Component page
// preloading detail for every row up front.
export async function GET(
  _request: Request,
  ctx: RouteContext<"/api/disputes/[id]">,
) {
  const { id } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const res = await fetch(`${API_URL}/api/v1/admin/disputes/${id}`, {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store",
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    return Response.json(
      { error: data.error ?? "failed to load dispute" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
