import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies the liveness-check selfie image (Section 4.1/7.1) — same
// server-side-token pattern as api/kyc-submissions/[id]/status/route.ts.
// Unlike that route this streams binary image bytes rather than JSON, since
// the Go API's GetKYCSelfiePhoto responds with the raw file: the selfie is
// never reachable through a public/static URL, so an <img> tag can't point
// at the Go API directly — it has to go through this same-origin proxy,
// which attaches the admin's bearer token server-side.
export async function GET(
  _request: Request,
  ctx: RouteContext<"/api/kyc-submissions/[id]/selfie-photo">,
) {
  const { id } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const res = await fetch(
    `${API_URL}/api/v1/admin/kyc-submissions/${id}/selfie-photo`,
    { headers: { Authorization: `Bearer ${token}` } },
  );

  if (!res.ok) {
    return Response.json(
      { error: "failed to load selfie photo" },
      { status: res.status },
    );
  }

  return new Response(res.body, {
    status: 200,
    headers: {
      "Content-Type": res.headers.get("Content-Type") ?? "image/jpeg",
      "Cache-Control": "private, max-age=60",
    },
  });
}
