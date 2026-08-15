import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

export async function POST(
  request: Request,
  ctx: RouteContext<"/api/admin-users/[id]/roles">,
) {
  const { id } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.role_id) {
    return Response.json({ error: "role_id is required" }, { status: 400 });
  }

  const res = await fetch(`${API_URL}/api/v1/admin/users/${id}/roles`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });

  if (res.status === 204) return new Response(null, { status: 204 });
  const data = await res.json().catch(() => ({}));
  return Response.json(
    { error: data.error ?? "failed to assign role" },
    { status: res.status },
  );
}
