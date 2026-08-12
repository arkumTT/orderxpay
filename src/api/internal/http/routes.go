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
//	/api/v1/admin/...   Back Office auth (admin_users only)              (Section 7)
func RegisterRoutes(app *fiber.App, h *handlers.Handler) {
	app.Get("/healthz", h.Health)

	v1 := app.Group("/api/v1")

	public := v1.Group("/public")
	public.Post("/admin/auth/login", h.AdminLogin)
	public.Post("/merchants", h.CreateMerchant)
	public.Post("/merchants/:id/otp/request", h.RequestMerchantOTP)
	public.Post("/merchants/:id/otp/verify", h.VerifyMerchantOTP)
	public.Get("/checkout/:reference", h.GetInvoiceByReference)
	public.Get("/merchants/:id", h.GetMerchantPublicProfile) // Section 4.6 hosted catalog page
	public.Get("/merchants/:id/items", h.ListItems)          // same — catalog data is meant to be public
	public.Post("/merchants/:id/order-requests", h.CreateOrderRequest)
	public.Post("/webhooks/psp", h.HandlePSPWebhook)

	app_ := v1.Group("/app", middleware.RequireAuth(h.TokenMaker), middleware.RequireActorType(auth.ActorMerchant, auth.ActorStaff))
	registerMerchantScopedRoutes(app_, h)

	admin := v1.Group("/admin", middleware.RequireAuth(h.TokenMaker), middleware.RequireActorType(auth.ActorAdminUser))
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

	merchants.Post("/:id/conversations", h.LogConversation)
	merchants.Get("/:id/conversations", h.ListConversations)

	merchants.Get("/:id/settlements", h.ListSettlements)
	merchants.Get("/:id/fee-rule", h.GetMerchantFeeRuleOrGlobal)
}

// registerAdminRoutes covers the Back Office platform (Section 7).
func registerAdminRoutes(r fiber.Router, h *handlers.Handler) {
	merchants := r.Group("/merchants")
	merchants.Get("", h.ListMerchants)
	merchants.Get("/:id", h.GetMerchant)
	merchants.Patch("/:id/status", h.UpdateMerchantStatus)    // 7.1 suspend/restrict/activate
	merchants.Patch("/:id/kyc-tier", h.UpdateMerchantKYCTier) // 7.1 KYC review queue decision
	merchants.Get("/:id/settlements", h.ListSettlements)      // 7.2 reconciliation view
	merchants.Post("/:id/fee-rule", h.UpsertMerchantFeeRule)  // 7.4 per-merchant override

	r.Post("/settlements", h.CreateSettlement) // 7.2 batch run
	r.Get("/fee-rules/global", h.GetGlobalFeeRule)
	r.Post("/fee-rules/global", h.UpsertGlobalFeeRule) // 7.4 global default

	r.Get("/audit-log/:targetId", h.ListAuditLogForTarget) // 7.9
}
