# OrderxPay

<!-- test/branch-protection-check: verifying required status checks + PR review rule on main -->

Mobile-first order-to-cash platform for Ghanaian retailers. See
`OrderxPay_Product_Architecture_Framework.html` for the full product/architecture
spec — module breakdowns below reference its section numbers.

## Repo layout

```
src/
  mobile/       Flutter merchant app (Sections 4, 6, 12)
  back-office/  Next.js internal admin platform (Section 7)
  web/          Next.js customer-facing surfaces: hosted checkout + catalog (Section 5)
  api/          Go + Fiber backend — core platform services (Section 3.1), Postgres via sqlc/pgx, PASETO auth
```

Each app is independent (own `go.mod` / `package.json` / `pubspec.yaml`) — no
shared workspace tooling between them. `src/api` is the single standalone
backend all three frontends call.

## Local development

1. Start Postgres: `docker compose up -d`
   - dev database: `orderxpay_dev`, user: `postgres` (see `docker-compose.yml`
     for credentials — dev only, never used for anything but a local container)
2. API: see `src/api/README.md`
3. Back office: see `src/back-office/README.md`
4. Web: see `src/web/README.md`
5. Mobile: see `src/mobile/README.md`

## Status

Structural scaffold only — module logic (KYC, invoice engine, ledger,
WhatsApp integration, etc.) is not yet implemented.
