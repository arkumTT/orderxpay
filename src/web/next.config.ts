import type { NextConfig } from "next";

// Item photos (Item.image_url) are served from the API's own /uploads/
// path (src/api's static file handler) — the host varies by environment
// (localhost for local dev, a LAN IP when testing on a phone, a real
// domain in production), so this is derived from NEXT_PUBLIC_API_URL at
// build time rather than hardcoded, so next/image can still optimize and
// lazy-load them without a stale/wrong allowlisted host.
const apiUrl = new URL(process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080");

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [
      {
        protocol: apiUrl.protocol === "https:" ? "https" : "http",
        hostname: apiUrl.hostname,
        port: apiUrl.port,
        pathname: "/uploads/**",
      },
    ],
    // Next.js's image optimizer refuses to fetch from private/LAN IPs by
    // default (SSRF protection — an image src pointing at an internal IP
    // could otherwise be used to probe a server's own network) even when
    // that host is explicitly allowlisted above via remotePatterns. That
    // default is right for the general case, but here the "private IP"
    // in question is our own API server on our own LAN, used specifically
    // for testing against a phone that can't reach "localhost" — not an
    // untrusted third party. In production NEXT_PUBLIC_API_URL points at
    // a real public domain, so this flag has no effect there at all; it
    // only matters for this LAN-testing setup.
    dangerouslyAllowLocalIP: true,
  },
};

export default nextConfig;
