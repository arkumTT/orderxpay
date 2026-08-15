import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies dispute creation to the Go API server-side (Section 7.7) — same
// pattern as api/settlements/route.ts.
export async function POST(request: Request) {
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.invoice_reference || !body?.reason_category) {
    return Response.json(
      { error: "invoice_reference and reason_category are required" },
      { status: 400 },
    );
  }

  const res = await fetch(`${API_URL}/api/v1/admin/disputes`, {
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
      { error: data.error ?? "failed to create dispute" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
