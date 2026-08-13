import { cookies } from "next/headers";
import { SESSION_COOKIE } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies the login request to the Go API server-side and stores the
// returned PASETO token as an httpOnly cookie — the token never reaches
// client JS, unlike the earlier version of this page which called the API
// directly from the browser and left the token to be persisted "somehow".
export async function POST(request: Request) {
  const body = await request.json().catch(() => null);
  if (!body?.email || !body?.password) {
    return Response.json({ error: "email and password are required" }, { status: 400 });
  }

  const res = await fetch(`${API_URL}/api/v1/public/admin/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    return Response.json({ error: data.error ?? "login failed" }, { status: res.status });
  }

  const expiresAt = new Date(data.expires_at);
  const maxAgeSeconds = Math.max(0, Math.floor((expiresAt.getTime() - Date.now()) / 1000));

  const store = await cookies();
  store.set(SESSION_COOKIE, data.access_token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: maxAgeSeconds,
  });

  return Response.json({ roles: data.roles, permissions: data.permissions });
}
