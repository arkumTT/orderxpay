package http

import (
	"github.com/gofiber/fiber/v2"

	"github.com/orderxpay/api/internal/auth"
	"github.com/orderxpay/api/internal/http/handlers"
	"github.com/orderxpay/api/internal/middleware"
)

// RegisterRoutes wires every route group. Path prefixes:
//
//	/api/v1/public/...  no auth — hosted checkout/catalog, order requests, PSP webhooks (Section 5, 4.6)
//	/api/v1/app/...     merchant app auth (merchant owner or staff)      (Section 4)
//	/api/v1/admin/...   Back Office auth (users only, gated per-route by RBAC permission — Section 7.8)
func RegisterRoutes(app *fiber.App, h *handlers.Handler) {
	app.Get("/healthz", h.Health)

	v1 := app.Group("/api/v1")

	public := v1.Group("/public")
	public.Post("/admin/auth/login", h.UserLogin)
	public.Post("/merchants", h.CreateMerchant)
	public.Post("/merchants/:id/otp/request", h.RequestMerchantOTP)
	public.Post("/merchants/:id/otp/verify", h.VerifyMerchantOTP)
	public.Post("/dev/token", h.DevIssueMerchantToken) // ENV=development only — see auth.go
	public.Get("/checkout/:reference", h.GetInvoiceByReference)
	public.Post("/checkout/:reference/pay", h.InitiateCheckoutPayment)
	public.Get("/checkout/:reference/verify", h.VerifyCheckoutPayment)
	public.Get("/merchants/:id", h.GetMerchantPublicProfile) // Section 4.6 hosted catalog page
	public.Get("/merchants/:id/items", h.ListItems)          // same — catalog data is meant to be public
	public.Post("/merchants/:id/order-requests", h.CreateOrderRequest)
	public.Post("/webhooks/psp", h.HandlePSPWebhook)

	app_ := v1.Group("/app", middleware.RequireAuth(h.TokenMaker), middleware.RequireActorType(auth.ActorMerchant, auth.ActorStaff))
	registerMerchantScopedRoutes(app_, h)

	admin := v1.Group("/admin", middleware.RequireAuth(h.TokenMaker), middleware.RequireActorType(auth.ActorUser))
	registerAdminRoutes(admin, h)
}

// registerMerchantScopedRoutes covers everything the merchant app itself calls
// (Section 4): catalog, invoices, payments read, staff, delivery options,
// conversations, order-request review.
func registerMerchantScopedRoutes(r fiber.Router, h *handlers.Handler) {
	merchants := r.Group("/merchants")
	merchants.Get("/:id", h.GetMerchant)

	merchants.Post("/:id/staff", h.CreateStaff)
	merchants.Get("/:id/staff", h.ListStaff)
	merchants.Delete("/:id/staff/:staffId", h.DeleteStaff)

	merchants.Post("/:id/items", h.CreateItem)
	merchants.Get("/:id/items", h.ListItems)
	merchants.Get("/:id/items/:itemId", h.GetItem)
	merchants.Put("/:id/items/:itemId", h.UpdateItem)
	merchants.Delete("/:id/items/:itemId", h.ArchiveItem)

	merchants.Get("/:id/order-requests", h.ListPendingOrderRequests)
	merchants.Patch("/:id/order-requests/:requestId", h.SetOrderRequestStatus)

	merchants.Post("/:id/invoices", h.CreateInvoice)
	merchants.Get("/:id/invoices", h.ListInvoicesByMerchant)
	merchants.Get("/invoices/:id/payments", h.ListPaymentsByInvoice)

	merchants.Post("/:id/delivery-options", h.CreateDeliveryOption)
	merchants.Get("/:id/delivery-options", h.ListDeliveryOptions)
	merchants.Patch("/delivery-options/:optionId", h.SetDeliveryOptionStatus)

	merchants.Post("/:id/kyc-submissions", h.CreateKYCSubmission)
	merchants.Get("/:id/kyc-submissions", h.ListKYCSubmissionsByMerchant)

	merchants.Post("/:id/conversations", h.LogConversation)
	merchants.Get("/:id/conversations", h.ListConversations)

	merchants.Get("/:id/settlements", h.ListSettlements)
	merchants.Get("/:id/fee-rule", h.GetMerchantFeeRuleOrGlobal)
	merchants.Patch("/:id/fee-settings", h.UpdateMerchantFeeSettings)
}

