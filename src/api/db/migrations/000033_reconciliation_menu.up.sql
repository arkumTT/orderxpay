-- A dedicated Back Office view for margin reconciliation (Fee Architecture
-- brief, "Also worth building" — the item flagged as the highest-leverage
-- thing not yet built). It compares booked commission against the PSP fee
-- actually charged and the realized margin, per merchant per period, plus a
-- row-level list of individual payments that came back underwater — the
-- view the aggregate revenue dashboard (000003's "/reporting") structurally
-- can't give, because it nets a leaky invoice against a profitable
-- merchant.
--
-- Same audience and same permission as the revenue dashboard
-- (reporting.view), so it sits directly under Reporting in the flat
-- top-level group rather than in one of its own.
INSERT INTO menus (parent_id, permission_id, label, path, sort_order)
SELECT NULL, p.id, 'Reconciliation', '/reconciliation', 51
FROM permissions p WHERE p.key = 'reporting.view';
