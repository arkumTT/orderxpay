import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

export async function PATCH(
  request: Request,
  ctx: RouteContext<"/api/delivery-providers/[id]">,
) {
  const { id } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.name || !body?.deep_link_template || !body?.status) {
    return Response.json(
      { error: "name, deep_link_template, and status are required" },
      { status: 400 },
    );
  }

  const res = await fetch(
    `${API_URL}/api/v1/admin/delivery-providers/${id}`,
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
      { error: data.error ?? "failed to update delivery provider" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}

export async function DELETE(
  _request: Request,
  ctx: RouteContext<"/api/delivery-providers/[id]">,
) {
  const { id } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const res = await fetch(
    `${API_URL}/api/v1/admin/delivery-providers/${id}`,
    {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}` },
    },
  );

  if (res.status === 204) return new Response(null, { status: 204 });
  const data = await res.json().catch(() => ({}));
  return Response.json(
    { error: data.error ?? "failed to delete delivery provider" },
    { status: res.status },
  );
}
