package handlers

import (
	"errors"
	"sort"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/orderxpay/api/internal/auth"
	db "github.com/orderxpay/api/internal/db/sqlc"
	"github.com/orderxpay/api/internal/middleware"
)

// MenuNode is the nested tree shape returned by ListMyMenus/ListMenus —
// submenus live in Children, so the frontend never has to assemble the
// tree itself.
type MenuNode struct {
	ID        string     `json:"id"`
	Label     string     `json:"label"`
	Path      string     `json:"path,omitempty"`
	Icon      string     `json:"icon,omitempty"`
	SortOrder int32      `json:"sort_order"`
	Children  []MenuNode `json:"children,omitempty"`
}

func buildMenuTree(rows []db.Menu) []MenuNode {
	children := map[pgtype.UUID][]db.Menu{}
	for _, m := range rows {
		children[m.ParentID] = append(children[m.ParentID], m)
	}

	var assemble func(parent pgtype.UUID) []MenuNode
	assemble = func(parent pgtype.UUID) []MenuNode {
		kids := children[parent]
		sort.Slice(kids, func(i, j int) bool {
			if kids[i].SortOrder != kids[j].SortOrder {
				return kids[i].SortOrder < kids[j].SortOrder
			}
			return kids[i].Label < kids[j].Label
		})

		nodes := make([]MenuNode, 0, len(kids))
		for _, k := range kids {
			nodes = append(nodes, MenuNode{
				ID:        uuid.UUID(k.ID.Bytes).String(),
				Label:     k.Label,
				Path:      k.Path.String,
				Icon:      k.Icon.String,
				SortOrder: k.SortOrder,
				Children:  assemble(k.ID),
			})
		}
		return nodes
	}

	return assemble(pgtype.UUID{})
}

// ListMyMenus returns the caller's own visible menu tree — permission-null
// items plus items gated by a permission the caller actually holds (via
// role or direct grant). This is what the Back Office sidebar calls; no
// special permission is required beyond being an authenticated user.
func (h *Handler) ListMyMenus(c *fiber.Ctx) error {
	payload, ok := c.Locals(middleware.AuthPayloadKey).(*auth.Payload)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "missing auth payload"})
	}

	rows, err := h.Queries.ListMenusForUser(c.Context(), toPgUUID(payload.ActorID))
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load menus"})
	}

	// sqlc gives the recursive-CTE query its own row type even though it's
	// field-for-field identical to db.Menu — buildMenuTree only needs the shape.
	menus := make([]db.Menu, len(rows))
	for i, r := range rows {
		menus[i] = db.Menu{
			ID:           r.ID,
			ParentID:     r.ParentID,
			PermissionID: r.PermissionID,
			Label:        r.Label,
			Path:         r.Path,
			Icon:         r.Icon,
			SortOrder:    r.SortOrder,
			CreatedAt:    r.CreatedAt,
			UpdatedAt:    r.UpdatedAt,
		}
	}
	return c.JSON(buildMenuTree(menus))
}

// ListMenus returns every menu (ignoring permission filtering) as a tree —
// for a menu-management UI, gated behind admin.manage_menus.
func (h *Handler) ListMenus(c *fiber.Ctx) error {
	rows, err := h.Queries.ListMenus(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load menus"})
	}
	return c.JSON(buildMenuTree(rows))
}

type menuRequest struct {
	ParentID      string `json:"parent_id"`      // optional, empty = top-level
	PermissionKey string `json:"permission_key"` // optional, empty = visible to any authenticated user
	Label         string `json:"label"`
	Path          string `json:"path"`
	Icon          string `json:"icon"`
	SortOrder     int32  `json:"sort_order"`
}

func (h *Handler) resolvePermissionID(c *fiber.Ctx, key string) (pgtype.UUID, bool, error) {
	if key == "" {
		return pgtype.UUID{}, true, nil
	}
	perm, err := h.Queries.GetPermissionByKey(c.Context(), key)
	if errors.Is(err, pgx.ErrNoRows) {
		return pgtype.UUID{}, false, nil
	} else if err != nil {
		return pgtype.UUID{}, false, err
	}
	return perm.ID, true, nil
}

func (h *Handler) CreateMenu(c *fiber.Ctx) error {
	var req menuRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Label == "" {
		return badRequest(c, "label is required")
	}

	parentID, err := uuidOrNull(req.ParentID)
	if err != nil {
		return badRequest(c, "invalid parent_id")
	}
	permissionID, ok, err := h.resolvePermissionID(c, req.PermissionKey)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to look up permission"})
	}
	if !ok {
		return badRequest(c, "unknown permission_key")
	}

	menu, err := h.Queries.CreateMenu(c.Context(), db.CreateMenuParams{
		ParentID:     parentID,
		PermissionID: permissionID,
		Label:        req.Label,
		Path:         textOrNull(req.Path),
		Icon:         textOrNull(req.Icon),
		SortOrder:    req.SortOrder,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create menu"})
	}
	return c.Status(fiber.StatusCreated).JSON(menu)
}

func (h *Handler) UpdateMenu(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid menu id")
	}
	var req menuRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Label == "" {
		return badRequest(c, "label is required")
	}

	parentID, err := uuidOrNull(req.ParentID)
	if err != nil {
		return badRequest(c, "invalid parent_id")
	}
	if parentID.Valid && parentID == id {
		return badRequest(c, "a menu cannot be its own parent")
	}
	permissionID, ok, err := h.resolvePermissionID(c, req.PermissionKey)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to look up permission"})
	}
	if !ok {
		return badRequest(c, "unknown permission_key")
	}

	menu, err := h.Queries.UpdateMenu(c.Context(), db.UpdateMenuParams{
		ID:           id,
		ParentID:     parentID,
		PermissionID: permissionID,
		Label:        req.Label,
		Path:         textOrNull(req.Path),
		Icon:         textOrNull(req.Icon),
		SortOrder:    req.SortOrder,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update menu"})
	}
	return c.JSON(menu)
}

// DeleteMenu cascades to submenus (ON DELETE CASCADE on parent_id).
func (h *Handler) DeleteMenu(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid menu id")
	}
	if err := h.Queries.DeleteMenu(c.Context(), id); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to delete menu"})
	}
	return c.SendStatus(fiber.StatusNoContent)
}
