package whatsapp

import (
	"context"
	"encoding/json"
	"fmt"
)

// CatalogItem is one OrderxPay item, shaped for Meta's Catalog Batch API
// (Section 6.2). RetailerID should be the item's own stable ID — Meta
// uses it to match CREATE/UPDATE requests to existing catalog entries
// across syncs.
type CatalogItem struct {
	RetailerID       string
	Title            string
	PricePesewas     int64
	Currency         string // e.g. "GHS"
	ImageURL         string // empty is fine — Meta accepts items without one, just won't show a photo
	ProductURL       string // where a tap on the catalog entry sends the customer
	Available        bool
	AvailableToOrder bool // "made_to_order" items map to Meta's "available for order" rather than in/out of stock
}

type catalogBatchRequest struct {
	ItemType string               `json:"item_type"`
	Requests []catalogItemRequest `json:"requests"`
}

type catalogItemRequest struct {
	Method string         `json:"method"`
	Data   map[string]any `json:"data"`
}

// CatalogBatchResult is Meta's response shape for items_batch — a 200
// response doesn't guarantee every item synced cleanly, ValidationStatus
// carries per-item errors/warnings that must be checked.
type CatalogBatchResult struct {
	Handles          []string `json:"handles"`
	ValidationStatus []struct {
		RetailerID string `json:"retailer_id"`
		Errors     []struct {
			Message string `json:"message"`
		} `json:"errors"`
		Warnings []struct {
			Message string `json:"message"`
		} `json:"warnings"`
	} `json:"validation_status"`
}

// SyncCatalogItems pushes a merchant's items into their connected Meta
// catalog (Section 6.2) via the Catalog Batch API
// (POST /{catalog_id}/items_batch, verified against Meta's documented
// request/response shape at the time this was written — re-check
// developers.facebook.com/docs/marketing-api/catalog-batch/reference if
// Meta has since changed required fields). Every item is sent as an
// UPDATE with allow_upsert (Meta's default), which creates the item if
// this retailer_id hasn't been seen before and updates it otherwise — a
// merchant's "Sync now" tap always reconciles the full current catalog
// rather than needing to track which items are genuinely new.
//
// brand is applied to every item — Meta requires it, and OrderxPay has no
// per-item brand concept, so the merchant's own business name is the
// closest honest value. link points at the merchant's whole hosted
// catalog page (src/web/app/catalog/[merchantId]) rather than a
// per-item page, since no per-item page exists in this codebase yet —
// a real, working URL, just not item-specific; a fast-follow if per-item
// deep links are ever built.
func (c *Client) SyncCatalogItems(ctx context.Context, catalogID string, items []CatalogItem, brand string) (*CatalogBatchResult, error) {
	if !c.Enabled() {
		return nil, fmt.Errorf("whatsapp: access token not configured")
	}
	if catalogID == "" {
		return nil, fmt.Errorf("whatsapp: catalog_id is required")
	}

	requests := make([]catalogItemRequest, 0, len(items))
	for _, it := range items {
		currency := it.Currency
		if currency == "" {
			currency = "GHS"
		}
		price := fmt.Sprintf("%.2f %s", float64(it.PricePesewas)/100, currency)

		availability := "out of stock"
		switch {
		case it.AvailableToOrder:
			availability = "available for order"
		case it.Available:
			availability = "in stock"
		}

		data := map[string]any{
			"id":           it.RetailerID,
			"title":        it.Title,
			"description":  it.Title, // items have no separate description field to draw from
			"price":        price,
			"availability": availability,
			"condition":    "new",
			"brand":        brand,
			"link":         it.ProductURL,
		}
		if it.ImageURL != "" {
			data["image_link"] = it.ImageURL
		}

		requests = append(requests, catalogItemRequest{Method: "UPDATE", Data: data})
	}

	body, err := json.Marshal(catalogBatchRequest{ItemType: "PRODUCT_ITEM", Requests: requests})
	if err != nil {
		return nil, err
	}

	var result CatalogBatchResult
	if err := c.do(ctx, "POST", "/"+catalogID+"/items_batch", body, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// DeleteCatalogItems removes items from the catalog (e.g. archived
// OrderxPay items) — same endpoint, DELETE method, id-only payload per
// Meta's spec.
func (c *Client) DeleteCatalogItems(ctx context.Context, catalogID string, retailerIDs []string) (*CatalogBatchResult, error) {
	if !c.Enabled() {
		return nil, fmt.Errorf("whatsapp: access token not configured")
	}
	if catalogID == "" {
		return nil, fmt.Errorf("whatsapp: catalog_id is required")
	}

	requests := make([]catalogItemRequest, 0, len(retailerIDs))
	for _, id := range retailerIDs {
		requests = append(requests, catalogItemRequest{Method: "DELETE", Data: map[string]any{"id": id}})
	}

	body, err := json.Marshal(catalogBatchRequest{ItemType: "PRODUCT_ITEM", Requests: requests})
	if err != nil {
		return nil, err
	}

	var result CatalogBatchResult
	if err := c.do(ctx, "POST", "/"+catalogID+"/items_batch", body, &result); err != nil {
		return nil, err
	}
	return &result, nil
}
