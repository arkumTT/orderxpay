import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies credential rotation (Section 7.3) — same server-side-token
// pattern as api/settlements/route.ts. The secret value passes through this
// route but is never stored or logged here; the API itself never echoes it
// back either.
export async function POST(
  request: Request,
  ctx: RouteContext<"/api/integrations/[key]/secret">,
) {
  const { key } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.secret_value) {
    return Response.json(
      { error: "secret_value is required" },
      { status: 400 },
    );
  }

  const res = await fetch(
    `${API_URL}/api/v1/admin/integrations/${key}/secret`,
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
      { error: data.error ?? "failed to update integration" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
