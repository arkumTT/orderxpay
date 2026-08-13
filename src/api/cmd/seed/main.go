// cmd/seed creates (or updates) a Back Office user and assigns it a role —
// this is the out-of-band bootstrap path for the first Super Admin, since
// there's deliberately no public signup endpoint (Section 7.8).
//
// Usage:
//
//	go run ./cmd/seed -email=you@orderxpay.test -password=... -role="Super Admin" -name="Ama Owusu"
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

func main() {
	name := flag.String("name", "", "user's display name")
	email := flag.String("email", "", "user's login email")
	password := flag.String("password", "", "user's login password (min 8 chars)")
	role := flag.String("role", "Super Admin", "role name to assign (must already exist)")
	flag.Parse()

	if *name == "" || *email == "" || len(*password) < 8 {
		fmt.Fprintln(os.Stderr, "usage: go run ./cmd/seed -name=... -email=... -password=... [-role=\"Super Admin\"]")
		os.Exit(1)
	}

	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		log.Fatal("DATABASE_URL is required")
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	defer pool.Close()

	queries := db.New(pool)

	roleRow, err := queries.GetRoleByName(ctx, *role)
	if err != nil {
		log.Fatalf("role %q not found — has the RBAC migration run? (%v)", *role, err)
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(*password), bcrypt.DefaultCost)
	if err != nil {
		log.Fatalf("hash password: %v", err)
	}

	user, err := queries.GetUserByEmail(ctx, *email)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		user, err = queries.CreateUser(ctx, db.CreateUserParams{
			Name:         *name,
			Email:        *email,
			PasswordHash: string(hash),
		})
		if err != nil {
			log.Fatalf("create user: %v", err)
		}
		fmt.Printf("created user %s (%s)\n", user.Email, user.ID)
	case err == nil:
		fmt.Printf("user %s already exists (%s) — assigning role only\n", user.Email, user.ID)
	default:
		log.Fatalf("look up user: %v", err)
	}

	if err := queries.AssignUserRole(ctx, db.AssignUserRoleParams{
		UserID: user.ID,
		RoleID: roleRow.ID,
	}); err != nil {
		log.Fatalf("assign role: %v", err)
	}

	fmt.Printf("assigned role %q to %s\n", roleRow.Name, user.Email)
}
