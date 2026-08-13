// Split out from session.ts (which is server-only) so proxy.ts — a separate,
// edge-capable bundle — can reference the cookie name without pulling in
// the server-only guard.
export const SESSION_COOKIE = "orderxpay_session";
