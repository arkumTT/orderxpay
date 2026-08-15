import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies the on-demand risk scan (Section 7.6) — same server-side-token
// pattern as api/settlements/route.ts.
export async function POST() {
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const res = await fetch(`${API_URL}/api/v1/admin/risk/scan`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    return Response.json(
      { error: data.error ?? "failed to run risk scan" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