// registerAdminRoutes covers the Back Office platform (Section 7). Every
// route is gated by a specific permission key from the RBAC seed catalog
// (db/migrations/000002_rbac_users.up.sql) via middleware.RequirePermission
// — actor-type auth alone (any Back Office user) is not enough.
func registerAdminRoutes(r fiber.Router, h *handlers.Handler) {
	perm := middleware.RequirePermission

	merchants := r.Group("/merchants")
	merchants.Get("", perm("merchants.view"), h.ListMerchants)
	merchants.Get("/:id", perm("merchants.view"), h.GetMerchant)
	merchants.Patch("/:id/status", perm("merchants.manage_status"), h.UpdateMerchantStatus)
	merchants.Patch("/:id/kyc-tier", perm("merchants.kyc_review"), h.UpdateMerchantKYCTier)
	merchants.Get("/:id/settlements", perm("settlements.view"), h.ListSettlements)
	merchants.Post("/:id/fee-rule", perm("pricing.manage"), h.UpsertMerchantFeeRule)
	merchants.Delete("/:id/fee-rule", perm("pricing.manage"), h.DeleteMerchantFeeRule)

	r.Get("/kyc-submissions", perm("merchants.kyc_review"), h.ListKYCSubmissionsAdmin)
	r.Patch("/kyc-submissions/:id/status", perm("merchants.kyc_review"), h.ReviewKYCSubmission)

	r.Get("/disputes", perm("disputes.view"), h.ListDisputesAdmin)
	r.Post("/disputes", perm("disputes.manage"), h.CreateDispute)
	r.Get("/disputes/:id", perm("disputes.view"), h.GetDisputeDetail)
	r.Patch("/disputes/:id/status", perm("disputes.manage"), h.ResolveDispute)

	r.Get("/risk/flags", perm("risk.view"), h.ListRiskFlagsAdmin)
	r.Post("/risk/scan", perm("risk.manage"), h.RunRiskScan)
	r.Patch("/risk/flags/:id/status", perm("risk.manage"), h.ResolveRiskFlag)

	r.Get("/settlements", perm("settlements.view"), h.ListAllSettlements)
	r.Post("/settlements", perm("settlements.manage"), h.GenerateSettlement)
	r.Patch("/settlements/:id/status", perm("settlements.manage"), h.UpdateSettlementStatus)
	r.Get("/fee-rules/global", perm("pricing.view"), h.GetGlobalFeeRule)
	r.Post("/fee-rules/global", perm("pricing.manage"), h.UpsertGlobalFeeRule)
	r.Get("/fee-rules/overrides", perm("pricing.view"), h.ListFeeRuleOverrides)

	r.Get("/feature-flags", perm("pricing.view"), h.ListFeatureFlags)
	r.Patch("/feature-flags/:id", perm("pricing.manage"), h.SetFeatureFlagGlobal)
	r.Post("/feature-flags/:id/merchants", perm("pricing.manage"), h.AddFeatureFlagMerchant)
	r.Delete("/feature-flags/:id/merchants/:merchantId", perm("pricing.manage"), h.RemoveFeatureFlagMerchant)

	r.Get("/reporting", perm("reporting.view"), h.GetReporting)

	r.Get("/integrations", perm("integrations.manage"), h.ListIntegrations)
	r.Post("/integrations/:key/secret", perm("integrations.manage"), h.SetIntegrationSecret)
	r.Patch("/integrations/:key/notes", perm("integrations.manage"), h.UpdateIntegrationNotes)
	r.Get("/webhook-deliveries", perm("integrations.manage"), h.ListWebhookDeliveries)

	r.Get("/delivery-providers", perm("integrations.manage"), h.ListDeliveryProviders)
	r.Post("/delivery-providers", perm("integrations.manage"), h.CreateDeliveryProvider)
	r.Patch("/delivery-providers/:id", perm("integrations.manage"), h.UpdateDeliveryProvider)
	r.Delete("/delivery-providers/:id", perm("integrations.manage"), h.DeleteDeliveryProvider)

	r.Get("/support/search", perm("support.view"), h.SupportSearch)
	r.Get("/support/transactions/:reference", perm("support.view"), h.GetSupportTransaction)

	r.Get("/audit-log", perm("audit.view"), h.ListAuditLogAdmin)
	r.Get("/audit-log/:targetId", perm("audit.view"), h.ListAuditLogForTarget)

	// 7.8: managing Back Office users themselves.
	users := r.Group("/users", perm("admin.manage_users"))
	users.Post("", h.CreateUser)
	users.Get("", h.ListUsers)
	users.Patch("/:id/status", h.SetUserStatus)
	users.Get("/:id/roles", h.ListUserRoles)
	users.Post("/:id/roles", h.AssignUserRole)
	users.Delete("/:id/roles/:roleId", h.RemoveUserRole)
	r.Get("/roles", perm("admin.manage_users"), h.ListRoles)
	r.Get("/permissions", perm("admin.manage_users"), h.ListPermissions)

	// Section 13 "Admin shell/navigation": /menus/me is the one exception to
	// "every route needs a specific permission" — it's available to any
	// authenticated Back Office user, since it's how the sidebar itself is
	// rendered. Managing the menu catalog is a separate, gated concern.
	r.Get("/menus/me", h.ListMyMenus)
	menus := r.Group("/menus", perm("admin.manage_menus"))
	menus.Get("", h.ListMenus)
	menus.Post("", h.CreateMenu)
	menus.Put("/:id", h.UpdateMenu)
	menus.Delete("/:id", h.DeleteMenu)
}
