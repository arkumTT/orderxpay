import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

export async function POST(
  request: Request,
  ctx: RouteContext<"/api/merchants/[id]/notes">,
) {
  const { id } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.body?.trim()) {
    return Response.json({ error: "body is required" }, { status: 400 });
  }

  const res = await fetch(`${API_URL}/api/v1/admin/merchants/${id}/notes`, {
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
      { error: data.error ?? "failed to create note" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
