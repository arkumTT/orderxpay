import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

export async function POST(request: Request) {
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.key || !body?.name || !body?.deep_link_template) {
    return Response.json(
      { error: "key, name, and deep_link_template are required" },
      { status: 400 },
    );
  }

  const res = await fetch(`${API_URL}/api/v1/admin/delivery-providers`, {
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
      { error: data.error ?? "failed to create delivery provider" },
      { status: res.status },
    );
  }
  return Response.json(data, { status: res.status });
}
