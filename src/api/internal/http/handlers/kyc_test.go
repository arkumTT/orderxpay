package handlers

import (
	"strings"
	"testing"
)

// A valid registered submission, used as the base for the "one field
// missing" cases below.
func registeredRequest() submitKYCRequest {
	return submitKYCRequest{
		BusinessType:         "registered",
		GhanaCardNumber:      "GHA-123456789-0",
		SelfiePhotoPath:      "selfie.jpg",
		BusinessRegNumber:    "CS123456789",
		Tin:                  "C0001234567",
		EntityType:           "company_limited_by_shares",
		RegistrationCertPath: "cert.pdf",
	}
}

func TestInformalForkNeedsOnlyIdentityEvidence(t *testing.T) {
	req := submitKYCRequest{
		BusinessType:    "informal",
		GhanaCardNumber: "GHA-123456789-0",
		SelfiePhotoPath: "selfie.jpg",
	}
	req.normalize()
	if err := req.validate(); err != nil {
		t.Fatalf("an informal trader with a card number and a liveness selfie should pass, got: %v", err)
	}
	if got := req.requestedTier(); got != 1 {
		t.Errorf("the informal fork should request Tier 1, got %d", got)
	}
}

func TestRegisteredForkNeedsEveryPieceOfRegistrationEvidence(t *testing.T) {
	valid := registeredRequest()
	valid.normalize()
	if err := valid.validate(); err != nil {
		t.Fatalf("a complete registered submission should pass, got: %v", err)
	}
	if got := valid.requestedTier(); got != 2 {
		t.Errorf("the registered fork should request Tier 2, got %d", got)
	}

	// Each of these mirrors a clause of the
	// kyc_submissions_registered_evidence CHECK. If one stops being
	// rejected here it becomes a 500 from a constraint violation instead
	// of a sentence naming the missing field.
	for field, blank := range map[string]func(*submitKYCRequest){
		"business_reg_number":    func(r *submitKYCRequest) { r.BusinessRegNumber = "" },
		"tin":                    func(r *submitKYCRequest) { r.Tin = "" },
		"entity_type":            func(r *submitKYCRequest) { r.EntityType = "" },
		"registration_cert_path": func(r *submitKYCRequest) { r.RegistrationCertPath = "" },
	} {
		req := registeredRequest()
		blank(&req)
		req.normalize()
		err := req.validate()
		if err == nil {
			t.Errorf("a registered submission missing %s should be rejected", field)
			continue
		}
		if !strings.Contains(err.Error(), strings.SplitN(field, "_path", 2)[0]) {
			t.Errorf("the error for a missing %s should name it, got: %v", field, err)
		}
	}
}

// Whitespace is not evidence: a TIN of " " must not satisfy the CHECK's
// `tin <> ”` by arriving as a non-empty string.
func TestWhitespaceOnlyFieldsAreNotEvidence(t *testing.T) {
	req := registeredRequest()
	req.Tin = "   "
	req.normalize()
	if err := req.validate(); err == nil {
		t.Error("a whitespace-only TIN should be rejected")
	}
}

// The informal fork must not carry registration evidence into the database
// — a reviewer should not see a half-filled TIN on a decision that does not
// turn on one.
func TestInformalForkDropsRegisteredEvidence(t *testing.T) {
	req := submitKYCRequest{
		BusinessType:         "informal",
		GhanaCardNumber:      "GHA-123456789-0",
		SelfiePhotoPath:      "selfie.jpg",
		Tin:                  "C0001234567",
		EntityType:           "ngo",
		RegistrationCertPath: "cert.pdf",
	}
	req.normalize()
	if req.Tin != "" || req.EntityType != "" || req.RegistrationCertPath != "" {
		t.Errorf("informal submissions should carry no registration evidence, got tin=%q entity=%q cert=%q",
			req.Tin, req.EntityType, req.RegistrationCertPath)
	}
}

func TestBothForksRequireIdentityEvidence(t *testing.T) {
	for _, businessType := range []string{"informal", "registered"} {
		noCard := registeredRequest()
		noCard.BusinessType = businessType
		noCard.GhanaCardNumber = ""
		noCard.normalize()
		if err := noCard.validate(); err == nil {
			t.Errorf("%s: a submission with no Ghana Card number should be rejected", businessType)
		}

		noSelfie := registeredRequest()
		noSelfie.BusinessType = businessType
		noSelfie.SelfiePhotoPath = ""
		noSelfie.normalize()
		if err := noSelfie.validate(); err == nil {
			t.Errorf("%s: a submission with no liveness selfie should be rejected", businessType)
		}
	}
}

func TestUnknownBusinessTypeAndEntityTypeAreRejected(t *testing.T) {
	req := registeredRequest()
	req.BusinessType = "sole_trader"
	req.normalize()
	if err := req.validate(); err == nil {
		t.Error("an unrecognised business_type should be rejected, not stored")
	}

	req = registeredRequest()
	req.EntityType = "limited_liability_partnership"
	req.normalize()
	if err := req.validate(); err == nil {
		t.Error("an entity_type the schema CHECK would reject should be caught here first")
	}
}

// entityTypes is duplicated in the migration's CHECK constraint; if the two
// drift, a legitimate submission fails as a 500 instead of validating.
func TestEntityTypesMatchTheSchemaCheck(t *testing.T) {
	want := []string{
		"sole_proprietorship",
		"partnership",
		"company_limited_by_shares",
		"company_limited_by_guarantee",
		"ngo",
	}
	if len(entityTypes) != len(want) {
		t.Fatalf("entityTypes has %d entries, the schema CHECK has %d", len(entityTypes), len(want))
	}
	for _, k := range want {
		if !entityTypes[k] {
			t.Errorf("entityTypes is missing %q, which the schema CHECK allows", k)
		}
	}
}
