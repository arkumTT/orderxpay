# src/back-office — OrderxPay Back Office

Next.js (App Router, TypeScript, Tailwind). Internal admin platform —
Section 7 of the architecture doc.

## Layout

```
src/app/(auth)/login/           unauthenticated
src/app/(dashboard)/            sidebar shell + one route per Section 7 module
src/lib/api.ts                  fetch wrapper for the Go API (NEXT_PUBLIC_API_URL)
src/lib/nav.ts                  sidebar nav config, doubles as the module index
src/components/placeholder-page.tsx
```

Every module under `(dashboard)/` is currently a structural placeholder —
see `src/lib/nav.ts` for the full list and its architecture-doc section
reference.

## Local development

```bash
cp .env.local.example .env.local   # points at the local Go API
npm install
npm run dev
```

Requires `src/api` running locally (see its README) for the login page and
any future data-fetching to work.

## Not yet built

- Session handling (the login page calls the API but doesn't yet persist
  the token or protect routes — needs an httpOnly-cookie flow via a route
  handler, not localStorage)
- Every module's actual data table/forms — see Section 7 of the
  architecture doc for what each should contain
