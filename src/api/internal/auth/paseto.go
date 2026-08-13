package auth

import (
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/o1egl/paseto/v2"
)

var (
	ErrInvalidToken = errors.New("token is invalid")
	ErrExpiredToken = errors.New("token has expired")
)

// ActorType identifies which kind of principal a token was issued to.
type ActorType string

const (
	ActorMerchant ActorType = "merchant" // merchant owner, via the mobile app
	ActorStaff    ActorType = "staff"    // merchant staff (Section 4.9), via the mobile app
	ActorUser     ActorType = "user"     // Back Office user (Section 7.8), RBAC via roles/permissions
)

// Payload is the claim set embedded in every PASETO token issued by the API.
// Roles/Permissions are only populated for ActorUser tokens — they're a
// snapshot taken at login time (see GetUserPermissionKeys), so a
// permission/role change takes effect on next login, not mid-session.
type Payload struct {
	ID          uuid.UUID `json:"id"`
	ActorID     uuid.UUID `json:"actor_id"`
	ActorType   ActorType `json:"actor_type"`
	MerchantID  uuid.UUID `json:"merchant_id,omitempty"`
	Roles       []string  `json:"roles,omitempty"`
	Permissions []string  `json:"permissions,omitempty"`
	IssuedAt    time.Time `json:"issued_at"`
	ExpiredAt   time.Time `json:"expired_at"`
}

func (p Payload) Valid() error {
	if time.Now().After(p.ExpiredAt) {
		return ErrExpiredToken
	}
	return nil
}

func (p Payload) HasPermission(key string) bool {
	for _, perm := range p.Permissions {
		if perm == key {
			return true
		}
	}
	return false
}

// CreateTokenParams describes a new token to issue. MerchantID is the zero
// UUID for ActorUser tokens; Roles/Permissions are empty for merchant/staff
// tokens.
type CreateTokenParams struct {
	ActorID     uuid.UUID
	ActorType   ActorType
	MerchantID  uuid.UUID
	Roles       []string
	Permissions []string
	Duration    time.Duration
}

// Maker issues and verifies PASETO v2 local (symmetric) tokens.
type Maker interface {
	CreateToken(params CreateTokenParams) (string, *Payload, error)
	VerifyToken(token string) (*Payload, error)
}

type pasetoMaker struct {
	symmetricKey []byte
}

// NewPasetoMaker builds a Maker from a 32-byte symmetric key.
func NewPasetoMaker(symmetricKey string) (Maker, error) {
	if len(symmetricKey) != 32 {
		return nil, errors.New("symmetric key must be exactly 32 bytes")
	}
	return &pasetoMaker{symmetricKey: []byte(symmetricKey)}, nil
}

func (m *pasetoMaker) CreateToken(params CreateTokenParams) (string, *Payload, error) {
	now := time.Now()
	payload := &Payload{
		ID:          uuid.New(),
		ActorID:     params.ActorID,
		ActorType:   params.ActorType,
		MerchantID:  params.MerchantID,
		Roles:       params.Roles,
		Permissions: params.Permissions,
		IssuedAt:    now,
		ExpiredAt:   now.Add(params.Duration),
	}

	token, err := paseto.NewV2().Encrypt(m.symmetricKey, payload, nil)
	if err != nil {
		return "", nil, err
	}
	return token, payload, nil
}

func (m *pasetoMaker) VerifyToken(token string) (*Payload, error) {
	payload := &Payload{}
	if err := paseto.NewV2().Decrypt(token, m.symmetricKey, payload, nil); err != nil {
		return nil, ErrInvalidToken
	}
	if err := payload.Valid(); err != nil {
		return nil, err
	}
	return payload, nil
}
