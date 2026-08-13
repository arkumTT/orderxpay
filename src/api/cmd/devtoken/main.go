// cmd/devtoken issues a merchant/staff PASETO token directly, bypassing OTP
// sign-in (Section 4.1), which isn't implemented yet — see
// RequestMerchantOTP/VerifyMerchantOTP in internal/http/handlers/auth.go.
// DEV ONLY: this is a stand-in for real sign-in, not a feature to ship.
//
// Usage:
//
//	go run ./cmd/devtoken -actor=merchant -merchant-id=<uuid>
//	go run ./cmd/devtoken -actor=staff -staff-id=<uuid> -merchant-id=<uuid>
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/google/uuid"

	"github.com/orderxpay/api/internal/auth"
)

func main() {
	actor := flag.String("actor", "merchant", "merchant | staff")
	merchantID := flag.String("merchant-id", "", "merchant uuid")
	staffID := flag.String("staff-id", "", "staff uuid (actor=staff only)")
	duration := flag.Duration("duration", 24*time.Hour, "token lifetime")
	flag.Parse()

	if *merchantID == "" {
		fmt.Fprintln(os.Stderr, "usage: go run ./cmd/devtoken -actor=merchant -merchant-id=<uuid> [-staff-id=<uuid>]")
		os.Exit(1)
	}

	key := os.Getenv("PASETO_SYMMETRIC_KEY")
	if key == "" {
		log.Fatal("PASETO_SYMMETRIC_KEY is required")
	}
	maker, err := auth.NewPasetoMaker(key)
	if err != nil {
		log.Fatalf("auth: %v", err)
	}

	mID, err := uuid.Parse(*merchantID)
	if err != nil {
		log.Fatalf("invalid -merchant-id: %v", err)
	}

	var actorType auth.ActorType
	var actorID uuid.UUID
	switch *actor {
	case "merchant":
		actorType = auth.ActorMerchant
		actorID = mID
	case "staff":
		actorType = auth.ActorStaff
		if *staffID == "" {
			log.Fatal("-staff-id is required when -actor=staff")
		}
		actorID, err = uuid.Parse(*staffID)
		if err != nil {
			log.Fatalf("invalid -staff-id: %v", err)
		}
	default:
		log.Fatalf("-actor must be merchant or staff, got %q", *actor)
	}

	token, _, err := maker.CreateToken(auth.CreateTokenParams{
		ActorID:    actorID,
		ActorType:  actorType,
		MerchantID: mID,
		Duration:   *duration,
	})
	if err != nil {
		log.Fatalf("create token: %v", err)
	}
	fmt.Println(token)
}
