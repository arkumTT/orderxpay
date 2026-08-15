import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

export async function PATCH(
  request: Request,
  ctx: RouteContext<"/api/feature-flags/[id]">,
) {
  const { id } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (typeof body?.enabled_globally !== "boolean") {
    return Response.json(
      { error: "enabled_globally must be a boolean" },
      { status: 400 },
    );
  }

  const res = await fetch(`${API_URL}/api/v1/admin/feature-flags/${id}`, {
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
      { error: data.error ?? "failed to update feature flag" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
