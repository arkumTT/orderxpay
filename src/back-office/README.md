# src/back-office — OrderxPay Back Office

Next.js (App Router, TypeScript, Tailwind). Internal admin platform —
Section 7 of the architecture doc.

## Layout

```
src/proxy.ts                    edge auth gate — redirects to /login if the session cookie is missing
src/app/api/auth/login/         route handler: proxies login to the Go API, sets an httpOnly cookie
src/app/api/auth/logout/        route handler: clears the cookie
src/app/(auth)/login/           unauthenticated
src/app/(dashboard)/            sidebar shell + one route per Section 7 module
src/lib/session.ts              server-only: reads the session cookie, authenticated fetch to the Go API
src/lib/menus.ts                GET /api/v1/admin/menus/me — the sidebar tree
src/lib/merchants.ts            GET /api/v1/admin/merchants(/:id)
src/components/sidebar-nav.tsx  renders the menu tree (submenus included) from lib/menus
src/components/placeholder-page.tsx
```

## Local development

```bash
cp .env.local.example .env.local   # points at the local Go API
npm install
npm run dev
```

Requires `src/api` running locally with at least one Back Office user
provisioned (`make seed` there) — there's no signup page here, matching the
API's own "no public admin signup" rule.

## Auth

The session token (a PASETO string from the Go API) lives only in an
httpOnly cookie set by `POST /api/auth/login` — it's never sent to client
JS. `src/proxy.ts` is a fast edge-level redirect guard (checks the cookie
exists, nothing more); the real check is server-side: every
`(dashboard)/layout.tsx` render calls `GET /api/v1/admin/menus/me` with the
cookie, and a `401` there — expired or otherwise invalid token — redirects
to `/login` too.

**Client Components can't make authenticated API calls** — the token isn't
reachable from browser JS by design. Any state-changing action (suspend a
merchant, approve KYC, assign a role) needs its own route handler under
`src/app/api/...` that reads the cookie server-side and forwards the
request, the same pattern as `src/app/api/auth/login/route.ts`. None of
those exist yet — see "Not yet built" below.

## Navigation menus

The sidebar (`src/components/sidebar-nav.tsx`) and the Overview page's card
grid both render from `GET /api/v1/admin/menus/me` (`src/lib/menus.ts`) —
there's no hardcoded nav list anymore. Submenus come through as nested
`children` and render indented. Add or reorder menu items via the API
(`db/migrations/000003_menus.up.sql` in `src/api`, or
`POST/PUT/DELETE /api/v1/admin/menus` once you're signed in as a user with
`admin.manage_menus`) — this frontend just reflects whatever the API
returns for the current user.

## What's wired vs. placeholder

Fetching and displaying real data works for:

- Merchants list (`/merchants`) and detail (`/merchants/[id]`)
- The sidebar and Overview page (both from `/menus/me`)

Everything else under `(dashboard)/` — Settlements, Pricing, Integrations,
Reporting, Risk & Fraud, Disputes, Admin Users, Audit Log, Support,
KYC Review — is still `PlaceholderPage`. The pattern to extend is: add a
`lib/<thing>.ts` with a server-only fetch function (see `lib/merchants.ts`),
call it from the page as an async Server Component, handle the
`ApiError`/403 case.

## Not yet built

- Any state-changing call from this frontend (suspend a merchant, approve
  KYC, assign a role, create a user) — needs an authenticated route-handler
  proxy per action, see "Auth" above
- Every other module's data table/forms — see Section 7 of the
  architecture doc for what each should contain
