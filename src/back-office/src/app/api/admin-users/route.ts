import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies Back Office user creation (Section 7.8) — same server-side-token
// pattern as api/settlements/route.ts.
export async function POST(request: Request) {
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.name || !body?.email || !body?.password) {
    return Response.json(
      { error: "name, email, and password are required" },
      { status: 400 },
    );
  }

  const res = await fetch(`${API_URL}/api/v1/admin/users`, {
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
      { error: data.error ?? "failed to create user" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
