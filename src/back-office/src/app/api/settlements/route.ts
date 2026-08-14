import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies settlement generation to the Go API server-side (Section 7.2) —
// same pattern as api/auth/login: the session token is httpOnly and
// unreachable from client JS, so Client Component mutations go through a
// local route handler that attaches it.
export async function POST(request: Request) {
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.merchant_id || !body?.period_start || !body?.period_end) {
    return Response.json(
      { error: "merchant_id, period_start, and period_end are required" },
      { status: 400 },
    );
  }

  const res = await fetch(`${API_URL}/api/v1/admin/settlements`, {
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
      { error: data.error ?? "failed to generate settlement" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
