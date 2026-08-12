# src/web — OrderxPay customer-facing surfaces

Next.js (App Router, TypeScript, Tailwind). No login, no account — Section 5
and 4.6 of the architecture doc.

## Routes

```
/checkout/[reference]    hosted checkout page (Section 5.1)
/catalog/[merchantId]    hosted catalog + order-request page (Section 4.6, 12.2)
```

Both are server-rendered on demand (not statically generated) since they
depend on live invoice/catalog data from `src/api`.

## Local development

```bash
cp .env.local.example .env.local   # points at the local Go API
npm install
npm run dev
```

Requires `src/api` running locally, with a merchant/items/invoice already in
the database (there's no UI yet to create them from this app — that's the
mobile app's job).

## Not yet built

- Payment method selection on the checkout page — depends on which PSP is
  selected (Section 9.1); currently shows a placeholder
- USSD fallback (Section 5.2) — not a web concern, but noted here since it's
  part of the same customer payment experience
