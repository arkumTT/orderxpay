package handlers

import (
	"errors"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type createUserRequest struct {
	Name     string `json:"name"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

// CreateUser provisions a new Back Office user (Section 7.8). Requires
// admin.manage_users — there is no public signup; the very first user is
// created out-of-band via cmd/seed.
func (h *Handler) CreateUser(c *fiber.Ctx) error {
	var req createUserRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Name == "" || req.Email == "" || len(req.Password) < 8 {
		return badRequest(c, "name, email, and a password of at least 8 characters are required")
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to hash password"})
	}

	user, err := h.Queries.CreateUser(c.Context(), db.CreateUserParams{
		Name:         req.Name,
		Email:        req.Email,
		PasswordHash: string(hash),
	})
	if err != nil {
		return c.Status(fiber.StatusConflict).JSON(fiber.Map{"error": "a user with this email may already exist"})
	}
	user.PasswordHash = ""
	return c.Status(fiber.StatusCreated).JSON(user)
}

func (h *Handler) ListUsers(c *fiber.Ctx) error {
	users, err := h.Queries.ListUsers(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list users"})
	}
	for i := range users {
		users[i].PasswordHash = ""
	}
	return c.JSON(users)
}

type setUserStatusRequest struct {
	Status string `json:"status"` // active | suspended
}

func (h *Handler) SetUserStatus(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid user id")
	}
	var req setUserStatusRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Status != "active" && req.Status != "suspended" {
		return badRequest(c, "status must be active or suspended")
	}

	user, err := h.Queries.SetUserStatus(c.Context(), db.SetUserStatusParams{ID: id, Status: req.Status})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update user status"})
	}
	user.PasswordHash = ""
	return c.JSON(user)
}

func (h *Handler) ListUserRoles(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid user id")
	}
	roles, err := h.Queries.ListUserRoles(c.Context(), id)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list user roles"})
	}
	return c.JSON(roles)
}

type roleAssignmentRequest struct {
	RoleID string `json:"role_id"`
}

func (h *Handler) AssignUserRole(c *fiber.Ctx) error {
	userID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid user id")
	}
	var req roleAssignmentRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	roleID, err := parseUUID(req.RoleID)
	if err != nil {
		return badRequest(c, "invalid role_id")
	}

	if err := h.Queries.AssignUserRole(c.Context(), db.AssignUserRoleParams{
		UserID: userID,
		RoleID: roleID,
	}); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to assign role"})
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *Handler) RemoveUserRole(c *fiber.Ctx) error {
	userID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid user id")
	}
	roleID, err := parseUUIDParam(c, "roleId")
	if err != nil {
		return badRequest(c, "invalid role id")
	}

	if err := h.Queries.RemoveUserRole(c.Context(), db.RemoveUserRoleParams{
		UserID: userID,
		RoleID: roleID,
	}); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to remove role"})
	}
	return c.SendStatus(fiber.StatusNoContent)
}

// ListRoles backs the role-assignment UI (Section 7.8), showing each role's
// permissions so an admin can see what they're granting.
func (h *Handler) ListRoles(c *fiber.Ctx) error {
	roles, err := h.Queries.ListRoles(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list roles"})
	}

	type roleWithPermissions struct {
		db.Role
		Permissions []db.Permission `json:"permissions"`
	}

	result := make([]roleWithPermissions, len(roles))
	for i, r := range roles {
		perms, err := h.Queries.ListPermissionsByRole(c.Context(), r.ID)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load role permissions"})
		}
		result[i] = roleWithPermissions{Role: r, Permissions: perms}
	}
	return c.JSON(result)
}

func (h *Handler) ListPermissions(c *fiber.Ctx) error {
	permissions, err := h.Queries.ListPermissions(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list permissions"})
	}
	return c.JSON(permissions)
}
