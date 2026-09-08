import { getSessionToken } from "@/lib/session";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

// Proxies a business registration certificate (Section 4.1) — same
// server-side-token pattern as the selfie-photo route beside it, and for
// the same reason: the file lives outside any static mount and is readable
// only by an admin holding merchants.kyc_review, so a link in the review
// queue has to come through this same-origin proxy.
//
// Unlike the selfie, this one is commonly a PDF, so the upstream
// Content-Type is passed straight through rather than defaulted to an
// image type — and it is served inline so a reviewer can read it in a tab
// instead of downloading it.
export async function GET(
  _request: Request,
  ctx: RouteContext<"/api/kyc-submissions/[id]/registration-cert">,
) {
  const { id } = await ctx.params;
  const token = await getSessionToken();
  if (!token) {
    return Response.json({ error: "no session" }, { status: 401 });
  }

  const res = await fetch(
    `${API_URL}/api/v1/admin/kyc-submissions/${id}/registration-cert`,
    { headers: { Authorization: `Bearer ${token}` } },
  );

  if (!res.ok) {
    return Response.json(
      { error: "failed to load registration certificate" },
      { status: res.status },
    );
  }

  return new Response(res.body, {
    status: 200,
    headers: {
      "Content-Type":
        res.headers.get("Content-Type") ?? "application/octet-stream",
      "Content-Disposition": "inline",
      "Cache-Control": "private, max-age=60",
    },
  });
}
