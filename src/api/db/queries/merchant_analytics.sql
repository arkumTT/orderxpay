-- Section 4.7: merchant-facing analytics + bookkeeping export. All queries
-- are merchant-scoped (mounted under RequireOwnMerchant) and, unless noted,
-- only count invoices that actually collected money (paid or
-- partially_paid) within the requested period — a declined/expired invoice
-- isn't a "sale".

-- name: GetMerchantBestSellingItems :many
SELECT
  ili.description,
  SUM(ili.quantity)::bigint AS total_quantity,
  SUM(ili.line_total_pesewas)::bigint AS total_revenue_pesewas
FROM invoice_line_items ili
JOIN invoices i ON i.id = ili.invoice_id
WHERE i.merchant_id = sqlc.arg(merchant_id)
  AND i.status IN ('paid', 'partially_paid')
  AND i.created_at >= sqlc.arg(period_start)::timestamptz
  AND i.created_at < sqlc.arg(period_end)::timestamptz
GROUP BY ili.description
ORDER BY total_quantity DESC, total_revenue_pesewas DESC
LIMIT sqlc.arg(row_limit);

-- name: GetMerchantDailyCollections :many
-- Grouped by actual payment date (not invoice date), matching the platform-
-- wide GetDailyRevenue query in reporting.sql.
SELECT
  DATE(p.paid_at) AS day,
  COALESCE(SUM(p.amount_pesewas), 0)::bigint AS collected_pesewas,
  COUNT(p.id)::bigint AS payment_count
FROM payments p
JOIN invoices i ON i.id = p.invoice_id
WHERE i.merchant_id = sqlc.arg(merchant_id)
  AND p.status = 'success'
  AND p.paid_at >= sqlc.arg(period_start)::timestamptz
  AND p.paid_at < sqlc.arg(period_end)::timestamptz
GROUP BY DATE(p.paid_at)
ORDER BY day;

-- name: GetMerchantOrderStats :one
SELECT
  COUNT(*)::bigint AS order_count,
  COALESCE(AVG(total_pesewas), 0)::bigint AS average_order_value_pesewas,
  COALESCE(SUM(total_pesewas), 0)::bigint AS total_collected_pesewas,
  COUNT(DISTINCT customer_contact)::bigint AS unique_customer_count
FROM invoices
WHERE merchant_id = sqlc.arg(merchant_id)
  AND status IN ('paid', 'partially_paid')
  AND created_at >= sqlc.arg(period_start)::timestamptz
  AND created_at < sqlc.arg(period_end)::timestamptz;

-- name: GetMerchantRepeatCustomers :many
-- A "repeat" customer placed more than one paid/partially-paid order in the
-- period, identified by customer_contact since there's no customers table.
SELECT
  customer_contact,
  COUNT(*)::bigint AS order_count,
  COALESCE(SUM(total_pesewas), 0)::bigint AS total_spent_pesewas
FROM invoices
WHERE merchant_id = sqlc.arg(merchant_id)
  AND status IN ('paid', 'partially_paid')
  AND created_at >= sqlc.arg(period_start)::timestamptz
  AND created_at < sqlc.arg(period_end)::timestamptz
GROUP BY customer_contact
HAVING COUNT(*) > 1
ORDER BY order_count DESC, total_spent_pesewas DESC
LIMIT sqlc.arg(row_limit);

-- name: ListMerchantInvoicesForExport :many
-- Backs the CSV bookkeeping export — every invoice in the period regardless
-- of status (an accountant needs to see declined/expired ones too), with
-- items and the payment method(s) used summarized per row.
SELECT
  i.reference,
  i.customer_contact,
  i.created_at,
  i.status,
  COALESCE(items.items_summary, '') AS items_summary,
  i.total_pesewas AS amount_invoiced_pesewas,
  COALESCE(pay.amount_paid_pesewas, 0)::bigint AS amount_paid_pesewas,
  (i.total_pesewas - COALESCE(pay.amount_paid_pesewas, 0))::bigint AS outstanding_pesewas,
  COALESCE(pay.channel, '') AS channel
FROM invoices i
LEFT JOIN LATERAL (
  SELECT STRING_AGG(ili.description || ' x' || ili.quantity, '; ' ORDER BY ili.id) AS items_summary
  FROM invoice_line_items ili WHERE ili.invoice_id = i.id
) items ON true
LEFT JOIN LATERAL (
  SELECT
    COALESCE(SUM(p.amount_pesewas), 0)::bigint AS amount_paid_pesewas,
    STRING_AGG(DISTINCT p.method, ', ') AS channel
  FROM payments p WHERE p.invoice_id = i.id AND p.status = 'success'
) pay ON true
WHERE i.merchant_id = sqlc.arg(merchant_id)
  AND i.created_at >= sqlc.arg(period_start)::timestamptz
  AND i.created_at < sqlc.arg(period_end)::timestamptz
ORDER BY i.created_at DESC;
